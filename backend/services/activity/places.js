// backend/services/activity/places.js
// Activity service — place activities: added / viewed / liked / discovered, check-ins, photo uploads, and the place viewed-marker.
// Split from services/activityService.js (Phase 6); that path is now a barrel.

const { admin, getFirestore } = require('../../config/firebase');
const { COLLECTIONS } = require('../../models/FirestoreModels');
const db = getFirestore();
const { createActivity } = require('../../controllers/activityController');
const SSEService = require('../sseService');
const notificationService = require('../notificationService');
const { resolvePlacePhoto } = require('./core');
const { circleAudience } = require('./audience');


// Track when a user adds a new place
const trackPlaceAdded = async (placeId, circleId, placeName, circleName, addedByUserId) => {
  try {
    // Get the circle to check privacy settings first
    const circleDoc = await db.collection(COLLECTIONS.CIRCLES).doc(circleId).get();
    if (!circleDoc.exists) {
      console.log('Circle not found, skipping activity tracking');
      return;
    }
    
    const circleData = circleDoc.data();
    const circlePrivacy = circleData.privacy || 'private';
    const audience = await circleAudience(circleData, circleData.owner || addedByUserId);

    // Skip the row entirely when nobody but the owner could ever see it. An
    // innerCircle or shared-private circle DOES get a row — the read gate
    // narrows it to the right people, so taking someone off the list retracts
    // what they can see.
    if (audience.emits) {
      // Create activity record in the activities collection. Thumbnail via
      // resolvePlacePhoto: a canonical-matched save (share extension, adopt)
      // carries no photos of its own — the venue's canonical record does.
      const placeDoc = await db.collection(COLLECTIONS.PLACES).doc(placeId).get();
      const placePhoto = await resolvePlacePhoto(placeId);
      const placeAddress = placeDoc.exists ? (placeDoc.data().address || null) : null;
      
      await createActivity(
        'place_added',
        addedByUserId,
        'place',
        placeId,
        placeName || 'Unknown Place',
        {
          circleId: circleId,
          circleName: circleName || 'Unknown Circle',
          placePhoto: placePhoto,
          placeAddress: placeAddress
        }
      );
    }
    
    // Get all connections of the user who added the place (both directions)
    const [connectionsSnapshot1, connectionsSnapshot2] = await Promise.all([
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('connectedUserId', '==', addedByUserId)
        .where('status', '==', 'accepted')
        .get(),
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', addedByUserId)
        .where('status', '==', 'accepted')
        .get()
    ]);

    const batch = db.batch();
    const allConnections = [...connectionsSnapshot1.docs, ...connectionsSnapshot2.docs];
    let updatedConnectionsCount = 0;
    
    allConnections.forEach(doc => {
      const connectionData = doc.data();
      const connectionRef = doc.ref;
      
      // Determine the other user's ID in this connection
      const otherUserId = connectionData.userId === addedByUserId 
        ? connectionData.connectedUserId 
        : connectionData.userId;
      
      // Only connections this circle's audience admits
      if (audience.allows(otherUserId)) {
        const activity = {
          type: 'place',
          entityId: placeId,
          entityName: placeName || 'Unknown Place',
          circleId: circleId,
          circleName: circleName || 'Unknown Circle',
          createdAt: new Date().toISOString(),
          viewedBy: [addedByUserId] // Creator has already "viewed" their own activity
        };
        
        // Update connection with new activity
        // Don't persist hasRecentPlace - it will be calculated dynamically
        batch.update(connectionRef, {
          hasNewActivity: true,
          // hasRecentPlace: true, // REMOVED - calculated dynamically in getConnections
          recentActivity: admin.firestore.FieldValue.arrayUnion(activity),
          updatedAt: new Date().toISOString()
        });
        
        updatedConnectionsCount++;
      }
    });

    await batch.commit();
    // Place addition activity tracked
    
    // Send real-time SSE events to connections who should see this activity
    allConnections.forEach(doc => {
      const connectionData = doc.data();
      const otherUserId = connectionData.userId === addedByUserId 
        ? connectionData.connectedUserId 
        : connectionData.userId;
      
      if (audience.allows(otherUserId)) {
        // Send place added event
        SSEService.sendEvent(otherUserId, {
          type: 'place_added',
          data: {
            placeId: placeId,
            placeName: placeName || 'Unknown Place',
            circleId: circleId,
            circleName: circleName || 'Unknown Circle',
            addedByUserId: addedByUserId,
            connectionId: doc.id,
            timestamp: new Date().toISOString()
          }
        });
        
        // Also send connection activity event
        SSEService.sendEvent(otherUserId, {
          type: 'connection_activity',
          data: {
            connectionId: doc.id,
            activityType: 'place',
            entityId: placeId,
            entityName: placeName || 'Unknown Place',
            circleId: circleId,
            circleName: circleName || 'Unknown Circle',
            timestamp: new Date().toISOString()
          }
        });
        
        // Send push notification if enabled for this connection
        if (connectionData.activityNotificationsEnabled === true) { // Explicit opt-in required
          (async () => {
            try {
              // Get place adder's display name
              const adderDoc = await db.collection(COLLECTIONS.USERS).doc(addedByUserId).get();
              const adderName = adderDoc.exists ? adderDoc.data().displayName : 'Someone';
              
              await notificationService.sendToUser(otherUserId, {
                type: 'activity_notification',
                title: 'New Place Added',
                body: `${adderName} added ${placeName} to ${circleName}`,
                data: {
                  type: 'place_added',
                  placeId: placeId,
                  circleId: circleId,
                  addedByUserId: addedByUserId,
                  deepLink: `circles://place/${placeId}?circleId=${circleId}`
                }
              });
            } catch (notificationError) {
              console.warn('Failed to send place addition push notification:', notificationError);
            }
          })();
        }
      }
    });

    // Also notify FOLLOWERS of the actor. A follow is itself the opt-in:
    // unlike connections (which need the per-connection activityNotifications
    // flag), following someone means you want their activity. Followers only
    // have access to PUBLIC circles, so this fires for public adds only.
    if (circlePrivacy === 'public') {
      try {
        // Who already received something via the connection loop above:
        const allConnectionOtherIds = new Set(allConnections.map(doc => {
          const cd = doc.data();
          return cd.userId === addedByUserId ? cd.connectedUserId : cd.userId;
        }));
        const alreadyPushedIds = new Set(allConnections
          .filter(doc => doc.data().activityNotificationsEnabled === true)
          .map(doc => {
            const cd = doc.data();
            return cd.userId === addedByUserId ? cd.connectedUserId : cd.userId;
          }));

        const actorDoc = await db.collection(COLLECTIONS.USERS).doc(addedByUserId).get();
        const actorName = actorDoc.exists ? (actorDoc.data().displayName || 'Someone') : 'Someone';
        const followers = (actorDoc.exists ? actorDoc.data().followers : []) || [];

        let followerPushCount = 0;
        await Promise.all(followers
          .filter(fid => fid !== addedByUserId)
          .map(async (followerId) => {
            // Pure followers (not connections) also need the real-time feed
            // event; connection-followers already got it in the loop above.
            if (!allConnectionOtherIds.has(followerId)) {
              SSEService.sendEvent(followerId, {
                type: 'new_activity',
                data: {
                  type: 'place_added',
                  actorId: addedByUserId,
                  entityType: 'place',
                  entityId: placeId,
                  entityName: placeName || 'Unknown Place',
                  timestamp: new Date().toISOString()
                }
              });
            }
            // Push once: skip anyone the connection loop already pushed.
            if (alreadyPushedIds.has(followerId)) return;
            try {
              await notificationService.sendToUser(followerId, {
                type: 'activity_notification',
                title: 'New Place Added',
                body: `${actorName} added ${placeName} to ${circleName}`,
                data: {
                  type: 'place_added',
                  placeId: placeId,
                  circleId: circleId,
                  addedByUserId: addedByUserId,
                  deepLink: `circles://place/${placeId}?circleId=${circleId}`
                }
              });
              followerPushCount++;
            } catch (pushError) {
              console.warn('Failed to send follower place-add push:', pushError.message);
            }
          }));
        console.log(`✅ Notified ${followerPushCount} followers of place add by ${addedByUserId}`);
      } catch (followerError) {
        console.error('Follower notification failed:', followerError.message);
      }
    }

  } catch (error) {
    console.error('Error tracking place addition:', error);
  }
};


