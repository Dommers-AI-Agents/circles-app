// backend/services/contributionStats.js
//
// "You're 2nd for adding places this month": the numbers behind the
// top-contributor push (milestoneService.checkTopContributors) and the screen
// its tap opens. One definition of the window and the ranking, so the push and
// the screen never disagree.
const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');
const { getConnectedUserIds } = require('../utils/networkAccess');
const { isSameUser, normalizeUserId } = require('./idService');

const db = getFirestore();
const WINDOW_DAYS = 30;
const MAX_PLACES = 24;
const MAX_BOARD = 10;

/** Live places added since `since`, counted per adder. Pure. */
const countByAdder = (places) => {
  const counts = new Map();
  for (const p of places) {
    if (!p || p.deletedAt || !p.addedBy) continue;
    const id = normalizeUserId(p.addedBy);
    counts.set(id, (counts.get(id) || 0) + 1);
  }
  return counts;
};

/**
 * 1-based rank of `userId` among everyone who added a place (ties share the
 * better rank), the leader's count, and how many added anything. Pure.
 */
const rankOf = (counts, userId) => {
  const mine = counts.get(normalizeUserId(userId)) || 0;
  const values = [...counts.values()];
  const leader = values.length ? Math.max(...values) : 0;
  return {
    count: mine,
    rank: mine > 0 ? 1 + values.filter((v) => v > mine).length : null,
    contributors: values.length,
    leaderCount: leader,
    behindFirst: mine > 0 ? Math.max(0, leader - mine) : null
  };
};

/** The top contributors, best first: [[userId, count], ...]. Pure. */
const topContributors = (counts, n = 3) => [...counts.entries()].sort((a, b) => b[1] - a[1]).slice(0, n);

const sinceIso = (now = new Date()) => new Date(now.getTime() - WINDOW_DAYS * 24 * 3600 * 1000).toISOString();

async function recentPlaces(now = new Date()) {
  const snap = await db.collection(COLLECTIONS.PLACES).where('createdAt', '>=', sinceIso(now)).get();
  return snap.docs.map((d) => ({ id: d.id, ...d.data() }));
}

/**
 * The signed-in user's month: count, rank among everyone, a board of them and
 * their connections, and the places they added (newest first).
 */
async function forUser(userId, now = new Date()) {
  const places = await recentPlaces(now);
  const counts = countByAdder(places);
  const standing = rankOf(counts, userId);

  const connections = await getConnectedUserIds(userId);
  const boardIds = [normalizeUserId(userId), ...[...connections].filter((id) => counts.has(normalizeUserId(id)))];
  const uniqueIds = [...new Set(boardIds.map(normalizeUserId))];
  const users = uniqueIds.length ? await db.getAll(...uniqueIds.map((id) => db.collection(COLLECTIONS.USERS).doc(id))) : [];
  const byId = new Map(users.filter((d) => d.exists).map((d) => [d.id, d.data()]));
  const board = uniqueIds
    .map((id) => ({
      userId: id,
      displayName: (byId.get(id) || {}).displayName || 'Someone',
      profilePicture: (byId.get(id) || {}).profilePicture || null,
      count: counts.get(id) || 0,
      isMe: isSameUser(id, userId)
    }))
    .sort((a, b) => b.count - a.count || (a.isMe ? -1 : 1))
    .slice(0, MAX_BOARD);

  const mine = places
    .filter((p) => !p.deletedAt && isSameUser(p.addedBy, userId))
    .sort((a, b) => String(b.createdAt).localeCompare(String(a.createdAt)))
    .slice(0, MAX_PLACES)
    .map((p) => ({
      id: p.id,
      name: p.name || 'Place',
      category: p.category || null,
      photo: (Array.isArray(p.photos) && p.photos.map((x) => (typeof x === 'string' ? x : x && x.url)).find(Boolean)) || null,
      createdAt: p.createdAt
    }));

  return { windowDays: WINDOW_DAYS, ...standing, board, places: mine };
}

module.exports = { WINDOW_DAYS, countByAdder, rankOf, topContributors, recentPlaces, forUser };
