// backend/services/workoutFeedService.js
//
// Shared workouts. The client posts a finished workout's summary (custom
// exercise names live only on the phone) to one audience: all connections,
// or the Inner Circle (optionally one named list). Every share also lands in
// the activity feed as a `workout_shared` row gated to that same audience,
// and the row opens the post (GET /widgets/workouts/posts/:id) where a
// viewer can copy it as a routine. Readers are always intersected with the
// author's accepted connections, so a disconnect revokes access with no
// cleanup ([[inner-circle-privacy-tier]]).
//
// Queries are equality-only (monthKey + userId-in), sorted in memory.
const { getFirestore } = require('../config/firebase');
const { ServiceError } = require('../utils/serviceError');
const { COLLECTIONS } = require('../models/FirestoreModels');
const { getConnectedUserIds, getInnerCircleGrantorLists } = require('../utils/networkAccess');
const { listIdFor } = require('./innerCircleLists');
const { queryInChunks } = require('../utils/firestoreChunks');

class WorkoutFeedError extends ServiceError {}

const NAME_MAX = 80;
const LINE_MAX = 60;
const MAX_EXERCISES = 30;
const MAX_CARDIO = 10;
const MAX_ROUTINE = 30;
const AUDIENCES = ['connections', 'innerCircle'];
const MAX_POSTS = 60;
const FEED_DAYS = 45;

const { clean } = require('../utils/text');
const crypto = require('crypto');
const LINK_BASE = 'https://api.favcircles.com/app/workout/';
// A link token is 22 url-safe characters; a post id is `${uid}_${ms}`
const isLinkToken = (id) => /^[A-Za-z0-9_-]{22}$/.test(String(id || ''));
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
  // What a viewer copies as their own routine: exercise identity plus the
  // opening working set. Older app versions don't send it.
  const routine = (Array.isArray(input.routine) ? input.routine : []).slice(0, MAX_ROUTINE).map((r) => ({
    exerciseId: clean(r && r.exerciseId, LINE_MAX) || null,
    name: clean(r && r.name, LINE_MAX) || 'Exercise',
    muscleGroup: clean(r && r.muscleGroup, 30) || 'Other',
    sets: Math.max(1, int(r && r.sets, 20)),
    reps: int(r && r.reps, 200),
    weight: Number.isFinite(Number(r && r.weight)) && Number(r.weight) > 0 ? Math.min(2000, Number(r.weight)) : null
  }));
  return {
    name,
    startedAt: new Date(startedAt).toISOString(),
    durationSeconds: int(input.durationSeconds, 24 * 3600),
    completedSets: int(input.completedSets, 999),
    exercises,
    cardio,
    prCount: int(input.prCount, 99),
    unit: input.unit === 'kg' ? 'kg' : 'lb',
    routine
  };
}

class WorkoutFeedService {
  constructor() {
    this.db = getFirestore();
  }

  get posts() { return this.db.collection(COLLECTIONS.WORKOUT_POSTS); }
  get links() { return this.db.collection(COLLECTIONS.WORKOUT_LINKS); }

  /**
   * One post per finished workout; re-sharing the same workout replaces it
   * (and doesn't add a second feed row). `audience` is 'connections' or
   * 'innerCircle' (the default, as before audiences existed); for the Inner
   * Circle, `audienceListId` names one list, none means any of them.
   */
  async share({ userId, summary, audience = 'innerCircle', audienceListId = null, onFirstShare = null, now = new Date() }) {
    const normalized = normalizeSummary(summary);
    const started = new Date(normalized.startedAt);
    const postId = `${userId}_${started.getTime()}`;
    const chosen = AUDIENCES.includes(audience) ? audience : 'innerCircle';
    const listId = chosen === 'innerCircle' ? listIdFor('innerCircle', audienceListId) : null;
    const ref = this.posts.doc(postId);
    const previous = await ref.get();
    const existed = previous.exists;
    const linkToken = existed ? previous.data().linkToken : null;
    await ref.set({
      userId,
      summary: normalized,
      audience: chosen,
      audienceListId: listId,
      monthKey: monthKeyOf(now),
      createdAt: now.toISOString(),
      // A text-message link made earlier keeps working
      ...(linkToken ? { linkToken } : {})
    });
    if (!existed && onFirstShare) {
      // Best effort: the post is saved either way
      try { await onFirstShare({ postId, summary: normalized, audience: chosen, audienceListId: listId }); } catch (e) {
        console.error('[workout-feed] activity row failed', e.message);
      }
    }
    return { postId, audience: chosen, audienceListId: listId, createdAt: now.toISOString() };
  }

