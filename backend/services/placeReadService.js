// backend/services/placeReadService.js
//
// Read-side helpers shared by every endpoint that returns places: venue-field
// overlay from the canonical globalPlaces record, global social data (likes,
// comment counts), addedBy user enrichment, photo normalization and per-place
// visibility. Extracted from firebasePlaceController so other controllers stop
// importing from a controller (which also forced lazy requires to dodge the
// import cycle).
const { getFirestore } = require('../config/firebase');
const { COLLECTIONS, serializeDoc } = require('../models/FirestoreModels');
const { GLOBAL_COLLECTIONS } = require('../models/GlobalPlace');
const { isSameUser } = require('./idService');
const { ensureGlobalPlaceLink } = require('./globalPlaceResolver');

const db = getFirestore();

// Helper function to normalize photos array for iOS compatibility
const normalizePhotosArray = (place) => {
  if (place.photos && Array.isArray(place.photos)) {
    place.photos = place.photos.map(photo => {
      if (typeof photo === 'string') {
        return photo; // Already a string URL
      } else if (photo && typeof photo === 'object' && photo.url) {
        return photo.url; // Extract URL from object
      }
      return photo; // Keep as-is for any other format
    });
  }
  return place;
};

// Photos belong to the VENUE, not to any one person's save of it: a photo you
// add is shared with everyone who saved that place (attributed to you, and
// deletable only by you). Reads therefore serve the venue's pool, falling back
// to the save's own array only when the place isn't linked to a venue yet.
const overlayVenuePhotos = (place, venueData) => {
  const venuePhotos = (venueData && venueData.photos) || [];
  if (venuePhotos.length === 0) return place;

  // Union, venue order first, de-duped by URL — a save may still hold a photo
  // the pooling backfill hasn't reached.
  const urlOf = (p) => (typeof p === 'string' ? p : p && p.url) || null;
  const seen = new Set();
  const merged = [];
  [...venuePhotos, ...(place.photos || [])].forEach((photo) => {
    const url = urlOf(photo);
    if (!url || seen.has(url)) return;
    seen.add(url);
    merged.push(photo);
  });
  place.photos = merged;
  return place;
};

// Venue data owned by the canonical globalPlaces record. Top-level fields map
// 1:1; rating/hours/contact fields live nested under googleData on the record.
const VENUE_TOP_FIELDS = ['name', 'address', 'location', 'category', 'subcategory', 'description'];
// delivery/dineIn/reservable/takeout/curbsidePickup are Google Atmosphere
// booleans (may be null = unknown) powering partner-action chip eligibility;
// they ride Details calls that already bill Atmosphere for rating/price_level
const VENUE_GOOGLE_FIELDS = ['rating', 'userRatingsTotal', 'priceLevel', 'openingHours', 'website', 'phone',
                             'delivery', 'dineIn', 'reservable', 'takeout', 'curbsidePickup'];

// Merge canonical venue fields over a save doc's (possibly stale) copies.
// Per-user fields (notes, tags, privacy, photos, ...) are untouched.
const overlayVenueFields = (place, globalData) => {
  const merged = { ...place };
  VENUE_TOP_FIELDS.forEach(field => {
    const value = globalData[field];
    if (value !== undefined && value !== null && value !== '') {
      merged[field] = value;
    }
  });
  const googleData = globalData.googleData || {};
  VENUE_GOOGLE_FIELDS.forEach(field => {
    const value = googleData[field];
    if (value !== undefined && value !== null && value !== '') {
      merged[field] = value;
    }
  });
  return merged;
};

// Social data (likes, comment counts) lives on the canonical globalPlaces
// record shared by every saved copy of a venue. Falls back to the doc's own
// (legacy) fields only if the place can't be linked.
const getGlobalSocial = async (placeDoc) => {
  const globalPlaceId = placeDoc.data().globalPlaceId || await ensureGlobalPlaceLink(placeDoc);
  if (!globalPlaceId) {
    return {
      globalPlaceId: null,
      likes: placeDoc.data().likes || [],
      commentsCount: 0,
      venueData: null
    };
  }
  const globalDoc = await db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).doc(globalPlaceId).get();
  const data = globalDoc.exists ? globalDoc.data() : {};
  return {
    globalPlaceId,
    likes: data.likes || [],
    commentsCount: data.commentsCount || 0,
    venueData: globalDoc.exists ? data : null
  };
};

// Batched variant for list endpoints: one getAll over the unique canonical
// records referenced by a page of places. Returns Map<globalPlaceId, social>.
const fetchGlobalSocialMap = async (places) => {
  const ids = [...new Set(places.map(place => place.globalPlaceId).filter(Boolean))];
  const map = new Map();
  if (ids.length === 0) return map;
  const docs = await db.getAll(...ids.map(id => db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).doc(id)));
  docs.forEach(doc => {
    if (doc.exists) {
      const data = doc.data();
      map.set(doc.id, {
        likes: data.likes || [],
        commentsCount: data.commentsCount || 0,
        venueData: data
      });
    }
  });
  return map;
};


// Batch-fetch the users behind places' addedBy ids so responses can carry
// addedByUser (iOS falls back to "Added by a connection" without it). Keyed by
// both the user doc id and the original id format from the place doc.
const buildAddedByUserMap = async (places) => {
  const userIds = [...new Set(places.map(place => place.addedBy).filter(Boolean))];
  const userMap = new Map();
  if (userIds.length === 0) return userMap;

  const userDocs = await Promise.all(userIds.map(userId => {
    // Handle complex ID format if needed (e.g. "provider.uid.suffix")
    let actualUserId = userId;
    if (userId.includes('.')) {
      const parts = userId.split('.');
      if (parts.length >= 2) {
        actualUserId = parts[1];
      }
    }
    return db.collection(COLLECTIONS.USERS).doc(actualUserId).get();
  }));

  userDocs.forEach((doc, index) => {
    if (!doc.exists) return;
    const userData = serializeDoc(doc);
    const userInfo = {
      id: userData.id,
      displayName: userData.displayName || 'Unknown User',
      profilePicture: userData.profilePicture
    };
    userMap.set(userData.id, userInfo);
    userMap.set(userIds[index], userInfo);
  });
  return userMap;
};

// A place's OWN privacy can only further RESTRICT visibility beyond its
// circle — callers apply this AFTER the circle-level access check. The only
// per-place override the app sets is `private` = owner-only; every other value
// (the `followCircle` default, and legacy `public`/`myNetwork`) inherits the
// circle's visibility. Without this, a place marked Private inside a public or
// myNetwork circle was still served to everyone who could see the circle.
const isPlaceVisibleToViewer = (place, viewerId) =>
  isSameUser(place.addedBy, viewerId) || place.privacy !== 'private';

module.exports = {
  normalizePhotosArray,
  overlayVenuePhotos,
  VENUE_TOP_FIELDS,
  VENUE_GOOGLE_FIELDS,
  overlayVenueFields,
  getGlobalSocial,
  fetchGlobalSocialMap,
  buildAddedByUserMap,
  isPlaceVisibleToViewer
};