// Track when a user views a specific place
const trackPlaceView = async (viewerUserId, placeId, connectionUserId) => {
  try {
    // Find the connection between these users
    const [connectionSnapshot1, connectionSnapshot2] = await Promise.all([
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', viewerUserId)
        .where('connectedUserId', '==', connectionUserId)
        .where('status', '==', 'accepted')
        .limit(1)
        .get(),
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', connectionUserId)
        .where('connectedUserId', '==', viewerUserId)
        .where('status', '==', 'accepted')
        .limit(1)
        .get()
    ]);

    const connectionSnapshot = !connectionSnapshot1.empty ? connectionSnapshot1 : connectionSnapshot2;

    if (!connectionSnapshot.empty) {
      const connectionRef = connectionSnapshot.docs[0].ref;
      const connectionData = connectionSnapshot.docs[0].data();
      
      // Mark this specific place activity as viewed
      if (connectionData.recentActivity && connectionData.recentActivity.length > 0) {
        const updatedActivities = connectionData.recentActivity.map(activity => {
          if (activity.entityId === placeId && activity.type === 'place' && !activity.viewedAt) {
            return { ...activity, viewedAt: new Date().toISOString() };
          }
          return activity;
        });
        
        await connectionRef.update({
          recentActivity: updatedActivities,
          updatedAt: new Date().toISOString()
        });
        
        // Place marked as viewed
      }
    }
  } catch (error) {
    console.error('Error tracking place view:', error);
  }
};


