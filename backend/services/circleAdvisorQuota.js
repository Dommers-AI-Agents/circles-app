// Spend controls for the circle advisor.
//
// The advisor is the one feature here that costs real money per invocation, and
// a screen somebody can re-open is a screen somebody will re-open. Four limits,
// cheapest first:
//
//   1. Premium gate     — only paying accounts can call it at all.
//   2. Result cache     — unchanged circles never hit the model twice.
//   3. Per-user weekly  — 2 runs per rolling 7 days bounds one account.
//   4. Global daily     — a kill switch a bug or an abuser can't get past.
//
// The cache does most of the work: circles change rarely, so re-opening the
// screen is free. The counters exist for the cases the cache can't cover.

const crypto = require('crypto');
const admin = require('firebase-admin');
const { getFirestore } = require('../config/firebase');
const subscriptionLimitService = require('./subscriptionLimitService');

const db = getFirestore();

const COLLECTION = 'circleAdvisorUsage';
const GLOBAL_DOC = '__global';

const WEEK_MS = 7 * 24 * 60 * 60 * 1000;
const PER_USER_WEEKLY = parseInt(process.env.CIRCLE_ADVISOR_WEEKLY_RUNS_PER_USER || '2', 10);
const GLOBAL_DAILY = parseInt(process.env.CIRCLE_ADVISOR_DAILY_RUNS_GLOBAL || '200', 10);
// As long as the weekly window: with two runs a week, an unchanged circle set
// re-asked after a day must not spend one of them.
const CACHE_TTL_MS = parseInt(process.env.CIRCLE_ADVISOR_CACHE_TTL_MS || String(WEEK_MS), 10);

/** Statuses that count as paying. Trial included — that's what a trial is for. */
const PREMIUM_STATUSES = ['active', 'trial'];

const today = () => new Date().toISOString().slice(0, 10);

/** Run timestamps (ISO) inside the rolling week ending at `now`, oldest first. */
const runsThisWeek = (usage, now = Date.now()) =>
  (usage.runTimes || [])
    .filter((t) => now - new Date(t).getTime() < WEEK_MS)
    .sort();

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
 *   { allowed: false, reason: 'user_weekly_limit', limit, nextAvailableAt }
 *   { allowed: false, reason: 'global_daily_limit', limit }
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
  const weekRuns = runsThisWeek(usage);
  if (weekRuns.length >= PER_USER_WEEKLY) {
    // The oldest run in the window is the next to age out.
    const nextAvailableAt = new Date(new Date(weekRuns[0]).getTime() + WEEK_MS).toISOString();
    return { allowed: false, reason: 'user_weekly_limit', limit: PER_USER_WEEKLY, nextAvailableAt };
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
    remaining: PER_USER_WEEKLY - weekRuns.length - 1
  };
};

/**
 * Records a completed run, caches its result, and adds what it cost to the
 * user's and the global spend counters (daily and lifetime, in cents).
 *
 * Called only after the model actually answered — a failed call shouldn't burn
 * somebody's daily allowance for a result they never saw.
 */
const record = async (userId, cacheKey, result, cents = 0) => {
  const day = today();
  const increment = admin.firestore.FieldValue.increment;

  const bump = (ref, extra = {}) => db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(ref);
    const usage = snapshot.exists ? snapshot.data() : {};
    const sameDay = usage.date === day;
    transaction.set(ref, {
      date: day,
      count: (sameDay ? (usage.count || 0) : 0) + 1,
      spendCents: (sameDay ? (usage.spendCents || 0) : 0) + cents,
      totalRuns: increment(1),
      totalSpendCents: increment(cents),
      ...extra
    }, { merge: true });
  });

  const userRef = db.collection(COLLECTION).doc(userId);
  const userSnapshot = await userRef.get();
  const runTimes = [
    ...runsThisWeek(userSnapshot.exists ? userSnapshot.data() : {}),
    new Date().toISOString()
  ];

  await bump(userRef, {
    runTimes,
    cacheKey,
    cachedResult: result,
    cachedAt: new Date().toISOString()
  });
  await bump(db.collection(COLLECTION).doc(GLOBAL_DOC));
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
  PER_USER_WEEKLY,
  GLOBAL_DAILY,
  PREMIUM_STATUSES
};
