// backend/controllers/dashboardController.js
const { admin, getFirestore } = require('../config/firebase');
const { COLLECTIONS, serializeDoc, serializeQuerySnapshot } = require('../models/FirestoreModels');
const backgroundAggregationService = require('../services/backgroundAggregationService');
const cacheInvalidationService = require('../services/cacheInvalidationService');
const { fetchActivitiesByActors } = require('../services/activityFeedService');
const db = getFirestore();

// Helper function to calculate map center from places
const calculateMapCenter = (places) => {
  if (places.length === 0) return { latitude: 37.7749, longitude: -122.4194 }; // Default SF
  
  const sum = places.reduce((acc, place) => ({
    latitude: acc.latitude + place.coordinates.latitude,
    longitude: acc.longitude + place.coordinates.longitude
  }), { latitude: 0, longitude: 0 });
  
  return {
    latitude: sum.latitude / places.length,
    longitude: sum.longitude / places.length
  };
};

// Helper function to calculate map bounds
const calculateMapBounds = (places) => {
  if (places.length === 0) return null;
  
  const lats = places.map(p => p.coordinates.latitude);
  const lngs = places.map(p => p.coordinates.longitude);
  
  return {
    north: Math.max(...lats),
    south: Math.min(...lats),
    east: Math.max(...lngs),
    west: Math.min(...lngs)
  };
};

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