// Track when a user likes a place
const trackPlaceLiked = async (placeId, placeName, circleId, circleName, likedByUserId, placeOwnerId) => {
  try {
    // Don't track if user likes their own place
    if (likedByUserId === placeOwnerId) {
      return;
    }

    // Create activity record (with the place thumbnail so the feed row shows it)
    const placePhoto = await resolvePlacePhoto(placeId);
    await createActivity(
      'place_liked',
      likedByUserId,
      'place',
      placeId,
      placeName,
      {
        placeId: placeId,
        placeName: placeName,
        placePhoto: placePhoto,
        circleId: circleId,
        circleName: circleName,
        likedByUserId: likedByUserId
      }
    );

    // Send real-time notification to place owner
    SSEService.sendEvent(placeOwnerId, {
      type: 'place_liked',
      data: {
        placeId: placeId,
        placeName: placeName,
        circleId: circleId,
        circleName: circleName,
        likedByUserId: likedByUserId,
        timestamp: new Date().toISOString()
      }
    });

    // Also send new_activity event for activity feed
    SSEService.sendEvent(placeOwnerId, {
      type: 'new_activity',
      data: {
        type: 'place_liked',
        actorId: likedByUserId,
        entityType: 'place',
        entityId: placeId,
        entityName: placeName,
        timestamp: new Date().toISOString()
      }
    });

    // Send activity to connections who have opted in
    const [connectionsSnapshot1, connectionsSnapshot2] = await Promise.all([
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('connectedUserId', '==', likedByUserId)
        .where('status', '==', 'accepted')
        .get(),
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', likedByUserId)
        .where('status', '==', 'accepted')
        .get()
    ]);
    
    const allConnections = [...connectionsSnapshot1.docs, ...connectionsSnapshot2.docs];
    
    allConnections.forEach(doc => {
      const connectionData = doc.data();
      const otherUserId = connectionData.userId === likedByUserId 
        ? connectionData.connectedUserId 
        : connectionData.userId;
      
      // Skip if this is the place owner (they already got the notification above)
      if (otherUserId === placeOwnerId) {
        return;
      }
      
      // Send SSE events for real-time updates
      SSEService.sendEvent(otherUserId, {
        type: 'connection_place_liked',
        data: {
          placeId: placeId,
          placeName: placeName,
          circleId: circleId,
          circleName: circleName,
          likedByUserId: likedByUserId,
          timestamp: new Date().toISOString()
        }
      });
      
      // Send push notification only if enabled for this connection
      if (connectionData.activityNotificationsEnabled === true) { // Explicit opt-in required
        (async () => {
          try {
            // Get liker's display name
            const likerDoc = await db.collection(COLLECTIONS.USERS).doc(likedByUserId).get();
            const likerName = likerDoc.exists ? likerDoc.data().displayName : 'Someone';
            
            await notificationService.sendToUser(otherUserId, {
              type: 'activity_notification',
              title: 'Connection Activity',
              body: `${likerName} liked a place: ${placeName}`,
              data: {
                type: 'place_liked',
                placeId: placeId,
                circleId: circleId,
                likedByUserId: likedByUserId,
                deepLink: `circles://place/${placeId}?circleId=${circleId}`
              }
            });
          } catch (notificationError) {
            console.warn('Failed to send place like connection push notification:', notificationError);
          }
        })();
      }
    });

    console.log(`✅ Tracked place like for ${placeName}`);
  } catch (error) {
    console.error('Error tracking place like:', error);
  }
};


