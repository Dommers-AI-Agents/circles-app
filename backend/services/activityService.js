// backend/services/activityService.js
// Service for tracking user activity and interactions

const { admin, getFirestore } = require('../config/firebase');
const { COLLECTIONS, serializeDoc } = require('../models/FirestoreModels');
const db = getFirestore();

// Import createActivity helper from activity controller
const { createActivity } = require('../controllers/activityController');

// Import SSE service for real-time notifications
const SSEService = require('./sseService');

// Import notification service for push notifications
const notificationService = require('./notificationService');

// Track when a user adds a new circle
const trackCircleCreated = async (circleId, createdByUserId) => {
  try {
    // Get circle details
    const circleDoc = await db.collection(COLLECTIONS.CIRCLES).doc(circleId).get();
    let circleName = 'Unknown Circle';
    let circlePrivacy = 'private';
    
    if (circleDoc.exists) {
      const circleData = circleDoc.data();
      circleName = circleData.name || 'Unknown Circle';
      circlePrivacy = circleData.privacy || 'private';
    }
    
    // Only create activity for public and myNetwork circles
    // Private circles should not generate activities
    if (circlePrivacy !== 'private') {
      // Create activity record in the activities collection
      await createActivity(
        'circle_created',
        createdByUserId,
        'circle',
        circleId,
        circleName,
        {
          circleId: circleId,
          circleName: circleName
        }
      );
    }

    // Only create connection activities and notifications for non-private circles
    if (circlePrivacy !== 'private') {
      // Get all connections of the user who created the circle (both directions)
      const [connectionsSnapshot1, connectionsSnapshot2] = await Promise.all([
        db.collection(COLLECTIONS.CONNECTIONS)
          .where('connectedUserId', '==', createdByUserId)
          .where('status', '==', 'accepted')
          .get(),
        db.collection(COLLECTIONS.CONNECTIONS)
          .where('userId', '==', createdByUserId)
          .where('status', '==', 'accepted')
          .get()
      ]);

      const batch = db.batch();
      const allConnections = [...connectionsSnapshot1.docs, ...connectionsSnapshot2.docs];
      
      allConnections.forEach(doc => {
        const connectionData = doc.data();
        const connectionRef = doc.ref;
        
        // Determine the other user's ID in this connection
        const otherUserId = connectionData.userId === createdByUserId 
          ? connectionData.connectedUserId 
          : connectionData.userId;
        
        // Check if this connection should see the activity based on circle privacy
        let shouldShowActivity = false;
        
        if (circlePrivacy === 'public') {
          // Public circles - all connections see the activity
          shouldShowActivity = true;
        } else if (circlePrivacy === 'myNetwork') {
          // My Network circles - all connections see the activity
          shouldShowActivity = true;
        }
        // Private circles already excluded above
        
        if (shouldShowActivity) {
          const activity = {
            type: 'circle',
            entityId: circleId,
            entityName: circleName,
            createdAt: new Date().toISOString(),
            viewedBy: [createdByUserId] // Creator has already "viewed" their own activity
          };
          
          // Update connection with new activity
          batch.update(connectionRef, {
            hasNewActivity: true,
            recentActivity: admin.firestore.FieldValue.arrayUnion(activity),
            updatedAt: new Date().toISOString()
          });
        }
      });

      await batch.commit();
      // Circle creation activity tracked
      
      // Send real-time SSE events to connections who should see this activity
      allConnections.forEach(async (doc) => {
        const connectionData = doc.data();
        const otherUserId = connectionData.userId === createdByUserId 
          ? connectionData.connectedUserId 
          : connectionData.userId;
        
        // Check if this connection should see the activity based on circle privacy
        let shouldShowActivity = false;
        if (circlePrivacy === 'public' || circlePrivacy === 'myNetwork') {
          shouldShowActivity = true;
        }
        
        if (shouldShowActivity) {
          // Send circle creation event
          SSEService.sendEvent(otherUserId, {
            type: 'circle_created',
            data: {
              circleId: circleId,
              circleName: circleName,
              createdByUserId: createdByUserId,
              connectionId: doc.id,
              timestamp: new Date().toISOString()
            }
          });
          
          // Also send connection activity event
          SSEService.sendEvent(otherUserId, {
            type: 'connection_activity',
            data: {
              connectionId: doc.id,
              activityType: 'circle',
              entityId: circleId,
              entityName: circleName,
              timestamp: new Date().toISOString()
            }
          });
          
          // Send push notification if enabled for this connection
          const connectionData = doc.data();
          if (connectionData.activityNotificationsEnabled === true) { // Explicit opt-in required
            try {
              // Get creator's display name
              const creatorDoc = await db.collection(COLLECTIONS.USERS).doc(createdByUserId).get();
              const creatorName = creatorDoc.exists ? creatorDoc.data().displayName : 'Someone';
              
              await notificationService.sendToUser(otherUserId, {
                type: 'activity_notification',
                title: 'New Circle Created',
                body: `${creatorName} created a new circle: ${circleName}`,
                data: {
                  type: 'circle_created',
                  circleId: circleId,
                  createdByUserId: createdByUserId,
                  deepLink: `circles://circle/${circleId}`
                }
              });
            } catch (notificationError) {
              console.warn('Failed to send circle creation push notification:', notificationError);
            }
          }
        }
      });
    }
    
  } catch (error) {
    console.error('Error tracking circle creation:', error);
  }
};

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
    const sharedWith = circleData.sharedWith || [];
    
    // Only create activity record for non-private circles
    if (circlePrivacy !== 'private') {
      // Create activity record in the activities collection
      const placeDoc = await db.collection(COLLECTIONS.PLACES).doc(placeId).get();
      let placePhoto = null;
      let placeAddress = null;
      
      if (placeDoc.exists) {
        const placeData = placeDoc.data();
        placePhoto = placeData.photos && placeData.photos.length > 0 ? placeData.photos[0] : null;
        placeAddress = placeData.address || null;
      }
      
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
      
      // Check if this connection should see the activity based on circle privacy
      let shouldShowActivity = false;
      
      if (circlePrivacy === 'public') {
        // Public circles - all connections see the activity
        shouldShowActivity = true;
      } else if (circlePrivacy === 'myNetwork') {
        // My Network circles - all connections see the activity
        shouldShowActivity = true;
      }
      // Private circles NEVER generate activities, per user requirements
      
      // Only update connections who should see this activity
      if (shouldShowActivity) {
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
      
      // Check if this connection should see the activity based on circle privacy  
      let shouldShowActivity = false;
      if (circlePrivacy === 'public' || circlePrivacy === 'myNetwork') {
        shouldShowActivity = true;
      }
      // Private circles NEVER generate SSE events, per user requirements
      
      if (shouldShowActivity) {
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
    
  } catch (error) {
    console.error('Error tracking place addition:', error);
  }
};

// Track when a user views another user's circles or profile
const trackConnectionView = async (viewerUserId, viewedUserId) => {
  try {
    // Find the connection between these users
    const connectionSnapshot = await db.collection(COLLECTIONS.CONNECTIONS)
      .where('userId', '==', viewerUserId)
      .where('connectedUserId', '==', viewedUserId)
      .where('status', '==', 'accepted')
      .limit(1)
      .get();

    if (!connectionSnapshot.empty) {
      const connectionRef = connectionSnapshot.docs[0].ref;
      const now = new Date().toISOString();
      
      await connectionRef.update({
        lastViewedAt: now,
        viewCount: admin.firestore.FieldValue.increment(1),
        updatedAt: now
      });
    }
  } catch (error) {
    console.error('Error tracking connection view:', error);
  }
};

// Clear activity notification (when user views the connection)
const clearActivityNotification = async (userId, connectedUserId) => {
  try {
    // Check both directions since connections can be stored either way
    const [connectionSnapshot1, connectionSnapshot2] = await Promise.all([
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', userId)
        .where('connectedUserId', '==', connectedUserId)
        .limit(1)
        .get(),
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', connectedUserId)
        .where('connectedUserId', '==', userId)
        .limit(1)
        .get()
    ]);

    // Update whichever direction exists
    const connectionSnapshot = !connectionSnapshot1.empty ? connectionSnapshot1 : connectionSnapshot2;

    if (!connectionSnapshot.empty) {
      const connectionRef = connectionSnapshot.docs[0].ref;
      
      // Mark all activities as viewed by this user
      const connectionData = connectionSnapshot.docs[0].data();
      const updatedActivities = (connectionData.recentActivity || []).map(activity => {
        // Add viewer to viewedBy array if not already present
        if (!activity.viewedBy || !activity.viewedBy.includes(userId)) {
          return {
            ...activity,
            viewedBy: [...(activity.viewedBy || []), userId]
          };
        }
        return activity;
      });
      
      await connectionRef.update({
        hasNewActivity: false,
        recentActivity: updatedActivities,
        updatedAt: new Date().toISOString()
      });
      
      // Activity notification cleared
    }
  } catch (error) {
    console.error('Error clearing activity notification:', error);
  }
};

// Get all connections with sorting by view count and place count
const getConnectionsWithStats = async (userId) => {
  try {
    // Get connections where user is either the requester or the target
    const connectionsQuery1 = db.collection(COLLECTIONS.CONNECTIONS)
      .where('userId', '==', userId)
      .where('status', '==', 'accepted');
      
    const connectionsQuery2 = db.collection(COLLECTIONS.CONNECTIONS)
      .where('connectedUserId', '==', userId)
      .where('status', '==', 'accepted');

    const [snapshot1, snapshot2] = await Promise.all([
      connectionsQuery1.get(),
      connectionsQuery2.get()
    ]);

    // Connections found

    // Combine results and remove duplicates
    const allDocs = [...snapshot1.docs, ...snapshot2.docs];
    const uniqueDocs = allDocs.filter((doc, index, self) => 
      index === self.findIndex(d => d.id === doc.id)
    );

    const connections = [];
    
    for (const doc of uniqueDocs) {
      const connectionData = doc.data();
      
      // Determine which user is the connected one
      const connectedUserId = connectionData.userId === userId 
        ? connectionData.connectedUserId 
        : connectionData.userId;
      
      // Get connected user details
      const userDoc = await db.collection(COLLECTIONS.USERS)
        .doc(connectedUserId)
        .get();
      
      if (userDoc.exists) {
        // Get total places count for this user
        const userCirclesSnapshot = await db.collection(COLLECTIONS.CIRCLES)
          .where('owner', '==', connectedUserId)
          .get();
        
        let totalPlaces = 0;
        for (const circleDoc of userCirclesSnapshot.docs) {
          const circleData = circleDoc.data();
          totalPlaces += (circleData.places || []).length;
        }
        
        // Check for unviewed activities (Instagram-style)
        const recentActivity = connectionData.recentActivity || [];
        const hasUnviewedActivity = recentActivity.some(activity => {
          // Check if this user hasn't viewed this activity yet
          const viewedBy = activity.viewedBy || [];
          return !viewedBy.includes(userId);
        });
        
        // Count unviewed activities by type
        const unviewedCounts = {
          places: 0,
          circles: 0,
          suggestions: 0
        };
        
        recentActivity.forEach(activity => {
          const viewedBy = activity.viewedBy || [];
          if (!viewedBy.includes(userId)) {
            if (activity.type === 'place') unviewedCounts.places++;
            else if (activity.type === 'circle') unviewedCounts.circles++;
            else if (activity.type === 'suggestion') unviewedCounts.suggestions++;
          }
        });
        
        // Calculate unviewed activities
        
        // Properly serialize the connection document
        const serializedConnection = serializeDoc(doc);
        const serializedUser = serializeDoc(userDoc);
        
        // Get last message info for this connection
        let lastMessageAt = null;
        let lastMessageSenderId = null;
        let hasRecentMessage = false;
        
        // Find conversations between current user and connected user
        const conversationQuery1 = db.collection(COLLECTIONS.CONVERSATIONS)
          .where('type', '==', 'direct')
          .where('participants', 'array-contains', userId)
          .get();
          
        const conversationSnapshot = await conversationQuery1;
        
        // Filter to find conversation with this specific connected user
        const conversation = conversationSnapshot.docs.find(doc => {
          const data = doc.data();
          return data.participants.includes(connectedUserId);
        });
        
        if (conversation) {
          const convData = conversation.data();
          if (convData.lastMessageTime) {
            lastMessageAt = convData.lastMessageTime;
            lastMessageSenderId = convData.lastMessageSenderId || null;
            
            // Check if message is recent (within last 7 days)
            const messageDate = new Date(convData.lastMessageTime);
            const sevenDaysAgo = new Date();
            sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7);
            hasRecentMessage = messageDate > sevenDaysAgo;
          }
        }
        
        // Ensure all fields have defaults for backwards compatibility
        connections.push({
          ...serializedConnection,
          connectedUser: serializedUser,
          totalPlaces: totalPlaces,
          hasRecentPlace: hasUnviewedActivity, // Now means hasUnviewedActivity
          hasUnviewedActivity: hasUnviewedActivity,
          unviewedCounts: unviewedCounts,
          viewCount: serializedConnection.viewCount || 0,
          recentActivity: serializedConnection.recentActivity || [],
          hasNewActivity: serializedConnection.hasNewActivity || false,
          lastViewedAt: serializedConnection.lastViewedAt || null,
          lastMessageAt: lastMessageAt,
          lastMessageSenderId: lastMessageSenderId,
          hasRecentMessage: hasRecentMessage
        });
      }
    }

    // Sort connections by criteria - messages first, then activity
    connections.sort((a, b) => {
      // First priority: recent messages (most recent first)
      if (a.lastMessageAt && b.lastMessageAt) {
        // Both have messages - sort by most recent
        return new Date(b.lastMessageAt) - new Date(a.lastMessageAt);
      } else if (a.lastMessageAt) {
        return -1; // a has messages, b doesn't - a comes first
      } else if (b.lastMessageAt) {
        return 1; // b has messages, a doesn't - b comes first
      }
      
      // Second priority: unviewed activity
      const aHasActivity = a.hasUnviewedActivity;
      const bHasActivity = b.hasUnviewedActivity;
      if (aHasActivity !== bHasActivity) {
        return aHasActivity ? -1 : 1;
      }
      
      // Third priority: view count (only if user has viewed them)
      if ((a.viewCount > 0 || b.viewCount > 0) && a.viewCount !== b.viewCount) {
        return b.viewCount - a.viewCount;
      }
      
      // Fourth priority: total places count
      if (a.totalPlaces !== b.totalPlaces) {
        return b.totalPlaces - a.totalPlaces;
      }
      
      // Final: alphabetical by name
      const nameA = a.connectedUser.displayName || '';
      const nameB = b.connectedUser.displayName || '';
      return nameA.localeCompare(nameB);
    });

    return connections;
  } catch (error) {
    console.error('Error getting connections with stats:', error);
    return [];
  }
};

