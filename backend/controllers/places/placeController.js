// controllers/places/placeController.js
// Place save records: list by circle(s), get, create, update, delete, search, address edit, reorder, move, add-existing, my-save lookups
// Split out of firebasePlaceController.js (handlers unchanged).
const { getFirestore } = require('../../config/firebase');
const { queryInChunks } = require('../../utils/firestoreChunks');
const { COLLECTIONS, validatePlace, serializeDoc, serializeQuerySnapshot } = require('../../models/FirestoreModels');
const geofire = require('geofire-common');
const { normalizeUserId, isSameUser } = require('../../services/idService');
const { ensureGlobalPlaceLink } = require('../../services/globalPlaceResolver');
const { indexPlaceRemoved, indexPlaceMoved } = require('../../services/circleLocationSummary');
const { trackPlaceAdded, markCirclePlacesViewed } = require('../../services/activityService');
const placeCache = require('../../services/placeCache');
const piggyBankService = require('../../services/piggyBankService');
const { sameVenue, carryOverPatch } = require('../../services/placeMoveMerge');
const { normalizePhotosArray, overlayVenuePhotos, overlayVenueFields, getGlobalSocial, fetchGlobalSocialMap, buildAddedByUserMap, isPlaceVisibleToViewer } = require('../../services/placeReadService');
const { resolveIncomingPrivacy, canViewCircle } = require('../../services/visibility');
const { canViewCircleFor } = require('../../services/circleAccess');
const { validateGuestList } = require('../../services/innerCircleService');
const { buildViewerContext, makeViewerContext } = require('../../services/viewerContext');
const { getInnerCircleGrantorIds, getInnerCircleGrantorLists } = require('../../utils/networkAccess');
const { listIdFor } = require('../../services/innerCircleLists');
const { getMyCheckInStats } = require('../../services/checkInStatsService');
const homePromptService = require('../../services/homePromptService');
const db = getFirestore();
const { propagateVenueUpdates } = require('../../services/placeVenueSync.js');
const venueDetails = require('../../services/venueDetailsService');
const { sendServiceError } = require('../../utils/serviceError');
const { publicUserSummary } = require('../../services/publicProjection');

const placeSaveService = require('../../services/placeSaveService');
const { isVerifiedVenueOwner } = placeSaveService;

// @desc    Get places by circle ID
// @route   GET /api/circles/:circleId/places
// @access  Private
exports.getPlacesByCircleId = async (req, res, next) => {
  try {
    const { circleId } = req.params;

    // First verify user has access to this circle
    const circleRef = db.collection(COLLECTIONS.CIRCLES).doc(circleId);
    const circleDoc = await circleRef.get();

    if (!circleDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Circle not found'
      });
    }

    const circle = serializeDoc(circleDoc);

    // Both-direction connection docs between viewer and owner. Fetched lazily
    // and reused by the activity/isNew pass below instead of re-querying the
    // same pair.
    const fetchOwnerConnectionDocs = () => Promise.all([
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', req.user.uid)
        .where('connectedUserId', '==', circle.owner)
        .where('status', '==', 'accepted')
        .get(),
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', circle.owner)
        .where('connectedUserId', '==', req.user.uid)
        .where('status', '==', 'accepted')
        .get()
    ]).then(([c1, c2]) => [...c1.docs, ...c2.docs]);

    let ownerConnectionDocs = null;

    if (!(await canViewCircleFor(circle, req.user.uid))) {
      return res.status(403).json({
        success: false,
        message: 'Not authorized to access this circle'
      });
    }

    // Get places for this circle, ordered by creation date (newest first)
    // Filter out soft-deleted places - need to handle both null and undefined values
    // First get all places for this circle, then filter in code since Firestore
    // treats null and undefined differently and we need to exclude only non-null values
    const placesSnapshot = await db.collection(COLLECTIONS.PLACES)
      .where('circleId', '==', circleId)
      .orderBy('createdAt', 'desc')
      .get();
      
    // Filter out soft-deleted places, and places marked Private that the
    // viewer doesn't own (private is owner-only even in a visible circle)
    const allPlaces = serializeQuerySnapshot(placesSnapshot);
    const viewerCtx = await buildViewerContext(req.user.uid);
    const places = allPlaces.filter(place =>
      (place.deletedAt === null || place.deletedAt === undefined) &&
      isPlaceVisibleToViewer(place, req.user.uid, viewerCtx)
    );

    // Get unique user IDs who added places
    const userIds = [...new Set(places.map(place => place.addedBy))];
    
    // Fetch user information for all users who added places
    const userPromises = userIds.map(userId => {
      // Handle complex ID format if needed
      let actualUserId = userId;
      if (userId && userId.includes('.')) {
        const parts = userId.split('.');
        if (parts.length >= 2) {
          actualUserId = parts[1]; // Use the middle part as Firebase UID
        }
      }
      return db.collection(COLLECTIONS.USERS).doc(actualUserId).get();
    });
    const userDocs = await Promise.all(userPromises);
    
    // Create a map of user information
    const userMap = new Map();
    userDocs.forEach((doc, index) => {
      if (doc.exists) {
        const userData = serializeDoc(doc);
        const originalUserId = userIds[index]; // The original ID from the place
        
        // Map both the simple and complex ID formats. Name and photo only —
        // contributors' email used to ride along (security audit 2026-10-01).
        userMap.set(userData.id, publicUserSummary(userData));
        
        // Also map the original ID if it's different
        if (originalUserId !== userData.id) {
          userMap.set(originalUserId, userMap.get(userData.id));
        }
      }
    });
    
    // Social data (likes, comment counts) lives on the canonical venue
    // records — one batched read covers the whole page
    const socialByGlobalId = await fetchGlobalSocialMap(places);
    
    // Get activity records to determine which places are new for this user
    // Look for connections where this user is connected to the circle owner
    let activityRecords = [];
    if (circle.owner !== req.user.uid) {
      // User is not the owner, check for activity records
      // Check BOTH directions of the connection to ensure we find all activities
      // (reuses the docs already fetched for the myNetwork permission check)
      const connections = ownerConnectionDocs ?? await fetchOwnerConnectionDocs();

      connections.forEach(doc => {
        const connectionData = doc.data();
        if (connectionData.recentActivity && connectionData.recentActivity.length > 0) {
          // Add all activities from this connection
          activityRecords.push(...connectionData.recentActivity);
        }
      });
      
      // Remove duplicates based on entityId
      const uniqueActivities = [];
      const seenIds = new Set();
      activityRecords.forEach(activity => {
        if (!seenIds.has(activity.entityId)) {
          seenIds.add(activity.entityId);
          uniqueActivities.push(activity);
        }
      });
      activityRecords = uniqueActivities;
    }
    
    // Add user information and comment count to each place
    // Filter privateNotes based on ownership
    const placesWithUsers = places.map((place, index) => {
      // Check if this place is new for the current user
      let isNew = false;
      
      // Don't mark as new if user is the one who added it
      if (place.addedBy !== req.user.uid) {
        // Find activity record for this place
        const placeActivity = activityRecords.find(activity => 
          activity.type === 'place' && activity.entityId === place.id
        );
        
        if (placeActivity) {
          // Check if user has viewed this place
          const viewedBy = placeActivity.viewedBy || [];
          isNew = !viewedBy.includes(req.user.uid);
        }
        // No activity record could mean the place predates activity tracking
        // or sits in a private circle — treated as not-new either way.
      }
      
      // Only include privateNotes if the current user added this place
      const social = socialByGlobalId.get(place.globalPlaceId);
      const placeData = {
        ...(social ? overlayVenuePhotos(overlayVenueFields(place, social.venueData), social.venueData, req.user.uid) : place),
        ...(social ? { likes: social.likes, likesCount: social.likes.length } : {}),
        addedByUser: userMap.get(place.addedBy) || null,
        commentsCount: social ? social.commentsCount : 0,
        isNew: isNew // Set the isNew flag
      };
      
      // Filter privateNotes - only visible to the user who added the place
      if (place.addedBy !== req.user.uid) {
        delete placeData.privateNotes;
      }
      
      // Normalize photos array format for iOS compatibility
      normalizePhotosArray(placeData);
      
      return placeData;
    });
    
    // Create a map for quick lookup
    const placesMap = new Map();
    placesWithUsers.forEach(place => {
      placesMap.set(place.id, place);
    });
    
    // Return places in the order specified in the circle's places array
    let orderedPlaces = [];
    if (circle.places && circle.places.length > 0) {
      orderedPlaces = circle.places
        .map(placeId => placesMap.get(placeId))
        .filter(place => place !== undefined); // Filter out any deleted places
    } else {
      // Fallback to date-based sorting if no order is specified
      orderedPlaces = placesWithUsers.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
    }
    
    res.status(200).json({
      success: true,
      count: orderedPlaces.length,
      places: orderedPlaces
    });

    // Entering a connection's circle counts as seeing its new places — mark
    // them viewed AFTER responding, so this visit still shows the red dots and
    // the next one is clean. (Own circles have no connection record; skipped.)
    if (circle.owner !== req.user.uid) {
      markCirclePlacesViewed(req.user.uid, circle.owner, circleId)
        .catch(err => console.error('markCirclePlacesViewed error:', err.message));
    }
  } catch (error) {
    console.error('Error fetching places:', error);
    next(error);
  }
};

