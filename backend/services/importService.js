// Import service: turns normalized payloads from external platforms
// (Mapstr, Google Takeout, Swarm) into circles + places.
//
// Place creation deliberately mirrors the legacy path in
// placeController.createPlace (places collection + circle places[] /
// placesCount) — that is the source of truth for how the app populates
// circles. If createPlace ever starts writing globalPlaces, mirror it here.

const { getFirestore } = require('../config/firebase');
const {
  COLLECTIONS,
  createPlace,
  createCircle,
  validatePlace,
  validateCircle
} = require('../models/FirestoreModels');
const { categoryFromGoogleTypes, categoryFromMapstrTags } = require('./importCategoryMapping');
const systemCircles = require('./systemCircles');

const db = getFirestore();

// 'photos' (Build my map from my photos) is accepted here but only reached
// through POST /api/import/photos, which applies the photo allowance first
const VALID_SOURCES = ['mapstr', 'google_maps', 'swarm', 'google_list', 'photos'];

// google_list = a shared Google Maps LIST (share extension / app). Unlike the
// bulk sources it does NOT pool into a per-source import circle: the list
// becomes its OWN circle named after the list (or lands in an existing circle
// the user picked), and duplicates are judged per TARGET circle — a place the
// user already has elsewhere still belongs in "Paris coffee" if the list has
// it, exactly like Add-to-Circle in the app.
const LIST_SOURCES = new Set(['google_list']);

// Every import lands in ONE circle per source ("Google Imports", …) so the
// user can review/reorganize/delete the batch as a unit instead of having
// Takeout list names scattered through their circles. The original list name
// survives on each place as sourceListName. Import circles are created with
// showOnMap:true so a new user's map lights up immediately; the owner can
// hide the batch via the circle's showOnMap toggle if it's overwhelming.
const IMPORT_CIRCLE_NAMES = {
  google_maps: 'Google Imports',
  mapstr: 'Mapstr Imports',
  swarm: 'Swarm Imports',
  photos: systemCircles.KINDS.photoPlaces.name
};

// User-visible tag stamped on every imported place (filter/sweep handle)
const IMPORT_TAGS = {
  google_maps: 'google-import',
  mapstr: 'mapstr-import',
  swarm: 'swarm-import',
  google_list: 'google-list',
  photos: 'from-photos'
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

const normalizeText = (value) =>
  (value || '').toLowerCase().replace(/[^\w\s]/g, '').replace(/\s+/g, ' ').trim();

// null without a real address: "Starbucks|address pending" would make every
// branch of a chain one place (Swarm and Takeout rows often have none yet)
const PLACEHOLDER_ADDRESSES = new Set(['', 'address pending']);
const nameAddressKey = (name, address) => {
  const addr = normalizeText(address);
  return PLACEHOLDER_ADDRESSES.has(addr) ? null : `${normalizeText(name)}|${addr}`;
};

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
  const byApplePlaceId = new Map(); // Apple Maps place id → entry (exact venue)
  const byGlobalPlaceId = new Map(); // canonical venue → entry

  snapshot.forEach(doc => {
    const place = doc.data();
    if (place.deletedAt) return;
    const entry = { placeId: doc.id, circleId: place.circleId, name: place.name };
    if (place.sourceExternalId) bySourceExternalId.set(place.sourceExternalId, entry);
    if (place.googlePlaceId) byGooglePlaceId.set(place.googlePlaceId, entry);
    if (place.applePlaceId) byApplePlaceId.set(place.applePlaceId, entry);
    if (place.globalPlaceId) byGlobalPlaceId.set(place.globalPlaceId, entry);
    const key = nameAddressKey(place.name, place.address);
    if (key) {
      if (!byNameAddress.has(key)) byNameAddress.set(key, []);
      byNameAddress.get(key).push(entry);
    }
    const coords = place.location && place.location.coordinates;
    if (Array.isArray(coords) && coords.length === 2) {
      const nameKey = normalizedName(place.name);
      if (!byNormName.has(nameKey)) byNormName.set(nameKey, []);
      byNormName.get(nameKey).push({ ...entry, lat: coords[1], lng: coords[0] });
    }
  });

  return { bySourceExternalId, byGooglePlaceId, byNameAddress, byNormName, byApplePlaceId, byGlobalPlaceId };
}

