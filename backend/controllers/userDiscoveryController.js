// backend/controllers/userDiscoveryController.js
const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');
const geofire = require('geofire-common');

const db = getFirestore();

// Helper function to calculate place counts from circles
const calculateUserPlaceCounts = async (userId) => {
  const circlesSnapshot = await db.collection(COLLECTIONS.CIRCLES)
    .where('owner', '==', userId)
    .get();
  
  let totalPlaces = 0;
  let circlesCount = circlesSnapshot.size;
  
  circlesSnapshot.forEach(circleDoc => {
    const circle = circleDoc.data();
    totalPlaces += (circle.placesCount || 0);
  });
  
  return { placesCount: totalPlaces, circlesCount };
};

// Get user discovery suggestions (popular users, nearby, friend-of-friends)
const getDiscoverUsers = async (req, res) => {
  try {
    const userId = req.user.uid;
    const { 
      type = 'all', // 'popular', 'nearby', 'friendsOfFriends', 'all'
      lat,
      lng,
      radius = 50, // km
      limit = 20 
    } = req.query;
    
    console.log(`🔍 Getting discovery users for ${userId}, type: ${type}`);
    
    // Get current user's connections and following list
    const [currentUserDoc, connectionsSnapshot] = await Promise.all([
      db.collection(COLLECTIONS.USERS).doc(userId).get(),
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', userId)
        .where('status', '==', 'accepted')
        .get()
    ]);
    
    const currentUserData = currentUserDoc.data();
    const userFollowing = new Set(currentUserData.following || []);
    const connectedUserIds = new Set();
    
    connectionsSnapshot.forEach(doc => {
      connectedUserIds.add(doc.data().connectedUserId);
    });
    
    let discoveryUsers = [];
    
    // 1. Popular Users (users with most places and followers)
    if (type === 'popular' || type === 'all') {
      const popularUsersQuery = await db.collection(COLLECTIONS.USERS)
        .orderBy('followersCount', 'desc')
        .limit(50)
        .get();
      
      for (const doc of popularUsersQuery.docs) {
        if (doc.id === userId || connectedUserIds.has(doc.id)) continue;
        
        const userData = doc.data();
        const { placesCount, circlesCount } = await calculateUserPlaceCounts(doc.id);
        
        // Only include users with at least 5 places
        if (placesCount >= 5) {
          discoveryUsers.push({
            id: doc.id,
            ...userData,
            placesCount,
            circlesCount,
            discoveryType: 'popular',
            isFollowing: userFollowing.has(doc.id),
            connectionStatus: connectedUserIds.has(doc.id) ? 'accepted' : 'none'
          });
        }
      }
    }
    
    // 2. Nearby Users (if location provided)
    if ((type === 'nearby' || type === 'all') && lat && lng) {
      const center = [parseFloat(lat), parseFloat(lng)];
      const radiusInM = radius * 1000;
      const nearbyUserDocs = [];
      
      // First try to get users with geohash (more efficient)
      try {
        const bounds = geofire.geohashQueryBounds(center, radiusInM);
        const promises = [];
        
        for (const b of bounds) {
          const q = db.collection(COLLECTIONS.USERS)
            .orderBy('geohash')
            .startAt(b[0])
            .endAt(b[1]);
          promises.push(q.get());
        }
        
        const snapshots = await Promise.all(promises);
        
        for (const snap of snapshots) {
          for (const doc of snap.docs) {
            if (doc.id === userId || connectedUserIds.has(doc.id)) continue;
            
            const userData = doc.data();
            
            // Filter by actual distance
            if (userData.lastKnownLocation) {
              const lat2 = userData.lastKnownLocation.latitude;
              const lng2 = userData.lastKnownLocation.longitude;
              const distanceInKm = geofire.distanceBetween([lat, lng], [lat2, lng2]);
              
              if (distanceInKm <= radius) {
                nearbyUserDocs.push({ doc, distance: distanceInKm });
              }
            }
          }
        }
      } catch (error) {
        console.log('⚠️ Geohash query failed, falling back to all users:', error.message);
      }
      
      // If no nearby users found with geohash, check all users with lastKnownLocation
      if (nearbyUserDocs.length === 0) {
        console.log('📍 No geohash users found, checking all users with location...');
        const allUsersQuery = await db.collection(COLLECTIONS.USERS)
          .where('lastKnownLocation', '!=', null)
          .limit(100)
          .get();
        
        for (const doc of allUsersQuery.docs) {
          if (doc.id === userId || connectedUserIds.has(doc.id)) continue;
          
          const userData = doc.data();
          if (userData.lastKnownLocation) {
            const lat2 = userData.lastKnownLocation.latitude;
            const lng2 = userData.lastKnownLocation.longitude;
            const distanceInKm = geofire.distanceBetween([parseFloat(lat), parseFloat(lng)], [lat2, lng2]);
            
            if (distanceInKm <= radius) {
              nearbyUserDocs.push({ doc, distance: distanceInKm });
            }
          }
        }
      }
      
      // Sort by distance and take closest
      nearbyUserDocs.sort((a, b) => a.distance - b.distance);
      
      for (const { doc, distance } of nearbyUserDocs.slice(0, 20)) {
        const userData = doc.data();
        const { placesCount, circlesCount } = await calculateUserPlaceCounts(doc.id);
        
        if (placesCount > 0) {
          discoveryUsers.push({
            id: doc.id,
            ...userData,
            placesCount,
            circlesCount,
            discoveryType: 'nearby',
            distance: Math.round(distance * 10) / 10, // Round to 1 decimal
            isFollowing: userFollowing.has(doc.id),
            connectionStatus: connectedUserIds.has(doc.id) ? 'accepted' : 'none'
          });
        }
      }
      
      // If still no nearby users, just show some popular users as fallback
      if (discoveryUsers.filter(u => u.discoveryType === 'nearby').length === 0 && type === 'nearby') {
        console.log('📍 No nearby users found, showing popular users as fallback');
        const popularUsersQuery = await db.collection(COLLECTIONS.USERS)
          .orderBy('followersCount', 'desc')
          .limit(10)
          .get();
        
        for (const doc of popularUsersQuery.docs) {
          if (doc.id === userId || connectedUserIds.has(doc.id)) continue;
          
          const userData = doc.data();
          const { placesCount, circlesCount } = await calculateUserPlaceCounts(doc.id);
          
          if (placesCount >= 5) {
            discoveryUsers.push({
              id: doc.id,
              ...userData,
              placesCount,
              circlesCount,
              discoveryType: 'popular', // Mark as popular since they're not actually nearby
              isFollowing: userFollowing.has(doc.id),
              connectionStatus: connectedUserIds.has(doc.id) ? 'accepted' : 'none'
            });
          }
        }
      }
    }
    
    // 3. Friends of Friends
    if (type === 'friendsOfFriends' || type === 'all') {
      const friendsOfFriendsMap = new Map();
      
      // Check if user has any connections first
      if (connectedUserIds.size === 0) {
        console.log('👥 User has no connections, cannot show mutual connections');
        
        // If no connections and specifically asking for friendsOfFriends, return empty
        if (type === 'friendsOfFriends') {
          // Return empty array - user needs connections first to see mutual connections
          console.log('👥 Returning empty array for mutual connections - user has no connections');
        }
      } else {
        // Get connections of connected users
        for (const connectedUserId of connectedUserIds) {
          const friendConnectionsQuery = await db.collection(COLLECTIONS.CONNECTIONS)
            .where('userId', '==', connectedUserId)
            .where('status', '==', 'accepted')
            .get();
          
          friendConnectionsQuery.forEach(doc => {
            const friendOfFriendId = doc.data().connectedUserId;
            
            // Skip self and already connected users
            if (friendOfFriendId !== userId && !connectedUserIds.has(friendOfFriendId)) {
              if (!friendsOfFriendsMap.has(friendOfFriendId)) {
                friendsOfFriendsMap.set(friendOfFriendId, []);
              }
              friendsOfFriendsMap.get(friendOfFriendId).push(connectedUserId);
            }
          });
        }
        
        // Get user data for friends of friends
        const sortedFriendsOfFriends = Array.from(friendsOfFriendsMap.entries())
          .sort((a, b) => b[1].length - a[1].length) // Sort by mutual connections count
          .slice(0, 30);
        
        // If no friends of friends found, return empty for mutual connections request
        if (sortedFriendsOfFriends.length === 0 && type === 'friendsOfFriends') {
          console.log('👥 No friends of friends found');
          // Return empty array - no mutual connections available
        } else {
          // Process friends of friends normally
          for (const [friendOfFriendId, mutualConnections] of sortedFriendsOfFriends) {
            const userDoc = await db.collection(COLLECTIONS.USERS).doc(friendOfFriendId).get();
            
            if (userDoc.exists) {
              const userData = userDoc.data();
              const { placesCount, circlesCount } = await calculateUserPlaceCounts(friendOfFriendId);
              
              if (placesCount > 0) {
                // Get names of mutual connections
                const mutualNames = [];
                for (const mutualId of mutualConnections.slice(0, 3)) {
                  const mutualDoc = await db.collection(COLLECTIONS.USERS).doc(mutualId).get();
                  if (mutualDoc.exists) {
                    mutualNames.push(mutualDoc.data().displayName);
                  }
                }
                
                discoveryUsers.push({
                  id: friendOfFriendId,
                  ...userData,
                  placesCount,
                  circlesCount,
                  discoveryType: 'friendsOfFriends',
                  mutualConnectionsCount: mutualConnections.length,
                  mutualConnectionNames: mutualNames,
                  isFollowing: userFollowing.has(friendOfFriendId),
                  connectionStatus: 'none'
                });
              }
            }
          }
        }
      }
    }
    
    // Remove duplicates and sort by relevance
    const uniqueUsers = new Map();
    discoveryUsers.forEach(user => {
      if (!uniqueUsers.has(user.id)) {
        uniqueUsers.set(user.id, user);
      }
    });
    
    const finalUsers = Array.from(uniqueUsers.values())
      .sort((a, b) => {
        // Prioritize friends of friends
        if (a.discoveryType === 'friendsOfFriends' && b.discoveryType !== 'friendsOfFriends') return -1;
        if (b.discoveryType === 'friendsOfFriends' && a.discoveryType !== 'friendsOfFriends') return 1;
        
        // Then nearby users
        if (a.discoveryType === 'nearby' && b.discoveryType === 'popular') return -1;
        if (b.discoveryType === 'nearby' && a.discoveryType === 'popular') return 1;
        
        // Finally sort by places count
        return (b.placesCount || 0) - (a.placesCount || 0);
      })
      .slice(0, parseInt(limit));
    
    console.log(`✅ Found ${finalUsers.length} discovery users`);
    
    res.json({
      success: true,
      users: finalUsers,
      count: finalUsers.length
    });
    
  } catch (error) {
    console.error('Error getting discovery users:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get discovery users',
      error: error.message
    });
  }
};

