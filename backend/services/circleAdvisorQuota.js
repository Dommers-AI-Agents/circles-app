// Spend controls for the circle advisor.
//
// The advisor is the one feature here that costs real money per invocation, and
// a screen somebody can re-open is a screen somebody will re-open. Four limits,
// cheapest first:
//
//   1. Premium gate     — only paying accounts can call it at all.
//   2. Result cache     — unchanged circles never hit the model twice.
//   3. Per-user daily   — bounds one enthusiastic account.
//   4. Global daily     — a kill switch a bug or an abuser can't get past.
//
// The cache does most of the work: circles change rarely, so re-opening the
// screen is free. The counters exist for the cases the cache can't cover.

const crypto = require('crypto');
const { getFirestore } = require('../config/firebase');
const subscriptionLimitService = require('./subscriptionLimitService');

const db = getFirestore();

const COLLECTION = 'circleAdvisorUsage';
const GLOBAL_DOC = '__global';

const PER_USER_DAILY = parseInt(process.env.CIRCLE_ADVISOR_DAILY_RUNS_PER_USER || '5', 10);
const GLOBAL_DAILY = parseInt(process.env.CIRCLE_ADVISOR_DAILY_RUNS_GLOBAL || '200', 10);
const CACHE_TTL_MS = parseInt(process.env.CIRCLE_ADVISOR_CACHE_TTL_MS || String(24 * 60 * 60 * 1000), 10);

/** Statuses that count as paying. Trial included — that's what a trial is for. */
const PREMIUM_STATUSES = ['active', 'trial'];

const today = () => new Date().toISOString().slice(0, 10);

/**
 * Fingerprint of the circle set. Only the fields the advisor actually reasons
 * about — renaming a circle or adding a place changes the answer, so it
 * changes the key; opening the screen twice does not.
 */
const fingerprint = (circles) => {
  const stable = circles
    .map((c) => [c.id, c.name, c.placesCount, (c.topCategories || []).join('|'), (c.topCities || []).join('|')].join('~'))
    .sort()
    .join('\n');
  return crypto.createHash('sha256').update(stable).digest('hex');
};

const isPremium = async (userId) => {
  const data = await subscriptionLimitService.getUserSubscriptionData(userId);
  return PREMIUM_STATUSES.includes(data.subscriptionStatus);
};

/**
 * Everything that must be true before we spend a token, in cost order.
 *
 * Returns one of:
 *   { allowed: false, reason: 'premium_required' }
 *   { allowed: false, reason: 'user_daily_limit' | 'global_daily_limit', limit }
 *   { allowed: true, cached: <advice> }   — serve this, spend nothing
 *   { allowed: true, cacheKey, remaining }
 */
const check = async (userId, circles) => {
  if (!(await isPremium(userId))) {
    return { allowed: false, reason: 'premium_required' };
  }

  const cacheKey = fingerprint(circles);
  const userRef = db.collection(COLLECTION).doc(userId);
  const snapshot = await userRef.get();
  const usage = snapshot.exists ? snapshot.data() : {};

  // A cached answer for an unchanged circle set costs nothing and doesn't
  // consume a run — re-opening the screen should never be rationed.
  if (
    usage.cacheKey === cacheKey &&
    usage.cachedResult &&
    usage.cachedAt &&
    Date.now() - new Date(usage.cachedAt).getTime() < CACHE_TTL_MS
  ) {
    return { allowed: true, cached: usage.cachedResult };
  }

  const day = today();
  const userCount = usage.date === day ? (usage.count || 0) : 0;
  if (userCount >= PER_USER_DAILY) {
    return { allowed: false, reason: 'user_daily_limit', limit: PER_USER_DAILY };
  }

  const globalSnapshot = await db.collection(COLLECTION).doc(GLOBAL_DOC).get();
  const globalUsage = globalSnapshot.exists ? globalSnapshot.data() : {};
  const globalCount = globalUsage.date === day ? (globalUsage.count || 0) : 0;
  if (globalCount >= GLOBAL_DAILY) {
    return { allowed: false, reason: 'global_daily_limit', limit: GLOBAL_DAILY };
  }

  return {
    allowed: true,
    cacheKey,
    remaining: PER_USER_DAILY - userCount - 1
  };
};

/**
 * Records a completed run and caches its result.
 *
 * Called only after the model actually answered — a failed call shouldn't burn
 * somebody's daily allowance for a result they never saw.
 */
const record = async (userId, cacheKey, result) => {
  const day = today();
  const userRef = db.collection(COLLECTION).doc(userId);

  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(userRef);
    const usage = snapshot.exists ? snapshot.data() : {};
    const count = usage.date === day ? (usage.count || 0) : 0;

    transaction.set(userRef, {
      date: day,
      count: count + 1,
      cacheKey,
      cachedResult: result,
      cachedAt: new Date().toISOString()
    }, { merge: true });
  });

  const globalRef = db.collection(COLLECTION).doc(GLOBAL_DOC);
  await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(globalRef);
    const usage = snapshot.exists ? snapshot.data() : {};
    const count = usage.date === day ? (usage.count || 0) : 0;
    transaction.set(globalRef, { date: day, count: count + 1 }, { merge: true });
  });
};

/**
 * Clears a user's cached advice without touching their run count.
 *
 * Called after a merge: the circle set just changed, so the cached answer
 * describes a world that no longer exists. Dropping the cache rather than the
 * counter means the next look is fresh but still costs a run — which is
 * correct, since it genuinely needs a new model call.
 */
const invalidateCache = async (userId) => {
  await db.collection(COLLECTION).doc(userId).set({
    cacheKey: null,
    cachedResult: null,
    cachedAt: null
  }, { merge: true });
};

module.exports = {
  check,
  record,
  invalidateCache,
  fingerprint,
  isPremium,
  PER_USER_DAILY,
  GLOBAL_DAILY,
  PREMIUM_STATUSES
};
