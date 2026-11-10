// services/checkInHistory.js
//
// "My check-ins" (Wes, 2026-11-09): after a check-in, the next step opens a
// summary of every place you've checked in at — how many times, first and
// last, how many lately — newest first. Built from the per-venue aggregate
// (users/{uid}/checkInStats, see checkInStatsService) plus the venue's name
// and cover, so it never counts raw check-ins per place. Only the viewer's
// own history; nothing here is social.
const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');
const { getDocsById } = require('../utils/batchGet');
const placePhotos = require('./placePhotoService');
const { combinedHistory } = require('./checkInStatsService');

const DAY = 24 * 60 * 60 * 1000;
const RECENT_DAYS = 30;

/**
 * Pure. One row per venue bucket, newest check-in first.
 * @param {Array<{id: string, data: object}>} buckets  the stats docs (id = globalPlaceId)
 * @param {Map<string, object>|object} venues  venue data by globalPlaceId (name, address, category, photos, coverPhotoUrl)
 * @param {Array<object>} checkIns  the viewer's raw check-ins (startTime/createdAt, globalPlaceId) — for "lately"
 * @param {number} now  ms
 */
function placeRows(buckets, venues, checkIns = [], now = Date.now()) {
  const venueOf = (id) => (venues instanceof Map ? venues.get(id) : (venues || {})[id]) || null;
  const since = now - RECENT_DAYS * DAY;
  const recent = new Map();
  for (const c of checkIns || []) {
    const ms = Date.parse(c.startTime || c.createdAt);
    if (!Number.isFinite(ms) || ms < since || ms > now || !c.globalPlaceId) continue;
    recent.set(c.globalPlaceId, (recent.get(c.globalPlaceId) || 0) + 1);
  }
  const rows = [];
  for (const bucket of buckets || []) {
    const data = bucket.data || {};
    const history = combinedHistory(data);
    if (!history) continue; // an empty bucket (nothing to show)
    const venue = venueOf(bucket.id);
    const importedCount = Object.values(data.imported || {}).reduce((sum, p) => sum + ((p && p.count) || 0), 0);
    rows.push({
      globalPlaceId: bucket.id,
      placeId: data.lastPlaceId || null,
      name: (venue && venue.name) || data.placeName || 'A place',
      address: (venue && venue.address) || null,
      category: (venue && venue.category) || null,
      photoUrl: venue ? (venue.coverPhotoUrl || placePhotos.coverUrl(venue.photos || []) || null) : null,
      count: history.count,
      importedCount,
      firstCheckInAt: history.firstCheckInAt,
      lastCheckInAt: history.lastCheckInAt,
      recentCount: recent.get(bucket.id) || 0
    });
  }
  rows.sort((a, b) => {
    const la = a.lastCheckInAt || '', lb = b.lastCheckInAt || '';
    if (la !== lb) return la < lb ? 1 : -1;
    return b.count - a.count;
  });
  return rows;
}

/** Pure. The header's numbers from the rows. */
function totals(rows) {
  return {
    total: rows.reduce((sum, r) => sum + r.count, 0),
    places: rows.length,
    recent: rows.reduce((sum, r) => sum + r.recentCount, 0)
  };
}

/** The viewer's places, read and shaped. */
async function listMyCheckInPlaces(userId, { db = getFirestore(), now = Date.now() } = {}) {
  const [statsSnap, mine] = await Promise.all([
    db.collection(COLLECTIONS.USERS).doc(userId).collection(COLLECTIONS.CHECK_IN_STATS).get(),
    db.collection(COLLECTIONS.CHECK_INS).where('userId', '==', userId)
      .select('startTime', 'createdAt', 'globalPlaceId').get()
      .catch(() => ({ docs: [] })) // "lately" is a bonus; the list still shows
  ]);
  const buckets = statsSnap.docs.map((d) => ({ id: d.id, data: d.data() }));
  const venueDocs = await getDocsById('globalPlaces', buckets.map((b) => b.id), {
    fields: ['name', 'address', 'category', 'photos', 'coverPhotoUrl'], db
  });
  const venues = new Map([...venueDocs].map(([id, doc]) => [id, doc.data()]));
  const rows = placeRows(buckets, venues, mine.docs.map((d) => d.data()), now);
  return { ...totals(rows), recentDays: RECENT_DAYS, items: rows };
}

module.exports = { placeRows, totals, listMyCheckInPlaces, RECENT_DAYS };
