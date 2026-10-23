// backend/services/connectionMap.js
const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');
const { normalizeUserId } = require('./idService');

const db = getFirestore();

// Fetch the caller's connections ONCE and index them by the other
// participant's normalized id → { status, direction, connectionId }. Replaces
// the per-candidate pair of connection queries that made user search O(N)
// sequential reads. Outgoing wins over incoming (matches the old precedence).
// The statuses a connection row can be in while it still means something to
// a client. An account merge folds duplicate rows by tombstoning them
// (deletedAt + status 'merged') rather than deleting, so the merge is
// auditable and reversible — but a tombstone is not a connection. Serving one
// to the app put a status the iOS enum had never heard of into a strictly
// decoded array, which threw away all 73 of a user's connections and left the
// Inner Circle picker blank. Every reader that hands rows to a client goes
// through this.
const LIVE_STATUSES = new Set(['pending', 'accepted', 'blocked', 'following']);
const isLiveConnection = (data) =>
  !!data && !data.deletedAt && data.deletedViaMerge !== true && LIVE_STATUSES.has(data.status);

const buildConnectionMap = async (currentUserId) => {
  const [outgoing, incoming] = await Promise.all([
    db.collection(COLLECTIONS.CONNECTIONS).where('userId', '==', currentUserId).get(),
    db.collection(COLLECTIONS.CONNECTIONS).where('connectedUserId', '==', currentUserId).get()
  ]);
  const map = new Map();
  outgoing.docs.forEach((doc) => {
    const d = doc.data();
    if (!isLiveConnection(d)) return;
    map.set(normalizeUserId(d.connectedUserId), {
      status: d.status,
      direction: d.status === 'pending' ? 'outgoing' : null,
      connectionId: doc.id
    });
  });
  incoming.docs.forEach((doc) => {
    const d = doc.data();
    if (!isLiveConnection(d)) return;
    const other = normalizeUserId(d.userId);
    if (!map.has(other)) {
      map.set(other, {
        status: d.status,
        direction: d.status === 'pending' ? 'incoming' : null,
        connectionId: doc.id
      });
    }
  });
  return map;
};

// One row per person. A pair should have one connection doc, but a few old
// pairs have two (one each way, both accepted: left by a July 2025 merge
// script), and a list built from both directions showed that person twice.
// Keep the row that says the most: blocked, then accepted, then pending, then
// following; on a tie the caller's own row (their bell and view counts live
// there), then the older one. `docs` are Firestore snapshots, already live.
const STATUS_RANK = { blocked: 0, accepted: 1, pending: 2, following: 3 };
const createdMillis = (value) => {
  if (!value) return Infinity;
  if (typeof value.toMillis === 'function') return value.toMillis();
  if (typeof value._seconds === 'number') return value._seconds * 1000;
  const ms = Date.parse(value);
  return Number.isNaN(ms) ? Infinity : ms;
};
const onePerPerson = (docs, callerId) => {
  const best = new Map();
  const beats = (a, b) => {
    const da = a.data(), db_ = b.data();
    const rank = (STATUS_RANK[da.status] ?? 9) - (STATUS_RANK[db_.status] ?? 9);
    if (rank !== 0) return rank < 0;
    const mineA = da.userId === callerId, mineB = db_.userId === callerId;
    if (mineA !== mineB) return mineA;
    return createdMillis(da.createdAt) < createdMillis(db_.createdAt);
  };
  for (const doc of docs) {
    const d = doc.data();
    const other = normalizeUserId(d.userId === callerId ? d.connectedUserId : d.userId);
    if (!other) continue;
    const kept = best.get(other);
    if (!kept || beats(doc, kept)) best.set(other, doc);
  }
  // Keep the incoming order for the rows that survive.
  const keep = new Set(best.values());
  return docs.filter((doc) => keep.has(doc));
};

module.exports = { buildConnectionMap, isLiveConnection, onePerPerson, LIVE_STATUSES };