  /**
   * Whether `viewerId` may see a post: the author always; otherwise only a
   * current connection, and for an Inner Circle post only someone the author
   * put on (that list of) their Inner Circle.
   */
  async canView(post, viewerId) {
    if (String(post.userId) === String(viewerId)) return true;
    // Shared only by link: opened through the link, never through the feed
    if (post.audience === 'link') return false;
    // Both reads at once: in sequence they made a friend's tap ~1.2 s
    const needsLists = (post.audience || 'innerCircle') !== 'connections';
    const [connections, grantors] = await Promise.all([
      getConnectedUserIds(viewerId),
      needsLists ? getInnerCircleGrantorLists(viewerId) : Promise.resolve(null)
    ]);
    if (!connections.has(post.userId)) return false;
    if (!needsLists) return true;
    const lists = grantors.get(post.userId);
    if (!lists) return false;
    return !post.audienceListId || lists.has(post.audienceListId);
  }

  /**
   * A link for texting a finished workout: anyone holding it may view that
   * one workout (and copy it), signed in or not. The workout is saved as a
   * post if it wasn't shared to the feed — audience 'link', which no feed
   * shows — and a re-share of the same workout reuses its link.
   */
  async createLink({ userId, summary, now = new Date() }) {
    const normalized = normalizeSummary(summary);
    const postId = `${userId}_${new Date(normalized.startedAt).getTime()}`;
    const ref = this.posts.doc(postId);
    const snap = await ref.get();
    let token = snap.exists ? snap.data().linkToken : null;
    if (!snap.exists) {
      await ref.set({
        userId, summary: normalized, audience: 'link', audienceListId: null,
        monthKey: monthKeyOf(now), createdAt: now.toISOString()
      });
    } else if (snap.data().audience === 'link') {
      // Edited after the first link: the link shows the latest
      await ref.set({ summary: normalized }, { merge: true });
    }
    if (!token) {
      token = crypto.randomBytes(16).toString('base64url');
      await this.links.doc(token).set({ postId, userId, createdAt: now.toISOString() });
      await ref.set({ linkToken: token }, { merge: true });
    }
    return { token, postId, url: LINK_BASE + token };
  }

  /** The workout behind a link token, or null. */
  async postByLink(token) {
    if (!isLinkToken(token)) return null;
    const link = await this.links.doc(String(token)).get();
    if (!link.exists) return null;
    const doc = await this.posts.doc(String(link.data().postId)).get();
    return doc.exists ? doc : null;
  }

  /**
   * One post, for the feed row's detail view or a texted link (`postId` may
   * be a link token). 404 when missing or not theirs to see.
   */
  async getPost(postId, viewerId) {
    let doc = await this.posts.doc(String(postId)).get();
    let viaLink = false;
    if (!doc.exists) {
      doc = await this.postByLink(postId);
      viaLink = !!doc;
    }
    if (!doc || !doc.exists || (!viaLink && !(await this.canView(doc.data(), viewerId)))) {
      throw new WorkoutFeedError(404, 'not_found', 'This workout isn\'t available.');
    }
    const post = doc.data();
    const users = await this.usersById([post.userId]);
    const author = users[post.userId] || {};
    return {
      postId: doc.id,
      userId: post.userId,
      userName: author.displayName || 'Someone',
      avatarUrl: author.profilePicture || null,
      summary: post.summary,
      createdAt: post.createdAt
    };
  }

  /**
   * Posts from the viewer's connections that they may see — shared with all
   * connections, or with an Inner Circle the viewer is on — from this month
   * and last, newest first.
   */
  async feed(viewerId, now = new Date()) {
    const [lists, connections] = await Promise.all([getInnerCircleGrantorLists(viewerId), getConnectedUserIds(viewerId)]);
    const authors = [...connections];
    const allowed = (row) => {
      if (row.audience === 'link') return false;
      if (row.audience === 'connections') return true;
      const granted = lists.get(row.userId);
      // A post that named a list is for that list only.
      return !!granted && (!row.audienceListId || granted.has(row.audienceListId));
    };
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
      if (!allowed(data)) continue;
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