// Track when a user discovers a new place (from search, recommendations, etc.)
const trackPlaceDiscovered = async (placeId, placeName, discoveredByUserId, discoverySource = 'search', metadata = {}) => {
  try {
    // Create activity record
    await createActivity(
      'place_discovered',
      discoveredByUserId,
      'place',
      placeId,
      placeName,
      {
        placeId: placeId,
        placeName: placeName,
        discoverySource: discoverySource, // 'search', 'recommendation', 'trending', 'nearby'
        ...metadata
      }
    );

    // Send activity to connections who have opted in
    const [connectionsSnapshot1, connectionsSnapshot2] = await Promise.all([
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('connectedUserId', '==', discoveredByUserId)
        .where('status', '==', 'accepted')
        .get(),
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', discoveredByUserId)
        .where('status', '==', 'accepted')
        .get()
    ]);
    
    const allConnections = [...connectionsSnapshot1.docs, ...connectionsSnapshot2.docs];
    
    allConnections.forEach(doc => {
      const connectionData = doc.data();
      const otherUserId = connectionData.userId === discoveredByUserId 
        ? connectionData.connectedUserId 
        : connectionData.userId;
      
      // Send SSE events for real-time updates
      SSEService.sendEvent(otherUserId, {
        type: 'connection_place_discovered',
        data: {
          placeId: placeId,
          placeName: placeName,
          discoveredByUserId: discoveredByUserId,
          discoverySource: discoverySource,
          timestamp: new Date().toISOString()
        }
      });
      
      // Send push notification only if enabled for this connection
      if (connectionData.activityNotificationsEnabled === true) { // Explicit opt-in required
        (async () => {
          try {
            // Get discoverer's display name
            const discovererDoc = await db.collection(COLLECTIONS.USERS).doc(discoveredByUserId).get();
            const discovererName = discovererDoc.exists ? discovererDoc.data().displayName : 'Someone';
            
            let sourceText = '';
            switch (discoverySource) {
              case 'search': sourceText = 'discovered'; break;
              case 'recommendation': sourceText = 'found through recommendations'; break;
              case 'trending': sourceText = 'found in trending places'; break;
              case 'nearby': sourceText = 'discovered nearby'; break;
              default: sourceText = 'discovered'; break;
            }
            
            await notificationService.sendToUser(otherUserId, {
              type: 'activity_notification',
              title: 'New Discovery',
              body: `${discovererName} ${sourceText}: ${placeName}`,
              data: {
                type: 'place_discovered',
                placeId: placeId,
                discoveredByUserId: discoveredByUserId,
                deepLink: `circles://place/${placeId}`
              }
            });
          } catch (notificationError) {
            console.warn('Failed to send place discovery push notification:', notificationError);
          }
        })();
      }
    });

    console.log(`✅ Tracked place discovery: ${placeName} via ${discoverySource}`);
  } catch (error) {
    console.error('Error tracking place discovery:', error);
  }
};


