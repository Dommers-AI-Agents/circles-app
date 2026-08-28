// backend/services/globalPlaceResolver.js
// Shared place-id resolution and legacy->global place creation, used by the
// media endpoints (globalPlaceController) and the photo backfill script.

const admin = require('firebase-admin');
const { getFirestore } = require('../config/firebase');
const {
  GLOBAL_COLLECTIONS,
  createGlobalPlace,
  createAttributedPhoto,
  createAttributedVideo,
  calculateDataCompleteness,
  calculateQualityScore,
  generatePlaceKey
} = require('../models/GlobalPlace');
const { deriveCategory } = require('./placeCategoryDerivation');
const { deriveLocation } = require('./placeLocationDerivation');

const db = getFirestore();

// Resolve a placeId (global doc id OR legacy places doc id OR a raw Google
// place id) to its globalPlaces doc.
// Tiers: direct id -> legacyPlaceIds mapping -> deduplicationKey -> googlePlaceId.
// Tier 3/4 hits backfill legacyPlaceIds so future lookups hit tier 2.
// Returns { globalPlaceDoc, legacyPlaceDoc } — either may be null.
async function resolveGlobalPlace(placeId) {
  const directDoc = await db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).doc(placeId).get();
  if (directDoc.exists) {
    return { globalPlaceDoc: directDoc, legacyPlaceDoc: null };
  }

  const legacyPlaceDoc = await db.collection('places').doc(placeId).get();
  if (!legacyPlaceDoc.exists) {
    // Not a doc id at all — callers like the rewards venue link only hold a
    // Google place id. Pure lookup: no legacy doc exists, so no backfill.
    const googleQuery = await db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES)
      .where('googlePlaceId', '==', placeId)
      .limit(1)
      .get();
    if (!googleQuery.empty) {
      return { globalPlaceDoc: googleQuery.docs[0], legacyPlaceDoc: null };
    }
    return { globalPlaceDoc: null, legacyPlaceDoc: null };
  }
  const legacyPlace = legacyPlaceDoc.data();

  // Tier 2: GlobalPlace that already maps this legacy id
  const legacyIdQuery = await db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES)
    .where('legacyPlaceIds', 'array-contains', placeId)
    .limit(1)
    .get();
  if (!legacyIdQuery.empty) {
    return { globalPlaceDoc: legacyIdQuery.docs[0], legacyPlaceDoc };
  }

  const backfill = async (doc) => {
    await doc.ref.update({
      legacyPlaceIds: admin.firestore.FieldValue.arrayUnion(placeId),
      updatedAt: new Date().toISOString()
    });
  };

  // Tier 3: deduplication key (generatePlaceKey throws on missing name/address)
  if (legacyPlace.name && legacyPlace.address) {
    try {
      const deduplicationKey = generatePlaceKey(legacyPlace);
      const keyQuery = await db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES)
        .where('deduplicationKey', '==', deduplicationKey)
        .limit(1)
        .get();
      if (!keyQuery.empty) {
        await backfill(keyQuery.docs[0]);
        return { globalPlaceDoc: keyQuery.docs[0], legacyPlaceDoc };
      }
    } catch (keyError) {
      console.warn(`⚠️ [resolveGlobalPlace] deduplication key lookup failed for ${placeId}:`, keyError.message);
    }
  }

  // Tier 4: Google place id (covers older global docs created without a dedup key)
  if (legacyPlace.googlePlaceId) {
    const googleQuery = await db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES)
      .where('googlePlaceId', '==', legacyPlace.googlePlaceId)
      .limit(1)
      .get();
    if (!googleQuery.empty) {
      await backfill(googleQuery.docs[0]);
      return { globalPlaceDoc: googleQuery.docs[0], legacyPlaceDoc };
    }
  }

  return { globalPlaceDoc: null, legacyPlaceDoc };
}