// @desc    Get places by circle ID (public access)
// @route   GET /api/circles/:circleId/places/public
// @access  Public
exports.getPlacesByCircleIdPublic = async (req, res, next) => {
  try {
    console.log('🔍 getPlacesByCircleIdPublic - START - Request details:', {
      circleId: req.params.circleId,
      method: req.method,
      url: req.url
    });

    const { circleId } = req.params;

    // First get the circle to check if it's public
    const circleRef = db.collection(COLLECTIONS.CIRCLES).doc(circleId);
    const circleDoc = await circleRef.get();

    if (!circleDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Circle not found'
      });
    }

    const circle = serializeDoc(circleDoc);
    
    console.log('🔍 getPlacesByCircleIdPublic - Circle check:', {
      circleId: circleId,
      circleName: circle.name,
      circlePrivacy: circle.privacy
    });
    
    // Only allow access to public circles
    if (circle.privacy !== 'public') {
      return res.status(403).json({
        success: false,
        message: 'This circle is not public'
      });
    }
    
    // Get all places for this circle using the same query method as authenticated endpoint
    console.log('🔍 getPlacesByCircleIdPublic - Querying places by circleId:', circleId);
    
    const placesSnapshot = await db.collection(COLLECTIONS.PLACES)
      .where('circleId', '==', circleId)
      .orderBy('createdAt', 'desc')
      .get();
    
    console.log('🔍 Public places query results:', {
      isEmpty: placesSnapshot.empty,
      size: placesSnapshot.size
    });
    
    // Filter out soft-deleted places, and anything the place's own privacy
    // narrows below the circle. This is an unauthenticated share, so there is
    // no viewer to exempt and no relationships to check: with no context every
    // tier above public denies, which is exactly right here. Checking only for
    // `private` used to serve an Inner Circle place inside a public circle to
    // the open web.
    const allPlaces = serializeQuerySnapshot(placesSnapshot);
    const places = allPlaces.filter(place => {
      const isDeleted = place.deletedAt !== null && place.deletedAt !== undefined;
      return !isDeleted && isPlaceVisibleToViewer(place, null, null);
    });

    console.log(`🔍 Found ${places.length} active places for public circle`);
    
    // Get unique user IDs who added places
    const userIds = [...new Set(places.map(place => place.addedBy).filter(Boolean))];
    
    // Fetch only the adders' user docs, in one batched read (this anonymous
    // endpoint used to fan out a get per adder — security audit 2026-10-01).
    const userRefs = userIds.map(userId => {
      let actualUserId = userId;
      if (userId && userId.includes('.')) {
        const parts = userId.split('.');
        if (parts.length >= 2) {
          actualUserId = parts[1];
        }
      }
      return db.collection(COLLECTIONS.USERS).doc(actualUserId);
    });
    const userDocs = userRefs.length > 0 ? await db.getAll(...userRefs) : [];
    
    // Create a map of user information
    const userMap = new Map();
    userDocs.forEach((doc, index) => {
      if (doc.exists) {
        const userData = serializeDoc(doc);
        const originalUserId = userIds[index];
        
        // This endpoint needs no login: never hand an adder's email to the
        // open web (security audit 2026-10-01).
        userMap.set(userData.id, publicUserSummary(userData));
        
        if (originalUserId !== userData.id) {
          userMap.set(originalUserId, userMap.get(userData.id));
        }
      }
    });
    
    // Check if request has authenticated user (optional for public endpoints)
    let activityRecords = [];
    const userId = req.user?.uid;
    
    if (userId && circle.owner !== userId) {
      // Authenticated user viewing public circle - check for activity records
      const [connection1, connection2] = await Promise.all([
        db.collection(COLLECTIONS.CONNECTIONS)
          .where('userId', '==', userId)
          .where('connectedUserId', '==', circle.owner)
          .where('status', '==', 'accepted')
          .get(),
        db.collection(COLLECTIONS.CONNECTIONS)
          .where('userId', '==', circle.owner)
          .where('connectedUserId', '==', userId)
          .where('status', '==', 'accepted')
          .get()
      ]);
      
      // Combine activities from both connection documents
      const connections = [...connection1.docs, ...connection2.docs];
      
      connections.forEach(doc => {
        const connectionData = doc.data();
        if (connectionData.recentActivity && connectionData.recentActivity.length > 0) {
          activityRecords.push(...connectionData.recentActivity);
        }
      });
      
      // Remove duplicates
      const uniqueActivities = [];
      const seenIds = new Set();
      activityRecords.forEach(activity => {
        if (!seenIds.has(activity.entityId)) {
          seenIds.add(activity.entityId);
          uniqueActivities.push(activity);
        }
      });
      activityRecords = uniqueActivities;
      
      console.log(`🔍 Public endpoint: Found ${activityRecords.length} unique activity records for authenticated user`);
    }
    
    // Attach user information to each place
    const placesWithUsers = places.map(place => {
      let isNew = false;
      
      // Check if place is new for authenticated user
      if (userId && place.addedBy !== userId) {
        const placeActivity = activityRecords.find(activity => 
          activity.type === 'place' && activity.entityId === place.id
        );
        
        if (placeActivity) {
          const viewedBy = placeActivity.viewedBy || [];
          isNew = !viewedBy.includes(userId);
          
          if (isNew) {
            console.log(`🆕 Public circle: Place "${place.name}" is NEW for user ${userId}`);
          }
        }
      }
      
      const placeData = {
        ...place,
        addedByUser: userMap.get(place.addedBy) || null,
        isNew: isNew
      };
      // Private notes belong to the adder, and a place's own guest list is
      // nobody else's business — this anonymous endpoint spread both out
      // with the rest of the save doc (security audit 2026-10-01).
      if (!userId || !isSameUser(place.addedBy, userId)) {
        delete placeData.privateNotes;
      }
      delete placeData.sharedWith;
      
      // Normalize photos array format for iOS compatibility
      normalizePhotosArray(placeData);
      
      return placeData;
    });
    
    // Order places - if circle has places array, use it for ordering, otherwise use creation date
    let orderedPlaces = [];
    if (circle.places && circle.places.length > 0) {
      // Create a map for quick lookup
      const placesMap = new Map();
      placesWithUsers.forEach(place => {
        placesMap.set(place.id, place);
      });
      
      // Return places in the order specified in the circle's places array
      orderedPlaces = circle.places
        .map(placeId => placesMap.get(placeId))
        .filter(place => place !== undefined); // Filter out any deleted places
    } else {
      // Fallback to date-based sorting if no order is specified
      orderedPlaces = placesWithUsers.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
    }
    
    console.log(`🔍 Returning ${orderedPlaces.length} ordered places for public circle`);
    
    res.status(200).json({
      success: true,
      count: orderedPlaces.length,
      places: orderedPlaces
    });
  } catch (error) {
    console.error('Error fetching public places:', error);
    next(error);
  }
};

