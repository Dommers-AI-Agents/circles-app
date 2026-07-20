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

  const globalPlaceData = createGlobalPlace({
    ...legacyPlace,
    name: legacyPlace.name || 'Unknown Place',
    address: legacyPlace.address || '',
    location: legacyPlace.location || null,
    category: legacyPlace.category || 'other',
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

// Venue-level fields owned by the canonical globalPlaces record. Save docs
// keep only the denormalized query cache (name/address/location/geohash/
// category) plus per-user data; these get stripped once the link exists.
const STRIPPED_VENUE_FIELDS = [
  'likes', 'likesCount', 'website', 'phone', 'rating', 'userRatingsTotal',
  'openingHours', 'priceLevel', 'subcategory'
];

// Resolve-or-create the canonical globalPlaces doc for a legacy place doc and
// stamp globalPlaceId on it. Best-effort: returns the global place id, or null
// on failure — linking must never block a save (the backfill script catches
// stragglers).
async function ensureGlobalPlaceLink(placeDoc) {
  try {
    const existing = placeDoc.data().globalPlaceId;
    if (existing) return existing;

    const { globalPlaceDoc } = await resolveGlobalPlace(placeDoc.id);
    let globalPlaceId = globalPlaceDoc ? globalPlaceDoc.id : null;

    if (!globalPlaceId) {
      const created = await createGlobalPlaceFromLegacy(placeDoc);
      globalPlaceId = created.resolvedId;
    }

    // Stamp the link and drop the now-canonical venue fields in one write —
    // reads overlay them from the globalPlaces record
    const updates = { globalPlaceId };
    STRIPPED_VENUE_FIELDS.forEach(field => {
      if (placeDoc.data()[field] !== undefined) {
        updates[field] = admin.firestore.FieldValue.delete();
      }
    });
    await placeDoc.ref.update(updates);
    return globalPlaceId;
  } catch (error) {
    console.error(`⚠️ [GlobalPlace] Failed to link place ${placeDoc.id} to a global place:`, error.message);
    return null;
  }
}

module.exports = { resolveGlobalPlace, createGlobalPlaceFromLegacy, ensureGlobalPlaceLink };
