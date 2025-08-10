// backend/controllers/activityController.js
const { admin, getFirestore } = require('../config/firebase');
const { COLLECTIONS, serializeDoc, serializeQuerySnapshot } = require('../models/FirestoreModels');
const db = getFirestore();

// Helper function to check if a user can see a circle based on privacy settings
const canUserSeeCircle = async (userId, circle, connectedUserIds) => {
  if (!circle) return false;
  
  // Owner can always see their own circle
  if (circle.owner === userId) return true;
  
  // Check privacy level
  switch (circle.privacy) {
    case 'public':
      return true; // Public circles visible to all
    case 'myNetwork':
      // Network circles visible to connections only
      return connectedUserIds.has(circle.owner);
    case 'private':
      // Private circles only visible if explicitly shared
      const sharedWith = circle.sharedWith || [];
      return sharedWith.includes(userId);
    default:
      return false;
  }
};

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
    
    // OPTIMIZATION 1: Batch fetch all actor user details
    const actorIds = [...new Set(activities.map(a => a.actorId))];
    console.log('🚀 Batch fetching', actorIds.length, 'unique actors');
    
    const actorBatches = [];
    for (let i = 0; i < actorIds.length; i += 10) {
      actorBatches.push(actorIds.slice(i, i + 10));
    }
    
    const actorResults = await Promise.all(
      actorBatches.map(batch => 
        db.collection(COLLECTIONS.USERS)
          .where('__name__', 'in', batch)
          .get()
      )
    );
    
    const actorsMap = new Map();
    actorResults.forEach(snapshot => {
      snapshot.docs.forEach(doc => {
        actorsMap.set(doc.id, serializeDoc(doc));
      });
    });
    
    // OPTIMIZATION 2: Batch fetch all referenced circles
    const circleIds = [...new Set(activities
      .map(a => a.targetType === 'circle' ? a.targetId : a.circleId)
      .filter(Boolean))];
    
    console.log('🚀 Batch fetching', circleIds.length, 'unique circles for privacy checks');
    
    const circleBatches = [];
    for (let i = 0; i < circleIds.length; i += 10) {
      circleBatches.push(circleIds.slice(i, i + 10));
    }
    
    const circleResults = await Promise.all(
      circleBatches.map(batch => 
        db.collection(COLLECTIONS.CIRCLES)
          .where('__name__', 'in', batch)
          .get()
      )
    );
    
    const circlesMap = new Map();
    circleResults.forEach(snapshot => {
      snapshot.docs.forEach(doc => {
        circlesMap.set(doc.id, doc.data());
      });
    });
    
    // OPTIMIZATION 3: Batch fetch reactions for all activities
    const activityIds = activities.map(a => a._id || a.id).filter(Boolean);
    console.log('🚀 Batch fetching reactions for', activityIds.length, 'activities');
    
    // Fetch user's reactions for these activities (batch by 10 for Firebase limit)
    const userReactionsMap = new Map();
    
    for (let i = 0; i < activityIds.length; i += 10) {
      const batch = activityIds.slice(i, i + 10);
      if (batch.length > 0) {
        const userReactionsQuery = await db.collection(COLLECTIONS.ACTIVITY_REACTIONS)
          .where('activityId', 'in', batch)
          .where('userId', '==', userId)
          .get();
        
        userReactionsQuery.docs.forEach(doc => {
          const reaction = doc.data();
          userReactionsMap.set(reaction.activityId, reaction.emoji);
        });
      }
    }
    
    // Fetch reaction summaries for all activities
    const reactionSummariesMap = new Map();
    
    // We need to fetch all reactions for these activities to get counts
    for (let i = 0; i < activityIds.length; i += 10) {
      const batch = activityIds.slice(i, i + 10);
      const reactionsQuery = await db.collection(COLLECTIONS.ACTIVITY_REACTIONS)
        .where('activityId', 'in', batch)
        .get();
      
      reactionsQuery.docs.forEach(doc => {
        const reaction = doc.data();
        const activityId = reaction.activityId;
        
        if (!reactionSummariesMap.has(activityId)) {
          reactionSummariesMap.set(activityId, new Map());
        }
        
        const activityReactions = reactionSummariesMap.get(activityId);
        if (!activityReactions.has(reaction.emoji)) {
          activityReactions.set(reaction.emoji, {
            emoji: reaction.emoji,
            count: 0,
            users: []
          });
        }
        
        const reactionSummary = activityReactions.get(reaction.emoji);
        reactionSummary.count++;
        if (reactionSummary.users.length < 3) { // Only keep first 3 users for display
          reactionSummary.users.push({
            id: reaction.userId,
            displayName: reaction.userName,
            profilePicture: reaction.userPhoto
          });
        }
      });
    }
    
    // Process activities with cached data
    const enrichedActivities = activities.map(activity => {
      const activityId = activity._id || activity.id;
      
      // Convert timestamp
      if (activity.timestamp && activity.timestamp._seconds) {
        activity.timestamp = new Date(activity.timestamp._seconds * 1000).toISOString();
      } else if (activity.timestamp && activity.timestamp.toDate) {
        activity.timestamp = activity.timestamp.toDate().toISOString();
      } else if (activity.timestamp instanceof Date) {
        activity.timestamp = activity.timestamp.toISOString();
      }
      
      // Add actor from map
      activity.actor = actorsMap.get(activity.actorId) || null;
      
      // Mark as read
      activity.isRead = activity.viewers?.includes(userId) || false;
      
      // Add user's reaction
      activity.userReaction = userReactionsMap.get(activityId) || null;
      
      // Add reaction summary (top reactions)
      const activityReactions = reactionSummariesMap.get(activityId);
      if (activityReactions && activityReactions.size > 0) {
        activity.reactionSummary = Array.from(activityReactions.values())
          .sort((a, b) => b.count - a.count)
          .slice(0, 3); // Top 3 reaction types
      } else {
        activity.reactionSummary = [];
      }
      
      return activity;
    });
    
    // Filter activities based on privacy using cached circles
    const filteredActivities = enrichedActivities.filter(activity => {
      try {
        let circleId = null;
        
        if (activity.targetType === 'circle') {
          circleId = activity.targetId;
        } else if (activity.circleId) {
          circleId = activity.circleId;
        }
        
        if (!circleId) return true; // Include if no circle reference
        
        const circle = circlesMap.get(circleId);
        if (!circle) return false; // Exclude if circle not found
        
        // Check privacy using helper function (synchronous now)
        return canUserSeeCircle(userId, circle, connectedUserIds);
      } catch (error) {
        console.error('Error checking activity privacy:', error);
        return false;
      }
    });
    
    // Check if there are more activities (based on original fetch, not filtered)
    const hasMore = activities.length === parseInt(limit);
    
    res.status(200).json({
      success: true,
      activities: filteredActivities,
      count: filteredActivities.length,
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
        placeAddress: metadata.placeAddress || null,
        placeId: metadata.placeId || null,
        message: metadata.message || null,
        endTime: metadata.endTime || null
      },
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      viewers: [], // Track who has seen this activity
      reactionCount: 0,
      commentCount: 0
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