// @desc    Get single place
// @route   GET /api/places/:id
// @access  Private
exports.getPlace = async (req, res, next) => {
  // IMMEDIATE LOG TO DEBUG - VERSION 3 - 2025-08-18-11:58
  console.error(`📍📍📍 GET PLACE CALLED V3 - PlaceId: ${req.params.id}, User: ${req.user?.email || 'NO USER'}`);
  console.log(`\n📍 ========== GET PLACE REQUEST STARTED V3 ==========`);
  console.log(`📍 Request URL: ${req.originalUrl}`);
  console.log(`📍 Request params:`, req.params);
  console.log(`📍 Request query:`, req.query);
  
  try {
    const placeId = req.params.id;
    const userId = req.user.uid;
    const fromActivity = req.query.fromActivity === 'true';
    
    console.log(`📍 PlaceId: ${placeId}`);
    console.log(`📍 UserId: ${userId}`);
    console.log(`📍 User Email: ${req.user.email}`);
    console.log(`📍 User Original UID: ${req.user.originalUid}`);
    console.log(`📍 FromActivity: ${fromActivity}`);
    
    const placeDoc = await db.collection(COLLECTIONS.PLACES).doc(placeId).get();
    
    if (!placeDoc.exists) {
      console.log(`❌ Place ${placeId} not found in database`);
      return res.status(404).json({
        success: false,
        message: 'Place not found'
      });
    }

    const place = serializeDoc(placeDoc);
    console.log(`📍 Place found: ${place.name}`);
    console.log(`📍 CircleId: ${place.circleId || 'none (floating place)'}`);
    console.log(`📍 AddedBy: ${place.addedBy}`);
    
    // Check if place is soft-deleted
    if (place.deletedAt) {
      return res.status(404).json({
        success: false,
        message: 'Place not found'
      });
    }

    // Check permissions based on whether place belongs to a circle
    if (place.circleId) {
      console.log(`\n🔐 ========== CHECKING PERMISSIONS ==========`);
      // Place belongs to a circle - check circle permissions
      const circleDoc = await db.collection(COLLECTIONS.CIRCLES).doc(place.circleId).get();
      
      if (!circleDoc.exists) {
        console.log(`❌ Circle ${place.circleId} not found`);
        return res.status(404).json({
          success: false,
          message: 'Circle not found'
        });
      }

      const circle = serializeDoc(circleDoc);
      console.log(`🔐 Circle found: ${circle.name}`);
      console.log(`🔐 Circle owner: ${circle.owner}`);
      console.log(`🔐 Circle privacy: ${circle.privacy}`);
      
      // Check permissions
      // One rule, same as every other read path. The old version here also
      // consulted the owner's denormalised `connections`/`followers` arrays as
      // a fallback; canViewCircleFor reads the connections collection, which is
      // the source of truth those arrays are derived from.
      const hasAccess = await canViewCircleFor(circle, userId);

      // Deny access if none of the conditions are met
      if (!hasAccess) {
        console.log(`\n❌ ========== ACCESS DENIED ==========`);
        console.log(`❌ Place: ${place.name}`);
        console.log(`❌ Circle: ${circle.name}`);
        console.log(`❌ User: ${userId}`);
        console.log(`❌ Circle Owner: ${circle.owner}`);
        console.log(`❌ Circle Privacy: ${circle.privacy}`);
        console.log(`❌ Shared with: ${(circle.sharedWith || []).length} people`);
        console.log(`❌ ====================================\n`);
        
        console.error('❌ DENYING ACCESS - Version 3 - 2025-08-18-11:58');
        return res.status(403).json({
          success: false,
          message: 'Not authorized to access this place (v3-2025-08-18)'
        });
      } else {
        console.log(`\n✅ ========== ACCESS GRANTED ==========`);
        console.log(`✅ User ${userId} can access place ${place.name}`);
        console.log(`✅ ====================================\n`);
      }
    } else {
      // Floating place (no circle) - created from check-in
      // Allow access if user created the place or if it's from a check-in
      const isCreator = place.addedBy === req.user.uid;
      const isFromCheckIn = place.addedViaCheckIn === true;
      
      if (!isCreator && !isFromCheckIn) {
        console.error('❌ DENYING ACCESS - Version 3 - 2025-08-18-11:58');
        return res.status(403).json({
          success: false,
          message: 'Not authorized to access this place (v3-2025-08-18)'
        });
      }
      
      // For floating places from check-ins, anyone can view them
      // This allows users to see places where their connections checked in
      console.log(`✅ Allowing access to floating place: ${place.name} (check-in place)`);
    }

    // A place's own privacy narrows the circle's: Private is owner-only and
    // Inner Circle reaches only the owner's list, even inside a visible circle.
    if (!isPlaceVisibleToViewer(place, req.user.uid, await buildViewerContext(req.user.uid))) {
      return res.status(403).json({
        success: false,
        message: 'This place is private'
      });
    }

    // Social and venue data come from the canonical venue record (one read,
    // shared by every saved copy of this place)
    const [social, addedByUserMap] = await Promise.all([
      getGlobalSocial(placeDoc),
      buildAddedByUserMap([place])
    ]);

    // Filter privateNotes - only visible to the user who added the place
    // Viewer's own check-in history at this venue (null when none)
    const myCheckInStats = await getMyCheckInStats(
      req.user.uid, social.globalPlaceId || place.globalPlaceId || null);

    let placeData = {
      ...place,
      globalPlaceId: social.globalPlaceId || place.globalPlaceId || null,
      myCheckInStats,
      addedByUser: addedByUserMap.get(place.addedBy) || null,
      likes: social.likes,
      likesCount: social.likes.length,
      commentsCount: social.commentsCount,
      followersCount: (social.venueData && social.venueData.followersCount) || 0,
      isFollowing: ((social.venueData && social.venueData.followers) || []).includes(req.user.uid),
      // The bell: this follower gets the store's alerts
      followAlerts: ((social.venueData && social.venueData.alertFollowerIds) || []).includes(req.user.uid)
    };
    if (social.venueData) {
      placeData = overlayVenuePhotos(overlayVenueFields(placeData, social.venueData), social.venueData, req.user.uid);
    }
    
    // Normalize photos array format for iOS compatibility
    normalizePhotosArray(placeData);
    
    // Remove privateNotes if the current user is not the one who added the place
    if (place.addedBy !== req.user.uid) {
      delete placeData.privateNotes;
      console.log(`🔒 Filtering out privateNotes for user ${req.user.uid} viewing place added by ${place.addedBy}`);
    } else {
      console.log(`✅ Including privateNotes for owner ${req.user.uid} viewing their own place`);
    }
    
    res.status(200).json({
      success: true,
      place: placeData
    });
  } catch (error) {
    console.error('Error fetching place:', error);
    next(error);
  }
};

// @desc    Create new place
// @route   POST /api/places
// @access  Private
exports.createPlace = async (req, res, next) => {
  try {
    const result = await placeSaveService.savePlace(req.user, req.body);
    res.status(result.status).json(result.payload);
    if (result.afterResponse) await result.afterResponse();
  } catch (error) {
    console.error('Error creating place:', error);
    next(error);
  }
};