// @desc    Get all dashboard data in one request (Enhanced for home screen optimization)
// @route   GET /api/home/dashboard
// @access  Private
exports.getDashboard = async (req, res, next) => {
  try {
    const userId = req.user.uid;
    const { activityLimit = 20, includeMapData = true, includeUserList = true, preloadImages = false } = req.query;
    
    console.log('🚀 [Dashboard] Enhanced home screen data fetch for user:', userId);
    const startTime = Date.now();
    
    // Parallel fetch all primary data
    const [
      myCirclesSnapshot,
      connections1,
      connections2,
      currentUserDoc
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
    
    // Fetch activities scoped to network actors - scales with network size,
    // not platform activity volume. Extra fetched for privacy filtering below.
    const networkUserIds = new Set([...connectedUserIds, ...followedUserIds, userId]);
    const filteredActivities = await fetchActivitiesByActors(
      networkUserIds,
      parseInt(activityLimit) * 3
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

    // Enhanced: Build optimized user list for horizontal scroll (most active users first)
    let userList = [];
    if (includeUserList) {
      // Sort connected users by recent activity and interactions
      const userActivityCounts = {};
      enrichedActivities.forEach(activity => {
        if (activity.actorId && activity.actorId !== userId) {
          userActivityCounts[activity.actorId] = (userActivityCounts[activity.actorId] || 0) + 1;
        }
      });

      userList = Array.from(connectedUserIds)
        .map(id => usersMap[id])
        .filter(user => user && user._id !== userId)
        .sort((a, b) => {
          const aActivity = userActivityCounts[a._id] || 0;
          const bActivity = userActivityCounts[b._id] || 0;
          return bActivity - aActivity; // Most active first
        })
        .slice(0, 20) // Limit to 20 for performance
        .map(user => ({
          _id: user._id,
          displayName: user.displayName,
          profileImageUrl: user.profileImageUrl,
          isOnline: user.lastSeen ? (Date.now() - new Date(user.lastSeen).getTime()) < 300000 : false // 5 min threshold
        }));
    }

    // Enhanced: Build optimized map data (places with coordinates only)
    let mapData = null;
    if (includeMapData) {
      const placesWithCoords = allPlaces.filter(place => 
        place.coordinates && 
        place.coordinates.latitude && 
        place.coordinates.longitude
      );

      mapData = {
        places: placesWithCoords.map(place => ({
          _id: place._id,
          name: place.name,
          coordinates: place.coordinates,
          circleId: place.circleId,
          imageUrl: place.imageUrl,
          category: place.category
        })),
        center: calculateMapCenter(placesWithCoords),
        bounds: calculateMapBounds(placesWithCoords)
      };
    }
    
    const endTime = Date.now();
    const totalTime = endTime - startTime;
    
    console.log(`✅ [Dashboard] Enhanced dashboard loaded in ${totalTime}ms`);
    console.log(`  - My circles: ${enrichedMyCircles.length}`);
    console.log(`  - Network circles: ${enrichedNetworkCircles.length}`);
    console.log(`  - Total places: ${allPlaces.length}`);
    console.log(`  - Activities: ${enrichedActivities.length}`);
    console.log(`  - Users fetched: ${Object.keys(usersMap).length}`);
    console.log(`  - User list: ${userList.length}`);
    console.log(`  - Map places: ${mapData ? mapData.places.length : 0}`);
    
    res.status(200).json({
      success: true,
      data: {
        myCircles: enrichedMyCircles,
        networkCircles: enrichedNetworkCircles,
        activities: enrichedActivities,
        userList: userList, // Enhanced: Sorted active users for horizontal scroll
        mapData: mapData,   // Enhanced: Optimized map data with bounds
        stats: {
          totalCircles: enrichedMyCircles.length + enrichedNetworkCircles.length,
          totalPlaces: allPlaces.length,
          totalActivities: enrichedActivities.length,
          totalUsers: userList.length,
          mapPlaces: mapData ? mapData.places.length : 0,
          loadTimeMs: totalTime
        }
      }
    });
    
  } catch (error) {
    console.error('Error fetching dashboard:', error);
    next(error);
  }
};

// @desc    Get optimized home screen data (ultra-fast loading)
// @route   GET /api/home/homescreen
// @access  Private
exports.getHomeScreen = async (req, res, next) => {
  try {
    const userId = req.user.uid;
    const startTime = Date.now();
    
    console.log('⚡ [HomeScreen] Ultra-fast home screen data fetch for user:', userId);
    
    // Try background aggregated data first
    const cachedData = backgroundAggregationService.getCacheData(userId);
    if (cachedData) {
      console.log('⚡ [HomeScreen] Using background aggregated data');
      const totalTime = Date.now() - startTime;
      
      return res.status(200).json({
        success: true,
        data: {
          userList: cachedData.userList,
          recentActivities: cachedData.recentActivities,
          stats: {
            loadTimeMs: totalTime,
            totalUsers: cachedData.userList.length,
            totalActivities: cachedData.recentActivities.length,
            source: 'background_cache'
          }
        }
      });
    }
    
    console.log('⚡ [HomeScreen] No background data, performing live fetch');
    
    // Parallel fetch only essential data for immediate display
    const [
      connections1,
      connections2,
      currentUserDoc
    ] = await Promise.all([
      // Connections (both directions) - essential for user list
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', userId)
        .where('status', '==', 'accepted')
        .limit(25) // Limit for speed
        .get(),

      db.collection(COLLECTIONS.CONNECTIONS)
        .where('connectedUserId', '==', userId)
        .where('status', '==', 'accepted')
        .limit(25) // Limit for speed
        .get(),

      // Current user data
      db.collection(COLLECTIONS.USERS).doc(userId).get()
    ]);
    
    // Build connected users set
    const connectedUserIds = new Set();
    connections1.docs.forEach(doc => connectedUserIds.add(doc.data().connectedUserId));
    connections2.docs.forEach(doc => connectedUserIds.add(doc.data().userId));
    
    // Add followed users
    if (currentUserDoc.exists) {
      const userData = currentUserDoc.data();
      const followedUserIds = userData.following || [];
      followedUserIds.forEach(id => connectedUserIds.add(id));
    }
    
    // Fetch users for horizontal list (batch optimized)
    const userIdArray = Array.from(connectedUserIds).slice(0, 20); // Limit to 20 most recent
    let usersMap = {};
    
    if (userIdArray.length > 0) {
      const userSnapshots = await Promise.all([
        db.collection(COLLECTIONS.USERS)
          .where('__name__', 'in', userIdArray.slice(0, 10))
          .get(),
        userIdArray.length > 10 ? 
          db.collection(COLLECTIONS.USERS)
            .where('__name__', 'in', userIdArray.slice(10, 20))
            .get() : 
          Promise.resolve({ docs: [] })
      ]);
      
      userSnapshots.forEach(snapshot => {
        snapshot.docs.forEach(doc => {
          const user = serializeDoc(doc);
          usersMap[user._id] = user;
        });
      });
    }
    
    // Build optimized user list for horizontal scroll
    const userList = userIdArray
      .map(id => usersMap[id])
      .filter(user => user && user._id !== userId)
      .slice(0, 15) // Limit for ultra-fast display
      .map(user => ({
        _id: user._id,
        displayName: user.displayName,
        profileImageUrl: user.profileImageUrl,
        isOnline: user.lastSeen ? (Date.now() - new Date(user.lastSeen).getTime()) < 300000 : false
      }));
    
    // Fetch recent activities scoped to network actors - scales with network
    // size, not platform activity volume
    const networkUserIds = new Set([...connectedUserIds, userId]);
    const networkActivities = await fetchActivitiesByActors(networkUserIds, 10);

    const recentActivities = networkActivities
      .map(activity => {
        // Convert timestamp
        if (activity.timestamp && activity.timestamp._seconds) {
          activity.timestamp = new Date(activity.timestamp._seconds * 1000).toISOString();
        } else if (activity.timestamp && activity.timestamp.toDate) {
          activity.timestamp = activity.timestamp.toDate().toISOString();
        }
        
        return {
          ...activity,
          actor: usersMap[activity.actorId] || { _id: activity.actorId, displayName: 'Unknown User' },
          isRead: activity.viewers?.includes(userId) || false
        };
      });
    
    const endTime = Date.now();
    const totalTime = endTime - startTime;
    
    console.log(`⚡ [HomeScreen] Ultra-fast load completed in ${totalTime}ms`);
    console.log(`  - User list: ${userList.length}`);
    console.log(`  - Recent activities: ${recentActivities.length}`);
    
    res.status(200).json({
      success: true,
      data: {
        userList: userList,
        recentActivities: recentActivities,
        stats: {
          loadTimeMs: totalTime,
          totalUsers: userList.length,
          totalActivities: recentActivities.length
        }
      }
    });
    
  } catch (error) {
    console.error('Error fetching home screen data:', error);
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

// @desc    Get cache and aggregation stats
// @route   GET /api/home/cache/stats
// @access  Private
exports.getCacheStats = async (req, res, next) => {
  try {
    const backgroundStats = backgroundAggregationService.getCacheStats();
    const invalidationStats = cacheInvalidationService.getStats();
    
    res.status(200).json({
      success: true,
      data: {
        backgroundAggregation: backgroundStats,
        cacheInvalidation: invalidationStats,
        timestamp: new Date().toISOString()
      }
    });
  } catch (error) {
    console.error('Error getting cache stats:', error);
    next(error);
  }
};

// @desc    Manually refresh cache for current user
// @route   POST /api/home/cache/refresh
// @access  Private
exports.refreshUserCache = async (req, res, next) => {
  try {
    const userId = req.user.uid;
    
    await cacheInvalidationService.refreshCacheForUser(userId);
    
    res.status(200).json({
      success: true,
      message: 'Cache refresh initiated',
      data: {
        userId: userId,
        timestamp: new Date().toISOString()
      }
    });
  } catch (error) {
    console.error('Error refreshing user cache:', error);
    next(error);
  }
};

// @desc    Manually invalidate all cache (admin only)
// @route   POST /api/home/cache/invalidate-all
// @access  Private (admin)
exports.invalidateAllCache = async (req, res, next) => {
  try {
    // Add admin check here if needed
    const userId = req.user.uid;
    
    await cacheInvalidationService.invalidateAllCache();
    
    res.status(200).json({
      success: true,
      message: 'All cache invalidated',
      data: {
        performedBy: userId,
        timestamp: new Date().toISOString()
      }
    });
  } catch (error) {
    console.error('Error invalidating all cache:', error);
    next(error);
  }
};