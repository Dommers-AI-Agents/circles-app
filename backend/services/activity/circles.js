// backend/services/activity/circles.js
// Activity service — circle activities: created / viewed / liked / commented, and the viewed-markers for circles.
// Split from services/activityService.js (Phase 6); that path is now a barrel.

const { admin, getFirestore } = require('../../config/firebase');
const { COLLECTIONS } = require('../../models/FirestoreModels');
const db = getFirestore();
const { createActivity } = require('../../controllers/activityController');
const { circleAudience } = require('./audience');
const { normalizePrivacy, PRIVACY } = require('../visibility');
const SSEService = require('../sseService');
const notificationService = require('../notificationService');


// Track when a user adds a new circle
const trackCircleCreated = async (circleId, createdByUserId) => {
  try {
    // Get circle details
    const circleDoc = await db.collection(COLLECTIONS.CIRCLES).doc(circleId).get();
    let circleName = 'Unknown Circle';
    let circlePrivacy = 'private';
    let circleCover = null;

    let audience = { emits: false, allows: () => false };
    if (circleDoc.exists) {
      const circleData = circleDoc.data();
      circleName = circleData.name || 'Unknown Circle';
      circlePrivacy = circleData.privacy || 'private';
      circleCover = circleData.coverImage || null;
      audience = await circleAudience(circleData, circleData.owner || createdByUserId);
    }

    // Skip only when nobody but the owner could ever see it. An innerCircle
    // circle emits a row; the read gate narrows it to the owner's list.
    if (audience.emits) {
      // Create activity record in the activities collection. placePhoto is
      // the feed's generic thumbnail key — for circle activities it carries
      // the circle's cover image.
      await createActivity(
        'circle_created',
        createdByUserId,
        'circle',
        circleId,
        circleName,
        {
          circleId: circleId,
          circleName: circleName,
          placePhoto: circleCover
        }
      );
    }

    // Only create connection activities and notifications when someone besides
    // the owner is entitled to them
    if (audience.emits) {
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
        
        if (audience.allows(otherUserId)) {
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
        
        const shouldShowActivity = audience.allows(otherUserId);
        
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
    
    let circleCover = null;
    if (circleDoc.exists) {
      const circleData = circleDoc.data();
      circleName = circleData.name || 'Unknown Circle';
      circlePrivacy = circleData.privacy || 'private';
      circleCover = circleData.coverImage || null;
    }

    // Owner-only circles never generate like activities
    if (normalizePrivacy(circlePrivacy) !== PRIVACY.PRIVATE) {
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
          likedByUserId: likedByUserId,
          placePhoto: circleCover
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
    
    let circleCover = null;
    if (circleDoc.exists) {
      const circleData = circleDoc.data();
      circleName = circleData.name || 'Unknown Circle';
      circlePrivacy = circleData.privacy || 'private';
      circleCover = circleData.coverImage || null;
    }

    // Owner-only circles never generate comment activities
    if (normalizePrivacy(circlePrivacy) !== PRIVACY.PRIVATE) {
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
          commentText: commentText.substring(0, 100), // Truncate long comments
          placePhoto: circleCover
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


// Mark a single circle's activities (its new places + the circle itself) as
// viewed by `userId`, when they open that circle. This is what actually clears
// the per-place red dots — entering the circle counts as seeing them, so the
// viewer never has to tap each place. `ownerUserId` is the circle's owner.
const markCirclePlacesViewed = async (userId, ownerUserId, circleId) => {
  try {
    const [s1, s2] = await Promise.all([
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', userId).where('connectedUserId', '==', ownerUserId).limit(1).get(),
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', ownerUserId).where('connectedUserId', '==', userId).limit(1).get()
    ]);
    const snap = !s1.empty ? s1 : s2;
    if (snap.empty) return;

    const ref = snap.docs[0].ref;
    const data = snap.docs[0].data();
    let changed = false;
    const updated = (data.recentActivity || []).map(activity => {
      const belongsToCircle =
        activity.circleId === circleId ||
        (activity.type === 'circle' && activity.entityId === circleId);
      if (belongsToCircle && (!activity.viewedBy || !activity.viewedBy.includes(userId))) {
        changed = true;
        return { ...activity, viewedBy: [...(activity.viewedBy || []), userId] };
      }
      return activity;
    });
    if (!changed) return;

    const stillUnviewed = updated.some(a => !(a.viewedBy || []).includes(userId));
    await ref.update({
      recentActivity: updated,
      hasNewActivity: stillUnviewed,
      updatedAt: new Date().toISOString()
    });
  } catch (error) {
    console.error('Error marking circle places viewed:', error.message);
  }
};

module.exports = {
  trackCircleCreated,
  trackCircleView,
  trackCircleLiked,
  trackCircleCommented,
  markCircleActivitiesAsViewed,
  markCirclePlacesViewed,
};