// @desc    Update place
// @route   PUT /api/places/:id
// @access  Private
exports.updatePlace = async (req, res, next) => {
  try {
    const placeRef = db.collection(COLLECTIONS.PLACES).doc(req.params.id);
    const placeDoc = await placeRef.get();

    if (!placeDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Place not found'
      });
    }

    const place = serializeDoc(placeDoc);

    // Check if user can edit (owner of circle, shared with user, or person who added the place)
    const circleDoc = await db.collection(COLLECTIONS.CIRCLES).doc(place.circleId).get();
    const circle = serializeDoc(circleDoc);
    
    const isCircleOwner = circle.owner === req.user.uid;
    const isSharedWith = circle.sharedWith && circle.sharedWith.includes(req.user.uid);
    const isPlaceAdder = place.addedBy === req.user.uid;

    // A verified venue owner may correct their venue's data from any save of
    // it — they usually didn't add the save they're looking at. Their edit is
    // restricted to venue fields below; per-user fields stay untouchable.
    let isVenueOwnerEdit = false;
    if (!isCircleOwner && !isSharedWith && !isPlaceAdder) {
      // Super-users too: shared details are theirs to correct on any save
      isVenueOwnerEdit = req.user.isSuperUser === true
        || await isVerifiedVenueOwner(req.user.uid, req.params.id, place.googlePlaceId);
      if (!isVenueOwnerEdit) {
        // Private notes belong on the CALLER's save of the venue, but the app
        // may be showing another user's copy (opened via their circle/feed).
        // For a notes-only update, redirect the write to the caller's own
        // save record instead of failing.
        const otherKeys = Object.keys(req.body).filter((k) => k !== 'privateNotes');
        if ('privateNotes' in req.body && otherKeys.length === 0 && place.globalPlaceId) {
          const mineSnap = await db.collection(COLLECTIONS.PLACES)
            .where('addedBy', '==', req.user.uid)
            .where('globalPlaceId', '==', place.globalPlaceId)
            .get();
          const mine = mineSnap.docs.find((d) => !d.data().deletedAt);
          if (mine) {
            await mine.ref.update({
              privateNotes: req.body.privateNotes,
              updatedAt: new Date().toISOString()
            });
            const updatedDoc = await mine.ref.get();
            console.log(`📝 Notes redirected to caller's own save ${mine.id} (viewed copy: ${req.params.id})`);
            return res.status(200).json({
              success: true,
              place: serializeDoc(updatedDoc)
            });
          }
          return res.status(403).json({
            success: false,
            message: 'Save this place first to add a private note'
          });
        }
        return res.status(403).json({
          success: false,
          message: 'Not authorized to update this place'
        });
      }
    }

    // Validate updates
    const validationErrors = validatePlace({ ...place, ...req.body });
    if (validationErrors.length > 0) {
      return res.status(400).json({
        success: false,
        message: 'Validation error',
        errors: validationErrors
      });
    }

    // Don't allow changing circleId or addedBy. ratingCheckInId is a request
    // hint (which check-in prompted a re-rate), never a doc field.
    const { circleId, addedBy, ratingCheckInId, ratingHistory: _clientHistory, userRatedAt: _clientRatedAt, ...updateData } = req.body;
    updateData.updatedAt = new Date().toISOString();

    // An 'innerCircle' place reaches builds that predate the tier as 'private'
    // (see middleware/responseNormalizer). When such a build saves the form it
    // echoes that 'private' straight back; keep the stored tier instead of
    // silently collapsing it.
    if ('privacy' in updateData) {
      updateData.privacy = resolveIncomingPrivacy({
        incoming: updateData.privacy,
        stored: place.privacy,
        req
      });
    }

    // The named Inner Circle list travels with the tier: set on an Inner
    // Circle place, cleared on any other, so a tier change never leaves a
    // stale audience pointing at a list the person no longer meant.
    if ('audienceListId' in updateData || 'privacy' in updateData) {
      updateData.audienceListId = listIdFor(
        'privacy' in updateData ? updateData.privacy : place.privacy,
        'audienceListId' in updateData ? updateData.audienceListId : place.audienceListId
      );
    }

    // Per-place guest list: named people who may see this one save whatever
    // its tier says. Connections only, same rule as the Inner Circle.
    if ('sharedWith' in updateData) {
      try {
        updateData.sharedWith = await validateGuestList(req.user.uid, updateData.sharedWith);
      } catch (guestError) {
        return res.status(400).json({
          success: false,
          code: guestError.code,
          message: guestError.message
        });
      }
    }

    // Shared details (name, address, category, description, phone, website,
    // hours) belong to the VENUE, not this save: they change only through
    // venueDetailsService, and only for a super-user or the store's team
    // (Wes, 2026-10-01: the Google/Apple import is the truth; an owner or an
    // admin may correct it, never an ordinary saver). Google-derived numbers
    // are never client-writable.
    const detailFields = venueDetails.pickDetailFields(updateData);
    [...venueDetails.DETAIL_FIELDS, 'geohash', 'rating', 'userRatingsTotal', 'priceLevel', 'googlePlaceId']
      .forEach((field) => delete updateData[field]);

    // Venue team / super-user editing a save that isn't theirs: details only —
    // tags, privacy, photos, notes belong to whoever saved it.
    if (isVenueOwnerEdit) {
      Object.keys(updateData).forEach((field) => { if (field !== 'updatedAt') delete updateData[field]; });
    }

    if (Object.keys(detailFields).length > 0) {
      const globalPlaceId = place.globalPlaceId || await ensureGlobalPlaceLink(placeDoc);
      const venueDoc = globalPlaceId
        ? await db.collection('globalPlaces').doc(globalPlaceId).get()
        : null;
      const venue = venueDoc && venueDoc.exists ? venueDoc.data() : {};
      // Builds up to 1.3.6 resend name/address/category with every save, even
      // a notes-only one — an unchanged echo is not an edit
      const changed = venueDetails.changedDetailFields(detailFields, venue);
      if (changed.length > 0) {
        const allowed = !!globalPlaceId && await venueDetails.canEditDetails(req.user, globalPlaceId, venue);
        const personalChanges = Object.keys(updateData).filter((field) => field !== 'updatedAt');
        if (allowed) {
          const fields = {};
          changed.forEach((field) => { fields[field] = detailFields[field]; });
          try {
            await venueDetails.updateVenueDetails({ globalPlaceId, user: req.user, fields });
          } catch (detailError) {
            return sendServiceError(res, detailError, { log: 'Venue details update failed', fallbackMessage: 'Could not update this place' });
          }
        } else if (personalChanges.length === 0) {
          return res.status(403).json({ success: false, code: 'DETAILS_LOCKED', message: venueDetails.NOT_ALLOWED_MESSAGE });
        } else {
          // An older app saving notes/privacy alongside a details change it
          // can no longer make: keep the personal part, skip the rest
          console.log(`🔒 Details unchanged on ${req.params.id} (${changed.join(', ')}): not the owner or an admin`);
        }
      }
    }

    if (isVenueOwnerEdit) {
      const refreshed = await placeRef.get();
      return res.status(200).json({ success: true, place: serializeDoc(refreshed) });
    }

    // privateNotes belong to the person who added the place — reads already
    // strip them for everyone else, so don't let other editors overwrite them
    if ('privateNotes' in updateData && !isPlaceAdder) {
      delete updateData.privateNotes;
    }

    // userRating is the saver's personal 0-10 score — same ownership rule as
    // privateNotes, and clamp it so bad clients can't store junk
    if ('userRating' in updateData) {
      if (!isPlaceAdder) {
        delete updateData.userRating;
      } else {
        const num = Number(updateData.userRating);
        updateData.userRating = (updateData.userRating === null || Number.isNaN(num))
          ? null
          : Math.min(10, Math.max(0, Math.round(num)));
        // Latest wins, history kept: a new (or check-in-prompted) score is
        // appended to ratingHistory; clearing the rating leaves history alone.
        const { appendRating } = require('../../utils/ratingHistory');
        const nextHistory = appendRating(place.ratingHistory, {
          rating: updateData.userRating,
          at: updateData.updatedAt,
          checkInId: ratingCheckInId || null
        }, place.userRating === null || place.userRating === undefined ? null : {
          // Rated before history existed: keep the starting score
          rating: place.userRating,
          at: place.userRatedAt || place.updatedAt || place.createdAt || null
        });
        if (nextHistory) {
          updateData.ratingHistory = nextHistory;
          updateData.userRatedAt = updateData.updatedAt;
        }
      }
    }

    // publicNotes is retired: a note meant for others is a comment on the
    // venue. Older app builds still send the field, so drop it rather than
    // erroring — and never resurrect a note field on the save doc.
    if ('publicNotes' in updateData || 'notes' in updateData) {
      delete updateData.publicNotes;
      delete updateData.notes;
    }
    
    // Validate location coordinates if provided
    if (updateData.location && updateData.location.coordinates) {
      const [longitude, latitude] = updateData.location.coordinates;
      
      // Validate coordinates are within valid ranges
      if (typeof longitude !== 'number' || typeof latitude !== 'number' ||
          longitude < -180 || longitude > 180 ||
          latitude < -90 || latitude > 90 ||
          // Reject coordinates at exactly -180, -180 (invalid/default values)
          (longitude === -180 && latitude === -180)) {
        console.warn('⚠️ Invalid coordinates rejected in update:', { longitude, latitude, placeId: req.params.id });
        delete updateData.location; // Remove invalid location from update
      } else {
        // Keep the geohash in sync with the location (geofire expects [lat, lng])
        updateData.geohash = geofire.geohashForLocation([latitude, longitude]);
      }
    }
    
    // Log notes updates for debugging
    if (updateData.privateNotes !== undefined || updateData.publicNotes !== undefined || updateData.notes !== undefined) {
      console.log('📝 Updating place notes:', {
        placeId: req.params.id,
        userId: req.user.uid,
        placeAddedBy: place.addedBy,
        isPlaceAdder: isPlaceAdder,
        isCircleOwner: isCircleOwner,
        updates: {
          privateNotes: updateData.privateNotes !== undefined ? `${updateData.privateNotes?.substring(0, 50)}...` : 'not changed',
          publicNotes: updateData.publicNotes !== undefined ? `${updateData.publicNotes?.substring(0, 50)}...` : 'not changed',
          notes: updateData.notes !== undefined ? `${updateData.notes?.substring(0, 50)}...` : 'not changed'
        },
        existingNotes: {
          privateNotes: place.privateNotes ? `${place.privateNotes.substring(0, 50)}...` : 'empty',
          publicNotes: place.publicNotes ? `${place.publicNotes.substring(0, 50)}...` : 'empty',
          notes: place.notes ? `${place.notes.substring(0, 50)}...` : 'empty'
        }
      });
    }

    // Handle photo operations
    let addedPhotoUrl = null;
    let photoOps = null;
    if (updateData.addPhotos || updateData.removePhotos) {
      photoOps = {
        added: Array.isArray(updateData.addPhotos) ? updateData.addPhotos.filter((u) => typeof u === 'string') : [],
        removed: Array.isArray(updateData.removePhotos) ? updateData.removePhotos.filter((u) => typeof u === 'string') : []
      };
      console.log('📷 Processing photo operations:', {
        placeId: req.params.id,
        addPhotos: updateData.addPhotos ? `${updateData.addPhotos.length} photos` : 'none',
        removePhotos: updateData.removePhotos ? `${updateData.removePhotos.length} photos` : 'none',
        existingPhotos: place.photos ? `${place.photos.length} photos` : 'none'
      });

      let currentPhotos = place.photos || [];

      // Add new photos to the array
      if (updateData.addPhotos && Array.isArray(updateData.addPhotos)) {
        console.log('📷 Adding photos:', updateData.addPhotos);
        addedPhotoUrl = updateData.addPhotos[0] || null; // piggy-bank earn ref
        currentPhotos = [...currentPhotos, ...updateData.addPhotos];
        // Uploaded by this user, by definition — the clearest own-photo signal
        // in the app, and the one the postcard nudge most wants.
        updateData.hasOwnPhotos = true;
        if (addedPhotoUrl) updateData.ownPhotoUrl = addedPhotoUrl;
      }
      
      // Remove specified photos from the array
      if (updateData.removePhotos && Array.isArray(updateData.removePhotos)) {
        console.log('📷 Removing photos:', updateData.removePhotos);
        const photosToRemove = new Set(updateData.removePhotos);
        currentPhotos = currentPhotos.filter(url => !photosToRemove.has(url));
      }
      
      // Update the photos array in the update data
      updateData.photos = currentPhotos;
      
      // Remove the operation fields as they shouldn't be stored directly
      delete updateData.addPhotos;
      delete updateData.removePhotos;
      
      console.log('📷 Final photos array:', {
        totalPhotos: currentPhotos.length,
        photos: currentPhotos.slice(0, 3) // Show first 3 for debugging
      });
    }

    // Legacy descriptions embed literal "Phone: …" / "Website: …" lines (the
    // sanitizer preserves them for display). A contact-info edit must rewrite
    // those lines too, or the About text keeps showing the old numbers.
    if ((updateData.phone || updateData.website) && updateData.description === undefined) {
      const currentDescription = place.description || '';
      let syncedDescription = currentDescription;
      if (updateData.phone) {
        syncedDescription = syncedDescription.replace(/^\s*Phone:.*$/m, `Phone: ${updateData.phone}`);
      }
      if (updateData.website) {
        syncedDescription = syncedDescription.replace(/^\s*Website:.*$/m, `Website: ${updateData.website}`);
      }
      if (syncedDescription !== currentDescription) {
        updateData.description = syncedDescription;
      }
    }

    await placeRef.update(updateData);

    // Edit Place's photos go to the place's one library, not just this copy:
    // added ones attributed to this user, removed ones removed where they
    // may (placePhotoService.adoptSavePhotos)
    if (photoOps && place.globalPlaceId) {
      await require('../../services/placePhotoService').adoptSavePhotos({
        globalPlaceId: place.globalPlaceId,
        user: req.user,
        ownUrls: photoOps.added,
        removedUrls: photoOps.removed,
        isPrivate: await require('../../services/placePhotoService').saveIsPrivate({ ...place, ...updateData })
      });
    }

    // Piggy bank: 1 FavCoin for your first photo on this venue (dedup key is
    // per user+venue, so later photos and photo swaps pay nothing).
    let photoPiggyBank = null;
    if (addedPhotoUrl) {
      photoPiggyBank = await piggyBankService.credit({
        userId: req.user.uid,
        eventType: 'place_photo',
        sourceRef: {
          placeId: req.params.id,
          globalPlaceId: place.globalPlaceId || null,
          photoUrl: addedPhotoUrl
        }
      });
    }

    // Venue-level edits update the canonical record once, for every saver
    await propagateVenueUpdates(req.params.id, place.globalPlaceId, updateData);

    // Adding a photo to a place you already saved is the clearest "own image"
    // moment there is — better evidence than a save, where the photo may be
    // the venue's. Same fortnightly cooldown as every other postcard nudge.
    let postcardNudge = null;
    if (addedPhotoUrl) {
      try {
        postcardNudge = { eligible: await homePromptService.postcardNudgeEligible(req.user.uid) };
      } catch (nudgeError) {
        console.error('⚠️ Postcard nudge check failed (non-fatal):', nudgeError.message);
      }
    }

    // Get updated place. The response must reflect the canonical venue
    // record — phone/website/rating live there and are overlaid on reads; a
    // raw save doc here made a just-saved contact edit look like a no-op.
    const updatedPlaceDoc = await placeRef.get();
    let updatedPlace = serializeDoc(updatedPlaceDoc);
    try {
      const { venueData } = await getGlobalSocial(updatedPlaceDoc);
      if (venueData) updatedPlace = overlayVenueFields(updatedPlace, venueData);
    } catch (overlayError) {
      console.error('⚠️ Update-response venue overlay failed (non-fatal):', overlayError.message);
    }

    res.status(200).json({
      success: true,
      place: updatedPlace,
      piggyBank: photoPiggyBank,
      postcardNudge
    });
  } catch (error) {
    console.error('Error updating place:', error);
    next(error);
  }
};

