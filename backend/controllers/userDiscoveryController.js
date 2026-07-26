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

// Bulk place/circle counts for ALL users from a single circles read, avoiding
// an N+1 per-candidate query. ownerId -> { placesCount, circlesCount }.
const buildPlaceCountMap = async () => {
  const snap = await db.collection(COLLECTIONS.CIRCLES).get();
  const map = new Map();
  snap.docs.forEach((doc) => {
    const c = doc.data();
    if (!c.owner) return;
    const cur = map.get(c.owner) || { placesCount: 0, circlesCount: 0 };
    cur.placesCount += (c.placesCount || 0);
    cur.circlesCount += 1;
    map.set(c.owner, cur);
  });
  return map;
};

// Get user discovery suggestions for the network tabs:
//   popular          - scorecard of ALL users, ranked by places (connections/follows included)
//   discover / all   - only people you are NOT connected to and do NOT follow, ranked by places
//   nearby           - users closest by zipcode
//   friendsOfFriends - mutual connections (people your connections know)
const getDiscoverUsers = async (req, res) => {
  try {
    const userId = req.user.uid;
    const { type = 'all', limit = 20 } = req.query;
    const limitNum = parseInt(limit) || 20;

    // Current user, BOTH connection directions, and the bulk place-count map,
    // all in parallel.
    const [currentUserDoc, outConns, inConns, placeCounts] = await Promise.all([
      db.collection(COLLECTIONS.USERS).doc(userId).get(),
      db.collection(COLLECTIONS.CONNECTIONS).where('userId', '==', userId).get(),
      db.collection(COLLECTIONS.CONNECTIONS).where('connectedUserId', '==', userId).get(),
      buildPlaceCountMap()
    ]);

    const currentUserData = currentUserDoc.exists ? currentUserDoc.data() : {};
    const following = new Set(currentUserData.following || []);

    // Connection status by the OTHER user's id, from both directions. (The old
    // code only checked connections the user initiated, so half of a user's
    // connections leaked into/were hidden from these lists inconsistently.)
    const connStatus = new Map();
    outConns.docs.forEach((d) => connStatus.set(d.data().connectedUserId, d.data().status));
    inConns.docs.forEach((d) => {
      if (!connStatus.has(d.data().userId)) connStatus.set(d.data().userId, d.data().status);
    });
    const hasActiveConnection = (id) => ['accepted', 'pending'].includes(connStatus.get(id));

    const shape = (doc, discoveryType, extra = {}) => {
      const u = doc.data();
      const { placesCount, circlesCount } = placeCounts.get(doc.id) || { placesCount: 0, circlesCount: 0 };
      return {
        id: doc.id,
        ...u,
        placesCount,
        circlesCount,
        discoveryType,
        isFollowing: following.has(doc.id),
        connectionStatus: connStatus.get(doc.id) || 'none',
        ...extra
      };
    };

    let users = [];

    if (type === 'popular') {
      // Scorecard: every user except you, ranked by places. Connections and
      // people you follow are intentionally included.
      const snap = await db.collection(COLLECTIONS.USERS).limit(500).get();
      users = snap.docs
        .filter((d) => d.id !== userId)
        .map((d) => shape(d, 'popular'))
        .sort((a, b) => (b.placesCount - a.placesCount) || ((b.followersCount || 0) - (a.followersCount || 0)));
    } else if (type === 'nearby') {
      // Closest by zipcode: rank by numeric distance between the requester's
      // zip and each user's zip. Only users with a comparable zipcode qualify.
      const myZip = parseInt(String(req.query.zipcode || currentUserData.zipcode || '').slice(0, 5), 10);
      const snap = await db.collection(COLLECTIONS.USERS).limit(500).get();
      users = snap.docs
        .filter((d) => d.id !== userId)
        .map((d) => {
          const z = parseInt(String(d.data().zipcode || '').slice(0, 5), 10);
          const zipDistance = (Number.isFinite(myZip) && Number.isFinite(z)) ? Math.abs(z - myZip) : null;
          return { doc: d, zipDistance };
        })
        .filter((x) => x.zipDistance !== null)
        .sort((a, b) => a.zipDistance - b.zipDistance)
        .map((x) => shape(x.doc, 'nearby', { zipDistance: x.zipDistance }));
    } else if (type === 'friendsOfFriends') {
      // Mutual: people your accepted connections are connected to, that you
      // are not already connected to.
      const connectionIds = [...connStatus.keys()].filter((id) => connStatus.get(id) === 'accepted');
      const foFMap = new Map(); // fofId -> [via connection ids]
      if (connectionIds.length > 0) {
        const foFSnaps = await Promise.all(connectionIds.map((cid) =>
          db.collection(COLLECTIONS.CONNECTIONS).where('userId', '==', cid).where('status', '==', 'accepted').get()
        ));
        foFSnaps.forEach((snap, i) => {
          const via = connectionIds[i];
          snap.docs.forEach((d) => {
            const fof = d.data().connectedUserId;
            if (fof !== userId && !hasActiveConnection(fof)) {
              if (!foFMap.has(fof)) foFMap.set(fof, []);
              foFMap.get(fof).push(via);
            }
          });
        });
      }
      const sorted = [...foFMap.entries()].sort((a, b) => b[1].length - a[1].length).slice(0, limitNum);
      if (sorted.length > 0) {
        const docs = await db.getAll(...sorted.map(([id]) => db.collection(COLLECTIONS.USERS).doc(id)));
        const byId = new Map(docs.filter((d) => d.exists).map((d) => [d.id, d]));
        users = sorted
          .filter(([id]) => byId.has(id))
          .map(([id, via]) => shape(byId.get(id), 'friendsOfFriends', { mutualConnectionsCount: via.length }))
          .filter((u) => u.placesCount > 0);
      }
    } else {
      // 'discover' / 'all': people you have NO active connection with and do
      // not follow, ranked by places (new people worth discovering).
      const snap = await db.collection(COLLECTIONS.USERS).limit(500).get();
      users = snap.docs
        .filter((d) => d.id !== userId && !hasActiveConnection(d.id) && !following.has(d.id))
        .map((d) => shape(d, 'discover'))
        .filter((u) => u.placesCount > 0)
        .sort((a, b) => b.placesCount - a.placesCount);
    }

    const finalUsers = users.slice(0, limitNum);
    console.log(`✅ Discovery (${type}): ${finalUsers.length} users`);
    res.json({ success: true, users: finalUsers, count: finalUsers.length });
  } catch (error) {
    console.error('Error getting discovery users:', error);
    res.status(500).json({ success: false, message: 'Failed to get discovery users', error: error.message });
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