// Track when a user checks in to a place  
const trackCheckIn = async (placeId, placeName, circleId, circleName, checkedInByUserId) => {
  try {
    // Create activity record
    await createActivity(
      'check_in',
      checkedInByUserId,
      'place',
      placeId,
      placeName,
      {
        circleId: circleId,
        circleName: circleName
      }
    );
    
    // Send SSE events to connections
    const [connectionsSnapshot1, connectionsSnapshot2] = await Promise.all([
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('connectedUserId', '==', checkedInByUserId)
        .where('status', '==', 'accepted')
        .get(),
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', checkedInByUserId)
        .where('status', '==', 'accepted')
        .get()
    ]);
    
    const allConnections = [...connectionsSnapshot1.docs, ...connectionsSnapshot2.docs];
    
    allConnections.forEach(doc => {
      const connectionData = doc.data();
      const otherUserId = connectionData.userId === checkedInByUserId 
        ? connectionData.connectedUserId 
        : connectionData.userId;
      
      // Send SSE events to all connections (for real-time updates)
      SSEService.sendEvent(otherUserId, {
        type: 'check_in',
        data: {
          placeId: placeId,
          placeName: placeName,
          circleId: circleId,
          circleName: circleName,
          checkedInByUserId: checkedInByUserId,
          timestamp: new Date().toISOString()
        }
      });
      
      // Also send new_activity event
      SSEService.sendEvent(otherUserId, {
        type: 'new_activity',
        data: {
          type: 'check_in',
          actorId: checkedInByUserId,
          entityType: 'place',
          entityId: placeId,
          entityName: placeName,
          metadata: { circleId: circleId, circleName: circleName },
          timestamp: new Date().toISOString()
        }
      });
      
      // Send push notification only if enabled for this connection
      if (connectionData.activityNotificationsEnabled === true) { // Explicit opt-in required
        (async () => {
          try {
            // Get checker's display name
            const checkerDoc = await db.collection(COLLECTIONS.USERS).doc(checkedInByUserId).get();
            const checkerName = checkerDoc.exists ? checkerDoc.data().displayName : 'Someone';
            
            await notificationService.sendToUser(otherUserId, {
              type: 'activity_notification',
              title: 'Check-in Update',
              body: `${checkerName} checked in at ${placeName}`,
              data: {
                type: 'check_in',
                placeId: placeId,
                circleId: circleId,
                checkedInByUserId: checkedInByUserId,
                deepLink: `circles://place/${placeId}?circleId=${circleId}`
              }
            });
          } catch (notificationError) {
            console.warn('Failed to send check-in push notification:', notificationError);
          }
        })();
      }
    });
    
    console.log(`✅ Tracked check-in at ${placeName}`);
  } catch (error) {
    console.error('Error tracking check-in:', error);
  }
};