// @desc    Delete place
// @route   DELETE /api/places/:id
// @access  Private
exports.deletePlace = async (req, res, next) => {
  try {
    const placeRef = db.collection(COLLECTIONS.PLACES).doc(req.params.id);
    const placeDoc = await placeRef.get();

    if (!placeDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Place not found'
      });
    }

    const place = serializeDoc(placeDoc);

    // Check if user can delete (owner of circle, shared with user, or person who added the place)
    const circleDoc = await db.collection(COLLECTIONS.CIRCLES).doc(place.circleId).get();
    const circle = serializeDoc(circleDoc);
    
    const isCircleOwner = circle.owner === req.user.uid;
    const isSharedWith = circle.sharedWith && circle.sharedWith.includes(req.user.uid);
    const isPlaceAdder = place.addedBy === req.user.uid;
    
    if (!isCircleOwner && !isSharedWith && !isPlaceAdder) {
      return res.status(403).json({
        success: false,
        message: 'Not authorized to delete this place'
      });
    }

    // Use a batch write for atomic operation
    const batch = db.batch();
    
    // Remove place from circle's places array and decrement count
    const currentPlaces = circle.places || [];
    const updatedPlaces = currentPlaces.filter(placeId => placeId !== req.params.id);
    
    // Store the original circle state for potential rollback
    const originalCircleState = {
      places: currentPlaces,
      placesCount: circle.placesCount || 0
    };
    
    try {
      // Update circle in the batch
      const circleRef = db.collection(COLLECTIONS.CIRCLES).doc(place.circleId);
      batch.update(circleRef, {
        places: updatedPlaces,
        placesCount: Math.max(0, (circle.placesCount || 0) - 1), // Decrement places count (never go below 0)
        updatedAt: new Date().toISOString()
      });
      
      // Soft delete the place by setting deletedAt timestamp
      batch.update(placeRef, {
        deletedAt: new Date().toISOString(),
        updatedAt: new Date().toISOString()
      });
      
      // Commit the batch
      await batch.commit();

      console.log('✅ Place soft deleted successfully:', req.params.id);

      // Browse tree upkeep: decrement this circle's summary + drop cached tree.
      indexPlaceRemoved(place.circleId, place);
      placeCache.clear('browseTree', place.addedBy || req.user.uid);

      res.status(200).json({
        success: true,
        message: 'Place deleted successfully'
      });
    } catch (batchError) {
      // If batch operation fails, attempt to restore the original state
      console.error('❌ Batch delete failed, attempting rollback:', batchError);
      
      try {
        await db.collection(COLLECTIONS.CIRCLES).doc(place.circleId).update({
          places: originalCircleState.places,
          placesCount: originalCircleState.placesCount,
          updatedAt: new Date().toISOString()
        });
        console.log('✅ Rollback successful');
      } catch (rollbackError) {
        console.error('❌ Rollback failed:', rollbackError);
      }
      
      throw batchError;
    }
  } catch (error) {
    console.error('Error deleting place:', error);
    next(error);
  }
};

exports.updatePlaceAddress = async (req, res, next) => {
  try {
    const { address, location } = req.body;
    
    if (!address || typeof address !== 'string' || address.trim().length === 0) {
      return res.status(400).json({
        success: false,
        message: 'Please provide a valid address'
      });
    }
    
    // Validate location if provided
    if (location) {
      if (!location.type || location.type !== 'Point' || 
          !location.coordinates || !Array.isArray(location.coordinates) ||
          location.coordinates.length !== 2) {
        return res.status(400).json({
          success: false,
          message: 'Invalid location format. Expected GeoJSON Point.'
        });
      }
      
      const [longitude, latitude] = location.coordinates;
      
      // Validate coordinates
      if (typeof longitude !== 'number' || typeof latitude !== 'number' ||
          longitude < -180 || longitude > 180 ||
          latitude < -90 || latitude > 90 ||
          (longitude === -180 && latitude === -180)) {
        return res.status(400).json({
          success: false,
          message: 'Invalid coordinates provided'
        });
      }
    }
    
    const placeRef = db.collection(COLLECTIONS.PLACES).doc(req.params.id);
    const placeDoc = await placeRef.get();
    
    if (!placeDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Place not found'
      });
    }
    
    const place = serializeDoc(placeDoc);
    
    // A shared detail: the venue's owner/managers or a super-user, through
    // the one details path (it updates every save of the venue, this one too)
    const globalPlaceId = place.globalPlaceId || await ensureGlobalPlaceLink(placeDoc);
    try {
      await venueDetails.updateVenueDetails({
        globalPlaceId,
        user: req.user,
        fields: location ? { address, location } : { address }
      });
    } catch (detailError) {
      return sendServiceError(res, detailError, { log: 'Address update failed', fallbackMessage: 'Could not update the address' });
    }

    // Get the updated place
    const updatedDoc = await placeRef.get();
    const updatedPlace = serializeDoc(updatedDoc);
    
    console.log('✅ Place address updated successfully:', {
      placeId: req.params.id,
      oldAddress: place.address,
      newAddress: address.trim()
    });
    
    res.status(200).json({
      success: true,
      place: updatedPlace
    });
    
  } catch (error) {
    console.error('Error updating place address:', error);
    next(error);
  }
};

