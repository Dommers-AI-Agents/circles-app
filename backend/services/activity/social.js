// backend/services/activity/social.js
// Activity service — reactions, comments, suggestions, follows, profile + generic user activity, connection views, and notification clearing.
// Split from services/activityService.js (Phase 6); that path is now a barrel.

const { admin, getFirestore } = require('../../config/firebase');
const { COLLECTIONS } = require('../../models/FirestoreModels');
const db = getFirestore();
const { createActivity } = require('../../controllers/activityController');
const SSEService = require('../sseService');
const notificationService = require('../notificationService');


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
// Mark a connection's activities as viewed by `userId`.
// `excludeTypes` leaves those activity types UNVIEWED — e.g. the connection
// profile view passes ['place'] so per-place "new" dots survive until the
// viewer actually opens the circle (see markCirclePlacesViewed). hasNewActivity
// then reflects whether anything the viewer hasn't seen still remains.
const clearActivityNotification = async (userId, connectedUserId, { excludeTypes = [] } = {}) => {
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

      const connectionData = connectionSnapshot.docs[0].data();
      const updatedActivities = (connectionData.recentActivity || []).map(activity => {
        // Leave excluded types unviewed (their dots persist until seen in context)
        if (excludeTypes.includes(activity.type)) return activity;
        // Add viewer to viewedBy array if not already present
        if (!activity.viewedBy || !activity.viewedBy.includes(userId)) {
          return {
            ...activity,
            viewedBy: [...(activity.viewedBy || []), userId]
          };
        }
        return activity;
      });

      // Banner stays lit only while something remains unseen for this viewer
      const stillUnviewed = updatedActivities.some(a => !(a.viewedBy || []).includes(userId));

      await connectionRef.update({
        hasNewActivity: stillUnviewed,
        recentActivity: updatedActivities,
        updatedAt: new Date().toISOString()
      });

      // Activity notification cleared
    }
  } catch (error) {
    console.error('Error clearing activity notification:', error);
  }
};

module.exports = {
  trackReaction,
  trackComment,
  trackSuggestionSent,
  trackSuggestionAccepted,
  trackUserFollowed,
  trackProfileUpdated,
  trackUserActivity,
  trackConnectionView,
  clearActivityNotification,
};
