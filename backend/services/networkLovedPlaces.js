// backend/services/networkLovedPlaces.js
//
// "Places your people love": venues saved by two or more of the viewer's
// connections, most-saved first — the head of the My Network → Discover page.
// A well-connected person has no strangers left to discover in a small network;
// what their people love is always there.
//
// Privacy: a save counts only when the viewer may see it — its circle's tier
// (canViewCircle) and then the place's own (isPlaceVisibleToViewer). A save
// the viewer can't see never counts and never names its saver. Check-in and
// "Places I Follow" circles aren't someone saying they love a place.
const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');
const { GLOBAL_COLLECTIONS } = require('../models/GlobalPlace');
const { getConnectedUserIds } = require('../utils/networkAccess');
const { queryInChunks } = require('../utils/firestoreChunks');
const { buildViewerContext } = require('./viewerContext');
const { canViewCircle, isPlaceVisibleToViewer } = require('./visibility');
const { excludedUserIds } = require('./moderationService');
const { isSameUser, normalizeUserId } = require('./idService');
const placePhotos = require('./placePhotoService');

const db = getFirestore();
const MIN_SAVERS = 2;
const MAX_RESULTS = 60;
const CACHE_MS = 10 * 60 * 1000;
const cache = new Map();

const SAVE_FIELDS = ['globalPlaceId', 'addedBy', 'circleId', 'privacy', 'sharedWith', 'audienceListId', 'deletedAt', 'createdAt'];

/** A circle that isn't someone's own curation. Pure. */
const isSystemCircle = (circle) => !!circle && (circle.isCheckInCircle === true || circle.name === 'Places I Follow');

/**
 * Visible saves → one row per venue: distinct savers, newest save, ranked by
 * saver count then recency; only venues with at least `minSavers`. Pure.
 */
function rankVenues(saves, { minSavers = MIN_SAVERS, limit = MAX_RESULTS } = {}) {
  const byVenue = new Map();
  for (const save of saves) {
    if (!save.globalPlaceId || !save.addedBy) continue;
    const row = byVenue.get(save.globalPlaceId) || { globalPlaceId: save.globalPlaceId, savers: new Map(), latest: '' };
    const saver = normalizeUserId(save.addedBy);
    const at = String(save.createdAt || '');
    if (!row.savers.has(saver) || at > row.savers.get(saver)) row.savers.set(saver, at);
    if (at > row.latest) row.latest = at;
    byVenue.set(save.globalPlaceId, row);
  }
  return [...byVenue.values()]
    .filter((row) => row.savers.size >= minSavers)
    .sort((a, b) => b.savers.size - a.savers.size || b.latest.localeCompare(a.latest))
    .slice(0, limit)
    .map((row) => ({
      globalPlaceId: row.globalPlaceId,
      // Most recent savers first — the faces on the card
      saverIds: [...row.savers.entries()].sort((a, b) => b[1].localeCompare(a[1])).map(([id]) => id),
      latestSaveAt: row.latest
    }));
}

async function getAllDocs(collection, ids) {
  const unique = [...new Set(ids.filter(Boolean).map(String))];
  const out = new Map();
  for (let i = 0; i < unique.length; i += 300) {
    const docs = await db.getAll(...unique.slice(i, i + 300).map((id) => db.collection(collection).doc(id)));
    docs.forEach((d) => { if (d.exists) out.set(d.id, d.data()); });
  }
  return out;
}

/**
 * The viewer's page of loved places. Cached per viewer for a few minutes —
 * it reads every save of every connection.
 */
async function forViewer(viewerId, { limit = MAX_RESULTS, now = Date.now() } = {}) {
  const key = normalizeUserId(viewerId);
  const hit = cache.get(key);
  if (hit && now - hit.at < CACHE_MS) return hit.value.slice(0, limit);

  const [connections, ctx, viewerDoc] = await Promise.all([
    getConnectedUserIds(viewerId),
    buildViewerContext(viewerId),
    db.collection(COLLECTIONS.USERS).doc(String(viewerId)).get()
  ]);
  const blocked = excludedUserIds(viewerDoc.exists ? viewerDoc.data() : {});
  const people = [...connections].map(normalizeUserId).filter((id) => !blocked.has(id) && !isSameUser(id, viewerId));
  if (people.length === 0) return [];

  const snaps = await queryInChunks(people, (chunk) =>
    db.collection(COLLECTIONS.PLACES).where('addedBy', 'in', chunk).select(...SAVE_FIELDS).get());
  const saves = snaps.map((d) => ({ id: d.id, ...d.data() })).filter((s) => !s.deletedAt && s.globalPlaceId);

  const circles = await getAllDocs(COLLECTIONS.CIRCLES, saves.map((s) => s.circleId));
  const visible = saves.filter((s) => {
    const circle = circles.get(String(s.circleId));
    if (!circle || circle.deletedAt || isSystemCircle(circle)) return false;
    return canViewCircle(circle, viewerId, ctx) && isPlaceVisibleToViewer(s, viewerId, ctx);
  });

  const ranked = rankVenues(visible, { limit: MAX_RESULTS });
  if (ranked.length === 0) {
    cache.set(key, { at: now, value: [] });
    return [];
  }

  const [venues, users, mine] = await Promise.all([
    getAllDocs(GLOBAL_COLLECTIONS.GLOBAL_PLACES, ranked.map((r) => r.globalPlaceId)),
    getAllDocs(COLLECTIONS.USERS, [...new Set(ranked.flatMap((r) => r.saverIds.slice(0, 3)))]),
    db.collection(COLLECTIONS.PLACES).where('addedBy', '==', String(viewerId)).select('globalPlaceId', 'deletedAt').get()
  ]);
  const viewerSaved = new Set(mine.docs.map((d) => d.data()).filter((p) => !p.deletedAt).map((p) => p.globalPlaceId));

  const value = ranked
    .filter((r) => venues.has(r.globalPlaceId) && !venues.get(r.globalPlaceId).deletedAt)
    .map((r) => {
      const venue = venues.get(r.globalPlaceId);
      const photos = placePhotos.visiblePhotos(venue.photos || [], viewerId);
      return {
        globalPlaceId: r.globalPlaceId,
        name: venue.name || 'Place',
        category: venue.category || null,
        address: venue.address || null,
        photo: placePhotos.urlOf(photos[0]) || null,
        saverCount: r.saverIds.length,
        savers: r.saverIds.slice(0, 3).map((id) => ({
          userId: id,
          displayName: (users.get(id) || {}).displayName || 'Someone',
          profilePicture: (users.get(id) || {}).profilePicture || null
        })),
        viewerSaved: viewerSaved.has(r.globalPlaceId),
        latestSaveAt: r.latestSaveAt
      };
    });
  cache.set(key, { at: now, value });
  return value.slice(0, limit);
}

module.exports = { rankVenues, isSystemCircle, forViewer, MIN_SAVERS, _cache: cache };