// @desc    Reorder places within a circle
// @route   PUT /api/circles/:id/places/reorder
// @access  Private
exports.reorderPlacesInCircle = async (req, res, next) => {
  try {
    const { placeIds } = req.body;
    const circleId = req.params.id;
    
    if (!placeIds || !Array.isArray(placeIds)) {
      return res.status(400).json({
        success: false,
        message: 'Please provide an array of place IDs'
      });
    }
    
    // Get the circle
    const circleRef = db.collection(COLLECTIONS.CIRCLES).doc(circleId);
    const circleDoc = await circleRef.get();
    
    if (!circleDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Circle not found'
      });
    }
    
    const circle = serializeDoc(circleDoc);
    
    // Make sure user owns the circle
    if (circle.owner !== req.user.uid) {
      return res.status(401).json({
        success: false,
        message: 'Not authorized to modify this circle'
      });
    }
    
    // Verify all place IDs exist in the circle
    const existingPlaceIds = circle.places || [];
    const providedPlaceIds = placeIds;
    
    // Check if all provided IDs exist in the circle
    const allIdsExist = providedPlaceIds.every(id => existingPlaceIds.includes(id));
    
    if (!allIdsExist) {
      return res.status(400).json({
        success: false,
        message: 'Invalid place IDs - some places do not belong to this circle'
      });
    }
    
    // Check if all circle places are accounted for
    if (providedPlaceIds.length !== existingPlaceIds.length) {
      return res.status(400).json({
        success: false,
        message: 'All places in the circle must be included in the reorder'
      });
    }
    
    // Update the places array with the new order
    console.log('Reordering places from:', existingPlaceIds);
    console.log('Reordering places to:', placeIds);
    
    await circleRef.update({
      places: placeIds,
      updatedAt: new Date().toISOString()
    });
    
    console.log('Saved circle with new order:', placeIds);
    
    res.status(200).json({
      success: true,
      message: 'Places reordered successfully'
    });
    
  } catch (error) {
    console.error('Error reordering places:', error);
    next(error);
  }
};

// @desc    Add existing place to a circle
// @route   POST /api/places/:id/add-to-circle/:circleId
// @access  Private
exports.addExistingPlaceToCircle = async (req, res, next) => {
  try {
    const { id: placeId, circleId } = req.params; // Route uses :id, not :placeId
    const userId = req.user.uid;
    const { notes } = req.body;
    
    console.log('🔄 Adding existing place to circle:', {
      placeId,
      circleId,
      userId,
      notes
    });
    
    // Validate input parameters
    if (!placeId || placeId.trim() === '') {
      console.error('❌ Invalid placeId:', placeId);
      return res.status(400).json({
        success: false,
        message: 'Invalid place ID provided'
      });
    }
    
    if (!circleId || circleId.trim() === '') {
      console.error('❌ Invalid circleId:', circleId);
      return res.status(400).json({
        success: false,
        message: 'Invalid circle ID provided'
      });
    }
    
    // Check if the place exists
    let placeRef, placeDoc;
    try {
      console.log('📄 Attempting to get place document with ID:', placeId);
      placeRef = db.collection(COLLECTIONS.PLACES).doc(placeId);
      placeDoc = await placeRef.get();
    } catch (docError) {
      console.error('❌ Error accessing place document:', docError);
      console.error('❌ PlaceId that caused error:', placeId);
      return res.status(500).json({
        success: false,
        message: 'Failed to access place document',
        error: docError.message
      });
    }
    
    if (!placeDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Place not found'
      });
    }
    
    const originalPlace = serializeDoc(placeDoc);
    
    // Check if the circle exists and user has access
    const circleRef = db.collection(COLLECTIONS.CIRCLES).doc(circleId);
    const circleDoc = await circleRef.get();
    
    if (!circleDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Circle not found'
      });
    }
    
    const circle = serializeDoc(circleDoc);
    
    // Verify user owns the target circle
    if (circle.owner !== userId) {
      return res.status(403).json({
        success: false,
        message: 'You can only add places to your own circles'
      });
    }
    
    // Check if place already exists in this circle
    console.log('🔍 Checking for duplicate place:', {
      circleId,
      placeId,
      googlePlaceId: originalPlace.googlePlaceId,
      name: originalPlace.name,
      address: originalPlace.address
    });
    
    if (originalPlace.googlePlaceId) {
      const existingPlace = await db.collection(COLLECTIONS.PLACES)
        .where('circleId', '==', circleId)
        .where('googlePlaceId', '==', originalPlace.googlePlaceId)
        .where('deletedAt', '==', null)
        .get();
        
      console.log('🔍 Google Place ID duplicate check:', {
        googlePlaceId: originalPlace.googlePlaceId,
        foundDuplicates: !existingPlace.empty,
        duplicateCount: existingPlace.size
      });
        
      if (!existingPlace.empty) {
        // Double-check if the document actually exists (not just in query cache)
        const firstDoc = existingPlace.docs[0];
        const docStillExists = await db.collection(COLLECTIONS.PLACES).doc(firstDoc.id).get();
        
        if (docStillExists.exists) {
          console.log('⚠️ Duplicate place found:', {
            duplicateId: firstDoc.id,
            duplicateData: firstDoc.data()
          });
          
          return res.status(400).json({
            success: false,
            message: 'This place already exists in the selected circle'
          });
        } else {
          console.log('✅ False positive - document was deleted but still in query cache');
        }
      }
    } else {
      // For places without googlePlaceId, check by name and address
      const existingPlace = await db.collection(COLLECTIONS.PLACES)
        .where('circleId', '==', circleId)
        .where('name', '==', originalPlace.name)
        .where('address', '==', originalPlace.address)
        .where('deletedAt', '==', null)
        .get();
        
      console.log('🔍 Name/Address duplicate check:', {
        name: originalPlace.name,
        address: originalPlace.address,
        foundDuplicates: !existingPlace.empty,
        duplicateCount: existingPlace.size
      });
        
      if (!existingPlace.empty) {
        // Double-check if the document actually exists (not just in query cache)
        const firstDoc = existingPlace.docs[0];
        const docStillExists = await db.collection(COLLECTIONS.PLACES).doc(firstDoc.id).get();
        
        if (docStillExists.exists) {
          console.log('⚠️ Duplicate place found:', {
            duplicateId: firstDoc.id,
            duplicateData: firstDoc.data()
          });
          
          return res.status(400).json({
            success: false,
            message: 'This place already exists in the selected circle'
          });
        } else {
          console.log('✅ False positive - document was deleted but still in query cache');
        }
      }
    }
    
    // Create a new place entry for this circle
    // Copy all fields except ID fields
    const { _id, id, ...placeDataWithoutIds } = originalPlace;
    
    const newPlaceData = {
      ...placeDataWithoutIds,
      circleId: circleId,
      addedBy: userId,
      // A note supplied while copying is the copier's own annotation — keep it
      // private to them. Shared opinions go to comments on the venue.
      privateNotes: notes || null,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
      likes: [], // Reset likes for the new copy
      likesCount: 0
    };
    
    // Create the new place
    const newPlaceRef = await db.collection(COLLECTIONS.PLACES).add(newPlaceData);
    const newPlaceId = newPlaceRef.id; // Get the ID directly from the reference
    
    console.log('🆕 New place created with ID:', newPlaceId);
    
    // Verify the place was created successfully
    if (!newPlaceId) {
      throw new Error('Failed to create new place - no document ID generated');
    }
    
    // Get the created place document
    const newPlaceDoc = await newPlaceRef.get();
    const newPlace = serializeDoc(newPlaceDoc);

    // Copies inherit the source's globalPlaceId via the field spread above;
    // this covers older source docs that were never linked
    if (!newPlace.globalPlaceId) {
      const linkedGlobalPlaceId = await ensureGlobalPlaceLink(newPlaceDoc);
      if (linkedGlobalPlaceId) {
        newPlace.globalPlaceId = linkedGlobalPlaceId;
      }
    }

    // Update circle's places array and increment count using the direct ID
    const currentPlaces = circle.places || [];
    await circleRef.update({
      places: [...currentPlaces, newPlaceId], // Use the ID we got from the reference
      placesCount: (circle.placesCount || 0) + 1, // Increment places count
      updatedAt: new Date().toISOString()
    });
    
    // Track activity (skip for Private places — owner-only)
    if (trackPlaceAdded && newPlace.privacy !== 'private') {
      await trackPlaceAdded(newPlaceId, circleId, newPlace.name, circle.name, userId);
    }

    res.status(201).json({
      success: true,
      message: 'Place added to circle successfully',
      place: newPlace
    });
    
  } catch (error) {
    console.error('Error adding existing place to circle:', error);
    console.error('Error details:', {
      message: error.message,
      stack: error.stack,
      placeId: req.params.placeId,
      circleId: req.params.circleId,
      userId: req.user?.uid
    });
    
    // Send a more detailed error response
    return res.status(500).json({
      success: false,
      message: 'Failed to add place to circle',
      error: error.message
    });
  }
};

