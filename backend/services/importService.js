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

// Every import lands in ONE circle per source ("Google Imports", …) so the
// user can review/reorganize/delete the batch as a unit instead of having
// Takeout list names scattered through their circles. The original list name
// survives on each place as sourceListName. Import circles are created with
// showOnMap:false — a 500-place dump shouldn't bury the home map; the owner
// can flip it on from the circle's edit screen.
const IMPORT_CIRCLE_NAMES = {
  google_maps: 'Google Imports',
  mapstr: 'Mapstr Imports',
  swarm: 'Swarm Imports'
};

// User-visible tag stamped on every imported place (filter/sweep handle)
const IMPORT_TAGS = {
  google_maps: 'google-import',
  mapstr: 'mapstr-import',
  swarm: 'swarm-import'
};

// The source list name ("Want to go", "Favorite places") also becomes a tag —
// once everything lands in one import circle, it's the only user-visible
// trace of how the source platform grouped these places
const listNameTag = (name) => (name || '')
  .toLowerCase()
  .trim()
  .replace(/[^a-z0-9\s-]/g, '')
  .replace(/\s+/g, '-')
  .slice(0, 40) || null;

// Venue-level duplicate matching: same normalized name within this distance
// is the same place regardless of address formatting ("130 W Bland St" vs
// "130, W Bland St, …, United States")
const DUPLICATE_RADIUS_METERS = 250;

function distanceMeters(lat1, lng1, lat2, lng2) {
  const R = 6371000;
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLng = (lng2 - lng1) * Math.PI / 180;
  const s = Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(s));
}

const normalizedName = s => (s || '').toLowerCase().trim().replace(/[^\w\s]/g, '').replace(/\s+/g, ' ');
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
  const byNormName = new Map();    // normalized name → [{...entry, lat, lng}]

  snapshot.forEach(doc => {
    const place = doc.data();
    if (place.deletedAt) return;
    const entry = { placeId: doc.id, circleId: place.circleId, name: place.name };
    if (place.sourceExternalId) bySourceExternalId.set(place.sourceExternalId, entry);
    if (place.googlePlaceId) byGooglePlaceId.set(place.googlePlaceId, entry);
    const key = nameAddressKey(place.name, place.address);
    if (!byNameAddress.has(key)) byNameAddress.set(key, []);
    byNameAddress.get(key).push(entry);
    const coords = place.location && place.location.coordinates;
    if (Array.isArray(coords) && coords.length === 2) {
      const nameKey = normalizedName(place.name);
      if (!byNormName.has(nameKey)) byNormName.set(nameKey, []);
      byNormName.get(nameKey).push({ ...entry, lat: coords[1], lng: coords[0] });
    }
  });

  return { bySourceExternalId, byGooglePlaceId, byNameAddress, byNormName };
}