// Track when a user uploads a photo to a global place
const trackPhotoUploaded = async (photoId, placeId, placeName, photoUrl, uploadedByUserId) => {
  try {
    // Create activity record
    await createActivity(
      'photo_uploaded',
      uploadedByUserId,
      'place',
      placeId,
      placeName || 'Unknown Place',
      {
        placeId: placeId,
        placeName: placeName,
        placePhoto: photoUrl,
        photoId: photoId
      }
    );
    
    // Send SSE events to connections and followers
    const [connectionsSnapshot1, connectionsSnapshot2] = await Promise.all([
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('connectedUserId', '==', uploadedByUserId)
        .where('status', '==', 'accepted')
        .get(),
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', uploadedByUserId)
        .where('status', '==', 'accepted')
        .get()
    ]);
    
    const allConnections = [...connectionsSnapshot1.docs, ...connectionsSnapshot2.docs];
    
    allConnections.forEach(doc => {
      const connectionData = doc.data();
      const otherUserId = connectionData.userId === uploadedByUserId 
        ? connectionData.connectedUserId 
        : connectionData.userId;
      
      // Send photo uploaded event
      SSEService.sendEvent(otherUserId, {
        type: 'photo_uploaded',
        data: {
          photoId: photoId,
          placeId: placeId,
          placeName: placeName,
          photoUrl: photoUrl,
          uploadedByUserId: uploadedByUserId,
          timestamp: new Date().toISOString()
        }
      });
      
      // Also send new_activity event for activity feed
      SSEService.sendEvent(otherUserId, {
        type: 'new_activity',
        data: {
          type: 'photo_uploaded',
          actorId: uploadedByUserId,
          entityType: 'place',
          entityId: placeId,
          entityName: placeName,
          metadata: { placePhoto: photoUrl },
          timestamp: new Date().toISOString()
        }
      });
      
      // Send push notification if enabled for this connection
      if (connectionData.activityNotificationsEnabled === true) { // Explicit opt-in required
        (async () => {
          try {
            // Get uploader's display name
            const uploaderDoc = await db.collection(COLLECTIONS.USERS).doc(uploadedByUserId).get();
            const uploaderName = uploaderDoc.exists ? uploaderDoc.data().displayName : 'Someone';
            
            await notificationService.sendToUser(otherUserId, {
              type: 'activity_notification',
              title: 'New Photo Shared',
              body: `${uploaderName} uploaded a photo at ${placeName}`,
              data: {
                type: 'photo_uploaded',
                photoId: photoId,
                placeId: placeId,
                uploadedByUserId: uploadedByUserId,
                deepLink: `circles://place/${placeId}`
              }
            });
          } catch (notificationError) {
            console.warn('Failed to send photo upload push notification:', notificationError);
          }
        })();
      }
    });
    
    console.log(`✅ Tracked photo upload for place ${placeName}`);
  } catch (error) {
    console.error('Error tracking photo upload:', error);
  }
};


