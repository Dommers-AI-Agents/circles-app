// backend/services/connectionMap.js
const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');
const { normalizeUserId } = require('./idService');

const db = getFirestore();

// Fetch the caller's connections ONCE and index them by the other
// participant's normalized id → { status, direction, connectionId }. Replaces
// the per-candidate pair of connection queries that made user search O(N)
// sequential reads. Outgoing wins over incoming (matches the old precedence).
const buildConnectionMap = async (currentUserId) => {
  const [outgoing, incoming] = await Promise.all([
    db.collection(COLLECTIONS.CONNECTIONS).where('userId', '==', currentUserId).get(),
    db.collection(COLLECTIONS.CONNECTIONS).where('connectedUserId', '==', currentUserId).get()
  ]);
  const map = new Map();
  outgoing.docs.forEach((doc) => {
    const d = doc.data();
    map.set(normalizeUserId(d.connectedUserId), {
      status: d.status,
      direction: d.status === 'pending' ? 'outgoing' : null,
      connectionId: doc.id
    });
  });
  incoming.docs.forEach((doc) => {
    const d = doc.data();
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

module.exports = { buildConnectionMap };
