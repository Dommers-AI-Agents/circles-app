// controllers/places/placeController.js
// Place save records: list by circle(s), get, create, update, delete, search, address edit, reorder, move, add-existing, my-save lookups
// Split out of firebasePlaceController.js (handlers unchanged).
const { getFirestore } = require('../../config/firebase');
const { COLLECTIONS, createPlace, validatePlace, serializeDoc, serializeQuerySnapshot } = require('../../models/FirestoreModels');
const { Client } = require('@googlemaps/google-maps-services-js');
const geofire = require('geofire-common');
const { normalizeUserId, isSameUser } = require('../../services/idService');
const { ensureGlobalPlaceLink } = require('../../services/globalPlaceResolver');
const { ensureCircleCoverImage } = require('../../services/circleCover');
const { indexSavedPlace, indexPlaceRemoved, indexPlaceMoved } = require('../../services/circleLocationSummary');
const { GLOBAL_COLLECTIONS, buildSearchTokens } = require('../../models/GlobalPlace');
const { googleMapsApiKey } = require('../../config/config');
const notificationService = require('../../services/notificationService');
const { trackPlaceAdded, markCirclePlacesViewed } = require('../../services/activityService');
const placeCache = require('../../services/placeCache');
const requestDeduplicator = require('../../services/requestDeduplicator');
const subscriptionLimitService = require('../../services/subscriptionLimitService');
const rewardService = require('../../services/rewardService');
const piggyBankService = require('../../services/piggyBankService');
const { normalizePhotosArray, overlayVenuePhotos, VENUE_GOOGLE_FIELDS, overlayVenueFields, getGlobalSocial, fetchGlobalSocialMap, buildAddedByUserMap, isPlaceVisibleToViewer } = require('../../services/placeReadService');
const db = getFirestore();
const googleMapsClient = new Client({});
const { propagateVenueUpdates } = require('../../services/placeVenueSync.js');

// A verified store owner (approved ownership claim → stickerVenues.ownerUserId)
// — or a manager the owner invited (managerUserIds) — edits their venue's
// Google-backed fields like a super-user does.
const isVerifiedVenueOwner = async (uid, placeId, googlePlaceId) => {
  try {
    const venue = await rewardService.findVenueByPlace(placeId || googlePlaceId, googlePlaceId);
    if (!venue) return false;
    if (venue.ownerUserId && isSameUser(venue.ownerUserId, uid)) return true;
    return (venue.managerUserIds || []).some((id) => isSameUser(id, uid));
  } catch (error) {
    console.error('⚠️ Venue-owner check failed:', error.message);
    return false;
  }
};