// Create a globalPlaces doc from a legacy place so media uploads always have a home.
// Mirrors placeTransitionService's conversion but WITHOUT its circle/relation side
// effects. Existing photos/videos are attributed to the place's owner, not the uploader.
async function createGlobalPlaceFromLegacy(legacyPlaceDoc) {
  const legacyId = legacyPlaceDoc.id;
  const legacyPlace = legacyPlaceDoc.data();

  let ownerName = null;
  if (legacyPlace.addedBy) {
    try {
      const ownerDoc = await db.collection('users').doc(legacyPlace.addedBy).get();
      if (ownerDoc.exists) ownerName = ownerDoc.data().displayName || null;
    } catch (e) { /* attribution is best-effort */ }
  }

  // Photos inherited from a legacy place doc are usually Google Places photos
  // re-hosted on Firebase Storage — we can't prove a person took them, so they
  // get NO user attribution (iOS hides the "Photo by" chip when there's no name)
  const attributedPhotos = (Array.isArray(legacyPlace.photos) ? legacyPlace.photos : [])
    .map(photo => {
      const url = typeof photo === 'string' ? photo : photo?.url;
      if (!url) return null;
      return createAttributedPhoto({
        url,
        uploadedBy: null,
        uploadedByName: null,
        source: url.includes('googleusercontent.com') ? 'google_places' : 'legacy_import'
      });
    })
    .filter(Boolean);

  const attributedVideos = (Array.isArray(legacyPlace.videos) ? legacyPlace.videos : [])
    .map(video => {
      const videoUrl = typeof video === 'string' ? video : video?.videoUrl;
      if (!videoUrl) return null;
      return createAttributedVideo({
        videoUrl,
        uploadedBy: legacyPlace.addedBy || null,
        uploadedByName: ownerName,
        title: (typeof video === 'object' && video?.title) || '',
        description: (typeof video === 'object' && video?.description) || ''
      });
    })
    .filter(Boolean);

  // createGlobalPlace copies deduplicationKey verbatim — compute it here (guarded)
  let deduplicationKey = null;
  if (legacyPlace.name && legacyPlace.address) {
    try { deduplicationKey = generatePlaceKey(legacyPlace); } catch (e) { /* malformed doc */ }
  }

  // Derive a real category when the save arrived as 'other'/blank (the common
  // case for check-in/moment saves and thin imports). Non-destructive: a
  // category the client already resolved is kept and marked source 'client'.
  const incomingCategory = legacyPlace.category || 'other';
  let category = incomingCategory;
  let categoryMeta = { categorySource: incomingCategory === 'other' ? null : 'client' };
  if (incomingCategory === 'other') {
    const derived = deriveCategory({
      googlePrimaryType: legacyPlace.googlePrimaryType,
      googleTypes: legacyPlace.googleTypes,
      applePoiCategory: legacyPlace.applePoiCategory,
      name: legacyPlace.name,
      description: legacyPlace.description,
      address: legacyPlace.address
    });
    if (derived.category !== 'other') {
      category = derived.category;
      categoryMeta = {
        categorySource: derived.source,
        categoryConfidence: derived.confidence,
        categoryBefore: 'other',
        categoryClassifiedAt: new Date().toISOString()
      };
    } else {
      // Nothing could classify it. Flag it inline (no extra write) for the
      // nightly LLM sweep — scripts/sweep-category-review.js.
      categoryMeta.needsCategoryReview = true;
    }
  }

  // Derive the State/City lens from the address string (free, no geocoding).
  const loc = deriveLocation({
    address: legacyPlace.address,
    location: legacyPlace.location,
    neighborhood: legacyPlace.neighborhood
  });
  const locationMeta = loc.placed
    ? {
        state: loc.state, stateCode: loc.stateCode, city: loc.city,
        cityKey: loc.cityKey, neighborhood: loc.neighborhood,
        country: loc.country, countryCode: loc.countryCode,
        locationSource: loc.source, locationDerivedAt: new Date().toISOString()
      }
    : {
        neighborhood: loc.neighborhood || null,
        // Non-US places still carry their country ("…, Canada") for the
        // country-level region chips
        country: loc.country || null, countryCode: loc.countryCode || null
      };

  const globalPlaceData = createGlobalPlace({
    ...legacyPlace,
    name: legacyPlace.name || 'Unknown Place',
    address: legacyPlace.address || '',
    location: legacyPlace.location || null,
    category,
    ...categoryMeta,
    ...locationMeta,
    deduplicationKey,
    legacyPlaceIds: [legacyId],
    photos: attributedPhotos,
    videos: attributedVideos,
    publicReviews: []
  });
  globalPlaceData.userContributions = {
    totalPhotos: attributedPhotos.length,
    totalVideos: attributedVideos.length,
    totalReviews: 0,
    // Only videos are genuinely user-created; inherited photos are unattributed
    contributors: (attributedVideos.length > 0 && legacyPlace.addedBy) ? [legacyPlace.addedBy] : []
  };
  globalPlaceData.dataCompleteness = calculateDataCompleteness(globalPlaceData);
  globalPlaceData.qualityScore = calculateQualityScore(globalPlaceData);

  const docRef = await db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).add(globalPlaceData);
  console.log(`🆕 [GlobalPlace] Auto-created globalPlace ${docRef.id} from legacy place ${legacyId}`);
  return { resolvedId: docRef.id, resolvedData: globalPlaceData };
}