/**
 * Apple Maps place ids → the canonical venue already carrying them, in one
 * batched read (10 ids a query). How a photo save finds a venue the person
 * saved before under Google's name ("Goldie's on Morehead" vs Apple's
 * "Goldie's"). Unknown ids are simply absent.
 */
async function venuesByApplePlaceId(applePlaceIds) {
  const ids = [...new Set((applePlaceIds || []).filter((id) => typeof id === 'string' && id))];
  const out = new Map();
  if (!ids.length) return out;
  const { queryInChunks } = require('../utils/firestoreChunks');
  const docs = await queryInChunks(ids, (chunk) =>
    db.collection('globalPlaces').where('applePlaceId', 'in', chunk).get());
  docs.forEach((doc) => out.set(doc.data().applePlaceId, doc.id));
  return out;
}

const SIMILAR_NAME_RADIUS_METERS = 100;

// "Goldie's" vs "Goldie's on Morehead": one name's words all inside the
// other's, both pinned within 100 m. Apple and Google name the same venue
// differently, and the exact-name check misses it.
function findNearbySimilarName(index, name, lat, lng) {
  if (typeof lat !== 'number' || typeof lng !== 'number') return null;
  const words = (value) => normalizedName(value).split(' ').filter((w) => w.length > 1);
  const mine = words(name);
  if (!mine.length) return null;
  for (const [otherName, entries] of index.byNormName) {
    const theirs = otherName.split(' ').filter((w) => w.length > 1);
    if (!theirs.length) continue;
    const [shorter, longer] = mine.length <= theirs.length ? [mine, theirs] : [theirs, mine];
    if (!shorter.every((w) => longer.includes(w))) continue;
    const hit = entries.find((c) => distanceMeters(lat, lng, c.lat, c.lng) < SIMILAR_NAME_RADIUS_METERS);
    if (hit) return hit;
  }
  return null;
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

/** The dedupe index restricted to one circle (list imports dedupe per target). */
function indexForCircle(index, circleId) {
  const keep = (entry) => entry.circleId === circleId;
  const filterMap = (map) => {
    const out = new Map();
    map.forEach((value, key) => {
      if (Array.isArray(value)) {
        const kept = value.filter(keep);
        if (kept.length) out.set(key, kept);
      } else if (keep(value)) {
        out.set(key, value);
      }
    });
    return out;
  };
  return {
    bySourceExternalId: filterMap(index.bySourceExternalId),
    byGooglePlaceId: filterMap(index.byGooglePlaceId),
    byNameAddress: filterMap(index.byNameAddress),
    byNormName: filterMap(index.byNormName),
    byApplePlaceId: filterMap(index.byApplePlaceId),
    byGlobalPlaceId: filterMap(index.byGlobalPlaceId)
  };
}

/**
 * Where a list import lands: the circle the caller picked (must be theirs),
 * else an existing circle with the list's name, else null (= create it).
 */
function resolveListTargetCircle(list, ownedCircles) {
  const wantedName = (list.circleName || list.name || '').trim();
  if (list.existingCircleId) {
    const picked = ownedCircles.find(c => c.id === list.existingCircleId);
    if (!picked) return { error: 'existingCircleId is not one of your circles' };
    return { circle: picked, name: picked.name };
  }
  const sameName = ownedCircles.find(c => normalizeText(c.name) === normalizeText(wantedName));
  return { circle: sameName || null, name: wantedName };
}

async function loadOwnedCircles(userId) {
  const snapshot = await db.collection(COLLECTIONS.CIRCLES)
    .where('owner', '==', userId)
    .get();
  const circles = [];
  snapshot.forEach(doc => {
    const data = doc.data();
    circles.push({
      id: doc.id, name: data.name, placesCount: data.placesCount || 0, deletedAt: data.deletedAt || null,
      createdAt: data.createdAt || null,
      // What services/systemCircles reads to find "Places from my photos" by flag
      systemKind: data.systemKind || null, isImportCircle: data.isImportCircle === true, importSource: data.importSource || null,
      isCheckInCircle: data.isCheckInCircle === true, isFollowedPlacesCircle: data.isFollowedPlacesCircle === true,
      isDogSpotsCircle: data.isDogSpotsCircle === true, isDefaultCircle: data.isDefaultCircle === true
    });
  });
  return circles;
}

function validatePayloadShape(payload) {
  if (!payload || !VALID_SOURCES.includes(payload.source)) {
    return `source must be one of: ${VALID_SOURCES.join(', ')}`;
  }
  if (!Array.isArray(payload.lists) || payload.lists.length === 0) {
    return 'lists must be a non-empty array';
  }
  if (LIST_SOURCES.has(payload.source) && payload.lists.length !== 1) {
    return 'a google_list import carries exactly one list';
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

/** A Swarm place's check-in history ({ count, firstAt, lastAt }), cleaned; null otherwise. */
function importedHistoryFor(source, place) {
  const { cleanImportedHistory, IMPORT_HISTORY_SOURCES } = require('./checkInStatsService');
  if (!IMPORT_HISTORY_SOURCES.includes(source) || !place || !place.checkIns) return null;
  const clean = cleanImportedHistory(place.checkIns);
  return clean ? { count: clean.count, firstAt: clean.firstCheckInAt, lastAt: clean.lastCheckInAt } : null;
}

/** The save a duplicate row matches, by the same keys the duplicate check uses. */
function existingEntryFor(dedupeIndex, { sourceId, googlePlaceId, applePlaceId, knownVenue, dupKey, name, lat, lng }) {
  return (sourceId && dedupeIndex.bySourceExternalId.get(sourceId)) ||
    (googlePlaceId && dedupeIndex.byGooglePlaceId.get(googlePlaceId)) ||
    (applePlaceId && dedupeIndex.byApplePlaceId.get(applePlaceId)) ||
    (knownVenue && dedupeIndex.byGlobalPlaceId.get(knownVenue)) ||
    (dedupeIndex.byNameAddress.get(dupKey) || [])[0] ||
    findNearbySameName(dedupeIndex, name, lat, lng) ||
    null;
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
  const isListImport = LIST_SOURCES.has(payload.source);
  let importCircleName = IMPORT_CIRCLE_NAMES[payload.source];
  let importCircle = importCircleName ? (circlesByName.get(normalizeText(importCircleName)) || null) : null;
  if (payload.source === 'photos') {
    // The photo circle is found by its flag, so a renamed one still counts
    const hit = systemCircles.pick(ownedCircles, 'photoPlaces');
    importCircle = hit ? hit.circle : null;
    importCircleName = importCircle ? importCircle.name : importCircleName;
  }
  if (isListImport) {
    const target = resolveListTargetCircle(payload.lists[0], ownedCircles);
    if (target.error) return { error: target.error };
    importCircleName = target.name;
    importCircle = target.circle;
  }
  // List imports dedupe against the TARGET circle only (see LIST_SOURCES)
  const dedupeIndex = isListImport
    ? (importCircle ? indexForCircle(index, importCircle.id) : indexForCircle(index, null))
    : index;

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
        // Swarm: this venue's check-in history, carried to execute
        checkIns: importedHistoryFor(payload.source, place),
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
      // Swarm gives the phone's spot at check-in, not the venue's address: it
      // stays pending (found on the phone after import), never "35.2, -80.8"
      if (!result.address && payload.source === 'swarm') result.address = 'Address pending';
      if (!result.address) {
        result.address = result.lat !== null
          ? `${result.lat.toFixed(5)}, ${result.lng.toFixed(5)}`
          : 'Address pending';
      }

      // Duplicate detection: stable external id → google place id →
      // name+address → same name within 250m (venue-level)
      const dupKey = nameAddressKey(result.name, result.address);
      const existing =
        (result.sourceExternalId && dedupeIndex.bySourceExternalId.get(result.sourceExternalId)) ||
        (result.googlePlaceId && dedupeIndex.byGooglePlaceId.get(result.googlePlaceId)) ||
        (dedupeIndex.byNameAddress.get(dupKey) || [])[0] ||
        findNearbySameName(dedupeIndex, result.name, result.lat, result.lng) ||
        (dupKey && seenInList.has(dupKey) ? { placeId: null, circleId: null, name: result.name } : null);

      if (existing) {
        result.status = 'duplicate';
        result.duplicateOf = existing.placeId
          ? { placeId: existing.placeId, circleId: existing.circleId }
          : { placeId: null, circleId: null };
      }
      if (dupKey) seenInList.add(dupKey);
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
/**
 * The photo circle's cover after a batch: keep a cover someone chose; a
 * user photo replaces nothing or the 📸 placeholder; no photo at all gets
 * the placeholder.
 */
function photoCircleCover(current, firstPhoto, fallback) {
  if (current && current !== fallback) return current;
  if (firstPhoto) return firstPhoto;
  return current || fallback || null;
}

async function executeImport(userId, payload) {
  const shapeError = validatePayloadShape(payload);
  if (shapeError) return { error: shapeError };

  const subscriptionLimitService = require('./subscriptionLimitService');
  const index = await loadUserPlaceIndex(userId);
  const results = [];

  // Resolve the single per-source import circle once ("Google Imports", …).
  // Every list lands here; the source list name survives as sourceListName.
  const isListImport = LIST_SOURCES.has(payload.source);
  const importTag = IMPORT_TAGS[payload.source];
  const ownedCircles = await loadOwnedCircles(userId);
  let importCircleName = IMPORT_CIRCLE_NAMES[payload.source];
  let existingImportCircle = importCircleName
    ? ownedCircles.find(c => normalizeText(c.name) === normalizeText(importCircleName))
    : null;
  if (payload.source === 'photos' && (!payload.target || !payload.target.kind || payload.target.kind === 'photos')) {
    // "Places from my photos" is found by its flag (services/systemCircles):
    // renaming it keeps it the photo circle; a legacy one is stamped
    existingImportCircle = await systemCircles.pickAndHeal(ownedCircles, 'photoPlaces', { db });
    if (existingImportCircle) importCircleName = existingImportCircle.name;
  }
  if (isListImport) {
    const target = resolveListTargetCircle(payload.lists[0], ownedCircles);
    if (target.error) return { error: target.error };
    importCircleName = target.name;
    existingImportCircle = target.circle;
    if (!importCircleName) return { error: 'every list needs a name' };
  }

  // Add from photos (2026-10-17): into "Places from my photos" (default), a
  // circle of the person's own they picked, or a new circle they named
  const photoTarget = payload.source === 'photos' ? (payload.target || { kind: 'photos' }) : null;
  if (photoTarget && photoTarget.kind === 'circle') {
    const owned = ownedCircles.find(c => c.id === photoTarget.circleId && !c.deletedAt);
    if (!owned) return { error: 'You can only add places to your own circles', status: 403 };
    existingImportCircle = owned;
    importCircleName = owned.name;
  } else if (photoTarget && photoTarget.kind === 'new') {
    importCircleName = String(photoTarget.name || '').trim().slice(0, 50);
    if (!importCircleName) return { error: 'Give the new circle a name' };
    existingImportCircle = null;
  }

  let circleRef;
  let createdImportCircleThisRun = false;
  if (existingImportCircle) {
    circleRef = db.collection(COLLECTIONS.CIRCLES).doc(existingImportCircle.id);
  } else if (photoTarget && photoTarget.kind === 'new') {
    // A circle the person named (a trip, a month): one of their own, so it
    // counts toward the free circle cap like any other
    const limitCheck = await subscriptionLimitService.canCreateCircle(userId);
    if (!limitCheck.canCreate) {
      return { error: limitCheck.error, upgradeRequired: true };
    }
    const privacy = ['public', 'myNetwork', 'private'].includes(photoTarget.privacy) ? photoTarget.privacy : 'myNetwork';
    const circleData = createCircle({
      name: importCircleName,
      description: 'Places from my photos',
      privacy,
      showOnMap: photoTarget.showOnMap !== false
    }, userId);
    const circleErrors = validateCircle(circleData);
    if (circleErrors.length > 0) {
      return { error: circleErrors.join(', ') };
    }
    circleRef = await db.collection(COLLECTIONS.CIRCLES).add(circleData);
    createdImportCircleThisRun = true;
  } else if (isListImport) {
    const limitCheck = await subscriptionLimitService.canCreateCircle(userId);
    if (!limitCheck.canCreate) {
      return { error: limitCheck.error, upgradeRequired: true };
    }
    // The shared list becomes its own circle, named after the list. Circle
    // names are capped at 50 chars by validateCircle.
    const sourceList = payload.lists[0];
    const circleData = createCircle({
      name: importCircleName.slice(0, 50),
      description: (sourceList.description || `Imported from a shared Google Maps list`).slice(0, 500),
      privacy: 'myNetwork',
      showOnMap: true
    }, userId);
    const circleErrors = validateCircle(circleData);
    if (circleErrors.length > 0) {
      return { error: circleErrors.join(', ') };
    }
    circleData.isImportCircle = true;
    circleData.importSource = payload.source;
    if (sourceList.sourceUrl) circleData.sourceListUrl = sourceList.sourceUrl;
    circleRef = await db.collection(COLLECTIONS.CIRCLES).add(circleData);
    createdImportCircleThisRun = true;
  } else {
    // The photo circle is the app's own, not one of the user's six: it
    // never counts against the circle cap
    const limitCheck = payload.source === 'photos'
      ? { canCreate: true }
      : await subscriptionLimitService.canCreateCircle(userId);
    if (!limitCheck.canCreate) {
      return { error: limitCheck.error };
    }
    // Visible to connections from day one (these places were largely
    // shareable on the source platform already) AND on the home map — a new
    // user imports precisely to jump-start their map. Anyone who finds the
    // pins overwhelming can hide the circle via its showOnMap toggle.
    const circleData = createCircle({
      name: importCircleName,
      description: payload.source === 'photos'
        ? 'Places found in your photos. Turn this circle off the map any time.'
        : `Places imported from ${payload.source === 'google_maps' ? 'Google Maps' : payload.source === 'mapstr' ? 'Mapstr' : 'Swarm'}`,
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
    if (payload.source === 'photos') Object.assign(circleData, systemCircles.flagFields('photoPlaces'));
    circleRef = await db.collection(COLLECTIONS.CIRCLES).add(circleData);
    createdImportCircleThisRun = true;
  }

  // List imports dedupe against the TARGET circle only (see LIST_SOURCES);
  // a brand-new circle has nothing to collide with.
  // Photos into a chosen or new circle: a place already saved elsewhere
  // still belongs in "Lisbon · May 2026", like Add-to-Circle
  const perCircle = isListImport || (photoTarget && photoTarget.kind !== 'photos');
  const dedupeIndex = perCircle ? indexForCircle(index, circleRef.id) : index;

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
    // Photo saves carry Apple's place id: the venue it already belongs to
    // (if anyone saved it) makes the duplicate check exact
    const appleVenues = payload.source === 'photos'
      ? await venuesByApplePlaceId((list.places || []).map((p) => p.applePlaceId))
      : new Map();

    // Saves whose venue we already know by its Apple id: linked to it directly
    const knownVenueByPlaceId = new Map();
    // Swarm: places (new or already saved) whose check-in history to record
    const historyTargets = [];
    for (const place of list.places || []) {
      const sourceId = place.sourceExternalId || null;
      const applePlaceId = typeof place.applePlaceId === 'string' && place.applePlaceId ? place.applePlaceId : null;
      const knownVenue = applePlaceId ? appleVenues.get(applePlaceId) : null;
      const dupKey = nameAddressKey(place.name, place.address);
      const lat = typeof place.lat === 'number' ? place.lat : null;
      const lng = typeof place.lng === 'number' ? place.lng : null;
      const history = importedHistoryFor(payload.source, place);
      const alreadyExists =
        (sourceId && dedupeIndex.bySourceExternalId.has(sourceId)) ||
        (place.googlePlaceId && dedupeIndex.byGooglePlaceId.has(place.googlePlaceId)) ||
        (applePlaceId && dedupeIndex.byApplePlaceId.has(applePlaceId)) ||
        (knownVenue && dedupeIndex.byGlobalPlaceId.has(knownVenue)) ||
        (dupKey && dedupeIndex.byNameAddress.has(dupKey)) ||
        !!findNearbySameName(dedupeIndex, place.name, lat, lng) ||
        (payload.source === 'photos' && !!findNearbySimilarName(dedupeIndex, place.name, lat, lng));

      if (alreadyExists) {
        listResult.skippedDuplicates++;
        // Already saved: its check-in history still comes over, onto the save it duplicates
        if (history) {
          const existing = existingEntryFor(dedupeIndex, { sourceId, googlePlaceId: place.googlePlaceId, applePlaceId, knownVenue, dupKey, name: place.name, lat, lng });
          if (existing && existing.placeId) historyTargets.push({ placeId: existing.placeId, name: place.name, lat, lng, history });
        }
        continue;
      }
      // Sent only for its history (a duplicate the person left unticked):
      // never saved as a new place
      if (place.historyOnly === true) continue;

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
        // Photo places: just "from-photos" (the circle's own name as a tag
        // only repeated the circle as a filter chip)
        tags: [...new Set([...(place.tags || []), importTag, payload.source === 'photos' ? null : listNameTag(circleName)].filter(Boolean))],
        website: place.sourceUrl || null,
        googlePlaceId: place.googlePlaceId || null,
        applePoiCategory: typeof place.applePoiCategory === 'string' ? place.applePoiCategory : null,
        privacy: 'followCircle',
        importSource: payload.source,
        sourceExternalId: sourceId,
        // Photo places carry the user's own photo of the spot (already
        // uploaded, GPS stripped); other imports have none
        photos: payload.source === 'photos' && Array.isArray(place.photos)
          ? place.photos.filter((url) => typeof url === 'string' && url.startsWith('https://')).slice(0, 3)
          : []
      }, circleRef.id, userId);

      // createPlace drops unknown keys: stamp extras after. sourceListName
      // feeds future favorites signals; needsResolution marks rows a future
      // promote/resolve step would look up.
      placeData.sourceListName = circleName || null;
      if (applePlaceId) placeData.applePlaceId = applePlaceId;
      if (!hasCoordinates) placeData.needsResolution = true;
      // Swarm rows pinned at the check-in but not yet matched to the venue:
      // the phone's resolution queue finds the venue's address and true pin
      if (hasCoordinates && payload.source === 'swarm' && placeData.address === 'Address pending') {
        placeData.needsResolution = true;
      }

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
      if (history) historyTargets.push({ placeId: placeRef.id, name: place.name, lat, lng, history });
      if (hasCoordinates) linkablePlaceIds.push(placeRef.id);
      if (knownVenue) knownVenueByPlaceId.set(placeRef.id, knownVenue);

      // Keep the in-memory index current so duplicates within this request
      // (and across its lists) are caught too.
      const entry = { placeId: placeRef.id, circleId: circleRef.id, name: place.name };
      if (sourceId) dedupeIndex.bySourceExternalId.set(sourceId, entry);
      if (place.googlePlaceId) dedupeIndex.byGooglePlaceId.set(place.googlePlaceId, entry);
      if (applePlaceId) dedupeIndex.byApplePlaceId.set(applePlaceId, entry);
      if (knownVenue) dedupeIndex.byGlobalPlaceId.set(knownVenue, entry);
      if (dupKey) dedupeIndex.byNameAddress.set(dupKey, [entry]);
      if (hasCoordinates) {
        const nameKey = normalizedName(place.name);
        if (!dedupeIndex.byNormName.has(nameKey)) dedupeIndex.byNormName.set(nameKey, []);
        dedupeIndex.byNormName.get(nameKey).push({ ...entry, lat: place.lat, lng: place.lng });
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

      // "Places from my photos" always has a cover (Wes, 2026-10-17): one of
      // the uploaded photos, or the 📸 cover until a photo arrives. A cover
      // the person picked themselves stays.
      // Places saved from photos get the same Google enrichment as a manual
      // save (Wes, 2026-10-17): canonical venue first (free), else Google's
      // photo and details. The person's own photo is never replaced.
      const enrichedPhotos = payload.source === 'photos'
        ? await enrichPhotoSaves(newPlaceIds)
        : [];

      if (payload.source === 'photos') {
        const firstPhoto = [...(list.places || []).flatMap((p) => Array.isArray(p.photos) ? p.photos : []), ...enrichedPhotos]
          .find((url) => typeof url === 'string' && url.startsWith('https://'));
        try {
          const { PHOTOS_FALLBACK_COVER } = require('../config/eventCovers');
          const circleSnap = await circleRef.get();
          const current = circleSnap.exists ? circleSnap.data().coverImage : null;
          // The 📸 placeholder is only for circles this made, never for a
          // circle of the person's own they picked
          const fallback = photoTarget && photoTarget.kind === 'circle' ? null : PHOTOS_FALLBACK_COVER;
          const next = photoCircleCover(current, firstPhoto, fallback);
          if (circleSnap.exists && next !== current) await circleRef.update({ coverImage: next });
        } catch (coverError) {
          console.error('⚠️ Photo circle cover failed (non-fatal):', coverError.message);
        }
      }

      // These circles are network-visible, so imported places must behave
      // like normal saves: link the canonical venue record now. This is FREE
      // (text-based category + address-derived city/state lens — zero Google
      // calls) and best-effort — a failed link never fails the import.
      const { ensureGlobalPlaceLink } = require('./globalPlaceResolver');
      await mapWithConcurrency(linkablePlaceIds, 4, async (placeId) => {
        try {
          const snap = await db.collection(COLLECTIONS.PLACES).doc(placeId).get();
          const linked = await ensureGlobalPlaceLink(snap, { knownVenueId: knownVenueByPlaceId.get(placeId) || null });
          await stampApplePlaceId(placeId, linked);
        } catch (linkError) {
          console.error(`⚠️ Import: global-place link failed for ${placeId} (non-fatal):`, linkError.message);
        }
      });
    }

    // Check-in history (Swarm) after linking, so new saves have their venue.
    // Silent: stats only — no feed rows, notifications or points.
    if (historyTargets.length) {
      const { resolveCheckInVenue, recordImportedHistory } = require('./checkInStatsService');
      let recorded = 0;
      await mapWithConcurrency(historyTargets, 4, async (target) => {
        try {
          const location = isValidCoordinate(target.lat, target.lng) ? { coordinates: [target.lng, target.lat] } : null;
          const globalPlaceId = await resolveCheckInVenue({ placeId: target.placeId, placeName: target.name, location });
          if (await recordImportedHistory({
            userId, globalPlaceId, source: payload.source, history: target.history, placeName: target.name, placeId: target.placeId
          })) recorded++;
        } catch (historyError) {
          console.error(`⚠️ Import: check-in history failed for ${target.placeId} (non-fatal):`, historyError.message);
        }
      });
      listResult.historyRecorded = recorded;
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

/**
 * The venue learns its Apple Maps id from the first photo save that names
 * it, so the next save of it (by anyone) is matched exactly and fast.
 */
async function stampApplePlaceId(placeId, linkedGlobalId) {
  const save = (await db.collection(COLLECTIONS.PLACES).doc(placeId).get()).data() || {};
  const globalId = (typeof linkedGlobalId === 'string' && linkedGlobalId) || save.globalPlaceId;
  if (!save.applePlaceId || !globalId) return;
  const ref = db.collection('globalPlaces').doc(globalId);
  const venue = await ref.get();
  if (!venue.exists || venue.data().applePlaceId) return;
  // One venue per Apple id, as with Google ids: never a second holder
  const holders = await db.collection('globalPlaces').where('applePlaceId', '==', save.applePlaceId).limit(5).get();
  if (holders.docs.some((doc) => doc.id !== globalId && !doc.data().deletedAt && !doc.data().mergedInto)) return;
  await ref.update({ applePlaceId: save.applePlaceId });
}

// Fields a Google enrichment may fill on a photo save (venue fields; the
// canonical overlay keeps them in sync afterwards)
const ENRICHED_FIELDS = ['googlePlaceId', 'name', 'address', 'googleTypes', 'rating', 'userRatingsTotal', 'priceLevel',
  'website', 'phone', 'openingHours', 'delivery', 'dineIn', 'reservable', 'takeout', 'curbsidePickup',
  'description', 'descriptionSource'];

/**
 * Build my map: give each new save the manual-save enrichment
 * (services/googleEnrichment). Returns the Google photo URLs added, for the
 * circle cover. Best-effort per place; three at a time.
 */
async function enrichPhotoSaves(placeIds) {
  const { enrichSaveFromGoogle } = require('./googleEnrichment');
  const added = [];
  await mapWithConcurrency(placeIds, 3, async (placeId) => {
    try {
      const ref = db.collection(COLLECTIONS.PLACES).doc(placeId);
      const snap = await ref.get();
      if (!snap.exists) return;
      const save = snap.data();
      if (save.googlePlaceId) return;
      const draft = { ...save };
      if (!(await enrichSaveFromGoogle(draft))) return;
      const update = {};
      for (const field of ENRICHED_FIELDS) {
        if (draft[field] !== undefined && draft[field] !== save[field]) update[field] = draft[field];
      }
      const ownPhotos = Array.isArray(save.photos) && save.photos.length > 0;
      if (!ownPhotos && Array.isArray(draft.photos) && draft.photos.length > 0) {
        update.photos = draft.photos;
        update.photoSource = 'google_places';
        added.push(draft.photos[0]);
      }
      if (Object.keys(update).length) {
        update.updatedAt = new Date().toISOString();
        await ref.update(update);
      }
    } catch (error) {
      console.error(`⚠️ Photo save enrichment failed for ${placeId} (non-fatal):`, error.message);
    }
  });
  return added;
}

module.exports = {
  enrichPhotoSaves,
  findNearbySimilarName,
  loadUserPlaceIndex,
  photoCircleCover,
  prepareImport,
  executeImport,
  MAX_PLACES_PER_REQUEST
};
