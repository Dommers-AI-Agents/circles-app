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
    
    // Extract connected user IDs. Keep connections and follows in SEPARATE sets
    // too — moment-privacy gating needs to tell "connected to" from "follows".
    const connectedUserIds = new Set();
    const connectionSet = new Set();
    const followingSet = new Set();

    connections1.docs.forEach(doc => {
      const data = doc.data();
      connectedUserIds.add(data.connectedUserId);
      connectionSet.add(data.connectedUserId);
    });

    connections2.docs.forEach(doc => {
      const data = doc.data();
      connectedUserIds.add(data.userId);
      connectionSet.add(data.userId);
    });

    // Add followed users to the activity feed (LinkedIn-style)
    if (currentUserDoc.exists) {
      const userData = currentUserDoc.data();
      const following = userData.following || [];
      following.forEach(followedUserId => {
        connectedUserIds.add(followedUserId);
        followingSet.add(followedUserId);
      });
      // Followed places surface their announcements/offers here — their
      // activities are keyed by the synthetic actor id 'place_<globalPlaceId>'
      const followedPlaces = userData.followedPlaces || [];
      followedPlaces.forEach(globalPlaceId => {
        connectedUserIds.add(`place_${globalPlaceId}`);
      });
    }

    // Blocked users (either direction) contribute nothing to this feed
    if (currentUserDoc.exists) {
      const { excludedUserIds } = require('../services/moderationService');
      for (const blockedId of excludedUserIds(currentUserDoc.data())) {
        connectedUserIds.delete(blockedId);
        connectionSet.delete(blockedId);
        followingSet.delete(blockedId);
      }
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
    
    console.log(`🔍 Fetching activities for ${userIds.length} users (connections + following + self)`);
    
    // Only ever need the newest (offset + limit) activities. Cap every query
    // with .limit(fetchCap) so a user following hundreds of actors doesn't
    // pull the entire activities collection just to render one page.
    const startIndex = parseInt(offset) || 0;
    const limitCount = parseInt(limit) || 20;
    const fetchCap = startIndex + limitCount;
    const sinceDate = since ? new Date(since) : null;

    const buildActivityQuery = (actorBatch) => {
      let q = db.collection(COLLECTIONS.ACTIVITIES)
        .where('actorId', 'in', actorBatch)
        .orderBy('timestamp', 'desc');
      if (sinceDate) q = q.where('timestamp', '>=', sinceDate);
      return q.limit(fetchCap);
    };

    // Handle Firestore IN query limitation (max 30 values per query)
    let allActivities = [];
    if (userIds.length <= 30) {
      const activitiesSnapshot = await buildActivityQuery(userIds).get();
      allActivities = serializeQuerySnapshot(activitiesSnapshot);
    } else {
      const userBatches = [];
      for (let i = 0; i < userIds.length; i += 30) {
        userBatches.push(userIds.slice(i, i + 30));
      }
      const batchResults = await Promise.all(
        userBatches.map(batch => buildActivityQuery(batch).get().then(serializeQuerySnapshot))
      );
      allActivities = batchResults
        .flat()
        .sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp));
    }

    // Apply limit and offset after merging (for batched queries)
    const activities = allActivities.slice(startIndex, startIndex + limitCount);
    
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

    // Place actors ('place_<globalPlaceId>') aren't users — synthesize a
    // minimal actor from the canonical globalPlaces record so clients render
    // the venue's name and photo without model changes
    const placeActorIds = actorIds.filter(id => typeof id === 'string' && id.startsWith('place_'));
    if (placeActorIds.length > 0) {
      try {
        const globalIds = [...new Set(placeActorIds.map(id => id.slice('place_'.length)))];
        const placeDocs = await db.getAll(
          ...globalIds.map(id => db.collection('globalPlaces').doc(id))
        );
        placeDocs.forEach(doc => {
          if (!doc.exists) return;
          const data = doc.data();
          const firstPhoto = (data.photos || [])[0];
          const photoUrl = typeof firstPhoto === 'string'
            ? firstPhoto
            : (firstPhoto && firstPhoto.url) || null;
          actorsMap.set(`place_${doc.id}`, {
            _id: `place_${doc.id}`,
            id: `place_${doc.id}`,
            displayName: data.name || 'A place',
            profilePicture: photoUrl,
            isPlace: true
          });
        });
      } catch (placeActorError) {
        console.error('⚠️ Place actor enrichment failed:', placeActorError.message);
      }
    }
    
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
    
    // Both reaction passes (the caller's own reactions + full summaries) run
    // as one parallel batch instead of two sequential per-chunk loops.
    const userReactionsMap = new Map();
    const reactionSummariesMap = new Map();

    const reactionBatches = [];
    for (let i = 0; i < activityIds.length; i += 10) {
      const batch = activityIds.slice(i, i + 10);
      if (batch.length > 0) reactionBatches.push(batch);
    }

    const [userReactionResults, summaryResults] = await Promise.all([
      Promise.all(reactionBatches.map(batch =>
        db.collection(COLLECTIONS.ACTIVITY_REACTIONS)
          .where('activityId', 'in', batch)
          .where('userId', '==', userId)
          .get()
      )),
      Promise.all(reactionBatches.map(batch =>
        db.collection(COLLECTIONS.ACTIVITY_REACTIONS)
          .where('activityId', 'in', batch)
          .get()
      ))
    ]);

    userReactionResults.forEach(snapshot => {
      snapshot.docs.forEach(doc => {
        const reaction = doc.data();
        userReactionsMap.set(reaction.activityId, reaction.emoji);
      });
    });

    summaryResults.forEach(snapshot => {
      snapshot.docs.forEach(doc => {
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
    });
    
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
        // Moment privacy gate: a video_uploaded/video_liked row is only shown
        // to a viewer entitled to the underlying moment, judged by their
        // relationship to the moment OWNER (the uploader, or — for a like —
        // the moment's owner, not the liker). Legacy rows lack the stamp and
        // fall through as public so existing content isn't hidden.
        if (activity.type === 'video_uploaded' || activity.type === 'video_liked') {
          const vis = activity.metadata && activity.metadata.momentVisibility;
          const ownerId = activity.metadata && activity.metadata.momentOwnerId;
          if (vis && ownerId && ownerId !== userId) {
            if (vis === 'public') return true;
            if (vis === 'followers') return followingSet.has(ownerId);
            if (vis === 'network') return connectionSet.has(ownerId);
            return false; // private/unknown → owner only
          }
          return true;
        }

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
    
    // Check if there are more activities available for pagination
    const hasMore = allActivities.length > startIndex + limitCount;
    
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

// @desc    Delete an activity
// @route   DELETE /api/activities/:activityId
// @access  Private
exports.deleteActivity = async (req, res, next) => {
  try {
    const userId = req.user.uid;
    const { activityId } = req.params;
    
    console.log(`🗑️ Deleting activity ${activityId} for user ${userId}`);
    
    // Get the activity to verify ownership
    const activityDoc = await db.collection(COLLECTIONS.ACTIVITIES).doc(activityId).get();
    
    if (!activityDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Activity not found'
      });
    }
    
    const activity = activityDoc.data();
    
    // Only allow the activity owner to delete it
    if (activity.actorId !== userId) {
      return res.status(403).json({
        success: false,
        message: 'You can only delete your own activities'
      });
    }
    
    // Start a batch operation to delete related data
    const batch = db.batch();
    
    // Delete the activity itself
    batch.delete(activityDoc.ref);
    
    // Delete all reactions for this activity
    const reactionsSnapshot = await db.collection(COLLECTIONS.ACTIVITY_REACTIONS)
      .where('activityId', '==', activityId)
      .get();
    
    reactionsSnapshot.docs.forEach(doc => {
      batch.delete(doc.ref);
    });
    
    // Delete all comments for this activity
    const commentsSnapshot = await db.collection(COLLECTIONS.ACTIVITY_COMMENTS)
      .where('activityId', '==', activityId)
      .get();
    
    commentsSnapshot.docs.forEach(doc => {
      batch.delete(doc.ref);
    });
    
    // Commit the batch
    await batch.commit();
    
    console.log(`✅ Successfully deleted activity ${activityId} and related data`);
    
    res.status(200).json({
      success: true,
      message: 'Activity deleted successfully'
    });
    
  } catch (error) {
    console.error('Error deleting activity:', error);
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
        commentId: metadata.commentId || null,
        placePhoto: metadata.placePhoto || null,
        placeAddress: metadata.placeAddress || null,
        placeId: metadata.placeId || null,
        message: metadata.message || null,
        endTime: metadata.endTime || null,
        // Video/photo moment activities carry their thumbnail here — the feed
        // renders it when placePhoto is absent
        videoTitle: metadata.videoTitle || null,
        videoThumbnail: metadata.videoThumbnail || null,
        videoDuration: metadata.videoDuration || null,
        // Moment privacy gating: the feed only shows a video_uploaded/
        // video_liked row to viewers entitled to the moment, judged by their
        // relationship to momentOwnerId.
        momentVisibility: metadata.momentVisibility || null,
        momentOwnerId: metadata.momentOwnerId || null
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