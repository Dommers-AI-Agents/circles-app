// Import service: turns normalized payloads from external platforms
// (Mapstr, Google Takeout, Swarm) into circles + places.
//
// Place creation deliberately mirrors the legacy path in
// firebasePlaceController.createPlace (places collection + circle places[] /
// placesCount) — that is the source of truth for how the app populates
// circles. If createPlace ever starts writing globalPlaces, mirror it here.

const { Client } = require('@googlemaps/google-maps-services-js');
const { getFirestore } = require('../config/firebase');
const {
  COLLECTIONS,
  createPlace,
  createCircle,
  validatePlace,
  validateCircle
} = require('../models/FirestoreModels');
const placeCache = require('./placeCache');
const requestDeduplicator = require('./requestDeduplicator');
const { categoryFromGoogleTypes, categoryFromMapstrTags } = require('./importCategoryMapping');

const db = getFirestore();
const googleMapsClient = new Client({});
const googleApiKey = () => process.env.GOOGLE_MAPS_API_KEY || process.env.PLACES_API_KEY;

const VALID_SOURCES = ['mapstr', 'google_maps', 'swarm'];
const MAX_PLACES_PER_REQUEST = 300;
const RESOLVER_CONCURRENCY = 3;

// The Geocoding API is not enabled on this Google Cloud project (see
// placeDiscoveryService) — Find Place from Text is the only resolver.
// Set IMPORT_USE_FIND_PLACE=false to disable resolution entirely; rows
// without coordinates then surface as 'unresolved' in the review screen.
const useFindPlace = () => process.env.IMPORT_USE_FIND_PLACE !== 'false';

const normalizeText = (value) =>
  (value || '').toLowerCase().replace(/[^\w\s]/g, '').replace(/\s+/g, ' ').trim();

const nameAddressKey = (name, address) =>
  `${normalizeText(name)}|${normalizeText(address)}`;

const isValidCoordinate = (lat, lng) =>
  typeof lat === 'number' && typeof lng === 'number' &&
  lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180 &&
  !(lat === 0 && lng === 0);

// Simple promise pool: run tasks with bounded concurrency, preserve order.
async function mapWithConcurrency(items, limit, task) {
  const results = new Array(items.length);
  let next = 0;
  const workers = Array.from({ length: Math.min(limit, items.length) }, async () => {
    while (next < items.length) {
      const index = next++;
      results[index] = await task(items[index], index);
    }
  });
  await Promise.all(workers);
  return results;
}

/**
 * Load everything already in the user's account that import dedup needs,
 * as in-memory maps. One equality query instead of chunked `in` queries —
 * no composite indexes required, and a typical account is small enough.
 */
async function loadUserPlaceIndex(userId) {
  const snapshot = await db.collection(COLLECTIONS.PLACES)
    .where('addedBy', '==', userId)
    .get();

  const bySourceExternalId = new Map();
  const byGooglePlaceId = new Map();
  const byNameAddress = new Map(); // key → [{placeId, circleId, name}]

  snapshot.forEach(doc => {
    const place = doc.data();
    if (place.deletedAt) return;
    const entry = { placeId: doc.id, circleId: place.circleId, name: place.name };
    if (place.sourceExternalId) bySourceExternalId.set(place.sourceExternalId, entry);
    if (place.googlePlaceId) byGooglePlaceId.set(place.googlePlaceId, entry);
    const key = nameAddressKey(place.name, place.address);
    if (!byNameAddress.has(key)) byNameAddress.set(key, []);
    byNameAddress.get(key).push(entry);
  });

  return { bySourceExternalId, byGooglePlaceId, byNameAddress };
}

async function loadOwnedCircles(userId) {
  const snapshot = await db.collection(COLLECTIONS.CIRCLES)
    .where('owner', '==', userId)
    .get();
  const circles = [];
  snapshot.forEach(doc => {
    const data = doc.data();
    circles.push({ id: doc.id, name: data.name, placesCount: data.placesCount || 0 });
  });
  return circles;
}

/**
 * Resolve a Google Takeout row that has no coordinates via Places
 * Find Place from Text. Returns { lat, lng, googlePlaceId, types, formattedAddress }
 * or null. Cached for a year (import retries, shared lists) and deduplicated
 * against concurrent identical requests.
 */
async function resolveViaFindPlace(name, address) {
  const key = googleApiKey();
  if (!key || !useFindPlace()) return null;

  const input = address ? `${name}, ${address}` : name;
  const cacheKey = normalizeText(input);

  const cached = placeCache.get('findplace', cacheKey);
  if (cached) return cached.notFound ? null : cached;

  try {
    const result = await requestDeduplicator.execute(`findplace:${cacheKey}`, async () => {
      const response = await googleMapsClient.findPlaceFromText({
        params: {
          input,
          inputtype: 'textquery',
          fields: ['place_id', 'geometry', 'types', 'formatted_address'],
          key
        }
      });
      const candidate = response.data.candidates && response.data.candidates[0];
      if (!candidate || !candidate.geometry || !candidate.geometry.location) {
        return null;
      }
      return {
        lat: candidate.geometry.location.lat,
        lng: candidate.geometry.location.lng,
        googlePlaceId: candidate.place_id || null,
        types: candidate.types || [],
        formattedAddress: candidate.formatted_address || null
      };
    });

    // Cache misses too — a venue Google can't find today won't appear tomorrow,
    // and retried imports shouldn't re-bill for the same failures.
    placeCache.set('findplace', cacheKey, result || { notFound: true }, 365 * 24 * 60 * 60 * 1000);
    return result;
  } catch (error) {
    console.error(`❌ Import: Find Place failed for "${input}":`, error.message);
    return null;
  }
}