// Venue-level duplicate check: same normalized name saved within
// DUPLICATE_RADIUS_METERS. Catches case and address-format variants the
// exact name+address key misses ("OROSOKO Sound Bar" vs "Orosoko Sound Bar").
// Coordinate-less rows can't proximity-match — chains ("Planet Fitness")
// would false-positive on name alone.
function findNearbySameName(index, name, lat, lng) {
  if (typeof lat !== 'number' || typeof lng !== 'number') return null;
  const candidates = index.byNormName.get(normalizedName(name)) || [];
  return candidates.find(c => distanceMeters(lat, lng, c.lat, c.lng) < DUPLICATE_RADIUS_METERS) || null;
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

  // Everything imports into the one per-source circle; source list names are
  // kept for grouping in the preview and stamped as sourceListName on places.
  const importCircleName = IMPORT_CIRCLE_NAMES[payload.source];
  const importCircle = circlesByName.get(normalizeText(importCircleName)) || null;

  const counts = { new: 0, duplicate: 0, unmapped: 0 };
  const lists = [];

  for (const list of payload.lists) {
    const existingCircle = importCircle;
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
        // From the client's on-device Apple Maps lookup — feeds the category
        // cascade at canonical-link time
        applePoiCategory: typeof place.applePoiCategory === 'string' ? place.applePoiCategory : null,
        status: 'new',
        duplicateOf: null
      };

      // Zero-cost ingest (2026-08): NO Google Find Place calls at import.
      // Rows without source coordinates (most Google Takeout saved-list rows)
      // import as UNMAPPED — present in their circle's list, no map pin —
      // instead of being dropped. Resolution can happen later if/when a
      // promote step exists; today nothing is billed.
      if (!isValidCoordinate(result.lat, result.lng)) {
        result.lat = null;
        result.lng = null;
        result.status = 'unmapped';
      }

      if (!result.category && payload.source === 'mapstr' && result.tags.length > 0) {
        result.category = categoryFromMapstrTags(result.tags);
      }
      if (!result.category) result.category = 'other';
      if (!result.address) {
        result.address = result.lat !== null
          ? `${result.lat.toFixed(5)}, ${result.lng.toFixed(5)}`
          : 'Address pending';
      }

      // Duplicate detection: stable external id → google place id →
      // name+address → same name within 250m (venue-level)
      const dupKey = nameAddressKey(result.name, result.address);
      const existing =
        (result.sourceExternalId && index.bySourceExternalId.get(result.sourceExternalId)) ||
        (result.googlePlaceId && index.byGooglePlaceId.get(result.googlePlaceId)) ||
        (index.byNameAddress.get(dupKey) || [])[0] ||
        findNearbySameName(index, result.name, result.lat, result.lng) ||
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

  return {
    preview: {
      lists,
      counts,
      // Where every selected place will land, so the review screen can say so
      targetCircleName: importCircleName,
      targetCircleExists: !!importCircle
    }
  };
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

  // Resolve the single per-source import circle once ("Google Imports", …).
  // Every list lands here; the source list name survives as sourceListName.
  const importCircleName = IMPORT_CIRCLE_NAMES[payload.source];
  const importTag = IMPORT_TAGS[payload.source];
  const ownedCircles = await loadOwnedCircles(userId);
  const existingImportCircle = ownedCircles.find(
    c => normalizeText(c.name) === normalizeText(importCircleName)
  );

  let circleRef;
  let createdImportCircleThisRun = false;
  if (existingImportCircle) {
    circleRef = db.collection(COLLECTIONS.CIRCLES).doc(existingImportCircle.id);
  } else {
    const limitCheck = await subscriptionLimitService.canCreateCircle(userId);
    if (!limitCheck.canCreate) {
      return { error: limitCheck.error };
    }
    // Visible to connections from day one (these places were largely
    // shareable on the source platform already) AND on the home map — a new
    // user imports precisely to jump-start their map. Anyone who finds the
    // pins overwhelming can hide the circle via its showOnMap toggle.
    const circleData = createCircle({
      name: importCircleName,
      description: `Places imported from ${payload.source === 'google_maps' ? 'Google Maps' : payload.source === 'mapstr' ? 'Mapstr' : 'Swarm'}`,
      privacy: 'myNetwork',
      showOnMap: true
    }, userId);
    const circleErrors = validateCircle(circleData);
    if (circleErrors.length > 0) {
      return { error: circleErrors.join(', ') };
    }
    // createCircle drops unknown keys — stamp import markers after
    circleData.isImportCircle = true;
    circleData.importSource = payload.source;
    circleRef = await db.collection(COLLECTIONS.CIRCLES).add(circleData);
    createdImportCircleThisRun = true;
  }

  for (const list of payload.lists) {
    const listResult = {
      circleId: circleRef.id,
      circleName: importCircleName,
      created: 0,
      skippedDuplicates: 0,
      failed: []
    };
    const circleName = (list.circleName || list.name || '').trim();

    // Create places in one Firestore batch per list (≤300 places by cap,
    // well under the 500-op batch limit including the circle update).
    // No per-place activity/notification fan-out — an import of hundreds of
    // places must not spam the network feed.
    const batch = db.batch();
    const newPlaceIds = [];
    const linkablePlaceIds = []; // mapped rows only — canonical linking needs a location

    for (const place of list.places || []) {
      const sourceId = place.sourceExternalId || null;
      const dupKey = nameAddressKey(place.name, place.address);
      const alreadyExists =
        (sourceId && index.bySourceExternalId.has(sourceId)) ||
        (place.googlePlaceId && index.byGooglePlaceId.has(place.googlePlaceId)) ||
        index.byNameAddress.has(dupKey) ||
        !!findNearbySameName(index, place.name,
          typeof place.lat === 'number' ? place.lat : null,
          typeof place.lng === 'number' ? place.lng : null);

      if (alreadyExists) {
        listResult.skippedDuplicates++;
        continue;
      }

      // Coordinate-less rows import UNMAPPED (no pin) instead of failing —
      // zero-cost ingest never calls Google
      const hasCoordinates = isValidCoordinate(place.lat, place.lng);

      const placeData = createPlace({
        name: place.name,
        address: place.address || 'Address pending',
        location: hasCoordinates
          ? { type: 'Point', coordinates: [place.lng, place.lat] }
          : null,
        category: place.category || 'other',
        // Imported captions belong to the importer alone; publishing another
        // platform's private notes as venue comments would be a leak.
        privateNotes: place.notes || null,
        // Source tag makes the whole batch filterable/sweepable later; the
        // original list name rides along as a tag too ("want-to-go")
        tags: [...new Set([...(place.tags || []), importTag, listNameTag(circleName)].filter(Boolean))],
        website: place.sourceUrl || null,
        googlePlaceId: place.googlePlaceId || null,
        applePoiCategory: typeof place.applePoiCategory === 'string' ? place.applePoiCategory : null,
        privacy: 'followCircle',
        importSource: payload.source,
        sourceExternalId: sourceId
      }, circleRef.id, userId);

      // createPlace drops unknown keys: stamp extras after. sourceListName
      // feeds future favorites signals; needsResolution marks rows a future
      // promote/resolve step would look up.
      placeData.sourceListName = circleName || null;
      if (!hasCoordinates) placeData.needsResolution = true;

      if (hasCoordinates) {
        const errors = validatePlace(placeData);
        if (errors.length > 0) {
          listResult.failed.push({ name: place.name, reason: errors.join(', ') });
          continue;
        }
      } else if (!placeData.name || !placeData.name.trim()) {
        // Unmapped rows skip validatePlace's location requirement but still
        // need a name
        listResult.failed.push({ name: place.name, reason: 'Place name is required' });
        continue;
      }

      const placeRef = db.collection(COLLECTIONS.PLACES).doc();
      batch.set(placeRef, placeData);
      newPlaceIds.push(placeRef.id);
      if (hasCoordinates) linkablePlaceIds.push(placeRef.id);

      // Keep the in-memory index current so duplicates within this request
      // (and across its lists) are caught too.
      const entry = { placeId: placeRef.id, circleId: circleRef.id, name: place.name };
      if (sourceId) index.bySourceExternalId.set(sourceId, entry);
      if (place.googlePlaceId) index.byGooglePlaceId.set(place.googlePlaceId, entry);
      index.byNameAddress.set(dupKey, [entry]);
      if (hasCoordinates) {
        const nameKey = normalizedName(place.name);
        if (!index.byNormName.has(nameKey)) index.byNormName.set(nameKey, []);
        index.byNormName.get(nameKey).push({ ...entry, lat: place.lat, lng: place.lng });
      }
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

      // These circles are network-visible, so imported places must behave
      // like normal saves: link the canonical venue record now. This is FREE
      // (text-based category + address-derived city/state lens — zero Google
      // calls) and best-effort — a failed link never fails the import.
      const { ensureGlobalPlaceLink } = require('./globalPlaceResolver');
      await mapWithConcurrency(linkablePlaceIds, 4, async (placeId) => {
        try {
          const snap = await db.collection(COLLECTIONS.PLACES).doc(placeId).get();
          await ensureGlobalPlaceLink(snap);
        } catch (linkError) {
          console.error(`⚠️ Import: global-place link failed for ${placeId} (non-fatal):`, linkError.message);
        }
      });
    }

    results.push(listResult);
  }

  // Created the import circle this run but every place across every list was
  // a duplicate/failure — don't leave an empty circle behind.
  const totalCreated = results.reduce((sum, r) => sum + r.created, 0);
  if (createdImportCircleThisRun && totalCreated === 0) {
    await circleRef.delete();
    results.forEach(r => { r.circleId = null; });
  }

  return { results };
}

module.exports = {
  prepareImport,
  executeImport,
  MAX_PLACES_PER_REQUEST
};