// Clean up old activity records (run periodically)
const cleanupOldActivity = async (daysToKeep = 30) => {
  try {
    const cutoffDate = new Date();
    cutoffDate.setDate(cutoffDate.getDate() - daysToKeep);
    const cutoffDateStr = cutoffDate.toISOString();

    const connectionsSnapshot = await db.collection(COLLECTIONS.CONNECTIONS)
      .where('recentActivity', '!=', [])
      .get();

    const batch = db.batch();
    let updateCount = 0;

    connectionsSnapshot.docs.forEach(doc => {
      const data = doc.data();
      if (data.recentActivity && data.recentActivity.length > 0) {
        const filteredActivity = data.recentActivity.filter(
          activity => activity.createdAt > cutoffDateStr
        );
        
        if (filteredActivity.length !== data.recentActivity.length) {
          batch.update(doc.ref, {
            recentActivity: filteredActivity,
            updatedAt: new Date().toISOString()
          });
          updateCount++;
        }
      }
    });

    if (updateCount > 0) {
      await batch.commit();
      // Old activity cleaned up
    }
  } catch (error) {
    console.error('Error cleaning up old activity:', error);
  }
};

// Track when a user views a circle with new places
const trackCircleView = async (viewerUserId, circleId, connectionUserId) => {
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
      
      // Mark activities for this circle as viewed
      if (connectionData.recentActivity && connectionData.recentActivity.length > 0) {
        const updatedActivities = connectionData.recentActivity.map(activity => {
          if (activity.circleId === circleId && activity.type === 'place' && !activity.viewedAt) {
            return { ...activity, viewedAt: new Date().toISOString() };
          }
          return activity;
        });
        
        await connectionRef.update({
          recentActivity: updatedActivities,
          updatedAt: new Date().toISOString()
        });
        
        // Circle activities marked as viewed
      }
    }
  } catch (error) {
    console.error('Error tracking circle view:', error);
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

// Track when a user likes a circle
const trackCircleLiked = async (circleId, likedByUserId, circleOwnerId) => {
  try {
    // Don't track if user likes their own circle
    if (likedByUserId === circleOwnerId) {
      return;
    }

    // Get circle details and privacy settings
    const circleDoc = await db.collection(COLLECTIONS.CIRCLES).doc(circleId).get();
    let circleName = 'Unknown Circle';
    let circlePrivacy = 'private';
    
    if (circleDoc.exists) {
      const circleData = circleDoc.data();
      circleName = circleData.name || 'Unknown Circle';
      circlePrivacy = circleData.privacy || 'private';
    }

    // Only track likes for public and myNetwork circles
    // Private circles should never generate like activities
    if (circlePrivacy !== 'private') {
      // Create activity record
      await createActivity(
        'circle_liked',
        likedByUserId,
        'circle',
        circleId,
        circleName,
        {
          circleId: circleId,
          circleName: circleName,
          likedByUserId: likedByUserId
        }
      );

      // Send real-time notification to circle owner
      SSEService.sendEvent(circleOwnerId, {
        type: 'circle_liked',
        data: {
          circleId: circleId,
          circleName: circleName,
          likedByUserId: likedByUserId,
          timestamp: new Date().toISOString()
        }
      });

      // Circle like activity tracked
    }
  } catch (error) {
    console.error('Error tracking circle like:', error);
  }
};

// Track when a user comments on a circle
const trackCircleCommented = async (circleId, commentedByUserId, circleOwnerId, commentText) => {
  try {
    // Don't track if user comments on their own circle
    if (commentedByUserId === circleOwnerId) {
      return;
    }

    // Get circle details and privacy settings
    const circleDoc = await db.collection(COLLECTIONS.CIRCLES).doc(circleId).get();
    let circleName = 'Unknown Circle';
    let circlePrivacy = 'private';
    
    if (circleDoc.exists) {
      const circleData = circleDoc.data();
      circleName = circleData.name || 'Unknown Circle';
      circlePrivacy = circleData.privacy || 'private';
    }

    // Only track comments for public and myNetwork circles
    // Private circles should never generate comment activities
    if (circlePrivacy !== 'private') {
      // Create activity record
      await createActivity(
        'circle_commented',
        commentedByUserId,
        'circle',
        circleId,
        circleName,
        {
          circleId: circleId,
          circleName: circleName,
          commentedByUserId: commentedByUserId,
          commentText: commentText.substring(0, 100) // Truncate long comments
        }
      );

      // Send real-time notification to circle owner
      SSEService.sendEvent(circleOwnerId, {
        type: 'circle_commented',
        data: {
          circleId: circleId,
          circleName: circleName,
          commentedByUserId: commentedByUserId,
          commentText: commentText.substring(0, 100),
          timestamp: new Date().toISOString()
        }
      });

      // Circle comment activity tracked
    }
  } catch (error) {
    console.error('Error tracking circle comment:', error);
  }
};

// Mark a specific circle's activities as viewed
const markCircleActivitiesAsViewed = async (userId, circleId) => {
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
      
      // Update activities for this circle
      const updatedActivities = recentActivity.map(activity => {
        // Mark place activities in this circle as viewed
        if (activity.type === 'place' && activity.circleId === circleId) {
          if (!activity.viewedBy || !activity.viewedBy.includes(userId)) {
            return {
              ...activity,
              viewedBy: [...(activity.viewedBy || []), userId]
            };
          }
        }
        // Mark circle creation activity as viewed
        else if (activity.type === 'circle' && activity.entityId === circleId) {
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
      // Circle activities marked as viewed
    }
  } catch (error) {
    console.error('Error marking circle activities as viewed:', error);
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

// General activity logging for various types
const logActivity = async (activityData) => {
  try {
    const { type, actorId, visibility = 'connections', ...metadata } = activityData;
    
    const activityDoc = {
      type,
      actorId,
      visibility,
      metadata,
      createdAt: new Date().toISOString()
    };
    
    // Save to activities collection
    await db.collection(COLLECTIONS.ACTIVITIES).add(activityDoc);
    
    // If visibility is connections, update connection documents
    if (visibility === 'connections') {
      // Get all connections of the actor
      const [connections1, connections2] = await Promise.all([
        db.collection(COLLECTIONS.CONNECTIONS)
          .where('userId', '==', actorId)
          .where('status', '==', 'accepted')
          .get(),
        db.collection(COLLECTIONS.CONNECTIONS)
          .where('connectedUserId', '==', actorId)
          .where('status', '==', 'accepted')
          .get()
      ]);
      
      const batch = db.batch();
      const allConnections = [...connections1.docs, ...connections2.docs];
      
      allConnections.forEach(doc => {
        const connectionData = doc.data();
        const connectionRef = doc.ref;
        
        // Determine the other user's ID
        const otherUserId = connectionData.userId === actorId 
          ? connectionData.connectedUserId 
          : connectionData.userId;
        
        const activity = {
          type,
          ...metadata,
          actorId,
          createdAt: new Date().toISOString(),
          viewedBy: [actorId]
        };
        
        // Update connection with new activity
        batch.update(connectionRef, {
          hasNewActivity: true,
          recentActivity: admin.firestore.FieldValue.arrayUnion(activity),
          updatedAt: new Date().toISOString()
        });
      });
      
      await batch.commit();
    }
    
    console.log(`✅ Logged ${type} activity for user ${actorId}`);
  } catch (error) {
    console.error('Error logging activity:', error);
    throw error;
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

// Track when a user uploads a moment/video
const trackMomentUpload = async (momentId, placeId, placeName, uploadedByUserId) => {
  try {
    // Create activity record
    await createActivity(
      'video_uploaded',
      uploadedByUserId,
      'moment',
      momentId,
      placeName || 'Unknown Place',
      {
        placeId: placeId,
        placeName: placeName
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
      
      // Send moment uploaded event
      SSEService.sendEvent(otherUserId, {
        type: 'moment_uploaded',
        data: {
          momentId: momentId,
          placeId: placeId,
          placeName: placeName,
          uploadedByUserId: uploadedByUserId,
          timestamp: new Date().toISOString()
        }
      });
      
      // Also send new_activity event for activity feed
      SSEService.sendEvent(otherUserId, {
        type: 'new_activity',
        data: {
          type: 'moment_uploaded',
          actorId: uploadedByUserId,
          entityType: 'moment',
          entityId: momentId,
          entityName: placeName,
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
              title: 'New Moment Shared',
              body: `${uploaderName} shared a moment at ${placeName}`,
              data: {
                type: 'moment_uploaded',
                momentId: momentId,
                placeId: placeId,
                uploadedByUserId: uploadedByUserId,
                deepLink: `circles://moment/${momentId}`
              }
            });
          } catch (notificationError) {
            console.warn('Failed to send moment upload push notification:', notificationError);
          }
        })();
      }
    });
    
    console.log(`✅ Tracked moment upload for place ${placeName}`);
  } catch (error) {
    console.error('Error tracking moment upload:', error);
  }
};

// Track when a user adds a reaction
const trackReaction = async (targetType, targetId, targetName, reaction, reactedByUserId) => {
  try {
    // Create activity record
    await createActivity(
      'reaction_added',
      reactedByUserId,
      targetType, // 'circle', 'place', 'comment', etc.
      targetId,
      targetName,
      {
        reaction: reaction
      }
    );
    
    // Send SSE events to connections
    const [connectionsSnapshot1, connectionsSnapshot2] = await Promise.all([
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('connectedUserId', '==', reactedByUserId)
        .where('status', '==', 'accepted')
        .get(),
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', reactedByUserId)
        .where('status', '==', 'accepted')
        .get()
    ]);
    
    const allConnections = [...connectionsSnapshot1.docs, ...connectionsSnapshot2.docs];
    
    allConnections.forEach(doc => {
      const connectionData = doc.data();
      const otherUserId = connectionData.userId === reactedByUserId 
        ? connectionData.connectedUserId 
        : connectionData.userId;
      
      SSEService.sendEvent(otherUserId, {
        type: 'reaction_added',
        data: {
          targetType: targetType,
          targetId: targetId,
          targetName: targetName,
          reaction: reaction,
          reactedByUserId: reactedByUserId,
          timestamp: new Date().toISOString()
        }
      });
      
      // Also send new_activity event
      SSEService.sendEvent(otherUserId, {
        type: 'new_activity',
        data: {
          type: 'reaction_added',
          actorId: reactedByUserId,
          entityType: targetType,
          entityId: targetId,
          entityName: targetName,
          metadata: { reaction: reaction },
          timestamp: new Date().toISOString()
        }
      });
    });
    
    console.log(`✅ Tracked reaction ${reaction} on ${targetType}`);
  } catch (error) {
    console.error('Error tracking reaction:', error);
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

// Track when a user adds a comment
const trackComment = async (targetType, targetId, targetName, commentId, commentText, commentedByUserId) => {
  try {
    // Create activity record
    await createActivity(
      'comment_added',
      commentedByUserId,
      targetType, // 'circle', 'place', 'moment'
      targetId,
      targetName,
      {
        commentId: commentId,
        commentPreview: commentText.substring(0, 100) // First 100 chars
      }
    );
    
    // Send SSE events to connections
    const [connectionsSnapshot1, connectionsSnapshot2] = await Promise.all([
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('connectedUserId', '==', commentedByUserId)
        .where('status', '==', 'accepted')
        .get(),
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', commentedByUserId)
        .where('status', '==', 'accepted')
        .get()
    ]);
    
    const allConnections = [...connectionsSnapshot1.docs, ...connectionsSnapshot2.docs];
    
    allConnections.forEach(doc => {
      const connectionData = doc.data();
      const otherUserId = connectionData.userId === commentedByUserId 
        ? connectionData.connectedUserId 
        : connectionData.userId;
      
      SSEService.sendEvent(otherUserId, {
        type: 'comment_added',
        data: {
          targetType: targetType,
          targetId: targetId,
          targetName: targetName,
          commentId: commentId,
          commentPreview: commentText.substring(0, 100),
          commentedByUserId: commentedByUserId,
          timestamp: new Date().toISOString()
        }
      });
      
      // Also send new_activity event
      SSEService.sendEvent(otherUserId, {
        type: 'new_activity',
        data: {
          type: 'comment_added',
          actorId: commentedByUserId,
          entityType: targetType,
          entityId: targetId,
          entityName: targetName,
          metadata: { commentPreview: commentText.substring(0, 100) },
          timestamp: new Date().toISOString()
        }
      });
    });
    
    console.log(`✅ Tracked comment on ${targetType}`);
  } catch (error) {
    console.error('Error tracking comment:', error);
  }
};

// Track when a user likes a place
const trackPlaceLiked = async (placeId, placeName, circleId, circleName, likedByUserId, placeOwnerId) => {
  try {
    // Don't track if user likes their own place
    if (likedByUserId === placeOwnerId) {
      return;
    }

    // Create activity record
    await createActivity(
      'place_liked',
      likedByUserId,
      'place',
      placeId,
      placeName,
      {
        placeId: placeId,
        placeName: placeName,
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

// Track when a user likes a video/moment
const trackVideoLiked = async (videoId, placeId, placeName, likedByUserId, videoOwnerId) => {
  try {
    // Don't track if user likes their own video
    if (likedByUserId === videoOwnerId) {
      return;
    }

    // Create activity record
    await createActivity(
      'video_liked',
      likedByUserId,
      'video',
      videoId,
      `Moment at ${placeName}`,
      {
        videoId: videoId,
        placeId: placeId,
        placeName: placeName,
        likedByUserId: likedByUserId
      }
    );

    // Send real-time notification to video owner
    SSEService.sendEvent(videoOwnerId, {
      type: 'video_liked',
      data: {
        videoId: videoId,
        placeId: placeId,
        placeName: placeName,
        likedByUserId: likedByUserId,
        timestamp: new Date().toISOString()
      }
    });

    // Also send new_activity event for activity feed
    SSEService.sendEvent(videoOwnerId, {
      type: 'new_activity',
      data: {
        type: 'video_liked',
        actorId: likedByUserId,
        entityType: 'video',
        entityId: videoId,
        entityName: `Moment at ${placeName}`,
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
      
      // Skip if this is the video owner (they already got the notification above)
      if (otherUserId === videoOwnerId) {
        return;
      }
      
      // Send SSE events for real-time updates
      SSEService.sendEvent(otherUserId, {
        type: 'connection_video_liked',
        data: {
          videoId: videoId,
          placeId: placeId,
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
              body: `${likerName} liked a moment at ${placeName}`,
              data: {
                type: 'video_liked',
                videoId: videoId,
                placeId: placeId,
                likedByUserId: likedByUserId,
                deepLink: `circles://moment/${videoId}`
              }
            });
          } catch (notificationError) {
            console.warn('Failed to send video like connection push notification:', notificationError);
          }
        })();
      }
    });

    console.log(`✅ Tracked video like for moment at ${placeName}`);
  } catch (error) {
    console.error('Error tracking video like:', error);
  }
};

// Track when a user likes a Global Place upload
const trackGlobalPlaceLiked = async (uploadId, globalPlaceId, placeName, likedByUserId, uploadOwnerId) => {
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
        likedByUserId: likedByUserId
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

// ===========================================================================
// PHASE 5: DISCOVERY ACTIVITIES - New place suggestions and discovery features
// ===========================================================================

// Track when a user sends a place suggestion to another user
const trackSuggestionSent = async (suggestionId, placeId, placeName, fromUserId, toUserId, message = null) => {
  try {
    // Create activity record
    await createActivity(
      'suggestion_sent',
      fromUserId,
      'suggestion',
      suggestionId,
      placeName,
      {
        suggestionId: suggestionId,
        placeId: placeId,
        placeName: placeName,
        toUserId: toUserId,
        message: message ? message.substring(0, 100) : null
      }
    );

    // Send real-time notification to recipient
    SSEService.sendEvent(toUserId, {
      type: 'suggestion_received',
      data: {
        suggestionId: suggestionId,
        placeId: placeId,
        placeName: placeName,
        fromUserId: fromUserId,
        message: message,
        timestamp: new Date().toISOString()
      }
    });

    // Send activity to connections who have opted in
    const [connectionsSnapshot1, connectionsSnapshot2] = await Promise.all([
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('connectedUserId', '==', fromUserId)
        .where('status', '==', 'accepted')
        .get(),
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', fromUserId)
        .where('status', '==', 'accepted')
        .get()
    ]);
    
    const allConnections = [...connectionsSnapshot1.docs, ...connectionsSnapshot2.docs];
    
    allConnections.forEach(doc => {
      const connectionData = doc.data();
      const otherUserId = connectionData.userId === fromUserId 
        ? connectionData.connectedUserId 
        : connectionData.userId;
      
      // Skip if this is the suggestion recipient (they already got the direct notification above)
      if (otherUserId === toUserId) {
        return;
      }
      
      // Send SSE events for real-time updates to other connections
      SSEService.sendEvent(otherUserId, {
        type: 'connection_suggestion_sent',
        data: {
          suggestionId: suggestionId,
          placeId: placeId,
          placeName: placeName,
          fromUserId: fromUserId,
          toUserId: toUserId,
          timestamp: new Date().toISOString()
        }
      });
      
      // Send push notification only if enabled for this connection
      if (connectionData.activityNotificationsEnabled === true) { // Explicit opt-in required
        (async () => {
          try {
            // Get sender's display name
            const senderDoc = await db.collection(COLLECTIONS.USERS).doc(fromUserId).get();
            const senderName = senderDoc.exists ? senderDoc.data().displayName : 'Someone';
            
            // Get recipient's display name
            const recipientDoc = await db.collection(COLLECTIONS.USERS).doc(toUserId).get();
            const recipientName = recipientDoc.exists ? recipientDoc.data().displayName : 'someone';
            
            await notificationService.sendToUser(otherUserId, {
              type: 'activity_notification',
              title: 'Connection Activity',
              body: `${senderName} suggested ${placeName} to ${recipientName}`,
              data: {
                type: 'suggestion_sent',
                suggestionId: suggestionId,
                placeId: placeId,
                fromUserId: fromUserId,
                deepLink: `circles://place/${placeId}`
              }
            });
          } catch (notificationError) {
            console.warn('Failed to send suggestion activity push notification:', notificationError);
          }
        })();
      }
    });

    // Send push notification to suggestion recipient (always)
    try {
      const senderDoc = await db.collection(COLLECTIONS.USERS).doc(fromUserId).get();
      const senderName = senderDoc.exists ? senderDoc.data().displayName : 'Someone';
      
      await notificationService.sendToUser(toUserId, {
        type: 'suggestion_notification',
        title: 'New Place Suggestion',
        body: message 
          ? `${senderName} suggests ${placeName}: "${message.substring(0, 50)}..."`
          : `${senderName} suggests you check out ${placeName}`,
        data: {
          type: 'suggestion_received',
          suggestionId: suggestionId,
          placeId: placeId,
          fromUserId: fromUserId,
          deepLink: `circles://suggestion/${suggestionId}`
        }
      });
    } catch (notificationError) {
      console.warn('Failed to send suggestion push notification to recipient:', notificationError);
    }

    console.log(`✅ Tracked suggestion sent: ${placeName}`);
  } catch (error) {
    console.error('Error tracking suggestion sent:', error);
  }
};

// Track when a user accepts/acts on a place suggestion
const trackSuggestionAccepted = async (suggestionId, placeId, placeName, acceptedByUserId, suggestedByUserId) => {
  try {
    // Create activity record
    await createActivity(
      'suggestion_accepted',
      acceptedByUserId,
      'suggestion',
      suggestionId,
      placeName,
      {
        suggestionId: suggestionId,
        placeId: placeId,
        placeName: placeName,
        suggestedByUserId: suggestedByUserId
      }
    );

    // Send real-time notification to original suggester
    SSEService.sendEvent(suggestedByUserId, {
      type: 'suggestion_accepted',
      data: {
        suggestionId: suggestionId,
        placeId: placeId,
        placeName: placeName,
        acceptedByUserId: acceptedByUserId,
        timestamp: new Date().toISOString()
      }
    });

    // Send push notification to original suggester (always)
    try {
      const accepterDoc = await db.collection(COLLECTIONS.USERS).doc(acceptedByUserId).get();
      const accepterName = accepterDoc.exists ? accepterDoc.data().displayName : 'Someone';
      
      await notificationService.sendToUser(suggestedByUserId, {
        type: 'suggestion_feedback_notification',
        title: 'Suggestion Accepted!',
        body: `${accepterName} added your suggestion ${placeName} to their collection`,
        data: {
          type: 'suggestion_accepted',
          suggestionId: suggestionId,
          placeId: placeId,
          acceptedByUserId: acceptedByUserId,
          deepLink: `circles://place/${placeId}`
        }
      });
    } catch (notificationError) {
      console.warn('Failed to send suggestion accepted push notification:', notificationError);
    }

    console.log(`✅ Tracked suggestion accepted: ${placeName}`);
  } catch (error) {
    console.error('Error tracking suggestion accepted:', error);
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

// Track when a user follows/unfollows another user
const trackUserFollowed = async (followedUserId, followerUserId, action = 'followed') => {
  try {
    // Don't track if user follows themselves
    if (followedUserId === followerUserId) {
      return;
    }

    // Create activity record
    const activityType = action === 'followed' ? 'user_followed' : 'user_unfollowed';
    
    // Get followed user's display name
    const followedUserDoc = await db.collection(COLLECTIONS.USERS).doc(followedUserId).get();
    const followedUserName = followedUserDoc.exists ? followedUserDoc.data().displayName : 'Unknown User';
    
    await createActivity(
      activityType,
      followerUserId,
      'user',
      followedUserId,
      followedUserName,
      {
        followedUserId: followedUserId,
        followerUserId: followerUserId,
        action: action
      }
    );

    // Send real-time notification to followed user (only for follows, not unfollows)
    if (action === 'followed') {
      SSEService.sendEvent(followedUserId, {
        type: 'user_followed',
        data: {
          followedUserId: followedUserId,
          followerUserId: followerUserId,
          timestamp: new Date().toISOString()
        }
      });

      // Send push notification to followed user (always for follows)
      try {
        const followerDoc = await db.collection(COLLECTIONS.USERS).doc(followerUserId).get();
        const followerName = followerDoc.exists ? followerDoc.data().displayName : 'Someone';
        
        await notificationService.sendToUser(followedUserId, {
          type: 'social_notification',
          title: 'New Follower',
          body: `${followerName} started following you`,
          data: {
            type: 'user_followed',
            followerUserId: followerUserId,
            deepLink: `circles://profile/${followerUserId}`
          }
        });
      } catch (notificationError) {
        console.warn('Failed to send follow push notification:', notificationError);
      }
    }

    // Send activity to mutual connections who have opted in
    const [connectionsSnapshot1, connectionsSnapshot2] = await Promise.all([
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('connectedUserId', '==', followerUserId)
        .where('status', '==', 'accepted')
        .get(),
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', followerUserId)
        .where('status', '==', 'accepted')
        .get()
    ]);
    
    const allConnections = [...connectionsSnapshot1.docs, ...connectionsSnapshot2.docs];
    
    allConnections.forEach(doc => {
      const connectionData = doc.data();
      const otherUserId = connectionData.userId === followerUserId 
        ? connectionData.connectedUserId 
        : connectionData.userId;
      
      // Skip if this is the followed user (they already got the direct notification above)
      if (otherUserId === followedUserId) {
        return;
      }
      
      // Send SSE events for real-time updates to mutual connections
      SSEService.sendEvent(otherUserId, {
        type: 'connection_user_followed',
        data: {
          followedUserId: followedUserId,
          followerUserId: followerUserId,
          action: action,
          timestamp: new Date().toISOString()
        }
      });
      
      // Send push notification only if enabled for this connection and it's a follow
      if (connectionData.activityNotificationsEnabled === true && action === 'followed') { // Explicit opt-in required
        (async () => {
          try {
            // Get both users' display names
            const followerDoc = await db.collection(COLLECTIONS.USERS).doc(followerUserId).get();
            const followerName = followerDoc.exists ? followerDoc.data().displayName : 'Someone';
            
            await notificationService.sendToUser(otherUserId, {
              type: 'activity_notification',
              title: 'Connection Activity',
              body: `${followerName} started following ${followedUserName}`,
              data: {
                type: 'user_followed',
                followedUserId: followedUserId,
                followerUserId: followerUserId,
                deepLink: `circles://profile/${followedUserId}`
              }
            });
          } catch (notificationError) {
            console.warn('Failed to send follow activity push notification:', notificationError);
          }
        })();
      }
    });

    console.log(`✅ Tracked user ${action}: ${followedUserName}`);
  } catch (error) {
    console.error(`Error tracking user ${action}:`, error);
  }
};

// Track when a user updates their profile (bio, picture, etc.)
const trackProfileUpdated = async (userId, updateType = 'profile', updateDetails = {}) => {
  try {
    // Get user's display name
    const userDoc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
    const userName = userDoc.exists ? userDoc.data().displayName : 'Unknown User';
    
    // Create activity record
    await createActivity(
      'profile_updated',
      userId,
      'user',
      userId,
      userName,
      {
        updateType: updateType, // 'bio', 'picture', 'name', 'general'
        ...updateDetails
      }
    );

    // Send activity to connections who have opted in
    const [connectionsSnapshot1, connectionsSnapshot2] = await Promise.all([
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('connectedUserId', '==', userId)
        .where('status', '==', 'accepted')
        .get(),
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', userId)
        .where('status', '==', 'accepted')
        .get()
    ]);
    
    const allConnections = [...connectionsSnapshot1.docs, ...connectionsSnapshot2.docs];
    
    allConnections.forEach(doc => {
      const connectionData = doc.data();
      const otherUserId = connectionData.userId === userId 
        ? connectionData.connectedUserId 
        : connectionData.userId;
      
      // Send SSE events for real-time updates
      SSEService.sendEvent(otherUserId, {
        type: 'connection_profile_updated',
        data: {
          userId: userId,
          userName: userName,
          updateType: updateType,
          timestamp: new Date().toISOString()
        }
      });
      
      // Send push notification only if enabled for this connection
      if (connectionData.activityNotificationsEnabled === true) { // Explicit opt-in required
        (async () => {
          try {
            let updateText = '';
            switch (updateType) {
              case 'bio': updateText = 'updated their bio'; break;
              case 'picture': updateText = 'updated their profile picture'; break;
              case 'name': updateText = 'updated their name'; break;
              default: updateText = 'updated their profile'; break;
            }
            
            await notificationService.sendToUser(otherUserId, {
              type: 'activity_notification',
              title: 'Profile Update',
              body: `${userName} ${updateText}`,
              data: {
                type: 'profile_updated',
                userId: userId,
                updateType: updateType,
                deepLink: `circles://profile/${userId}`
              }
            });
          } catch (notificationError) {
            console.warn('Failed to send profile update push notification:', notificationError);
          }
        })();
      }
    });

    console.log(`✅ Tracked profile update: ${updateType} for ${userName}`);
  } catch (error) {
    console.error('Error tracking profile update:', error);
  }
};

// Track when a user joins a new circle or becomes active after a period
const trackUserActivity = async (userId, activityType = 'active', metadata = {}) => {
  try {
    // Get user's display name
    const userDoc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
    const userName = userDoc.exists ? userDoc.data().displayName : 'Unknown User';
    
    // Create activity record
    await createActivity(
      'user_activity',
      userId,
      'user',
      userId,
      userName,
      {
        activityType: activityType, // 'active', 'joined', 'milestone'
        ...metadata
      }
    );

    // Send activity to connections who have opted in (only for significant activities)
    if (['joined', 'milestone'].includes(activityType)) {
      const [connectionsSnapshot1, connectionsSnapshot2] = await Promise.all([
        db.collection(COLLECTIONS.CONNECTIONS)
          .where('connectedUserId', '==', userId)
          .where('status', '==', 'accepted')
          .get(),
        db.collection(COLLECTIONS.CONNECTIONS)
          .where('userId', '==', userId)
          .where('status', '==', 'accepted')
          .get()
      ]);
      
      const allConnections = [...connectionsSnapshot1.docs, ...connectionsSnapshot2.docs];
      
      allConnections.forEach(doc => {
        const connectionData = doc.data();
        const otherUserId = connectionData.userId === userId 
          ? connectionData.connectedUserId 
          : connectionData.userId;
        
        // Send SSE events for real-time updates
        SSEService.sendEvent(otherUserId, {
          type: 'connection_user_activity',
          data: {
            userId: userId,
            userName: userName,
            activityType: activityType,
            metadata: metadata,
            timestamp: new Date().toISOString()
          }
        });
        
        // Send push notification only if enabled for this connection
        if (connectionData.activityNotificationsEnabled === true) { // Explicit opt-in required
          (async () => {
            try {
              let activityText = '';
              switch (activityType) {
                case 'joined': activityText = 'joined Circles'; break;
                case 'milestone': 
                  const milestone = metadata.milestone || 'achievement';
                  activityText = `reached a new ${milestone}`;
                  break;
                default: activityText = 'became active'; break;
              }
              
              await notificationService.sendToUser(otherUserId, {
                type: 'activity_notification',
                title: 'Connection Update',
                body: `${userName} ${activityText}`,
                data: {
                  type: 'user_activity',
                  userId: userId,
                  activityType: activityType,
                  deepLink: `circles://profile/${userId}`
                }
              });
            } catch (notificationError) {
              console.warn('Failed to send user activity push notification:', notificationError);
            }
          })();
        }
      });
    }

    console.log(`✅ Tracked user activity: ${activityType} for ${userName}`);
  } catch (error) {
    console.error('Error tracking user activity:', error);
  }
};

module.exports = {
  trackCircleCreated,
  trackPlaceAdded,
  trackConnectionView,
  trackCircleView,
  trackPlaceView,
  trackCircleLiked,
  trackCircleCommented,
  trackPhotoUploaded,
  trackMomentUpload,
  trackReaction,
  trackCheckIn,
  trackComment,
  trackPlaceLiked,
  trackVideoLiked,
  trackGlobalPlaceLiked,
  // Phase 5: Discovery Activities
  trackSuggestionSent,
  trackSuggestionAccepted,
  trackPlaceDiscovered,
  trackUserFollowed,
  trackProfileUpdated,
  trackUserActivity,
  clearActivityNotification,
  getConnectionsWithStats,
  cleanupOldActivity,
  markCircleActivitiesAsViewed,
  markPlaceAsViewed,
  logActivity
};