function validatePayloadShape(payload) {
  if (!payload || !VALID_SOURCES.includes(payload.source)) {
    return `source must be one of: ${VALID_SOURCES.join(', ')}`;
  }
  if (!Array.isArray(payload.lists) || payload.lists.length === 0) {
    return 'lists must be a non-empty array';
  }
  let total = 0;
  for (const list of payload.lists) {
    const listName = list && (list.name || list.circleName);
    if (!list || typeof listName !== 'string' || !listName.trim()) {
      return 'every list needs a name';
    }
    if (!Array.isArray(list.places)) {
      return 'every list needs a places array';
    }
    total += list.places.length;
    for (const place of list.places) {
      if (!place || typeof place.name !== 'string' || !place.name.trim()) {
        return 'every place needs a name';
      }
    }
  }
  if (total === 0) return 'no places to import';
  if (total > MAX_PLACES_PER_REQUEST) {
    return `too many places in one request (max ${MAX_PLACES_PER_REQUEST}); split into multiple calls`;
  }
  return null;
}

/**
 * Prepare: resolve coordinates + categories, mark duplicates, and suggest
 * merges into existing circles. Read-only.
 */
async function prepareImport(userId, payload) {
  const shapeError = validatePayloadShape(payload);
  if (shapeError) return { error: shapeError };

  const [index, ownedCircles] = await Promise.all([
    loadUserPlaceIndex(userId),
    loadOwnedCircles(userId)
  ]);
  const circlesByName = new Map(ownedCircles.map(c => [normalizeText(c.name), c]));

  const counts = { new: 0, duplicate: 0, unresolved: 0 };
  const lists = [];

  for (const list of payload.lists) {
    const existingCircle = circlesByName.get(normalizeText(list.name)) || null;
    // Track name+address duplicates within this request too, so two identical
    // rows in one file don't both come back 'new'.
    const seenInList = new Set();

    const places = await mapWithConcurrency(list.places, RESOLVER_CONCURRENCY, async (place) => {
      const result = {
        name: place.name.trim(),
        address: place.address || null,
        lat: typeof place.lat === 'number' ? place.lat : null,
        lng: typeof place.lng === 'number' ? place.lng : null,
        category: place.category || null,
        notes: place.notes || null,
        tags: Array.isArray(place.tags) ? place.tags : [],
        sourceExternalId: place.sourceExternalId || null,
        sourceUrl: place.sourceUrl || null,
        googlePlaceId: null,
        status: 'new',
        duplicateOf: null
      };

      // Resolve coordinates (Google Takeout rows arrive without them)
      if (!isValidCoordinate(result.lat, result.lng)) {
        const resolved = await resolveViaFindPlace(result.name, result.address);
        if (resolved) {
          result.lat = resolved.lat;
          result.lng = resolved.lng;
          result.googlePlaceId = resolved.googlePlaceId;
          if (!result.address && resolved.formattedAddress) {
            result.address = resolved.formattedAddress;
          }
          if (!result.category) {
            result.category = categoryFromGoogleTypes(resolved.types);
          }
        }
      }

      if (!isValidCoordinate(result.lat, result.lng)) {
        result.status = 'unresolved';
        return result;
      }

      if (!result.category && payload.source === 'mapstr' && result.tags.length > 0) {
        result.category = categoryFromMapstrTags(result.tags);
      }
      if (!result.category) result.category = 'other';
      if (!result.address) {
        // validatePlace requires an address; fall back to coordinates text
        result.address = `${result.lat.toFixed(5)}, ${result.lng.toFixed(5)}`;
      }

      // Duplicate detection: stable external id → google place id → name+address
      const dupKey = nameAddressKey(result.name, result.address);
      const existing =
        (result.sourceExternalId && index.bySourceExternalId.get(result.sourceExternalId)) ||
        (result.googlePlaceId && index.byGooglePlaceId.get(result.googlePlaceId)) ||
        (index.byNameAddress.get(dupKey) || [])[0] ||
        (seenInList.has(dupKey) ? { placeId: null, circleId: null, name: result.name } : null);

      if (existing) {
        result.status = 'duplicate';
        result.duplicateOf = existing.placeId
          ? { placeId: existing.placeId, circleId: existing.circleId }
          : { placeId: null, circleId: null };
      }
      seenInList.add(dupKey);
      return result;
    });

    for (const place of places) counts[place.status]++;

    lists.push({
      proposedCircleName: list.name.trim(),
      existingCircleId: existingCircle ? existingCircle.id : null,
      places
    });
  }

  return { preview: { lists, counts } };
}

