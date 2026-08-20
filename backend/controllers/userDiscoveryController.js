// backend/controllers/userDiscoveryController.js
const { getFirestore } = require('../config/firebase');
const { FieldValue } = require('firebase-admin/firestore');
const { COLLECTIONS } = require('../models/FirestoreModels');
const geofire = require('geofire-common');
const { getPlaceCountMap } = require('../services/userStatsCache');
const { getSuggestionsFor } = require('../services/suggestionEngine');
const {
  getAssumedLocation,
  effectiveCoords,
  decorateUserCards,
  isFreshAssumedLocation
} = require('../services/userCardEnrichment');

const db = getFirestore();

// Get user discovery suggestions for the network tabs:
//   popular          - scorecard of ALL users, ranked by places (connections/follows included)
//   discover / all   - only people you are NOT connected to and do NOT follow, ranked by places
//   nearby           - users closest by zipcode
//   friendsOfFriends - mutual connections (people your connections know)
const getDiscoverUsers = async (req, res) => {
  try {
    const userId = req.user.uid;
    const { type = 'all', limit = 20, offset = 0 } = req.query;
    const limitNum = parseInt(limit) || 20;
    const offsetNum = Math.max(parseInt(offset) || 0, 0);

    // Current user, BOTH connection directions, and the bulk place-count map,
    // all in parallel.
    const [currentUserDoc, outConns, inConns, placeCounts] = await Promise.all([
      db.collection(COLLECTIONS.USERS).doc(userId).get(),
      db.collection(COLLECTIONS.CONNECTIONS).where('userId', '==', userId).get(),
      db.collection(COLLECTIONS.CONNECTIONS).where('connectedUserId', '==', userId).get(),
      getPlaceCountMap()
    ]);

    const currentUserData = currentUserDoc.exists ? currentUserDoc.data() : {};
    const following = new Set(currentUserData.following || []);
    // Everyone who follows the caller. Already in the doc we just read, so
    // telling the client "this person follows you" costs nothing extra — and
    // it is what separates a one-way follow from a mutual one in the UI.
    const myFollowers = new Set(currentUserData.followers || []);
    // Suggestions the caller has explicitly dismissed should never come back.
    const dismissed = new Set(currentUserData.dismissedSuggestions || []);

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
        followsYou: myFollowers.has(doc.id),
        connectionStatus: connStatus.get(doc.id) || 'none',
        ...extra
      };
    };

    // Blocked users (either direction) never appear on any people surface
    const { excludedUserIds } = require('../services/moderationService');
    const blockedSet = excludedUserIds(currentUserData);

    // Every suggestion surface excludes the same groups. Previously only
    // the 'discover' branch filtered out people you already follow, so Popular
    // and Nearby kept offering you people you'd followed weeks ago.
    const isSuggestable = (id) =>
      id !== userId && !dismissed.has(id) && !following.has(id) && !blockedSet.has(id);

    // Candidate ranking is derived from the place-count map (already in
    // memory, 15-min cache) instead of a 500-doc users collection scan per
    // request: every ranked surface here orders by placesCount, and every
    // exclusion filter (self/dismissed/following/blocked/connection) is
    // id-based — so ids are ranked and filtered BEFORE any user doc is read,
    // and only the docs for one page are fetched. Users with zero circles
    // aren't in the map; they ranked at the very bottom of these lists before
    // and never surfaced within a page anyway.
    const rankedIds = [...placeCounts.entries()]
      .sort((a, b) => (b[1].placesCount || 0) - (a[1].placesCount || 0))
      .map(([id]) => id);
    // Small buffer past the page so the followersCount tiebreak (needs the
    // docs) can still reorder around the page boundary.
    const pageWindow = offsetNum + limitNum + 10;

    const fetchDocsByIds = async (ids) => {
      if (ids.length === 0) return [];
      const docs = await db.getAll(...ids.map((id) => db.collection(COLLECTIONS.USERS).doc(id)));
      return docs.filter((d) => d.exists);
    };

    let users = [];

    if (type === 'popular') {
      // Most active: ranked by places saved. People you already follow are
      // excluded (offering to follow someone you followed last week makes the
      // surface feel broken) — but the CALLER is included, at their honest
      // rank. Seeing yourself among the most active is the progress readout,
      // and the client turns your row's action into "share your profile"
      // instead of a follow button.
      const pageIds = rankedIds
        .filter((id) => id === userId || isSuggestable(id))
        .slice(0, pageWindow);
      users = (await fetchDocsByIds(pageIds))
        .map((d) => shape(d, 'popular'))
        .sort((a, b) => (b.placesCount - a.placesCount) || ((b.followersCount || 0) - (a.followersCount || 0)));
    } else if (type === 'nearby') {
      // Real geographic proximity — but with an ASSUMED location fallback.
      //
      // Only a handful of users ever grant GPS, so matching on
      // lastKnownLocation alone made "Near you" miss neighbors who simply
      // hadn't shared location. Now everyone's coordinates fall back to the
      // median of the places they save (cached on the user doc), which is
      // where they actually spend time.
      // Candidate pool: the 150 biggest suggestable collections (already
      // ranked by placesCount). Location has to be read per candidate, so the
      // pool is bounded here instead of scanning 500 user docs — and a person
      // with zero saved places has no assumed location and nothing to show on
      // a discovery card anyway.
      const NEARBY_POOL = 150;
      const poolIds = rankedIds.filter((id) => isSuggestable(id)).slice(0, NEARBY_POOL);
      const [poolDocs, origin] = await Promise.all([
        fetchDocsByIds(poolIds),
        effectiveCoords(userId, currentUserData)
      ]);

      if (origin) {
        // Locate candidates: GPS ping → fresh cached assumption → compute
        // fresh. The compute budget is small on purpose: each compute is a
        // 40-doc places query + a write-back, but the result is CACHED on the
        // user doc for 7 days — so successive requests work through the tail
        // a few users at a time instead of one request fanning out into
        // hundreds of queries.
        const candidates = poolDocs;
        let computeBudget = 5;

        const located = (await Promise.all(candidates.map(async (d) => {
          const data = d.data();
          const gps = data.lastKnownLocation;
          if (gps && Number.isFinite(gps.latitude) && Number.isFinite(gps.longitude)) {
            return { doc: d, lat: gps.latitude, lng: gps.longitude };
          }
          const cached = data.assumedLocation;
          if (isFreshAssumedLocation(cached)) {
            return Number.isFinite(cached.latitude)
              ? { doc: d, lat: cached.latitude, lng: cached.longitude }
              : null;
          }
          if (((placeCounts.get(d.id) || {}).placesCount || 0) === 0) return null;
          if (computeBudget-- <= 0) return null;
          const assumed = await getAssumedLocation(d.id, data);
          return (assumed && Number.isFinite(assumed.latitude))
            ? { doc: d, lat: assumed.latitude, lng: assumed.longitude }
            : null;
        }))).filter(Boolean);

        // Distance in bands, activity-weighted inside each band: "near" keeps
        // meaning near, but among similarly-near people the big AND active
        // collections lead — a 10-place user who was here this week outranks
        // a 12-place account dormant since last year. Anyone beyond 160 km
        // isn't "near you" at all.
        const activityScore = (doc) => {
          const placesCount = (placeCounts.get(doc.id) || {}).placesCount || 0;
          const lastActive = doc.data().lastActive ? new Date(doc.data().lastActive) : null;
          const daysSince = lastActive ? (Date.now() - lastActive.getTime()) / 86400000 : Infinity;
          const recencyBoost = daysSince <= 7 ? 30 : daysSince <= 30 ? 10 : 0;
          return placesCount + recencyBoost;
        };
        users = located
          .map((x) => {
            const distance = geofire.distanceBetween(
              [origin.latitude, origin.longitude], [x.lat, x.lng]);
            const band = distance <= 2 ? 0 : distance <= 10 ? 1 : distance <= 40 ? 2 : distance <= 160 ? 3 : 4;
            return { ...x, distance, band };
          })
          .filter((x) => x.band < 4)
          .sort((a, b) => (a.band - b.band) || (activityScore(b.doc) - activityScore(a.doc)))
          .map((x) => shape(x.doc, 'nearby', { distance: Math.round(x.distance * 10) / 10 }));
      } else {
        // No coordinates at all for the caller — fall back to the zipcode
        // prefix, which at least groups a metro area together. Same
        // activity-weighted order as the located path (was unsorted).
        const myZip = String(req.query.zipcode || currentUserData.zipcode || '').slice(0, 5);
        const myPrefix = myZip.slice(0, 3);
        if (myPrefix.length === 3) {
          const zipScore = (d) => {
            const placesCount = (placeCounts.get(d.id) || {}).placesCount || 0;
            const lastActive = d.data().lastActive ? new Date(d.data().lastActive) : null;
            const daysSince = lastActive ? (Date.now() - lastActive.getTime()) / 86400000 : Infinity;
            return placesCount + (daysSince <= 7 ? 30 : daysSince <= 30 ? 10 : 0);
          };
          users = poolDocs
            .filter((d) => String(d.data().zipcode || '').slice(0, 3) === myPrefix)
            .sort((a, b) => zipScore(b) - zipScore(a))
            .map((d) => shape(d, 'nearby'));
        }
      }
    } else if (type === 'leaderboard') {
      // The Popular tab: a scorecard, not a suggestion list. Everyone —
      // including people you follow or are connected to — ranked by the size
      // of their collection. Watching people you know climb is the fun.
      const pageIds = rankedIds
        .filter((id) => id !== userId && !dismissed.has(id) && !blockedSet.has(id))
        .filter((id) => ((placeCounts.get(id) || {}).placesCount || 0) > 0)
        .slice(0, pageWindow);
      users = (await fetchDocsByIds(pageIds))
        .map((d) => shape(d, 'leaderboard'))
        .sort((a, b) => (b.placesCount - a.placesCount) || ((b.followersCount || 0) - (a.followersCount || 0)));
    } else if (type === 'followsYou') {
      // People already following the caller who the caller does not follow
      // back. Highest-intent suggestion there is — the other person has
      // already opted in, so following back is a single tap with no approval
      // step and no chance of rejection.
      // +1 so the final page slice can tell whether more remain (hasMore)
      const pending = [...myFollowers].filter((id) => isSuggestable(id)).slice(0, offsetNum + limitNum + 1);
      if (pending.length > 0) {
        const docs = await db.getAll(...pending.map((id) => db.collection(COLLECTIONS.USERS).doc(id)));
        users = docs.filter((d) => d.exists).map((d) => shape(d, 'followsYou'));
      }
    } else if (type === 'friendsOfFriends') {
      // People you may know, served from the precomputed suggestion doc.
      //
      // The old version walked accepted *connections* only, which is exactly
      // the sparse graph now that Follow is the primary action. The engine
      // traverses the follow graph instead, and also folds in the two taste
      // signals — so this list can now say "also saved Café Mogador" rather
      // than only "friends with X".
      const precomputed = await getSuggestionsFor(userId);

      if (precomputed && precomputed.length > 0) {
        const fresh = precomputed.filter((s) => isSuggestable(s.userId) && !hasActiveConnection(s.userId));
        users = fresh.slice(0, offsetNum + limitNum + 1).map((s) => ({
          id: s.userId,
          _id: s.userId,
          displayName: s.displayName,
          profilePicture: s.profilePicture,
          isVerified: s.isVerified,
          placesCount: s.placesCount,
          circlesCount: s.circlesCount,
          discoveryType: s.signal,
          suggestionReason: s.reason,
          isFollowing: false,
          followsYou: myFollowers.has(s.userId),
          connectionStatus: connStatus.get(s.userId) || 'none'
        }));
      } else {
        // No doc yet (new account, or the nightly job hasn't run). Fall back to
        // a shallow live walk of the follow graph so the section is never empty
        // just because the batch hasn't caught up.
        const viaMap = new Map();
        const followedIds = [...following].slice(0, 50);
        if (followedIds.length > 0) {
          const followedDocs = await db.getAll(
            ...followedIds.map((id) => db.collection(COLLECTIONS.USERS).doc(id))
          );
          followedDocs.forEach((doc) => {
            if (!doc.exists) return;
            const viaName = doc.data().displayName || 'Someone';
            (doc.data().following || []).forEach((secondHop) => {
              if (!isSuggestable(secondHop) || hasActiveConnection(secondHop)) return;
              if (!viaMap.has(secondHop)) viaMap.set(secondHop, []);
              viaMap.get(secondHop).push(viaName);
            });
          });
        }

        const sorted = [...viaMap.entries()].sort((a, b) => b[1].length - a[1].length).slice(0, offsetNum + limitNum + 1);
        if (sorted.length > 0) {
          const docs = await db.getAll(...sorted.map(([id]) => db.collection(COLLECTIONS.USERS).doc(id)));
          const byId = new Map(docs.filter((d) => d.exists).map((d) => [d.id, d]));
          users = sorted
            .filter(([id]) => byId.has(id))
            .map(([id, via]) => shape(byId.get(id), 'friendsOfFriends', {
              mutualConnectionsCount: via.length,
              mutualConnectionNames: via.slice(0, 3),
              suggestionReason: via.length > 1
                ? `Followed by ${via[0]} + ${via.length - 1} others`
                : `Followed by ${via[0]}`
            }));
        }
      }
    } else {
      // 'discover' / 'all': people you have NO active connection with and do
      // not follow, ranked by places (new people worth discovering).
      const pageIds = rankedIds
        .filter((id) => isSuggestable(id) && !hasActiveConnection(id))
        .filter((id) => ((placeCounts.get(id) || {}).placesCount || 0) > 0)
        .slice(0, pageWindow);
      users = (await fetchDocsByIds(pageIds))
        .map((d) => shape(d, 'discover'))
        .sort((a, b) => b.placesCount - a.placesCount);
    }

    // Page the ordered result. `offset` is optional — existing clients that
    // send only `limit` get the same first page as before.
    const finalUsers = users.slice(offsetNum, offsetNum + limitNum);
    await decorateUserCards(finalUsers);
    console.log(`✅ Discovery (${type}): ${finalUsers.length} users (offset ${offsetNum})`);
    res.json({
      success: true,
      users: finalUsers,
      count: finalUsers.length,
      hasMore: users.length > offsetNum + limitNum
    });
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
    
    // Get connection status and the bulk place-count map
    const [connectionsSnapshot, currentUserDoc, placeCounts] = await Promise.all([
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', userId)
        .get(),
      db.collection(COLLECTIONS.USERS).doc(userId).get(),
      getPlaceCountMap()
    ]);
    
    const connections = new Map();
    connectionsSnapshot.forEach(doc => {
      const conn = doc.data();
      connections.set(conn.connectedUserId, conn.status);
    });
    
    const currentUserData = currentUserDoc.data();
    const userFollowing = new Set(currentUserData.following || []);
    
    // Enrich search results with additional data. Counts come from the bulk
    // map (15-min cache) — the old per-result circles query ran SERIALLY, up
    // to ~52 sequential Firestore round trips per search keystroke.
    const enrichedResults = [];
    for (const user of searchResults) {
      const { placesCount, circlesCount } = placeCounts.get(user.id) || { placesCount: 0, circlesCount: 0 };

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

// Dismiss a suggested user so they stop being offered. Without this the same
// faces reappear in Discover forever, which reads as the list being broken.
const dismissSuggestion = async (req, res) => {
  try {
    const userId = req.user.uid;
    const targetUserId = req.body.userId;

    if (!targetUserId) {
      return res.status(400).json({ success: false, message: 'userId is required' });
    }

    await db.collection(COLLECTIONS.USERS).doc(userId).update({
      dismissedSuggestions: FieldValue.arrayUnion(targetUserId)
    });

    res.json({ success: true, message: 'Suggestion dismissed' });
  } catch (error) {
    console.error('Error dismissing suggestion:', error);
    res.status(500).json({ success: false, message: 'Failed to dismiss suggestion', error: error.message });
  }
};

module.exports = {
  getDiscoverUsers,
  searchUsersAdvanced,
  updateUserLocation,
  dismissSuggestion
};