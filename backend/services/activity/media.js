// backend/services/activity/media.js
// Activity service — moment uploads and video likes.
// Split from services/activityService.js (Phase 6); that path is now a barrel.

const { getFirestore } = require('../../config/firebase');
const { COLLECTIONS } = require('../../models/FirestoreModels');
const db = getFirestore();
const { createActivity } = require('../../controllers/activityController');
const SSEService = require('../sseService');
const notificationService = require('../notificationService');


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


// Track when a user likes a video/moment
const trackVideoLiked = async (videoId, placeId, placeName, likedByUserId, videoOwnerId) => {
  try {
    // Don't track if user likes their own video
    if (likedByUserId === videoOwnerId) {
      return;
    }

    // One read for both the thumbnail and the moment's visibility. The
    // like activity is gated in the feed by the viewer's relationship to the
    // moment OWNER (not the liker) — only people who could also see the moment
    // should see that it was liked.
    const videoDoc = await db.collection(COLLECTIONS.PLACE_VIDEOS).doc(videoId).get();
    const videoThumbnail = videoDoc.exists ? (videoDoc.data().thumbnailUrl || null) : null;
    const momentVisibility = videoDoc.exists ? (videoDoc.data().visibility || 'public') : 'public';
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
        videoThumbnail: videoThumbnail,
        likedByUserId: likedByUserId,
        momentVisibility: momentVisibility,
        momentOwnerId: videoOwnerId
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

module.exports = {
  trackMomentUpload,
  trackVideoLiked,
};