// Search users by name, username, or email
const searchUsersAdvanced = async (req, res) => {
  try {
    const userId = req.user.uid;
    const { query, limit = 20 } = req.query;
    
    if (!query || query.length < 2) {
      return res.status(400).json({
        success: false,
        message: 'Search query must be at least 2 characters'
      });
    }
    
    console.log(`🔍 Searching users with query: "${query}"`);
    
    const searchTerm = query.toLowerCase();
    const searchResults = [];
    const processedIds = new Set();
    
    // Search by display name (using Firestore's limited text search)
    // Note: For production, consider using Algolia or ElasticSearch
    const usersSnapshot = await db.collection(COLLECTIONS.USERS)
      .orderBy('displayNameLowercase')
      .startAt(searchTerm)
      .endAt(searchTerm + '\uf8ff')
      .limit(50)
      .get();
    
    usersSnapshot.forEach(doc => {
      if (doc.id !== userId && !processedIds.has(doc.id)) {
        processedIds.add(doc.id);
        searchResults.push({ id: doc.id, ...doc.data(), matchType: 'name' });
      }
    });
    
    // Search by email (exact match for privacy)
    if (query.includes('@')) {
      const emailQuery = await db.collection(COLLECTIONS.USERS)
        .where('email', '==', searchTerm)
        .limit(1)
        .get();
      
      emailQuery.forEach(doc => {
        if (doc.id !== userId && !processedIds.has(doc.id)) {
          processedIds.add(doc.id);
          searchResults.push({ id: doc.id, ...doc.data(), matchType: 'email' });
        }
      });
    }
    
    // Search by username if implemented
    const usernameQuery = await db.collection(COLLECTIONS.USERS)
      .where('username', '==', searchTerm)
      .limit(1)
      .get();
    
    usernameQuery.forEach(doc => {
      if (doc.id !== userId && !processedIds.has(doc.id)) {
        processedIds.add(doc.id);
        searchResults.push({ id: doc.id, ...doc.data(), matchType: 'username' });
      }
    });
    
    // Get connection status and calculate place counts
    const [connectionsSnapshot, currentUserDoc] = await Promise.all([
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', userId)
        .get(),
      db.collection(COLLECTIONS.USERS).doc(userId).get()
    ]);
    
    const connections = new Map();
    connectionsSnapshot.forEach(doc => {
      const conn = doc.data();
      connections.set(conn.connectedUserId, conn.status);
    });
    
    const currentUserData = currentUserDoc.data();
    const userFollowing = new Set(currentUserData.following || []);
    
    // Enrich search results with additional data
    const enrichedResults = [];
    for (const user of searchResults) {
      const { placesCount, circlesCount } = await calculateUserPlaceCounts(user.id);
      
      enrichedResults.push({
        id: user.id,
        email: user.email,
        displayName: user.displayName,
        profilePicture: user.profilePicture,
        bio: user.bio,
        username: user.username,
        placesCount,
        circlesCount,
        followersCount: user.followersCount || 0,
        connectionStatus: connections.get(user.id) || 'none',
        isFollowing: userFollowing.has(user.id),
        matchType: user.matchType,
        isVerified: user.isVerified || false
      });
    }
    
    // Sort by relevance
    enrichedResults.sort((a, b) => {
      // Exact matches first
      if (a.matchType === 'email' || a.matchType === 'username') return -1;
      if (b.matchType === 'email' || b.matchType === 'username') return 1;
      
      // Then by places count
      return (b.placesCount || 0) - (a.placesCount || 0);
    });
    
    const finalResults = enrichedResults.slice(0, parseInt(limit));
    
    console.log(`✅ Found ${finalResults.length} users matching "${query}"`);
    
    res.json({
      success: true,
      users: finalResults,
      count: finalResults.length,
      query
    });
    
  } catch (error) {
    console.error('Error searching users:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to search users',
      error: error.message
    });
  }
};

// Update user's last known location
const updateUserLocation = async (req, res) => {
  try {
    const userId = req.user.uid;
    const { latitude, longitude } = req.body;
    
    if (!latitude || !longitude) {
      return res.status(400).json({
        success: false,
        message: 'Latitude and longitude are required'
      });
    }
    
    const lat = parseFloat(latitude);
    const lng = parseFloat(longitude);
    
    // Generate geohash for location-based queries
    const hash = geofire.geohashForLocation([lat, lng]);
    
    await db.collection(COLLECTIONS.USERS).doc(userId).update({
      lastKnownLocation: {
        latitude: lat,
        longitude: lng,
        timestamp: new Date().toISOString()
      },
      geohash: hash
    });
    
    console.log(`📍 Updated location for user ${userId}: ${lat}, ${lng}`);
    
    res.json({
      success: true,
      message: 'Location updated successfully'
    });
    
  } catch (error) {
    console.error('Error updating user location:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to update location',
      error: error.message
    });
  }
};

module.exports = {
  getDiscoverUsers,
  searchUsersAdvanced,
  updateUserLocation
};