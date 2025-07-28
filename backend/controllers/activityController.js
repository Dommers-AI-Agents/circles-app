// backend/controllers/activityController.js
const { admin, getFirestore } = require('../config/firebase');
const { COLLECTIONS, serializeDoc, serializeQuerySnapshot } = require('../models/FirestoreModels');
const db = getFirestore();

// @desc    Get network activities for the current user
// @route   GET /api/network/activities
// @access  Private
exports.getNetworkActivities = async (req, res, next) => {
  try {
    const userId = req.user.uid;
    const { limit = 20, offset = 0, since } = req.query;
    
    // Fetching network activities for user
    
    // Get user's connections AND followed users
    const [connections1, connections2, currentUserDoc] = await Promise.all([
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', userId)
        .where('status', '==', 'accepted')
        .get(),
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('connectedUserId', '==', userId)
        .where('status', '==', 'accepted')
        .get(),
      db.collection(COLLECTIONS.USERS).doc(userId).get()
    ]);
    
    // Extract connected user IDs
    const connectedUserIds = new Set();
    
    connections1.docs.forEach(doc => {
      const data = doc.data();
      connectedUserIds.add(data.connectedUserId);
    });
    
    connections2.docs.forEach(doc => {
      const data = doc.data();
      connectedUserIds.add(data.userId);
    });
    
    // Add followed users to the activity feed (LinkedIn-style)
    if (currentUserDoc.exists) {
      const userData = currentUserDoc.data();
      const following = userData.following || [];
      following.forEach(followedUserId => {
        connectedUserIds.add(followedUserId);
      });
      // User following count tracked
    }
    
    // Add the current user to see their own activities too
    connectedUserIds.add(userId);
    
    // Found connections for activity feed
    // Activity feed includes connections and followed users
    
    if (connectedUserIds.size === 1) { // Only self
      // No connections found, returning empty activities
      return res.status(200).json({
        success: true,
        activities: [],
        count: 0,
        hasMore: false
      });
    }
    
    // Convert Set to Array for Firebase query
    const userIds = Array.from(connectedUserIds);
    
    // Build query
    let activitiesQuery = db.collection(COLLECTIONS.ACTIVITIES)
      .where('actorId', 'in', userIds)
      .orderBy('timestamp', 'desc')
      .limit(parseInt(limit));
    
    // Add date filter if provided
    if (since) {
      const sinceDate = new Date(since);
      activitiesQuery = activitiesQuery.where('timestamp', '>=', sinceDate);
    }
    
    // Add offset if provided
    if (offset > 0) {
      activitiesQuery = activitiesQuery.offset(parseInt(offset));
    }
    
    const activitiesSnapshot = await activitiesQuery.get();
    const activities = serializeQuerySnapshot(activitiesSnapshot);
    
    // Found activities
    
    // Activities collection verified
    
    // Activities fetched and ready for processing
    
    // Enrich activities with user data and serialize timestamps
    const enrichedActivities = await Promise.all(activities.map(async (activity) => {
      // Convert Firestore timestamp to ISO string
      if (activity.timestamp && activity.timestamp._seconds) {
        // Firestore timestamp object
        activity.timestamp = new Date(activity.timestamp._seconds * 1000).toISOString();
      } else if (activity.timestamp && activity.timestamp.toDate) {
        // Firestore Timestamp class
        activity.timestamp = activity.timestamp.toDate().toISOString();
      } else if (activity.timestamp instanceof Date) {
        // JavaScript Date object
        activity.timestamp = activity.timestamp.toISOString();
      }
      
      // Get actor details
      const actorDoc = await db.collection(COLLECTIONS.USERS).doc(activity.actorId).get();
      if (actorDoc.exists) {
        activity.actor = serializeDoc(actorDoc);
      }
      
      // Mark as read if current user has viewed it
      activity.isRead = activity.viewers?.includes(userId) || false;
      
      return activity;
    }));
    
    // Check if there are more activities
    const hasMore = activities.length === parseInt(limit);
    
    res.status(200).json({
      success: true,
      activities: enrichedActivities,
      count: enrichedActivities.length,
      hasMore: hasMore
    });
    
  } catch (error) {
    console.error('Error fetching network activities:', error);
    next(error);
  }
};

// @desc    Mark activities as read
// @route   PUT /api/network/activities/mark-read
// @access  Private
exports.markActivitiesAsRead = async (req, res, next) => {
  try {
    const userId = req.user.uid;
    const { activityIds } = req.body;
    
    if (!activityIds || !Array.isArray(activityIds) || activityIds.length === 0) {
      return res.status(400).json({
        success: false,
        message: 'Please provide activity IDs to mark as read'
      });
    }
    
    const batch = db.batch();
    
    for (const activityId of activityIds) {
      const activityRef = db.collection(COLLECTIONS.ACTIVITIES).doc(activityId);
      batch.update(activityRef, {
        viewers: admin.firestore.FieldValue.arrayUnion(userId)
      });
    }
    
    await batch.commit();
    
    res.status(200).json({
      success: true,
      message: 'Activities marked as read'
    });
    
  } catch (error) {
    console.error('Error marking activities as read:', error);
    next(error);
  }
};

// Helper function to create activity (called by other controllers)
exports.createActivity = async (type, actorId, targetType, targetId, targetName, metadata = {}) => {
  try {
    // Creating activity
    
    // Ensure the actorId is a string
    const actorIdStr = String(actorId);
    
    const activityData = {
      type,
      actorId: actorIdStr,
      targetType,
      targetId,
      targetName,
      circleId: metadata.circleId || null,
      circleName: metadata.circleName || null,
      metadata: {
        comment: metadata.comment || null,
        placePhoto: metadata.placePhoto || null,
        placeAddress: metadata.placeAddress || null
      },
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      viewers: [] // Track who has seen this activity
    };
    
    // Activity data prepared
    
    try {
      const activityRef = await db.collection(COLLECTIONS.ACTIVITIES).add(activityData);
      return activityRef.id;
    } catch (firestoreError) {
      console.error('❌ Firestore error creating activity:', firestoreError.code);
      throw firestoreError;
    }
  } catch (error) {
    console.error('❌ Error creating activity:', error);
    console.error('❌ Error details:', error.message);
    console.error('❌ Error stack:', error.stack);
    // Don't throw - we don't want activity tracking to break the main flow
  }
};