// @desc    Move a place to a different circle
// @route   POST /api/places/:id/move
// @access  Private
exports.movePlace = async (req, res, next) => {
  try {
    const placeId = req.params.id;
    const userId = req.user.uid;
    const { targetCircleId } = req.body;
    
    if (!targetCircleId) {
      return res.status(400).json({
        success: false,
        message: 'Target circle ID is required'
      });
    }
    
    // Get the place
    const placeRef = db.collection(COLLECTIONS.PLACES).doc(placeId);
    const placeDoc = await placeRef.get();
    
    if (!placeDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Place not found'
      });
    }
    
    const place = serializeDoc(placeDoc);
    
    // Get source circle
    const sourceCircleRef = db.collection(COLLECTIONS.CIRCLES).doc(place.circleId);
    const sourceCircleDoc = await sourceCircleRef.get();
    
    if (!sourceCircleDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Source circle not found'
      });
    }
    
    const sourceCircle = serializeDoc(sourceCircleDoc);
    
    // Get target circle
    const targetCircleRef = db.collection(COLLECTIONS.CIRCLES).doc(targetCircleId);
    const targetCircleDoc = await targetCircleRef.get();
    
    if (!targetCircleDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Target circle not found'
      });
    }
    
    const targetCircle = serializeDoc(targetCircleDoc);
    
    // Check permissions: user must own both circles or be the place creator
    const ownsSourceCircle = sourceCircle.owner === userId;
    const ownsTargetCircle = targetCircle.owner === userId;
    const isPlaceCreator = place.addedBy === userId;
    
    if (!ownsSourceCircle || !ownsTargetCircle) {
      if (!isPlaceCreator || !ownsTargetCircle) {
        return res.status(403).json({
          success: false,
          message: 'You must own both circles or be the place creator and own the target circle to move a place'
        });
      }
    }
    
    // Does the target circle already hold this venue? Then this is a merge:
    // the copy being moved goes away, the target keeps its copy plus
    // anything worth carrying over. (It used to refuse with "already
    // exists", which left the place stuck in the source circle.)
    const targetSnap = await db.collection(COLLECTIONS.PLACES)
      .where('circleId', '==', targetCircleId)
      .where('deletedAt', '==', null)
      .get();
    const existingDoc = targetSnap.docs.find((d) => d.id !== placeId && sameVenue(place, serializeDoc(d)));

    if (existingDoc) {
      const existing = serializeDoc(existingDoc);
      const patch = carryOverPatch(place, existing);
      const now = new Date().toISOString();
      await db.runTransaction(async (transaction) => {
        const sourcePlaces = sourceCircle.places || [];
        transaction.update(sourceCircleRef, {
          places: sourcePlaces.filter(id => id !== placeId),
          placesCount: Math.max(0, (sourceCircle.placesCount || 0) - 1),
          updatedAt: now
        });
        transaction.update(placeRef, { deletedAt: now, updatedAt: now, mergedInto: existingDoc.id });
        if (Object.keys(patch).length) {
          transaction.update(existingDoc.ref, { ...patch, updatedAt: now });
        }
      });
      indexPlaceRemoved(place.circleId, place);
      placeCache.clear('browseTree', userId);
      const mergedDoc = await existingDoc.ref.get();
      return res.status(200).json({
        success: true,
        merged: true,
        message: `${place.name} was already in ${targetCircle.name}, so it was removed from ${sourceCircle.name}`,
        place: serializeDoc(mergedDoc)
      });
    }

    // Use a transaction for atomic updates
    await db.runTransaction(async (transaction) => {
      // Remove place ID from source circle
      const sourcePlaces = sourceCircle.places || [];
      const updatedSourcePlaces = sourcePlaces.filter(id => id !== placeId);
      
      transaction.update(sourceCircleRef, {
        places: updatedSourcePlaces,
        placesCount: Math.max(0, (sourceCircle.placesCount || 0) - 1),
        updatedAt: new Date().toISOString()
      });
      
      // Add place ID to target circle
      const targetPlaces = targetCircle.places || [];
      transaction.update(targetCircleRef, {
        places: [placeId, ...targetPlaces], // Add at beginning
        placesCount: (targetCircle.placesCount || 0) + 1,
        updatedAt: new Date().toISOString()
      });
      
      // Update place's circleId
      transaction.update(placeRef, {
        circleId: targetCircleId,
        updatedAt: new Date().toISOString()
      });
    });
    
    // Get updated place
    const updatedPlaceDoc = await placeRef.get();
    const updatedPlace = serializeDoc(updatedPlaceDoc);

    // Browse tree upkeep: same venue, different circle — move the density count.
    indexPlaceMoved(place.circleId, targetCircleId, place);
    placeCache.clear('browseTree', userId);

    // Track activity (skip for Private places — owner-only)
    if (trackPlaceAdded && updatedPlace.privacy !== 'private') {
      await trackPlaceAdded(placeId, targetCircleId, updatedPlace.name, targetCircle.name, userId);
    }

    res.status(200).json({
      success: true,
      message: 'Place moved successfully',
      place: updatedPlace
    });
    
  } catch (error) {
    console.error('Error moving place:', error);
    next(error);
  }
};