// Create a canonical venue record straight from business details — no legacy
// save doc required. Used by the store-owner "add & claim your business" flow,
// where the owner's store may never have been saved by anyone. Callers should
// try findCanonicalByNameAndLocation first; this always creates.
async function createGlobalPlaceFromDetails({ name, address, location, category, phone, website, applePoiCategory }) {
  const incomingCategory = category || 'other';
  let resolvedCategory = incomingCategory;
  let categoryMeta = { categorySource: incomingCategory === 'other' ? null : 'client' };
  if (incomingCategory === 'other') {
    const derived = deriveCategory({ applePoiCategory, name, address });
    if (derived.category !== 'other') {
      resolvedCategory = derived.category;
      categoryMeta = {
        categorySource: derived.source,
        categoryConfidence: derived.confidence,
        categoryBefore: 'other',
        categoryClassifiedAt: new Date().toISOString()
      };
    } else {
      categoryMeta.needsCategoryReview = true;
    }
  }

  const loc = deriveLocation({ address, location });
  const locationMeta = loc.placed
    ? {
        state: loc.state, stateCode: loc.stateCode, city: loc.city,
        cityKey: loc.cityKey, neighborhood: loc.neighborhood,
        country: loc.country, countryCode: loc.countryCode,
        locationSource: loc.source, locationDerivedAt: new Date().toISOString()
      }
    : {
        neighborhood: loc.neighborhood || null,
        country: loc.country || null, countryCode: loc.countryCode || null
      };

  let deduplicationKey = null;
  if (name && address) {
    try { deduplicationKey = generatePlaceKey({ name, address }); } catch (e) { /* fine */ }
  }

  const globalPlaceData = createGlobalPlace({
    name,
    address: address || '',
    location: location || null,
    phone: phone || null,
    website: website || null,
    category: resolvedCategory,
    ...categoryMeta,
    ...locationMeta,
    deduplicationKey,
    legacyPlaceIds: [],
    photos: [],
    videos: [],
    publicReviews: []
  });
  globalPlaceData.dataCompleteness = calculateDataCompleteness(globalPlaceData);
  globalPlaceData.qualityScore = calculateQualityScore(globalPlaceData);

  const docRef = await db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).add(globalPlaceData);
  console.log(`🆕 [GlobalPlace] Created globalPlace ${docRef.id} from business details ("${name}")`);
  return { resolvedId: docRef.id, resolvedData: globalPlaceData };
}

// Venue-level fields owned by the canonical globalPlaces record. Save docs
// keep only the denormalized query cache (name/address/location/geohash/
// category) plus per-user data; these get stripped once the link exists.
const STRIPPED_VENUE_FIELDS = [
  'likes', 'likesCount', 'website', 'phone', 'rating', 'userRatingsTotal',
  'openingHours', 'priceLevel', 'subcategory',
  'delivery', 'dineIn', 'reservable', 'takeout', 'curbsidePickup'
];

// Denormalized query-cache fields mirrored from the canonical venue onto each
// save doc (used by geo/list/category/location browse queries).
const CACHED_VENUE_FIELDS = [
  'category', 'state', 'stateCode', 'city', 'cityKey', 'neighborhood',
  'country', 'countryCode'
];

// Resolve-or-create the canonical globalPlaces doc for a legacy place doc and
// stamp globalPlaceId on it. Best-effort: returns the global place id, or null
// on failure — linking must never block a save (the backfill script catches
// stragglers).
// ---- Name + proximity matcher ----------------------------------------------
// A manually-added or imported copy of a venue that already exists
// canonically carries no googlePlaceId, and its deduplicationKey
// ('manual:<name>:<address>') can never match a canonical record keyed
// 'google:<placeId>' — so every such save minted a DUPLICATE venue (found via
// a Mapstr import, 2026-08-12). Same normalized name within 150m is the same
// real-world venue; both criteria are deliberately conservative so distinct
// same-brand branches (usually far apart) never merge.
const NAME_MATCH_RADIUS_METERS = 150;

const normalizeVenueName = (name) => (name || '')
  .toLowerCase()
  .replace(/^the\s+/, '')
  .replace(/[^a-z0-9\s]/g, '')
  .replace(/\s+/g, ' ')
  .trim();

const haversineMeters = (lat1, lng1, lat2, lng2) => {
  const R = 6371000;
  const toRad = (d) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a = Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
};