// Google-backed saves arrive with client-authored venue fields. Re-anchor them
// server-side so a tampered Add Place request can't seed or shadow the
// canonical venue record: the existing globalPlaces record wins; a first save
// (which will seed that record) is verified against Google Places directly.
// Mutates placeData. Category stays client-supplied on the Google path — the
// Google-types → app-category mapping lives client-side.
const anchorVenueFieldsToSource = async (placeData) => {
  const googlePlaceId = placeData.googlePlaceId;

  const applyLocation = (coordinates) => {
    if (Array.isArray(coordinates) && coordinates.length === 2 &&
        typeof coordinates[0] === 'number' && typeof coordinates[1] === 'number') {
      placeData.location = { type: 'Point', coordinates: [coordinates[0], coordinates[1]] };
      placeData.geohash = geofire.geohashForLocation([coordinates[1], coordinates[0]]);
    }
  };

  const canonicalHit = await db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES)
    .where('googlePlaceId', '==', googlePlaceId)
    .limit(1)
    .get();
  if (!canonicalHit.empty) {
    const canonical = canonicalHit.docs[0].data();
    ['name', 'address', 'category', 'subcategory'].forEach((field) => {
      if (canonical[field] !== undefined && canonical[field] !== null && canonical[field] !== '') {
        placeData[field] = canonical[field];
      }
    });
    applyLocation(canonical.location?.coordinates);
    const googleData = canonical.googleData || {};
    VENUE_GOOGLE_FIELDS.forEach((field) => {
      if (googleData[field] !== undefined && googleData[field] !== null && googleData[field] !== '') {
        placeData[field] = googleData[field];
      }
    });
    console.log(`🔒 Venue fields anchored to canonical record for ${googlePlaceId}`);
    return;
  }

  if (!googleMapsApiKey) return;
  try {
    // Own cache namespace: refreshPlace caches a narrower field set under
    // 'placeDetails' and must not satisfy this lookup
    let details = placeCache.get('placeDetailsFull', googlePlaceId);
    if (!details) {
      details = await requestDeduplicator.execute(`placeDetailsFull_${googlePlaceId}`, async () => {
        const cached = placeCache.get('placeDetailsFull', googlePlaceId);
        if (cached) return cached;
        const response = await googleMapsClient.placeDetails({
          params: {
            place_id: googlePlaceId,
            // editorial_summary rides the Atmosphere SKU this call already
            // bills for rating/price_level — no incremental API cost
            fields: ['name', 'formatted_address', 'geometry', 'website',
                     'formatted_phone_number', 'rating', 'user_ratings_total', 'price_level',
                     'editorial_summary',
                     // Atmosphere SKU already billed above — no incremental cost
                     'delivery', 'dine_in', 'reservable', 'takeout', 'curbside_pickup'],
            key: googleMapsApiKey
          }
        });
        placeCache.set('placeDetailsFull', googlePlaceId, response.data.result);
        return response.data.result;
      });
    }
    if (!details) return;

    if (details.name) placeData.name = details.name;
    if (details.formatted_address) placeData.address = details.formatted_address;
    const loc = details.geometry?.location;
    if (loc) applyLocation([loc.lng, loc.lat]);
    placeData.website = details.website || null;
    placeData.phone = details.formatted_phone_number || null;
    placeData.rating = details.rating ?? null;
    placeData.userRatingsTotal = details.user_ratings_total ?? null;
    placeData.priceLevel = details.price_level ?? null;
    // ?? not || — false is a real answer ("does not deliver"), null = unknown
    placeData.delivery = details.delivery ?? null;
    placeData.dineIn = details.dine_in ?? null;
    placeData.reservable = details.reservable ?? null;
    placeData.takeout = details.takeout ?? null;
    placeData.curbsidePickup = details.curbside_pickup ?? null;
    // Google's editorial summary replaces whatever the client synthesized —
    // old app builds still send placeholder text ("A dining establishment in …")
    if (details.editorial_summary?.overview) {
      placeData.description = details.editorial_summary.overview;
      placeData.descriptionSource = 'google_editorial';
    }
    console.log(`🔒 Venue fields verified against Google Places for new venue ${googlePlaceId}`);
  } catch (error) {
    // Availability over strictness: a Google outage shouldn't block saves
    console.warn(`⚠️ Could not verify venue fields with Google for ${googlePlaceId}: ${error.message}`);
  }
};

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

    // Check permissions
    const isOwner = circle.owner === req.user.uid;
    const isSharedWith = circle.sharedWith && circle.sharedWith.includes(req.user.uid);
    const isPublic = circle.privacy === 'public';

    // Both-direction connection docs between viewer and owner. Fetched once
    // here (when needed for the myNetwork permission check) and reused by the
    // activity/isNew pass below instead of re-querying the same pair.
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

    // For myNetwork privacy, check if users are connected
    let isConnected = false;
    if (circle.privacy === 'myNetwork' && !isOwner) {
      ownerConnectionDocs = await fetchOwnerConnectionDocs();
      isConnected = ownerConnectionDocs.length > 0;
    }

    if (!isOwner && !isSharedWith && !isPublic && !(circle.privacy === 'myNetwork' && isConnected)) {
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
    const places = allPlaces.filter(place =>
      (place.deletedAt === null || place.deletedAt === undefined) &&
      isPlaceVisibleToViewer(place, req.user.uid)
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
        
        // Map both the simple and complex ID formats
        userMap.set(userData.id, {
          id: userData.id,
          displayName: userData.displayName || 'Unknown User',
          email: userData.email,
          profilePicture: userData.profilePicture
        });
        
        // Also map the original ID if it's different
        if (originalUserId !== userData.id) {
          userMap.set(originalUserId, {
            id: userData.id,
            displayName: userData.displayName || 'Unknown User',
            email: userData.email,
            profilePicture: userData.profilePicture
          });
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
        ...(social ? overlayVenuePhotos(overlayVenueFields(place, social.venueData), social.venueData) : place),
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
    
    // Filter out soft-deleted places, and any Private places — this is an
    // unauthenticated public share, so there is no owner to exempt
    const allPlaces = serializeQuerySnapshot(placesSnapshot);
    const places = allPlaces.filter(place => {
      const isDeleted = place.deletedAt !== null && place.deletedAt !== undefined;
      return !isDeleted && place.privacy !== 'private';
    });

    console.log(`🔍 Found ${places.length} active places for public circle`);
    
    // Get unique user IDs who added places
    const userIds = [...new Set(places.map(place => place.addedBy))];
    
    // Fetch user information for all users who added places
    const userPromises = userIds.map(userId => {
      let actualUserId = userId;
      if (userId && userId.includes('.')) {
        const parts = userId.split('.');
        if (parts.length >= 2) {
          actualUserId = parts[1];
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
        const originalUserId = userIds[index];
        
        userMap.set(userData.id, {
          id: userData.id,
          displayName: userData.displayName || 'Unknown User',
          email: userData.email,
          profilePicture: userData.profilePicture
        });
        
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
      const isOwner = circle.owner === userId;
      const isSharedWith = circle.sharedWith && circle.sharedWith.includes(userId);
      const isPublic = circle.privacy === 'public';
      
      console.log(`🔐 Is owner: ${isOwner}`);
      console.log(`🔐 Is shared with: ${isSharedWith}`);
      console.log(`🔐 Is public: ${isPublic}`);
      
      // Check relationship with circle owner to determine access
      let hasAccess = false;
      
      // Owner always has access
      if (isOwner) {
        hasAccess = true;
      }
      // Explicitly shared users have access
      else if (isSharedWith) {
        hasAccess = true;
      }
      // Public circles are accessible to everyone
      else if (isPublic) {
        hasAccess = true;
      }
      // For non-public circles, check relationship with owner
      else {
        console.log(`\n🔐 Checking relationship with circle owner...`);
        const ownerDoc = await db.collection(COLLECTIONS.USERS).doc(circle.owner).get();
        if (ownerDoc.exists) {
          const ownerData = serializeDoc(ownerDoc);
          
          // Check if current user is following the owner (gets access to public circles)
          const isFollowingOwner = ownerData.followers && ownerData.followers.includes(userId);
          
          // Check if current user is connected to the owner (gets access to myNetwork circles)  
          const isConnected = ownerData.connections && ownerData.connections.includes(userId);
          
          console.log(`🔐 Owner's connections array: ${ownerData.connections ? ownerData.connections.length + ' connections' : 'none'}`);
          console.log(`🔐 Is user in owner's connections: ${isConnected}`);
          console.log(`🔐 Is user following owner: ${isFollowingOwner}`);
          
          // Also check the connections collection for proper connection status
          const connectionQuery = await db.collection(COLLECTIONS.CONNECTIONS)
            .where('userId', '==', circle.owner)
            .where('connectedUserId', '==', userId)
            .where('status', '==', 'accepted')
            .get();
          
          const reverseConnectionQuery = await db.collection(COLLECTIONS.CONNECTIONS)
            .where('userId', '==', userId)
            .where('connectedUserId', '==', circle.owner)
            .where('status', '==', 'accepted')
            .get();
            
          const hasConnectionRecord = !connectionQuery.empty || !reverseConnectionQuery.empty;
          console.log(`🔐 Has connection record in connections collection: ${hasConnectionRecord}`);
          
          // For myNetwork privacy, connections have access
          if ((circle.privacy === 'myNetwork' || circle.privacy === 'my_network') && (isConnected || hasConnectionRecord)) {
            console.log(`✅ Access granted: User is connected to circle owner (myNetwork circle)`);
            hasAccess = true;
          }
          // For public circles, followers have access (but we already checked isPublic above)
          // This is redundant but kept for clarity
          else if (isPublic && isFollowingOwner) {
            hasAccess = true;
          }
        } else {
          console.log(`❌ Owner document not found for userId: ${circle.owner}`);
        }
      }
      
      // Deny access if none of the conditions are met
      if (!hasAccess) {
        console.log(`\n❌ ========== ACCESS DENIED ==========`);
        console.log(`❌ Place: ${place.name}`);
        console.log(`❌ Circle: ${circle.name}`);
        console.log(`❌ User: ${userId}`);
        console.log(`❌ Circle Owner: ${circle.owner}`);
        console.log(`❌ Circle Privacy: ${circle.privacy}`);
        console.log(`❌ Is Owner: ${isOwner}`);
        console.log(`❌ Is Shared With: ${isSharedWith}`);
        console.log(`❌ Is Public: ${isPublic}`);
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

    // A place marked Private is owner-only, even inside a visible circle
    if (!isPlaceVisibleToViewer(place, req.user.uid)) {
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
    let placeData = {
      ...place,
      globalPlaceId: social.globalPlaceId || place.globalPlaceId || null,
      addedByUser: addedByUserMap.get(place.addedBy) || null,
      likes: social.likes,
      likesCount: social.likes.length,
      commentsCount: social.commentsCount,
      followersCount: (social.venueData && social.venueData.followersCount) || 0,
      isFollowing: ((social.venueData && social.venueData.followers) || []).includes(req.user.uid)
    };
    if (social.venueData) {
      placeData = overlayVenuePhotos(overlayVenueFields(placeData, social.venueData), social.venueData);
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
    const { circleId } = req.body;

    if (!circleId) {
      return res.status(400).json({
        success: false,
        message: 'Circle ID is required'
      });
    }

    // Verify circle exists and user has permission
    const circleDoc = await db.collection(COLLECTIONS.CIRCLES).doc(circleId).get();
    
    if (!circleDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Circle not found'
      });
    }

    const circle = serializeDoc(circleDoc);
    
    // Check if user can add places (owner or shared with)
    const isOwner = circle.owner === req.user.uid;
    const isSharedWith = circle.sharedWith.includes(req.user.uid);
    
    if (!isOwner && !isSharedWith) {
      return res.status(403).json({
        success: false,
        message: 'Not authorized to add places to this circle'
      });
    }

    // Check subscription limits for the circle owner (not the current user if they're just shared with)
    const limitCheck = await subscriptionLimitService.canAddPlace(circle.owner, circleId);
    if (!limitCheck.canAdd) {
      return res.status(403).json({
        success: false,
        message: limitCheck.error,
        upgradeRequired: true,
        currentCount: limitCheck.currentCount,
        maxAllowed: limitCheck.maxAllowed
      });
    }

    // Validate place data
    const validationErrors = validatePlace(req.body);
    if (validationErrors.length > 0) {
      return res.status(400).json({
        success: false,
        message: 'Validation error',
        errors: validationErrors
      });
    }

    // Check for duplicates before creating (excluding soft-deleted places)
    // Skip duplicate check if force flag is set (user selected "Add Anyway")
    const { googlePlaceId, name, address, force } = req.body;
    
    if (!force) {
      if (googlePlaceId) {
        const existingPlace = await db.collection(COLLECTIONS.PLACES)
          .where('circleId', '==', circleId)
          .where('googlePlaceId', '==', googlePlaceId)
          .where('deletedAt', '==', null)
          .get();
          
        if (!existingPlace.empty) {
          return res.status(400).json({
            success: false,
            code: 'DUPLICATE_PLACE',
            existingPlaceId: existingPlace.docs[0].id,
            message: 'This place already exists in the selected circle'
          });
        }
      } else if (name && address) {
        // For custom places without googlePlaceId
        const existingPlace = await db.collection(COLLECTIONS.PLACES)
          .where('circleId', '==', circleId)
          .where('name', '==', name)
          .where('address', '==', address)
          .where('deletedAt', '==', null)
          .get();

        if (!existingPlace.empty) {
          return res.status(400).json({
            success: false,
            code: 'DUPLICATE_PLACE',
            existingPlaceId: existingPlace.docs[0].id,
            message: 'This place already exists in the selected circle'
          });
        }
      }
    } else {
      console.log('⚠️ Duplicate check bypassed with force flag for place:', { name, address, googlePlaceId });
    }

    // Create place data
    const placeData = createPlace(req.body, circleId, req.user.uid);

    // Share-extension saves arrive bare (name/address/coords) with
    // enrichFromGoogle set — the extension can't run the Places SDK. Mirror
    // the check-in pattern exactly: canonical venue first (zero Google spend
    // when anyone on the platform already saved this venue), Google
    // enrichment only for venues new to the whole platform. Failure leaves a
    // bare-but-valid save — availability over completeness.
    if (req.body.enrichFromGoogle === true && !placeData.googlePlaceId) {
      try {
        const coords = placeData.location?.coordinates;
        let canonicalDoc = null;
        if (Array.isArray(coords) && coords.length === 2) {
          const { findCanonicalByNameAndLocation } = require('../../services/globalPlaceResolver');
          canonicalDoc = await findCanonicalByNameAndLocation(placeData.name, { coordinates: coords });
        }
        const canonicalData = canonicalDoc ? canonicalDoc.data() : null;

        if (canonicalData && canonicalData.googlePlaceId) {
          // Genuinely enriched canonical: zero Google spend — the anchor
          // below overlays every venue field from it.
          placeData.googlePlaceId = canonicalData.googlePlaceId;
          console.log(`✅ Share save matched enriched canonical ${canonicalDoc.id} — skipping Google`);
        } else if (Array.isArray(coords) && coords.length === 2) {
          // No canonical, or a BARE one (seeded by an earlier bare save of
          // this venue — a bare match must not satisfy canonical-first, or
          // the venue stays bare forever).
          const { enrichPlaceWithGoogleData } = require('../checkInController');
          const googleData = await enrichPlaceWithGoogleData(placeData.name, {
            latitude: coords[1],
            longitude: coords[0]
          }, {
            // A bare canonical can still carry photos (copied from the first
            // save) — re-hosting Google's photo again would add a
            // byte-identical duplicate under a new URL.
            skipPhotos: !!(canonicalData && (canonicalData.photos || []).length)
          });
          if (googleData.googlePlaceId) {
            placeData.googlePlaceId = googleData.googlePlaceId;
            if (googleData.name) placeData.name = googleData.name;
            if (googleData.address) placeData.address = googleData.address;
            if (googleData.photos && googleData.photos.length > 0) placeData.photos = googleData.photos;
            if (googleData.googleTypes && googleData.googleTypes.length > 0) placeData.googleTypes = googleData.googleTypes;
            placeData.rating = googleData.rating ?? placeData.rating;
            placeData.userRatingsTotal = googleData.userRatingsTotal ?? placeData.userRatingsTotal;
            placeData.priceLevel = googleData.priceLevel ?? placeData.priceLevel;
            placeData.website = googleData.website || placeData.website;
            placeData.phone = googleData.phoneNumber || placeData.phone;
            placeData.openingHours = googleData.openingHours || placeData.openingHours;
            placeData.delivery = googleData.delivery ?? placeData.delivery;
            placeData.dineIn = googleData.dineIn ?? placeData.dineIn;
            placeData.reservable = googleData.reservable ?? placeData.reservable;
            placeData.takeout = googleData.takeout ?? placeData.takeout;
            placeData.curbsidePickup = googleData.curbsidePickup ?? placeData.curbsidePickup;
            if (googleData.description) {
              placeData.description = googleData.description;
              placeData.descriptionSource = 'google_editorial';
            }
            console.log(`✅ Share save enriched from Google: ${googleData.googlePlaceId}`);

            // Upgrade the bare canonical IN PLACE. Without this,
            // ensureGlobalPlaceLink matches the save to the bare record,
            // strips the enriched fields off the save, and every read
            // overlays bare data — the enrichment would vanish.
            if (canonicalDoc) {
              const { createAttributedPhoto } = require('../../models/GlobalPlace');
              const upgradedName = googleData.name || canonicalData.name;
              const canonicalUpdates = {
                googlePlaceId: googleData.googlePlaceId,
                name: upgradedName,
                nameLower: (upgradedName || '').toLowerCase(),
                searchTokens: buildSearchTokens(upgradedName),
                address: googleData.address || canonicalData.address,
                'googleData.rating': googleData.rating ?? null,
                'googleData.userRatingsTotal': googleData.userRatingsTotal ?? null,
                'googleData.priceLevel': googleData.priceLevel ?? null,
                'googleData.website': googleData.website || null,
                'googleData.phone': googleData.phoneNumber || null,
                'googleData.openingHours': googleData.openingHours || null,
                'googleData.delivery': googleData.delivery ?? null,
                'googleData.dineIn': googleData.dineIn ?? null,
                'googleData.reservable': googleData.reservable ?? null,
                'googleData.takeout': googleData.takeout ?? null,
                'googleData.curbsidePickup': googleData.curbsidePickup ?? null,
                updatedAt: new Date().toISOString()
              };
              if (googleData.description && !canonicalData.description) {
                canonicalUpdates.description = googleData.description;
                canonicalUpdates.descriptionSource = 'google_editorial';
              }
              if (googleData.photos && googleData.photos.length > 0 &&
                  !(canonicalData.photos || []).length) {
                canonicalUpdates.photos = googleData.photos.map(url => createAttributedPhoto({
                  url,
                  uploadedBy: null,
                  uploadedByName: null,
                  source: 'google_places'
                }));
              }
              await canonicalDoc.ref.update(canonicalUpdates);
              console.log(`⬆️ Upgraded bare canonical ${canonicalDoc.id} with Google enrichment`);
            }
          }
        }
      } catch (enrichError) {
        console.warn('⚠️ Share-save enrichment failed (continuing bare):', enrichError.message);
      }
    }

    // Second duplicate gate, post-enrichment: a share-extension save arrives
    // without googlePlaceId, so the name+address check above misses the same
    // venue saved earlier under a differently-formatted address. Now that
    // enrichment resolved the venue identity, re-check the circle by it.
    if (!force && !googlePlaceId && placeData.googlePlaceId) {
      const dupSnap = await db.collection(COLLECTIONS.PLACES)
        .where('circleId', '==', circleId)
        .where('googlePlaceId', '==', placeData.googlePlaceId)
        .where('deletedAt', '==', null)
        .get();
      if (!dupSnap.empty) {
        return res.status(400).json({
          success: false,
          code: 'DUPLICATE_PLACE',
          existingPlaceId: dupSnap.docs[0].id,
          message: 'This place already exists in the selected circle'
        });
      }
    }

    // Google-backed saves: venue fields are locked to their source at creation
    // too, mirroring the updatePlace lock. Super-users and the venue's
    // verified owner keep their submitted values.
    if (placeData.googlePlaceId) {
      const exempt = req.user.isSuperUser === true
        || await isVerifiedVenueOwner(req.user.uid, null, placeData.googlePlaceId);
      if (!exempt) {
        await anchorVenueFieldsToSource(placeData);
      }
    }

    // Validate photos - reject Google Places API URLs
    if (placeData.photos && placeData.photos.length > 0) {
      const invalidPhotos = placeData.photos.filter(photo => 
        photo.includes('maps.googleapis.com') || 
        photo.includes('photoreference=')
      );
      
      if (invalidPhotos.length > 0) {
        console.error('❌ Rejected place creation with Google Places API URLs:', invalidPhotos);
        return res.status(400).json({
          success: false,
          message: 'Invalid photo URLs detected. Photos must be uploaded to Firebase Storage, not Google Places API URLs.',
          invalidUrls: invalidPhotos
        });
      }
    }
    
    // If location is missing but address is provided, try to geocode it
    if (!placeData.location && placeData.address && googleMapsApiKey) {
      console.log('🗺️ Place missing location, attempting to geocode address:', placeData.address);
      try {
        // Check cache first
        let geocodeResult = placeCache.get('geocoding', placeData.address);
        
        if (!geocodeResult) {
          // Use deduplicator to prevent concurrent identical geocoding requests
          const requestKey = requestDeduplicator.generateGeocodeKey(placeData.address);
          
          geocodeResult = await requestDeduplicator.execute(requestKey, async () => {
            // Double-check cache in case another request just completed
            const cachedResult = placeCache.get('geocoding', placeData.address);
            if (cachedResult) {
              return cachedResult;
            }
            
            const geocodeResponse = await googleMapsClient.geocode({
              params: {
                address: placeData.address,
                key: googleMapsApiKey
              }
            });
            
            if (geocodeResponse.data.results && geocodeResponse.data.results.length > 0) {
              const result = geocodeResponse.data.results[0];
              // Cache the geocoding result with 1-year TTL (addresses rarely change)
              placeCache.set('geocoding', placeData.address, result, 365 * 24 * 60 * 60 * 1000);
              return result;
            }
            
            return null;
          });
        }
        
        if (geocodeResult) {
          const { lat, lng } = geocodeResult.geometry.location;
          
          // Validate coordinates
          if (typeof lng === 'number' && typeof lat === 'number' &&
              lng >= -180 && lng <= 180 &&
              lat >= -90 && lat <= 90 &&
              !(lng === -180 && lat === -180)) {
            placeData.location = {
              type: 'Point',
              coordinates: [lng, lat]
            };
            console.log('✅ Successfully geocoded address to:', { lat, lng });
          } else {
            console.warn('⚠️ Invalid coordinates from geocoding:', { lat, lng });
          }
        } else {
          console.warn('⚠️ No geocoding results for address:', placeData.address);
        }
      } catch (error) {
        console.warn('⚠️ Geocoding failed:', error.message);
        // Continue without location - not a fatal error
      }
    }
    
    // Log place creation for debugging
    console.log('🆕 Creating new place:', {
      name: placeData.name,
      circleId: circleId,
      addedBy: req.user.uid,
      hasLocation: !!placeData.location,
      notes: {
        notes: placeData.notes ? `${placeData.notes.substring(0, 50)}...` : 'empty',
        publicNotes: placeData.publicNotes ? `${placeData.publicNotes.substring(0, 50)}...` : 'empty',
        privateNotes: placeData.privateNotes ? `${placeData.privateNotes.substring(0, 50)}...` : 'empty'
      },
      category: placeData.category,
      googlePlaceId: placeData.googlePlaceId || 'none'
    });
    
    // Add to Firestore
    const placeRef = await db.collection(COLLECTIONS.PLACES).add(placeData);

    // Get the created place with ID
    const createdPlace = await placeRef.get();
    const place = serializeDoc(createdPlace);

    // Link the save to its canonical venue record (resolve-or-create)
    const globalPlaceId = await ensureGlobalPlaceLink(createdPlace);
    if (globalPlaceId) {
      place.globalPlaceId = globalPlaceId;
    }

    // Keep the browse location tree fresh: bump this circle's summary and drop
    // the adder's cached tree (best-effort; rebuild job corrects any drift).
    indexSavedPlace(circleId, placeData);
    placeCache.clear('browseTree', req.user.uid);

    // Update circle's places array and increment count (only add if place.id is defined)
    const currentPlaces = circle.places || [];
    if (place.id) {
      await db.collection(COLLECTIONS.CIRCLES).doc(circleId).update({
        places: [place.id, ...currentPlaces], // Add new place at the beginning
        placesCount: (circle.placesCount || 0) + 1, // Increment places count
        updatedAt: new Date().toISOString()
      });
      // Default cover: a circle with no cover takes its first place photo
      if (!circle.coverImage && Array.isArray(place.photos) && place.photos.length > 0) {
        ensureCircleCoverImage(circleId, place.photos[0]);
      }
    }

    // Gamification: the user's live place count rides along so the client can
    // trigger milestone celebrations (5, 10, 20, ... places)
    let totalPlaces = null;
    try {
      const countSnap = await db.collection(COLLECTIONS.PLACES)
        .where('addedBy', '==', req.user.uid)
        .where('deletedAt', '==', null)
        .count()
        .get();
      totalPlaces = countSnap.data().count;
    } catch (countError) {
      console.error('⚠️ Milestone place count failed (non-fatal):', countError.message);
    }

    // Piggy bank: FavCoins for the add. AWAITED (uniquely among the hooks —
    // one count query + one transaction, cheap) so the deposit animation can
    // ride the create response. credit() never throws; a credit failure just
    // yields { credited: false } and the add still succeeds.
    //
    // venueKey backs up globalPlaceId in the dedup key: if venue linking
    // failed, the canonical google:/manual: identity still blocks re-adding
    // the same venue from ever paying twice.
    let piggyVenueKey = null;
    try {
      const { generatePlaceKey } = require('../../models/GlobalPlace');
      piggyVenueKey = generatePlaceKey(place);
    } catch (keyError) { /* malformed name/address — placeId last resort */ }

    // Funnel: first place they added themselves (fire-and-forget)
    require('../../services/funnelService').stampFunnelMilestone(req.user.uid, 'firstPlaceAt');

    const piggyBank = await piggyBankService.credit({
      userId: req.user.uid,
      eventType: 'add_place',
      sourceRef: {
        placeId: placeRef.id,
        globalPlaceId: globalPlaceId || null,
        venueKey: piggyVenueKey,
        circleId
      }
    });

    // Welcome gift: 25 FavCoins the first time a user ever adds a place
    // (promised by the App Clip's generic signup). The onboarding SAMPLE
    // place counts toward totalPlaces, which used to make the gate
    // (totalPlaces === 1) unreachable for anyone who got a seeded sample —
    // their real first add arrived as place #2 and the gift never fired.
    // Exclude sample places from the gate count; the first_place:{uid}
    // dedup key keeps the looser gate once-ever. Awaited and merged into
    // the response so the client animates the full 25+3 drop together.
    let welcomeGift = null;
    if (totalPlaces !== null && totalPlaces <= 2) {
      try {
        // deletedAt filter keeps this consistent with the totalPlaces count
        // (a deleted sample must not subtract from live places)
        const sampleSnap = await db.collection(COLLECTIONS.PLACES)
          .where('addedBy', '==', req.user.uid)
          .where('isSamplePlace', '==', true)
          .where('deletedAt', '==', null)
          .count()
          .get();
        const realPlaces = totalPlaces - sampleSnap.data().count;
        if (realPlaces === 1) {
          welcomeGift = await piggyBankService.credit({
            userId: req.user.uid,
            eventType: 'first_place_added',
            sourceRef: { placeId: placeRef.id }
          });
        }
      } catch (giftError) {
        console.error('⚠️ Welcome gift check failed (non-fatal):', giftError.message);
      }
    }

    // Weekly engagement bonus: first qualifying place action of the ISO week.
    // Awaited (one doc-ID create attempt; duplicates bail instantly) so it can
    // ride the same deposit animation as the add itself.
    const weeklyBonus = await piggyBankService.credit({
      userId: req.user.uid,
      eventType: 'weekly_goal',
      sourceRef: { placeId: placeRef.id }
    });

    // One combined deposit for the animation: add_place + welcome gift + weekly
    // bonus. eventType prefers the rarest credited part so the client's label
    // matches the biggest reason for the drop.
    const creditedParts = [piggyBank, welcomeGift, weeklyBonus].filter(p => p && p.credited);
    const combinedPiggyBank = creditedParts.length
      ? {
          credited: true,
          coins: creditedParts.reduce((sum, p) => sum + p.coins, 0),
          eventType: (welcomeGift && welcomeGift.credited) ? 'first_place_added'
            : (piggyBank && piggyBank.credited) ? 'add_place'
            : 'weekly_goal'
        }
      : piggyBank;

    // Add commentsCount to the response (new places have 0 comments)
    res.status(201).json({
      success: true,
      totalPlaces,
      piggyBank: combinedPiggyBank,
      place: {
        ...place,
        commentsCount: 0
      }
    });

    // Track activity for network connections — but a Private place is
    // owner-only, so it must not broadcast a "added a place" activity
    if (place.privacy !== 'private') {
      await trackPlaceAdded(placeRef.id, circleId, place.name, circle.name, req.user.uid);
    }

    // If this add came from a shared place link, credit the sharer. (Store
    // points retired here 2026-08-10 — share conversions aren't tied to a
    // shop, so under per-store loyalty the sharer earns FavCoins only.)
    if (req.body.refUserId) {
      // Piggy bank: place_adopted — the quality-aligned flagship earn. The
      // SHARER gets the coins; fire-and-forget.
      piggyBankService.credit({
        userId: req.body.refUserId,
        eventType: 'place_adopted',
        sourceRef: {
          globalPlaceId: place.globalPlaceId || null,
          googlePlaceId: place.googlePlaceId || null,
          adderUserId: req.user.uid,
          adderPlaceId: placeRef.id
        }
      }).catch(() => {});
    }

    // Send notifications to interested users
    try {
      // Get users who should be notified
      const notifyUserIds = new Set();
      
      // Add circle members (if not private)
      if (circle.privacy !== 'private') {
        // Add shared users
        circle.sharedWith.forEach(userId => {
          if (userId !== req.user.uid) {
            notifyUserIds.add(userId);
          }
        });
        
        // Add circle owner if not the one adding
        if (circle.owner !== req.user.uid) {
          notifyUserIds.add(circle.owner);
        }
        
        // If circle is public, add user's network
        if (circle.privacy === 'public' || circle.privacy === 'myNetwork') {
          const userDoc = await db.collection(COLLECTIONS.USERS).doc(req.user.uid).get();
          if (userDoc.exists) {
            const userData = userDoc.data();
            const connections = userData.friends || [];
            connections.forEach(userId => notifyUserIds.add(userId));
          }
        }
      }
      
      if (notifyUserIds.size > 0) {
        await notificationService.notifyNewPlace(
          place,
          circle,
          Array.from(notifyUserIds)
        );
      }
    } catch (notifError) {
      console.error('Error sending place notifications:', notifError);
      // Don't fail the request if notifications fail
    }
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
      isVenueOwnerEdit = await isVerifiedVenueOwner(req.user.uid, req.params.id, place.googlePlaceId);
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

    // Don't allow changing circleId or addedBy
    const { circleId, addedBy, ...updateData } = req.body;
    updateData.updatedAt = new Date().toISOString();

    // Google-backed places: Google Places is the source of truth for venue
    // fields, so users can't edit them (they can flag bad data instead —
    // POST /places/:id/flag). Super-users and the venue's verified owner
    // (approved ownership claim) can still correct anything.
    // Manually created places (no googlePlaceId — home/work, custom spots)
    // keep editable venue fields since there is no Google record behind them.
    const isGoogleBacked = !!place.googlePlaceId;
    if (isGoogleBacked && req.user.isSuperUser !== true) {
      const lockedFields = [
        'name', 'address', 'location', 'geohash', 'category', 'subcategory',
        'website', 'phone', 'rating', 'userRatingsTotal', 'priceLevel',
        'openingHours', 'googlePlaceId'
      ];
      const touched = lockedFields.filter((field) => field in updateData);
      if (touched.length > 0
          && !(await isVerifiedVenueOwner(req.user.uid, req.params.id, place.googlePlaceId))) {
        touched.forEach((field) => delete updateData[field]);
        console.log(`🔒 Venue fields stripped from update of Google-backed place ${req.params.id}: ${touched.join(', ')}`);
      }
    }

    // Venue owners editing a save that isn't theirs may only touch venue
    // fields — tags, privacy, photos, notes belong to whoever saved it.
    if (isVenueOwnerEdit) {
      const VENUE_FIELDS = [
        'name', 'address', 'location', 'geohash', 'category', 'subcategory',
        'website', 'phone', 'rating', 'userRatingsTotal', 'priceLevel',
        'openingHours', 'updatedAt'
      ];
      Object.keys(updateData).forEach((field) => {
        if (!VENUE_FIELDS.includes(field)) delete updateData[field];
      });
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
    if (updateData.addPhotos || updateData.removePhotos) {
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
      piggyBank: photoPiggyBank
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

// @desc    Search places
// @route   GET /api/places/search
// @access  Private
exports.searchPlaces = async (req, res, next) => {
  try {
    const { q: query, category } = req.query;

    if (!query) {
      return res.status(400).json({
        success: false,
        message: 'Search query is required'
      });
    }

    let placesRef = db.collection(COLLECTIONS.PLACES);

    // Filter by category if provided
    if (category) {
      placesRef = placesRef.where('category', '==', category);
    }

    // Note: Firestore doesn't have full-text search built-in
    // For production, you'd want to use Algolia or similar
    // For now, we'll do a simple name search
    const snapshot = await placesRef
      .where('name', '>=', query)
      .where('name', '<=', query + '\uf8ff')
      .limit(50)
      .get();

    const places = serializeQuerySnapshot(snapshot).filter(place => !place.deletedAt);

    // Filter results to only include places from circles the user can access.
    // One batched getAll over the unique circle ids instead of a serial
    // per-place round trip.
    const circleIds = [...new Set(places.map(p => p.circleId).filter(Boolean))];
    const circleMap = new Map();
    if (circleIds.length > 0) {
      const circleDocs = await db.getAll(
        ...circleIds.map(id => db.collection(COLLECTIONS.CIRCLES).doc(id))
      );
      circleDocs.forEach(doc => {
        if (doc.exists) circleMap.set(doc.id, serializeDoc(doc));
      });
    }

    const accessiblePlaces = places.filter(place => {
      const circle = circleMap.get(place.circleId);
      if (!circle) return false;
      const isOwner = circle.owner === req.user.uid;
      const isSharedWith = (circle.sharedWith || []).includes(req.user.uid);
      const isPublic = circle.privacy === 'public';
      return isOwner || isSharedWith || isPublic;
    });

    // Sort results by name
    accessiblePlaces.sort((a, b) => a.name.localeCompare(b.name));

    // Attach adder info; filter privateNotes to the user who added the place
    const addedByUserMap = await buildAddedByUserMap(accessiblePlaces);
    const enrichedPlaces = accessiblePlaces.map(place => {
      const placeData = {
        ...place,
        addedByUser: addedByUserMap.get(place.addedBy) || null
      };
      if (place.addedBy !== req.user.uid) {
        delete placeData.privateNotes;
      }
      return placeData;
    });

    res.status(200).json({
      success: true,
      count: enrichedPlaces.length,
      places: enrichedPlaces
    });
  } catch (error) {
    console.error('Error searching places:', error);
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
    
    // Check permissions
    const isOwner = place.addedBy === req.user.uid;
    const circleRef = db.collection(COLLECTIONS.CIRCLES).doc(place.circleId);
    const circleDoc = await circleRef.get();
    
    if (!circleDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Associated circle not found'
      });
    }
    
    const circle = serializeDoc(circleDoc);
    const isCircleOwner = circle.owner === req.user.uid;
    const isCircleMember = circle.sharedWith && circle.sharedWith.includes(req.user.uid);
    
    if (!isOwner && !isCircleOwner && !isCircleMember) {
      return res.status(403).json({
        success: false,
        message: 'You do not have permission to update this place'
      });
    }

    // Google-backed places: address comes from Google Places — users flag bad
    // data instead of editing it (same policy as updatePlace)
    if (place.googlePlaceId && req.user.isSuperUser !== true) {
      return res.status(403).json({
        success: false,
        message: "This place's information comes from Google Places and can't be edited. If it's wrong, use \"Report incorrect info\" on the place page."
      });
    }

    // Prepare update data
    const updateData = {
      address: address.trim(),
      updatedAt: new Date().toISOString()
    };
    
    // Add location if provided
    if (location) {
      updateData.location = location;
      console.log(`📍 Updating location for place ${req.params.id} to:`, location.coordinates);

      // Keep the geohash in sync with the location (geofire expects [lat, lng])
      if (Array.isArray(location.coordinates)) {
        const [longitude, latitude] = location.coordinates;
        if (typeof longitude === 'number' && typeof latitude === 'number' &&
            longitude >= -180 && longitude <= 180 &&
            latitude >= -90 && latitude <= 90 &&
            !(longitude === -180 && latitude === -180)) {
          updateData.geohash = geofire.geohashForLocation([latitude, longitude]);
        }
      }
    }
    
    // Update the place
    await placeRef.update(updateData);

    // An address correction is a venue-level fix: update the canonical record
    // and every other saved copy of this venue
    await propagateVenueUpdates(req.params.id, place.globalPlaceId, updateData);

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
    
    // Check if target circle already has this place (by googlePlaceId or name+address)
    if (place.googlePlaceId) {
      const existingPlace = await db.collection(COLLECTIONS.PLACES)
        .where('circleId', '==', targetCircleId)
        .where('googlePlaceId', '==', place.googlePlaceId)
        .where('deletedAt', '==', null)
        .get();
        
      if (!existingPlace.empty) {
        return res.status(400).json({
          success: false,
          message: 'This place already exists in the target circle'
        });
      }
    } else {
      const existingPlace = await db.collection(COLLECTIONS.PLACES)
        .where('circleId', '==', targetCircleId)
        .where('name', '==', place.name)
        .where('address', '==', place.address)
        .where('deletedAt', '==', null)
        .get();
        
      if (!existingPlace.empty) {
        return res.status(400).json({
          success: false,
          message: 'This place already exists in the target circle'
        });
      }
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

      // Check permissions (id comparisons are normalized to tolerate
      // mixed id formats between circles, users, and connections)
      const isOwner = isSameUser(circle.owner, currentUserId);
      const isSharedWith = circle.sharedWith && circle.sharedWith.includes(currentUserId);
      const isPublic = circle.privacy === 'public';

      // For myNetwork privacy, check the pre-resolved connection set
      let isConnected = false;
      if (circle.privacy === 'myNetwork' && !isOwner) {
        isConnected = connectedUserIds.has(normalizeUserId(circle.owner));
      }

      if (!isOwner && !isSharedWith && !isPublic && !(circle.privacy === 'myNetwork' && isConnected)) {
        continue;
      }
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
        if (!isPlaceVisibleToViewer(place, currentUserId)) continue;

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
        ...overlayVenuePhotos(overlayVenueFields(place, social.venueData), social.venueData),
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
    
    // Get all user's own circles
    const ownCirclesSnapshot = await db.collection(COLLECTIONS.CIRCLES)
      .where('owner', '==', userId)
      .orderBy('updatedAt', 'desc')
      .get();
    
    // Get circles shared with the user
    const sharedCirclesSnapshot = await db.collection(COLLECTIONS.CIRCLES)
      .where('sharedWith', 'array-contains', userId)
      .orderBy('updatedAt', 'desc')
      .get();
    
    // Combine both snapshots
    const allCircles = [...ownCirclesSnapshot.docs, ...sharedCirclesSnapshot.docs];
    
    if (allCircles.length === 0) {
      return res.status(200).json({
        success: true,
        data: [],
        message: 'No circles found'
      });
    }
    
    // Collect all places from user's circles
    const placesPromises = [];
    const circleMap = new Map(); // Store circle info for each place
    
    allCircles.forEach(circleDoc => {
      const circle = serializeDoc(circleDoc);
      circleMap.set(circle.id, circle);
      
      // Get places from this circle
      const placesPromise = db.collection(COLLECTIONS.PLACES)
        .where('circleId', '==', circle.id)
        .orderBy('createdAt', 'desc')
        .get();
      
      placesPromises.push(placesPromise);
    });
    
    // Wait for all place queries
    const placesSnapshots = await Promise.all(placesPromises);
    
    // Combine and format all places
    const allPlaces = [];
    placesSnapshots.forEach(snapshot => {
      snapshot.forEach(placeDoc => {
        const place = serializeDoc(placeDoc);
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