// @desc    Get places from multiple circles in a single request
// @route   POST /api/places/batch
// @access  Private
exports.getPlacesByMultipleCircles = async (req, res, next) => {
  try {
    console.log('🔍 getPlacesByMultipleCircles - START - Request details:', {
      circleIds: req.body.circleIds?.length || 0,
      userUid: req.user?.uid,
      userEmail: req.user?.email
    });

    const { circleIds } = req.body;
    
    if (!circleIds || !Array.isArray(circleIds) || circleIds.length === 0) {
      return res.status(400).json({
        success: false,
        message: 'Circle IDs array is required'
      });
    }
    
    // Limit the number of circles to prevent abuse
    if (circleIds.length > 50) {
      return res.status(400).json({
        success: false,
        message: 'Maximum 50 circles allowed per batch request'
      });
    }
    
    const currentUserId = req.user.uid;
    const allPlaces = [];
    const processedCircles = new Set();

    // Resolve the user's accepted connections ONCE (both directions), storing
    // normalized ids. The previous per-circle exact-match connection queries
    // silently denied myNetwork circles whose owner id used a different format
    // than the connection doc (e.g. Apple Sign-In complex ids).
    const [connSnap1, connSnap2] = await Promise.all([
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', currentUserId)
        .where('status', '==', 'accepted')
        .get(),
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('connectedUserId', '==', currentUserId)
        .where('status', '==', 'accepted')
        .get()
    ]);
    const connectedUserIds = new Set();
    connSnap1.docs.forEach(doc => connectedUserIds.add(normalizeUserId(doc.data().connectedUserId)));
    connSnap2.docs.forEach(doc => connectedUserIds.add(normalizeUserId(doc.data().userId)));

    // The connection sets are already loaded above, so reuse them rather than
    // paying for buildViewerContext's own connection reads.
    const batchViewerCtx = makeViewerContext({
      viewerId: currentUserId,
      connections: connectedUserIds,
      innerCircleLists: await getInnerCircleGrantorLists(currentUserId)
    });

    // Place activities across ALL connections, keyed by place id — powers the
    // same isNew flag getPlacesByCircleId computes, from docs already in hand.
    // (Deliberately NOT paired with markCirclePlacesViewed: a bulk home load
    // is not "entering the circle", so red dots survive until the user
    // actually opens the circle via GET circles/:id/places.)
    const placeActivityById = new Map();
    [...connSnap1.docs, ...connSnap2.docs].forEach(doc => {
      (doc.data().recentActivity || []).forEach(activity => {
        if (activity.type === 'place' && activity.entityId && !placeActivityById.has(activity.entityId)) {
          placeActivityById.set(activity.entityId, activity);
        }
      });
    });

    // Fetch all requested circles in one batched read (doc-id lookups don't
    // need '__name__ in' chunk queries), then all their places in parallel
    // batched reads. The previous nested chunk-of-10 loops awaited serially —
    // ~500 sequential round trips for a full 50-circle batch.
    const uniqueCircleIds = [...new Set(circleIds)];
    const circleDocs = await db.getAll(
      ...uniqueCircleIds.map(id => db.collection(COLLECTIONS.CIRCLES).doc(id))
    );

    const accessibleCircles = [];
    for (const circleDoc of circleDocs) {
      if (!circleDoc.exists) continue;
      const circle = serializeDoc(circleDoc);
      if (processedCircles.has(circle.id)) continue;
      processedCircles.add(circle.id);

      // The connection set and inner-circle grants are already resolved for
      // this request, so the tier check costs nothing extra here.
      if (!canViewCircle(circle, currentUserId, batchViewerCtx)) continue;
      accessibleCircles.push(circle);
    }

    // Collect every accessible circle's place ids (deduped) and read them in
    // parallel batches.
    const accessibleCircleIds = new Set(accessibleCircles.map(c => c.id));
    const accessibleCircleById = new Map(accessibleCircles.map(c => [c.id, c]));
    const seenPlaceIds = new Set();
    const placeRefs = [];
    for (const circle of accessibleCircles) {
      for (const placeId of (circle.places || [])) {
        if (!seenPlaceIds.has(placeId)) {
          seenPlaceIds.add(placeId);
          placeRefs.push(db.collection(COLLECTIONS.PLACES).doc(placeId));
        }
      }
    }

    const PLACE_READ_BATCH = 300;
    const placeBatchReads = [];
    for (let i = 0; i < placeRefs.length; i += PLACE_READ_BATCH) {
      placeBatchReads.push(db.getAll(...placeRefs.slice(i, i + PLACE_READ_BATCH)));
    }
    const placeDocGroups = await Promise.all(placeBatchReads);

    for (const group of placeDocGroups) {
      for (const placeDoc of group) {
        if (!placeDoc.exists) continue;
        const place = serializeDoc(placeDoc);
        // Match getPlacesByCircleId semantics: soft-deleted places are
        // excluded whether deletedAt is null OR missing (the old
        // "deletedAt == null" query silently dropped legacy docs without
        // the field), place-level privacy is enforced, and the place must
        // still belong to one of the requested, accessible circles.
        if (place.deletedAt !== null && place.deletedAt !== undefined) continue;
        if (!accessibleCircleIds.has(place.circleId)) continue;
        if (!isPlaceVisibleToViewer(place, currentUserId, batchViewerCtx)) continue;

        // Filter privateNotes - only visible to the user who added the place
        const placeData = { ...place };
        if (place.addedBy !== currentUserId) {
          delete placeData.privateNotes;
        }

        // isNew: same semantics as getPlacesByCircleId — only meaningful in
        // circles the viewer doesn't own, never for places they added, and
        // driven by the connection activity's viewedBy list.
        let isNew = false;
        const parentCircle = accessibleCircleById.get(place.circleId);
        if (parentCircle && parentCircle.owner !== currentUserId && place.addedBy !== currentUserId) {
          const activity = placeActivityById.get(place.id);
          if (activity) {
            isNew = !(activity.viewedBy || []).includes(currentUserId);
          }
        }
        placeData.isNew = isNew;

        allPlaces.push(placeData);
      }
    }

    console.log(`✅ Batch fetched ${allPlaces.length} places from ${processedCircles.size} accessible circles`);

    // Lean pin mode (opt-in via ?lean=1 or body {lean:true}): map markers
    // render only name/coordinates/category — no photos, no social counts —
    // so skip the venue/social enrichment and strip the payload to what a
    // pin draws. Surfaces that display photos or social data must use the
    // default full mode. Old clients never send the flag, so the default
    // response shape is untouched.
    const lean = req.query.lean === '1' || req.body.lean === true;
    if (lean) {
      const leanPlaces = allPlaces.map(p => ({
        id: p.id,
        name: p.name,
        address: p.address,
        location: p.location,
        circleId: p.circleId,
        category: p.category,
        customCategoryId: p.customCategoryId,
        globalPlaceId: p.globalPlaceId,
        addedBy: p.addedBy,
        isNew: p.isNew
      }));
      return res.status(200).json({
        success: true,
        places: leanPlaces,
        circlesProcessed: processedCircles.size,
        totalPlaces: leanPlaces.length,
        lean: true
      });
    }

    // Overlay social + venue data from the canonical venue records, and
    // attach adder info so clients can show "Added by <name>"
    const [socialByGlobalId, addedByUserMap] = await Promise.all([
      fetchGlobalSocialMap(allPlaces),
      buildAddedByUserMap(allPlaces)
    ]);
    const placesWithSocial = allPlaces.map(place => {
      const social = socialByGlobalId.get(place.globalPlaceId);
      const addedByUser = addedByUserMap.get(place.addedBy) || null;
      if (!social) return normalizePhotosArray({ ...place, addedByUser });
      // normalizePhotosArray is REQUIRED after pooling venue photos: the venue
      // stores photo objects ({id,url,uploadedBy,...}) while the client decodes
      // photos as [String]. Without it the whole response fails to decode and
      // the screen renders empty.
      return normalizePhotosArray({
        ...overlayVenuePhotos(overlayVenueFields(place, social.venueData), social.venueData, req.user.uid),
        addedByUser,
        likes: social.likes,
        likesCount: social.likes.length,
        commentsCount: social.commentsCount
      });
    });

    res.status(200).json({
      success: true,
      places: placesWithSocial,
      circlesProcessed: processedCircles.size,
      totalPlaces: placesWithSocial.length
    });
    
  } catch (error) {
    console.error('Error in batch place fetch:', error);
    next(error);
  }
};

// @desc    Get all places from user's circles for check-in
// @route   GET /api/places/my-places
// @access  Private
// @desc    The caller's own save of a venue, looked up by canonical venue id.
//          Lets the app offer per-save actions (private notes, tags) while
//          showing another user's copy of the same venue.
// @route   GET /api/places/my-save/:globalPlaceId
// @access  Private
exports.getMySaveOfVenue = async (req, res, next) => {
  try {
    const { globalPlaceId } = req.params;
    let snap = await db.collection(COLLECTIONS.PLACES)
      .where('addedBy', '==', req.user.uid)
      .where('globalPlaceId', '==', globalPlaceId)
      .get();
    let doc = snap.docs.find((d) => !d.data().deletedAt);
    if (!doc) {
      // Older saves may predate global-place linking — try the Google id
      snap = await db.collection(COLLECTIONS.PLACES)
        .where('addedBy', '==', req.user.uid)
        .where('googlePlaceId', '==', globalPlaceId)
        .get();
      doc = snap.docs.find((d) => !d.data().deletedAt);
    }
    if (!doc) {
      return res.status(404).json({
        success: false,
        message: 'You have not saved this place'
      });
    }
    res.status(200).json({
      success: true,
      place: serializeDoc(doc)
    });
  } catch (error) {
    console.error('Error fetching own save of venue:', error);
    next(error);
  }
};

exports.getMyPlacesForCheckIn = async (req, res, next) => {
  try {
    const userId = req.user.uid;
    
    console.log('🏠 Fetching places for check-in - User:', userId);
    console.log('📍 This endpoint now includes places from both owned and shared circles');
    
    // Own circles and circles shared with the user, together
    const [ownCirclesSnapshot, sharedCirclesSnapshot] = await Promise.all([
      db.collection(COLLECTIONS.CIRCLES).where('owner', '==', userId).orderBy('updatedAt', 'desc').get(),
      db.collection(COLLECTIONS.CIRCLES).where('sharedWith', 'array-contains', userId).orderBy('updatedAt', 'desc').get()
    ]);
    
    // Combine both snapshots
    const allCircles = [...ownCirclesSnapshot.docs, ...sharedCirclesSnapshot.docs];
    
    if (allCircles.length === 0) {
      return res.status(200).json({
        success: true,
        data: [],
        message: 'No circles found'
      });
    }
    
    const circleMap = new Map(); // Store circle info for each place
    allCircles.forEach(circleDoc => {
      const circle = serializeDoc(circleDoc);
      circleMap.set(circle.id, circle);
    });

    // Every circle's places in chunked circleId-in queries (was one query per
    // circle — a 200-circle account made 200 reads per picker open). The list
    // is sorted below, so no per-query order is needed.
    const placeDocs = await queryInChunks([...circleMap.keys()], chunk =>
      db.collection(COLLECTIONS.PLACES).where('circleId', 'in', chunk).get());
    
    // Combine and format all places
    const allPlaces = [];
    placeDocs.forEach(placeDoc => {
      const place = serializeDoc(placeDoc);
      // Trashed saves stay out of the picker: checking in via one pinned
      // the check-in to a deleted doc and skipped the re-save
      if (place.deletedAt) return;
      const circle = circleMap.get(place.circleId);
      
      // Filter privateNotes - only visible to the user who added the place
      const placeData = {
        ...place,
        circleName: circle?.name || 'Unknown Circle',
        circleCategory: circle?.category || 'other'
      };
      
      // Remove privateNotes if the current user is not the one who added the place
      if (place.addedBy !== userId) {
        delete placeData.privateNotes;
      }
      
      allPlaces.push(placeData);
    });
  
    // Sort by most recently added/updated
    allPlaces.sort((a, b) => {
      const dateA = new Date(a.updatedAt || a.createdAt);
      const dateB = new Date(b.updatedAt || b.createdAt);
      return dateB - dateA;
    });
    
    console.log(`✅ Found ${allPlaces.length} places from ${allCircles.length} circles for check-in`);
    
    res.status(200).json({
      success: true,
      data: allPlaces,
      circleCount: allCircles.length,
      placeCount: allPlaces.length
    });
    
  } catch (error) {
    console.error('Error fetching places for check-in:', error);
    next(error);
  }
};