// Track when a user likes a Global Place upload
const trackGlobalPlaceLiked = async (uploadId, globalPlaceId, placeName, likedByUserId, uploadOwnerId, photoUrl = null) => {
  try {
    // Don't track if user likes their own upload
    if (likedByUserId === uploadOwnerId) {
      return;
    }

    // Create activity record
    await createActivity(
      'global_place_liked',
      likedByUserId,
      'global_place',
      uploadId,
      placeName,
      {
        uploadId: uploadId,
        globalPlaceId: globalPlaceId,
        placeName: placeName,
        likedByUserId: likedByUserId,
        // The liked photo doubles as the feed row's thumbnail
        placePhoto: photoUrl
      }
    );

    // Send real-time notification to upload owner
    SSEService.sendEvent(uploadOwnerId, {
      type: 'global_place_liked',
      data: {
        uploadId: uploadId,
        globalPlaceId: globalPlaceId,
        placeName: placeName,
        likedByUserId: likedByUserId,
        timestamp: new Date().toISOString()
      }
    });

    // Send activity to connections who have opted in
    const [connectionsSnapshot1, connectionsSnapshot2] = await Promise.all([
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('connectedUserId', '==', likedByUserId)
        .where('status', '==', 'accepted')
        .get(),
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', likedByUserId)
        .where('status', '==', 'accepted')
        .get()
    ]);
    
    const allConnections = [...connectionsSnapshot1.docs, ...connectionsSnapshot2.docs];
    
    allConnections.forEach(doc => {
      const connectionData = doc.data();
      const otherUserId = connectionData.userId === likedByUserId 
        ? connectionData.connectedUserId 
        : connectionData.userId;
      
      // Skip if this is the upload owner (they already got the notification above)
      if (otherUserId === uploadOwnerId) {
        return;
      }
      
      // Send SSE events for real-time updates
      SSEService.sendEvent(otherUserId, {
        type: 'connection_global_place_liked',
        data: {
          uploadId: uploadId,
          globalPlaceId: globalPlaceId,
          placeName: placeName,
          likedByUserId: likedByUserId,
          timestamp: new Date().toISOString()
        }
      });
      
      // Send push notification only if enabled for this connection
      if (connectionData.activityNotificationsEnabled === true) { // Explicit opt-in required
        (async () => {
          try {
            // Get liker's display name
            const likerDoc = await db.collection(COLLECTIONS.USERS).doc(likedByUserId).get();
            const likerName = likerDoc.exists ? likerDoc.data().displayName : 'Someone';
            
            await notificationService.sendToUser(otherUserId, {
              type: 'activity_notification',
              title: 'Connection Activity',
              body: `${likerName} liked a Global Place upload: ${placeName}`,
              data: {
                type: 'global_place_liked',
                uploadId: uploadId,
                globalPlaceId: globalPlaceId,
                likedByUserId: likedByUserId,
                deepLink: `circles://global-place/${globalPlaceId}`
              }
            });
          } catch (notificationError) {
            console.warn('Failed to send Global Place like connection push notification:', notificationError);
          }
        })();
      }
    });

    console.log(`✅ Tracked Global Place like for ${placeName}`);
  } catch (error) {
    console.error('Error tracking Global Place like:', error);
  }
};


// Mark a specific place as viewed
const markPlaceAsViewed = async (userId, placeId, circleId) => {
  try {
    // Get all connections for this user
    const [connectionsSnapshot1, connectionsSnapshot2] = await Promise.all([
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', userId)
        .where('status', '==', 'accepted')
        .get(),
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('connectedUserId', '==', userId)
        .where('status', '==', 'accepted')
        .get()
    ]);

    const batch = db.batch();
    const allConnections = [...connectionsSnapshot1.docs, ...connectionsSnapshot2.docs];
    let updateCount = 0;

    allConnections.forEach(doc => {
      const connectionData = doc.data();
      const recentActivity = connectionData.recentActivity || [];
      
      // Update activities for this place
      const updatedActivities = recentActivity.map(activity => {
        if (activity.type === 'place' && activity.entityId === placeId) {
          if (!activity.viewedBy || !activity.viewedBy.includes(userId)) {
            return {
              ...activity,
              viewedBy: [...(activity.viewedBy || []), userId]
            };
          }
        }
        return activity;
      });

      // Only update if something changed
      if (JSON.stringify(updatedActivities) !== JSON.stringify(recentActivity)) {
        batch.update(doc.ref, {
          recentActivity: updatedActivities,
          updatedAt: new Date().toISOString()
        });
        updateCount++;
      }
    });

    if (updateCount > 0) {
      await batch.commit();
      // Place marked as viewed
    }
  } catch (error) {
    console.error('Error marking place as viewed:', error);
  }
};

module.exports = {
  trackPlaceAdded,
  trackPlaceView,
  trackPlaceLiked,
  trackPlaceDiscovered,
  trackCheckIn,
  trackPhotoUploaded,
  trackGlobalPlaceLiked,
  markPlaceAsViewed,
};
