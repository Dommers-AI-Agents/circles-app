// backend/controllers/userDiscoveryController.js
const { getFirestore } = require('../config/firebase');
const { projectPublicUser } = require('../services/publicUserProjection');
const { FieldValue } = require('firebase-admin/firestore');
const { COLLECTIONS } = require('../models/FirestoreModels');
const geofire = require('geofire-common');
const { getPlaceCountMap } = require('../services/userStatsCache');
const { isHiddenAccount, HIDDEN_ACCOUNT_FIELDS } = require('../services/hiddenAccounts');
const { getSuggestionsFor } = require('../services/suggestionEngine');
const { coarseDistanceKm } = require('../services/publicProjection');
const { clampPagination } = require('../utils/pagination');
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
//   following        - people you follow but aren't connected with yet (Connect offered)
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
        ...projectPublicUser(u),
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
      // App Review and test accounts never surface (services/hiddenAccounts.js)
      return docs.filter((d) => d.exists && !isHiddenAccount(d.data()));
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
      // Suggestions are people you are NOT connected with: an existing
      // connection (or a request either way) drops out here like it does
      // from the engine's list (Wes, 2026-10-29: See all listed connections)
      const poolIds = rankedIds.filter((id) => isSuggestable(id) && !hasActiveConnection(id)).slice(0, NEARBY_POOL);
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
          // Coarse buckets only — an exact distance from a caller-chosen
          // origin let anyone triangulate another user's GPS fix (security
          // audit 2026-10-01). Ranking above still uses the true distance.
          .map((x) => shape(x.doc, 'nearby', { distance: coarseDistanceKm(x.distance) }));
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
      // You're on it too ("Where do you land?" — the cell shows your own
      // row as "This is you · Share").
      const pageIds = rankedIds
        .filter((id) => !dismissed.has(id) && !blockedSet.has(id))
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
      const pending = [...myFollowers].filter((id) => isSuggestable(id) && !hasActiveConnection(id))
        .slice(0, offsetNum + limitNum + 1);
      if (pending.length > 0) {
        const docs = await db.getAll(...pending.map((id) => db.collection(COLLECTIONS.USERS).doc(id)));
        users = docs.filter((d) => d.exists && !isHiddenAccount(d.data())).map((d) => shape(d, 'followsYou'));
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
        let fresh = precomputed.filter((s) => isSuggestable(s.userId) && !hasActiveConnection(s.userId));
        // Stored suggestions may predate an account being marked as a test
        // account: check the ones this page could show
        const pageCandidates = fresh.slice(0, offsetNum + limitNum + 11);
        if (pageCandidates.length > 0) {
          const docs = await db.getAll(
            ...pageCandidates.map((x) => db.collection(COLLECTIONS.USERS).doc(x.userId)),
            { fieldMask: HIDDEN_ACCOUNT_FIELDS }
          );
          const hidden = new Set(docs.filter((d) => !d.exists || isHiddenAccount(d.data())).map((d) => d.id));
          fresh = fresh.filter((x) => !hidden.has(x.userId));
        }
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
        // The default accounts (Wes, Brittany) follow nearly everyone, so
        // "Followed by Wes" was a random slice of the user base — only people
        // they chose to follow count as a bridge (new-user audit, 2026-10-09)
        const defaults = await require('../services/defaultAccounts').defaultFollowIds(db);
        const viaMap = new Map();
        const followedIds = [...following].filter((id) => !defaults.has(id)).slice(0, 50);
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
          const byId = new Map(docs.filter((d) => d.exists && !isHiddenAccount(d.data())).map((d) => [d.id, d]));
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
    } else if (type === 'following') {
      // People you follow but aren't connected with (and haven't asked yet).
      // Follow is one-way; Connect is the LinkedIn-style "I know them" step,
      // and it was nowhere to be found for exactly these people: every
      // suggestion surface dropped anyone already followed, so the only way
      // to connect was to open each profile (Wes, 2026-10-12). Mutual follows
      // first — they already opted in — then biggest collections.
      const candidateIds = [...following].filter((id) =>
        id !== userId && !dismissed.has(id) && !blockedSet.has(id) && !hasActiveConnection(id));
      const placesOf = (id) => ((placeCounts.get(id) || {}).placesCount || 0);
      const mutual = (id) => (myFollowers.has(id) ? 1 : 0);
      const orderedIds = candidateIds
        .sort((a, b) => (mutual(b) - mutual(a)) || (placesOf(b) - placesOf(a)))
        .slice(0, pageWindow);
      // Merged, deactivated and test accounts drop out in fetchDocsByIds
      const order = new Map(orderedIds.map((id, i) => [id, i]));
      users = (await fetchDocsByIds(orderedIds))
        .map((d) => shape(d, 'following', {
          suggestionReason: myFollowers.has(d.id) ? '👋 You follow each other' : 'You follow them'
        }))
        .sort((a, b) => order.get(a.id) - order.get(b.id));
    } else if (type === 'everyone') {
      // The full "People on FavCircles" list behind Discover's See all:
      // everyone on FavCircles, people with no places yet and people you
      // dismissed included (an X tapped by mistake shouldn't hide someone
      // for good; Wes, 2026-10-01). New-to-you people first, then people you
      // follow but aren't connected with, then people with a request open;
      // within each, biggest collections then newest sign-ups. Each row's
      // button says where you stand. Blocked, merged and test accounts stay
      // out — and so do your connections: a list for finding people has no
      // use for the ones you already have (Wes, 2026-10-29).
      const everyoneSnap = await db.collection(COLLECTIONS.USERS)
        .select('createdAt', ...HIDDEN_ACCOUNT_FIELDS).get();
      const placesOf = (id) => ((placeCounts.get(id) || {}).placesCount || 0);
      // createdAt is an ISO string on most accounts, a Firestore Timestamp on old ones
      const joined = (d) => {
        const v = d.data().createdAt;
        if (v && typeof v.toMillis === 'function') return v.toMillis();
        return Date.parse(v) || 0;
      };
      const group = (id) => (hasActiveConnection(id) ? 2 : following.has(id) ? 1 : 0);
      const pageIds = everyoneSnap.docs
        .filter((d) => {
          const u = d.data();
          return d.id !== userId && !blockedSet.has(d.id) && !isHiddenAccount(u)
            && connStatus.get(d.id) !== 'accepted';
        })
        .sort((a, b) => (group(a.id) - group(b.id)) || (placesOf(b.id) - placesOf(a.id)) || (joined(b) - joined(a)))
        .map((d) => d.id)
        .slice(0, pageWindow);
      const order = new Map(pageIds.map((id, i) => [id, i]));
      users = (await fetchDocsByIds(pageIds))
        .map((d) => shape(d, 'everyone', placesOf(d.id) === 0 ? { suggestionReason: '🆕 New here — no places yet' } : {}))
        .sort((a, b) => order.get(a.id) - order.get(b.id));
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
    
    // Name words (indexed tokens, services/userSearchService), plus exact
    // email and username lookups — all three in parallel
    const { findUsersByName } = require('../services/userSearchService');
    const cardFields = ['profilePicture', 'bio', 'username', 'followersCount', 'isVerified'];
    const [byName, emailQuery, usernameQuery] = await Promise.all([
      findUsersByName(searchTerm, { fields: cardFields }),
      query.includes('@')
        ? db.collection(COLLECTIONS.USERS).where('email', '==', searchTerm.trim()).limit(1).get()
        : Promise.resolve({ docs: [] }),
      db.collection(COLLECTIONS.USERS).where('username', '==', searchTerm.trim()).limit(1).get()
    ]);

    // Exact email/username matches lead; then name matches by relevance
    const { searchRelevanceRank } = require('../services/publicProjection');
    const take = (id, data, matchType) => {
      if (id === userId || processedIds.has(id)) return;
      processedIds.add(id);
      searchResults.push({ id, ...data, matchType });
    };
    emailQuery.docs.forEach(doc => take(doc.id, doc.data(), 'email'));
    usernameQuery.docs.forEach(doc => take(doc.id, doc.data(), 'username'));
    byName
      .map(user => ({ user, rank: searchRelevanceRank(user, searchTerm.trim()) }))
      .sort((a, b) => a.rank - b.rank || (a.user.displayName || '').localeCompare(b.user.displayName || ''))
      .forEach(({ user }) => {
        const { id, ...data } = user;
        take(id, data, 'name');
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
    
    const currentUserData = currentUserDoc.data() || {};
    const userFollowing = new Set(currentUserData.following || []);
    // Blocked either way never appears in search (security audit 2026-10-01)
    const { excludedUserIds } = require('../services/moderationService');
    const blockedForSearch = excludedUserIds(currentUserData);
    
    // Enrich search results with additional data. Counts come from the bulk
    // map (15-min cache) — the old per-result circles query ran SERIALLY, up
    // to ~52 sequential Firestore round trips per search keystroke.
    const enrichedResults = [];
    for (const user of searchResults) {
      if (blockedForSearch.has(user.id)) continue;
      if (isHiddenAccount(user)) continue; // App Review and test accounts
      const { placesCount, circlesCount } = placeCounts.get(user.id) || { placesCount: 0, circlesCount: 0 };

      enrichedResults.push({
        id: user.id,
        // No email, even on an exact email match: the searcher already knows
        // what they typed, and `matchedBy: 'email'` says that's why this card
        // is here. Echoing the stored address back confirmed it verbatim
        // (security audit 2026-10-01).
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
        matchedBy: user.matchType,
        isVerified: user.isVerified || false
      });
    }
    
    // Order was set above: exact email/username, then name relevance
    
    // Clamp the client's ?limit (security audit 2026-10-01)
    const finalResults = enrichedResults.slice(0, clampPagination({ limit }, { defaultLimit: 20, maxLimit: 50 }).limit);
    
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