async function findCanonicalByNameAndLocation(name, location, excludeId = null) {
  const normalized = normalizeVenueName(name);
  const coords = location && location.coordinates;
  if (!normalized || !Array.isArray(coords) || coords.length !== 2) return null;
  const [lng, lat] = coords;

  // Token must match buildSearchTokens' splitting (non-alphanumerics are
  // separators): "Nickyo's" indexes as "nickyo", never "nickyos"
  const tokens = (name || '').toLowerCase().split(/[^a-z0-9]+/).filter((t) => t.length >= 3);
  if (tokens.length === 0) return null;
  const longestToken = tokens.sort((a, b) => b.length - a.length)[0].slice(0, 20);

  const snapshot = await db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES)
    .where('searchTokens', 'array-contains', longestToken)
    .limit(25)
    .get();

  let best = null;
  let bestDistance = Infinity;
  snapshot.forEach((doc) => {
    if (excludeId && doc.id === excludeId) return;
    const data = doc.data();
    if (data.deletedAt) return;
    const candidateName = normalizeVenueName(data.name);
    // Exact normalized equality only. Containment matching linked distinct
    // neighbors — "Chelsea Market Baskets" is 150m from "Chelsea Market" and
    // is not the same venue (found during the 2026-08-12 dedup migration).
    if (candidateName !== normalized) return;
    const candidateCoords = data.location && data.location.coordinates;
    if (!Array.isArray(candidateCoords) || candidateCoords.length !== 2) return;
    const distance = haversineMeters(lat, lng, candidateCoords[1], candidateCoords[0]);
    if (distance <= NAME_MATCH_RADIUS_METERS && distance < bestDistance) {
      best = doc;
      bestDistance = distance;
    }
  });
  return best;
}

async function ensureGlobalPlaceLink(placeDoc) {
  try {
    const existing = placeDoc.data().globalPlaceId;
    if (existing) return existing;

    const { globalPlaceDoc } = await resolveGlobalPlace(placeDoc.id);
    let globalPlaceId = globalPlaceDoc ? globalPlaceDoc.id : null;
    // The canonical venue's data, whether we just created it or matched an
    // existing one. Both paths must stamp the save's query cache: a venue
    // someone else already saved has a correct category and location, and
    // dropping them here left the save invisible to every query that filters on
    // the cached fields (city browse, circle summaries, the map's region chips).
    let resolvedData = globalPlaceDoc ? globalPlaceDoc.data() : null;

    // Before minting a new canonical venue, check whether one already exists
    // under a different key namespace (same name, within 150m)
    if (!globalPlaceId) {
      const matched = await findCanonicalByNameAndLocation(
        placeDoc.data().name, placeDoc.data().location);
      if (matched) {
        await matched.ref.update({
          legacyPlaceIds: admin.firestore.FieldValue.arrayUnion(placeDoc.id),
          updatedAt: new Date().toISOString()
        });
        globalPlaceId = matched.id;
        resolvedData = matched.data();
        console.log(`🔗 [GlobalPlace] Matched "${placeDoc.data().name}" to existing venue ${matched.id} by name+proximity`);
      }
    }

    if (!globalPlaceId) {
      const created = await createGlobalPlaceFromLegacy(placeDoc);
      globalPlaceId = created.resolvedId;
      resolvedData = created.resolvedData;
    }

    // Stamp the link and drop the now-canonical venue fields in one write —
    // reads overlay them from the globalPlaces record
    const updates = { globalPlaceId };
    STRIPPED_VENUE_FIELDS.forEach(field => {
      if (placeDoc.data()[field] !== undefined) {
        updates[field] = admin.firestore.FieldValue.delete();
      }
    });
    // Keep the save's denormalized query cache (category + the location lens) in
    // sync with the canonical venue, so geo/list/browse queries are correct.
    if (resolvedData) {
      CACHED_VENUE_FIELDS.forEach(field => {
        const value = resolvedData[field];
        if (value !== undefined && value !== null && value !== placeDoc.data()[field]) {
          updates[field] = value;
        }
      });
    }
    await placeDoc.ref.update(updates);

    // An EXISTING venue that nothing has managed to categorize yet: flag it for
    // the nightly sweep rather than calling a model here — a save must never
    // wait on (or fail because of) an API call. Newly created venues are
    // flagged inline above, so this is a no-op for them, and it's a no-op again
    // for every later saver once the flag is set.
    await flagForCategoryReview(globalPlaceId, resolvedData);

    return globalPlaceId;
  } catch (error) {
    console.error(`⚠️ [GlobalPlace] Failed to link place ${placeDoc.id} to a global place:`, error.message);
    return null;
  }
}

// Mark a venue as needing the LLM category tier. Best-effort and idempotent:
// already-classified venues are never re-flagged (the sweep also re-checks), so
// a venue costs at most one classification in its lifetime.
async function flagForCategoryReview(globalPlaceId, venueData) {
  if (!globalPlaceId || !venueData) return;
  if ((venueData.category || 'other') !== 'other') return;
  if (venueData.categoryClassifiedAt) return;
  if (venueData.needsCategoryReview) return;

  try {
    await db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).doc(globalPlaceId).update({
      needsCategoryReview: true
    });
  } catch (e) {
    console.warn(`⚠️ [GlobalPlace] Could not flag ${globalPlaceId} for category review:`, e.message);
  }
}

module.exports = {
  resolveGlobalPlace,
  createGlobalPlaceFromLegacy,
  createGlobalPlaceFromDetails,
  ensureGlobalPlaceLink,
  findCanonicalByNameAndLocation
};
