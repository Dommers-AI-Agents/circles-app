// backend/services/workoutFeedService.js
//
// Workouts shared with the Inner Circle. The client posts a finished
// workout's summary (custom exercise names live only on the phone); the
// feed shows a viewer what the people who put them in their Inner Circle
// have posted — intersected with the viewer's accepted connections, so a
// disconnect revokes the grant with no cleanup ([[inner-circle-privacy-tier]]).
//
// Queries are equality-only (monthKey + userId-in), sorted in memory.
const { getFirestore } = require('../config/firebase');
const { ServiceError } = require('../utils/serviceError');
const { COLLECTIONS } = require('../models/FirestoreModels');
const { getConnectedUserIds, getInnerCircleGrantorIds } = require('../utils/networkAccess');
const { queryInChunks } = require('../utils/firestoreChunks');

class WorkoutFeedError extends ServiceError {}

const NAME_MAX = 80;
const LINE_MAX = 60;
const MAX_EXERCISES = 30;
const MAX_CARDIO = 10;
const MAX_POSTS = 60;
const FEED_DAYS = 45;

const { clean } = require('../utils/text');
const int = (v, max) => (Number.isFinite(Number(v)) ? Math.max(0, Math.min(max, Math.round(Number(v)))) : 0);
const monthKeyOf = (date) => `${date.getUTCFullYear()}-${String(date.getUTCMonth() + 1).padStart(2, '0')}`;

/** Validates and trims the client's summary; never trusts its shape. */
function normalizeSummary(input) {
  if (!input || typeof input !== 'object') throw new WorkoutFeedError(400, 'bad_summary', 'Nothing to share.');
  const name = clean(input.name, NAME_MAX) || 'Workout';
  const startedAt = Date.parse(input.startedAt);
  if (!Number.isFinite(startedAt)) throw new WorkoutFeedError(400, 'bad_summary', 'The workout has no date.');
  const exercises = (Array.isArray(input.exercises) ? input.exercises : []).slice(0, MAX_EXERCISES).map((e) => ({
    name: clean(e && e.name, LINE_MAX) || 'Exercise',
    sets: int(e && e.sets, 99),
    bestSet: clean(e && e.bestSet, LINE_MAX),
    isPR: !!(e && e.isPR)
  }));
  const cardio = (Array.isArray(input.cardio) ? input.cardio : []).slice(0, MAX_CARDIO).map((c) => ({
    name: clean(c && c.name, LINE_MAX) || 'Cardio',
    minutes: int(c && c.minutes, 600),
    detail: clean(c && c.detail, LINE_MAX)
  }));
  if (exercises.length === 0 && cardio.length === 0) throw new WorkoutFeedError(400, 'bad_summary', 'Nothing was logged in this workout.');
  return {
    name,
    startedAt: new Date(startedAt).toISOString(),
    durationSeconds: int(input.durationSeconds, 24 * 3600),
    completedSets: int(input.completedSets, 999),
    exercises,
    cardio,
    prCount: int(input.prCount, 99),
    unit: input.unit === 'kg' ? 'kg' : 'lb'
  };
}

class WorkoutFeedService {
  constructor() {
    this.db = getFirestore();
  }

  get posts() { return this.db.collection(COLLECTIONS.WORKOUT_POSTS); }

  /** One post per finished workout; re-sharing the same workout replaces it. */
  async share({ userId, summary }) {
    const normalized = normalizeSummary(summary);
    const started = new Date(normalized.startedAt);
    const postId = `${userId}_${started.getTime()}`;
    const now = new Date();
    await this.posts.doc(postId).set({
      userId,
      summary: normalized,
      monthKey: monthKeyOf(now),
      createdAt: now.toISOString()
    });
    return { postId, createdAt: now.toISOString() };
  }

  /**
   * Posts by people who granted the viewer Inner Circle access AND are still
   * connected, from this month and last, newest first.
   */
  async feed(viewerId, now = new Date()) {
    const [grantors, connections] = await Promise.all([getInnerCircleGrantorIds(viewerId), getConnectedUserIds(viewerId)]);
    const authors = [...grantors].filter((id) => connections.has(id));
    if (authors.length === 0) return [];
    const previous = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - 1, 1));
    const months = [monthKeyOf(now), monthKeyOf(previous)];
    const cutoff = now.getTime() - FEED_DAYS * 24 * 3600 * 1000;
    const perMonth = await Promise.all(months.map((month) =>
      queryInChunks(authors, (chunk) => this.posts.where('monthKey', '==', month).where('userId', 'in', chunk).get())));
    const rows = [];
    for (const doc of perMonth.flat()) {
      const data = doc.data();
      if (Date.parse(data.createdAt) < cutoff) continue;
      rows.push({ id: doc.id, ...data });
    }
    rows.sort((a, b) => (a.createdAt < b.createdAt ? 1 : -1));
    const top = rows.slice(0, MAX_POSTS);
    const users = await this.usersById([...new Set(top.map((r) => r.userId))]);
    return top.map((r) => ({
      postId: r.id,
      userId: r.userId,
      userName: (users[r.userId] && users[r.userId].displayName) || 'Someone',
      avatarUrl: (users[r.userId] && users[r.userId].profilePicture) || null,
      summary: r.summary,
      createdAt: r.createdAt
    }));
  }

  /** One batched read for the authors on the page instead of a get per user. */
  async usersById(ids) {
    if (ids.length === 0) return {};
    const users = this.db.collection(COLLECTIONS.USERS);
    const docs = await this.db.getAll(...ids.map((id) => users.doc(id)));
    const out = {};
    for (const doc of docs) if (doc.exists) out[doc.id] = doc.data();
    return out;
  }
}

module.exports = Object.assign(new WorkoutFeedService(), { WorkoutFeedError, normalizeSummary, monthKeyOf });
