// backend/services/peopleRowStats.js
// What the people row needs to know about each person: when they last did
// something, and how many places they have. Two small queries per user, a
// batch of users at a time so a 70-person row stays under a second.
//
// "Last did something" is their newest activity-feed row (a place added, a
// check-in, a moment, a comment, a like) — the `activities` collection is
// written for every one of those, so it is the one place that knows. The
// earlier signal, "a place created in the last 7 days", missed check-ins
// and moments entirely and matched nothing whose createdAt was stored as a
// string, so the whole row was ranked on place counts alone.
const { COLLECTIONS } = require('../models/FirestoreModels');
const { chunk } = require('../utils/firestoreChunks');
const { RECENT_DAYS } = require('./peopleRowScore');

const USERS_PER_BATCH = 20;

const toDate = (value) => {
  if (!value) return null;
  if (typeof value.toDate === 'function') return value.toDate();
  const d = value instanceof Date ? value : new Date(value);
  return Number.isNaN(d.getTime()) ? null : d;
};

const statsFor = async (db, userId) => {
  const [latest, total] = await Promise.all([
    db.collection(COLLECTIONS.ACTIVITIES).where('actorId', '==', userId).orderBy('timestamp', 'desc').limit(1).get(),
    db.collection(COLLECTIONS.PLACES).where('addedBy', '==', userId).count().get()
  ]);
  const row = latest.empty ? null : latest.docs[0].data();
  return {
    lastActivityAt: row ? toDate(row.timestamp || row.createdAt) : null,
    totalPlaces: total.data().count || 0
  };
};

/** Returns Map<userId, { lastActivityAt: Date|null, totalPlaces, hasRecentPlace }>. */
const peopleRowStats = async (db, userIds, now = Date.now()) => {
  const out = new Map();
  for (const batch of chunk(userIds, USERS_PER_BATCH)) {
    const rows = await Promise.all(batch.map((id) => statsFor(db, id)));
    batch.forEach((id, i) => {
      const r = rows[i];
      // hasRecentPlace is what older clients read as "active this week".
      const hasRecentPlace = !!(r.lastActivityAt && now - r.lastActivityAt.getTime() <= RECENT_DAYS * 24 * 60 * 60 * 1000);
      out.set(id, { ...r, hasRecentPlace });
    });
  }
  return out;
};

module.exports = { peopleRowStats, USERS_PER_BATCH };
