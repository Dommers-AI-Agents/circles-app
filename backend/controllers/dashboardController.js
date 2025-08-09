// backend/controllers/dashboardController.js
const { admin, getFirestore } = require('../config/firebase');
const { COLLECTIONS, serializeDoc, serializeQuerySnapshot } = require('../models/FirestoreModels');
const db = getFirestore();

// Helper function to check if a user can see a circle based on privacy settings
const canUserSeeCircle = (userId, circle, connectedUserIds) => {
  if (!circle) return false;
  
  // Owner can always see their own circle
  if (circle.owner === userId) return true;
  
  // Check privacy level
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
};

// @desc    Get all dashboard data in one request
// @route   GET /api/home/dashboard
// @access  Private
exports.getDashboard = async (req, res, next) => {
  try {
    const userId = req.user.uid;
    const { activityLimit = 20 } = req.query;
    
    console.log('🚀 [Dashboard] Fetching all home screen data for user:', userId);
    const startTime = Date.now();
    
    // Parallel fetch all primary data
    const [
      myCirclesSnapshot,
      connections1,
      connections2,
      currentUserDoc,
      activitiesSnapshot
    ] = await Promise.all([
      // User's own circles
      db.collection(COLLECTIONS.CIRCLES)
        .where('userId', '==', userId)
        .orderBy('updatedAt', 'desc')
        .get(),
      
      // Connections (both directions)
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', userId)
        .where('status', '==', 'accepted')
        .get(),
      
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('connectedUserId', '==', userId)
        .where('status', '==', 'accepted')
        .get(),
      
      // Current user data
      db.collection(COLLECTIONS.USERS).doc(userId).get(),
      
      // Recent activities (will filter later)
      db.collection(COLLECTIONS.ACTIVITIES)
        .orderBy('timestamp', 'desc')
        .limit(parseInt(activityLimit) * 3) // Fetch extra to account for filtering
        .get()
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
    let followedUserIds = [];
    if (currentUserDoc.exists) {
      const userData = currentUserDoc.data();
      followedUserIds = userData.following || [];
      followedUserIds.forEach(id => connectedUserIds.add(id));
    }
    
    // Get network circles if there are connections
    let networkCirclesSnapshot = null;
    if (connectedUserIds.size > 0) {
      networkCirclesSnapshot = await db.collection(COLLECTIONS.CIRCLES)
        .where('owner', 'in', Array.from(connectedUserIds))
        .where('privacy', 'in', ['public', 'myNetwork'])
        .get();
    }
    
    // Process my circles
    const myCircles = serializeQuerySnapshot(myCirclesSnapshot);
    
    // Process network circles
    const networkCircles = networkCirclesSnapshot 
      ? serializeQuerySnapshot(networkCirclesSnapshot)
      : [];
    
    // Combine all circles for place fetching
    const allCircles = [...myCircles, ...networkCircles];
    const circleIds = allCircles.map(c => c._id);
    
    // Collect all user IDs we need to fetch
    const userIdsToFetch = new Set([userId]);
    
    // Add circle owners
    allCircles.forEach(circle => {
      userIdsToFetch.add(circle.owner);
    });
    
    // Process and filter activities
    const allActivities = serializeQuerySnapshot(activitiesSnapshot);
    const networkUserIds = new Set([...connectedUserIds, ...followedUserIds, userId]);
    
    // Filter activities to only those from network
    const filteredActivities = allActivities.filter(activity => 
      networkUserIds.has(activity.actorId)
    );
    
    // Add activity actors to fetch list
    filteredActivities.forEach(activity => {
      userIdsToFetch.add(activity.actorId);
    });
    
    // Batch fetch all users
    const userIdArray = Array.from(userIdsToFetch);
    const userBatches = [];
    for (let i = 0; i < userIdArray.length; i += 10) {
      userBatches.push(userIdArray.slice(i, i + 10));
    }
    
    const userSnapshots = await Promise.all(
      userBatches.map(batch => 
        db.collection(COLLECTIONS.USERS)
          .where('__name__', 'in', batch)
          .get()
      )
    );
    
    // Build users map
    const usersMap = {};
    userSnapshots.forEach(snapshot => {
      snapshot.docs.forEach(doc => {
        const user = serializeDoc(doc);
        usersMap[user._id] = user;
      });
    });
    
    // Batch fetch places for all circles
    let allPlaces = [];
    if (circleIds.length > 0) {
      // Fetch in batches to avoid query limits
      const placeBatches = [];
      for (let i = 0; i < circleIds.length; i += 10) {
        placeBatches.push(circleIds.slice(i, i + 10));
      }
      
      const placeSnapshots = await Promise.all(
        placeBatches.map(batch =>
          db.collection(COLLECTIONS.PLACES)
            .where('circleId', 'in', batch)
            .get()
        )
      );
      
      placeSnapshots.forEach(snapshot => {
        allPlaces = allPlaces.concat(serializeQuerySnapshot(snapshot));
      });
    }
    
    // Create circle ID to places map
    const placesByCircleId = {};
    allPlaces.forEach(place => {
      if (!placesByCircleId[place.circleId]) {
        placesByCircleId[place.circleId] = [];
      }
      placesByCircleId[place.circleId].push(place);
    });
    
    // Enrich circles with owner details and places
    const enrichCircles = (circles) => {
      return circles.map(circle => ({
        ...circle,
        ownerDetails: usersMap[circle.owner] || null,
        places: placesByCircleId[circle._id] || []
      }));
    };
    
    const enrichedMyCircles = enrichCircles(myCircles);
    const enrichedNetworkCircles = enrichCircles(networkCircles);
    
    // Filter activities based on privacy
    const circlesMap = new Map(allCircles.map(c => [c._id, c]));
    
    const privacyFilteredActivities = filteredActivities.filter(activity => {
      let circleId = activity.targetType === 'circle' ? activity.targetId : activity.circleId;
      if (!circleId) return true;
      
      const circle = circlesMap.get(circleId);
      if (!circle) return false;
      
      return canUserSeeCircle(userId, circle, connectedUserIds);
    }).slice(0, parseInt(activityLimit)); // Take only requested amount after filtering
    
    // Enrich activities with actor details and convert timestamps
    const enrichedActivities = privacyFilteredActivities.map(activity => {
      // Convert timestamp
      if (activity.timestamp && activity.timestamp._seconds) {
        activity.timestamp = new Date(activity.timestamp._seconds * 1000).toISOString();
      } else if (activity.timestamp && activity.timestamp.toDate) {
        activity.timestamp = activity.timestamp.toDate().toISOString();
      } else if (activity.timestamp instanceof Date) {
        activity.timestamp = activity.timestamp.toISOString();
      }
      
      return {
        ...activity,
        actor: usersMap[activity.actorId] || null,
        isRead: activity.viewers?.includes(userId) || false
      };
    });
    
    const endTime = Date.now();
    const totalTime = endTime - startTime;
    
    console.log(`✅ [Dashboard] Complete dashboard loaded in ${totalTime}ms`);
    console.log(`  - My circles: ${enrichedMyCircles.length}`);
    console.log(`  - Network circles: ${enrichedNetworkCircles.length}`);
    console.log(`  - Total places: ${allPlaces.length}`);
    console.log(`  - Activities: ${enrichedActivities.length}`);
    console.log(`  - Users fetched: ${Object.keys(usersMap).length}`);
    
    res.status(200).json({
      success: true,
      data: {
        myCircles: enrichedMyCircles,
        networkCircles: enrichedNetworkCircles,
        activities: enrichedActivities,
        stats: {
          totalCircles: enrichedMyCircles.length + enrichedNetworkCircles.length,
          totalPlaces: allPlaces.length,
          totalActivities: enrichedActivities.length,
          loadTimeMs: totalTime
        }
      }
    });
    
  } catch (error) {
    console.error('Error fetching dashboard:', error);
    next(error);
  }
};

// @desc    Get dashboard data with caching headers
// @route   GET /api/home/dashboard/cached
// @access  Private
exports.getCachedDashboard = async (req, res, next) => {
  // Set cache headers
  res.set({
    'Cache-Control': 'private, max-age=60', // Cache for 1 minute
    'ETag': `"dashboard-${req.user.uid}-${Date.now()}"`
  });
  
  // Call the main dashboard function
  return exports.getDashboard(req, res, next);
};