/**
 * Execute: create circles and places in Firestore batches.
 * Idempotent — re-runs skip anything whose sourceExternalId (or
 * googlePlaceId / name+address) already exists.
 */
async function executeImport(userId, payload) {
  const shapeError = validatePayloadShape(payload);
  if (shapeError) return { error: shapeError };

  const subscriptionLimitService = require('./subscriptionLimitService');
  const index = await loadUserPlaceIndex(userId);
  const results = [];

  for (const list of payload.lists) {
    const circleName = (list.circleName || list.name || '').trim();
    const listResult = {
      circleId: null,
      circleName,
      created: 0,
      skippedDuplicates: 0,
      failed: []
    };

    // Resolve target circle: merge into an owned circle, or create one
    let circleRef = null;
    if (list.existingCircleId) {
      const circleDoc = await db.collection(COLLECTIONS.CIRCLES).doc(list.existingCircleId).get();
      if (!circleDoc.exists || circleDoc.data().owner !== userId) {
        listResult.failed.push({ name: circleName, reason: 'Target circle not found or not owned by you' });
        results.push(listResult);
        continue;
      }
      circleRef = circleDoc.ref;
      listResult.circleId = circleDoc.id;
      listResult.circleName = circleDoc.data().name;
    } else {
      const limitCheck = await subscriptionLimitService.canCreateCircle(userId);
      if (!limitCheck.canCreate) {
        listResult.failed.push({ name: circleName, reason: limitCheck.error });
        results.push(listResult);
        continue;
      }
      const circleData = createCircle({ name: circleName, privacy: 'private' }, userId);
      const circleErrors = validateCircle(circleData);
      if (circleErrors.length > 0) {
        listResult.failed.push({ name: circleName, reason: circleErrors.join(', ') });
        results.push(listResult);
        continue;
      }
      circleRef = await db.collection(COLLECTIONS.CIRCLES).add(circleData);
      listResult.circleId = circleRef.id;
    }

    // Create places in one Firestore batch per list (≤300 places by cap,
    // well under the 500-op batch limit including the circle update).
    // No per-place activity/notification fan-out — an import of hundreds of
    // places must not spam the network feed.
    const batch = db.batch();
    const newPlaceIds = [];

    for (const place of list.places || []) {
      const sourceId = place.sourceExternalId || null;
      const dupKey = nameAddressKey(place.name, place.address);
      const alreadyExists =
        (sourceId && index.bySourceExternalId.has(sourceId)) ||
        (place.googlePlaceId && index.byGooglePlaceId.has(place.googlePlaceId)) ||
        index.byNameAddress.has(dupKey);

      if (alreadyExists) {
        listResult.skippedDuplicates++;
        continue;
      }

      if (!isValidCoordinate(place.lat, place.lng)) {
        listResult.failed.push({ name: place.name, reason: 'Missing coordinates' });
        continue;
      }

      const placeData = createPlace({
        name: place.name,
        address: place.address,
        location: { type: 'Point', coordinates: [place.lng, place.lat] },
        category: place.category || 'other',
        publicNotes: place.notes || null,
        tags: place.tags || [],
        website: place.sourceUrl || null,
        googlePlaceId: place.googlePlaceId || null,
        privacy: 'followCircle',
        importSource: payload.source,
        sourceExternalId: sourceId
      }, circleRef.id, userId);

      const errors = validatePlace(placeData);
      if (errors.length > 0) {
        listResult.failed.push({ name: place.name, reason: errors.join(', ') });
        continue;
      }

      const placeRef = db.collection(COLLECTIONS.PLACES).doc();
      batch.set(placeRef, placeData);
      newPlaceIds.push(placeRef.id);

      // Keep the in-memory index current so duplicates within this request
      // (and across its lists) are caught too.
      const entry = { placeId: placeRef.id, circleId: circleRef.id, name: place.name };
      if (sourceId) index.bySourceExternalId.set(sourceId, entry);
      if (place.googlePlaceId) index.byGooglePlaceId.set(place.googlePlaceId, entry);
      index.byNameAddress.set(dupKey, [entry]);
    }

    if (newPlaceIds.length > 0) {
      const { FieldValue } = require('firebase-admin').firestore;
      batch.update(circleRef, {
        places: FieldValue.arrayUnion(...newPlaceIds),
        placesCount: FieldValue.increment(newPlaceIds.length),
        updatedAt: new Date().toISOString()
      });
      await batch.commit();
      listResult.created = newPlaceIds.length;
    } else if (!list.existingCircleId && listResult.circleId) {
      // Created a circle but every place was a duplicate/failure — keep the
      // empty circle only if the user explicitly asked for it; delete otherwise.
      await circleRef.delete();
      listResult.circleId = null;
    }

    results.push(listResult);
  }

  return { results };
}

module.exports = {
  prepareImport,
  executeImport,
  MAX_PLACES_PER_REQUEST
};
