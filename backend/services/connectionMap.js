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

module.exports = { buildConnectionMap, isLiveConnection, LIVE_STATUSES };
