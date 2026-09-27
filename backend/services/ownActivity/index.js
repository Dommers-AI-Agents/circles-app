// backend/services/ownActivity/index.js
// The profile's Activity tab: the owner's own timeline and the month's
// summary. One query shape — activities by actorId, newest first — on the
// (actorId, timestamp desc) index the people row already uses. Filters are
// applied in memory (a filtered page may come back short; the client keeps
// paging on `nextCursor` until `hasMore` is false).
const admin = require('firebase-admin');
const { getFirestore } = require('../../config/firebase');
const { COLLECTIONS } = require('../../models/FirestoreModels');
const shape = require('./shape');

const PAGE_MAX = 50;
/** Rows read per page before filtering; a filter never needs more than this many round-trips per page. */
const SCAN_LIMIT = 80;
const SUMMARY_SCAN = 1000;

const toTimestamp = (iso) => {
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? null : admin.firestore.Timestamp.fromDate(d);
};

class OwnActivityService {
  constructor() { this.db = getFirestore(); }
  get activities() { return this.db.collection(COLLECTIONS.ACTIVITIES); }

  /**
   * A page of the owner's rows. `cursor` = the last row's ISO timestamp.
   * Returns { items, nextCursor, hasMore, filter }.
   */
  async list({ userId, filter = 'all', cursor = null, limit = 30 }) {
    const f = shape.normalizeFilter(filter);
    const want = Math.min(PAGE_MAX, Math.max(1, limit));
    let query = this.activities.where('actorId', '==', String(userId)).orderBy('timestamp', 'desc').limit(SCAN_LIMIT);
    const after = cursor ? toTimestamp(cursor) : null;
    if (after) query = query.startAfter(after);
    const snap = await query.get();
    const docs = snap.docs.map((d) => ({ id: d.id, ...d.data() }));
    const kept = docs.filter((d) => shape.belongs(d, f)).slice(0, want);
    // The cursor moves past everything scanned when nothing was cut by `want`,
    // else to the last kept row — so a filtered page never skips a row.
    const lastScanned = docs[docs.length - 1];
    const lastKept = kept[kept.length - 1];
    const cutByWant = kept.length === want && docs.indexOf(docs.find((d) => d.id === lastKept.id)) < docs.length - 1;
    const cursorDoc = cutByWant ? lastKept : lastScanned;
    const hasMore = snap.size === SCAN_LIMIT || cutByWant;
    const extras = await this.momentExtras(kept);
    return {
      filter: f,
      items: kept.map((d) => shape.presentItem(d, extras.get(d.targetId) || {})),
      nextCursor: hasMore && cursorDoc ? isoOf(cursorDoc.timestamp || cursorDoc.createdAt) : null,
      hasMore
    };
  }

  /** Like and comment counts for the page's moments, one batched read. */
  async momentExtras(rows) {
    const ids = [...new Set(rows.filter((r) => shape.categoryOf(r.type) === 'moments' && r.targetId).map((r) => r.targetId))];
    const out = new Map();
    if (ids.length === 0) return out;
    try {
      const docs = await this.db.getAll(...ids.map((id) => this.db.collection(COLLECTIONS.PLACE_VIDEOS).doc(id)));
      for (const doc of docs) {
        if (!doc.exists) continue;
        const v = doc.data();
        out.set(doc.id, { likeCount: v.likeCount || 0, commentCount: v.commentCount || 0 });
      }
    } catch (error) {
      console.error('[own-activity] moment counts failed:', error.message);
    }
    return out;
  }

  /** The month's counts, streak, most visited place and "on this day". */
  async summary({ userId, month, timezone = 'UTC', now = new Date() }) {
    const tz = validZone(timezone);
    const { key, start, end } = shape.monthBounds(month, { now, timezone: tz });
    const base = this.activities.where('actorId', '==', String(userId));
    const dayStart = shape.zonedMidnight(...shape.localDateKey(new Date(now.getTime() - 365.25 * 86400000), tz).split('-').map((n) => parseInt(n, 10)), tz);
    const dayEnd = new Date(dayStart.getTime() + 86400000);
    const [monthSnap, pastSnap] = await Promise.all([
      base.where('timestamp', '>=', admin.firestore.Timestamp.fromDate(start)).where('timestamp', '<', admin.firestore.Timestamp.fromDate(end))
        .orderBy('timestamp', 'desc').limit(SUMMARY_SCAN).get(),
      base.where('timestamp', '>=', admin.firestore.Timestamp.fromDate(dayStart)).where('timestamp', '<', admin.firestore.Timestamp.fromDate(dayEnd))
        .orderBy('timestamp', 'desc').limit(20).get()
    ]);
    const rows = monthSnap.docs.map((d) => ({ id: d.id, ...d.data() }));
    const pastYearCheckIns = pastSnap.docs.map((d) => d.data()).filter((d) => d.type === 'check_in');
    return { month: key, timezone: tz, ...shape.summarize(rows, { now, timezone: tz, pastYearCheckIns }) };
  }
}

const isoOf = (value) => {
  if (!value) return null;
  if (typeof value.toDate === 'function') return value.toDate().toISOString();
  const d = new Date(value);
  return Number.isNaN(d.getTime()) ? null : d.toISOString();
};

const validZone = (tz) => {
  try { new Intl.DateTimeFormat('en-US', { timeZone: tz }); return tz; } catch (e) { return 'UTC'; }
};

module.exports = new OwnActivityService();
