// Optimized version of getNetworkActivities with batch operations
const getNetworkActivitiesOptimized = async (req, res, next) => {
  try {
    const userId = req.user.uid;
    const { limit = 20, offset = 0, since } = req.query;
    
    console.log('🚀 [Optimized] Fetching network activities for user:', userId);
    
    // Parallel fetch connections and current user
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
    
    // Build connected users set
    const connectedUserIds = new Set();
    
    connections1.docs.forEach(doc => {
      connectedUserIds.add(doc.data().connectedUserId);
    });
    
    connections2.docs.forEach(doc => {
      connectedUserIds.add(doc.data().userId);
    });
    
    // Add followed users
    if (currentUserDoc.exists) {
      const userData = currentUserDoc.data();
      const following = userData.following || [];
      following.forEach(followedUserId => {
        connectedUserIds.add(followedUserId);
      });
    }
    
    // Add self
    connectedUserIds.add(userId);
    
    if (connectedUserIds.size === 1) { // Only self
      return res.status(200).json({
        success: true,
        activities: [],
        count: 0,
        hasMore: false
      });
    }
    
    // Build query
    let activitiesQuery = db.collection(COLLECTIONS.ACTIVITIES)
      .where('actorId', 'in', Array.from(connectedUserIds))
      .orderBy('timestamp', 'desc')
      .limit(parseInt(limit));
    
    if (since) {
      const sinceDate = new Date(since);
      activitiesQuery = activitiesQuery.where('timestamp', '>=', sinceDate);
    }
    
    if (offset > 0) {
      activitiesQuery = activitiesQuery.offset(parseInt(offset));
    }
    
    const activitiesSnapshot = await activitiesQuery.get();
    const activities = serializeQuerySnapshot(activitiesSnapshot);
    
    // OPTIMIZATION 1: Batch fetch all actor user details
    const actorIds = [...new Set(activities.map(a => a.actorId))];
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
    
    // Process activities with cached data
    const enrichedActivities = activities.map(activity => {
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
        
        // Check privacy
        if (circle.owner === userId) return true;
        
        switch (circle.privacy) {
          case 'public':
            return true;
          case 'myNetwork':
            return connectedUserIds.has(circle.owner);
          case 'private':
            return (circle.sharedWith || []).includes(userId);
          default:
            return false;
        }
      } catch (error) {
        console.error('Error checking activity privacy:', error);
        return false;
      }
    });
    
    console.log(`🚀 [Optimized] Returning ${filteredActivities.length} activities (batch loaded)`);
    
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