// backend/services/venueInsights.js
//
// A store's Insights (Wes, 2026-11-09): the numbers owners pay an analytics
// tool for, from what FavCircles already records about the store. Business
// only. One pure fold (`computeInsights`) over the store's ledger, customer
// buckets, saves and comments; `getInsights` loads those and caches the
// result on the venue doc for an hour. A stale answer is served while a fresh
// one is computed, so the page never waits on the fold.
//
//   * Customers: new vs returning in the period, repeat rate, regulars (3+
//     purchases), lapsed (no purchase in 30 days), busiest hours and days in
//     the store's own time.
//   * Offers: which rewards were redeemed in the period, most first.
//   * Score: the FavCircles score — the average 0–10 rating across saves of
//     the store, how many savers recommend it (7 or more), the trend against
//     the 30 days before, and the latest ratings — shown beside the Google
//     rating. Both stay (memory: reviews-favcircles-first-keep-google).
//   * Comments: how many this period and how many still wait for a word from
//     the team (a reply by the owner or a manager counts as answered).
const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');
const { GLOBAL_COLLECTIONS } = require('../models/GlobalPlace');
const { STICKER_COLLECTIONS } = require('../models/StickerModels');
const { ServiceError } = require('../utils/serviceError');
const { localClock } = require('../utils/localClock');
const { isSameUser } = require('./idService');

const RANGE_DAYS = { '30d': 30, '90d': 90, '12m': 365 };
const DEFAULT_RANGE = '30d';
const CACHE_TTL_MS = 60 * 60 * 1000;
const LAPSED_DAYS = 30;
const REGULAR_PURCHASES = 3;
const RECOMMEND_MIN = 7;
const TREND_DAYS = 30;
const RECENT_RATINGS = 5;
const AWAITING_LISTED = 10;
const MAX_EVENTS = 5000;

const DAY_MS = 24 * 60 * 60 * 1000;
const db = () => getFirestore();

const parseRange = (range) => {
  const key = range ? String(range) : DEFAULT_RANGE;
  if (!RANGE_DAYS[key]) throw new ServiceError(400, 'invalid_range', 'Pick 30d, 90d or 12m.');
  return key;
};

const average = (numbers) => {
  if (!numbers.length) return null;
  return Math.round((numbers.reduce((sum, n) => sum + n, 0) / numbers.length) * 10) / 10;
};

const pct = (part, whole) => (whole > 0 ? Math.round((part / whole) * 100) : null);

const isVisit = (event) => event.type === 'venue_visit';
const isRedemption = (event) => event.type === 'redemption' && event.status !== 'cancelled';

/**
 * The fold. Pure, so the rules are table-tested: `events` are the store's
 * reward events since `since`; `customers` are `storeCustomers.listCustomers`
 * rows (all time); `saves` the thin save docs of the store (addedBy,
 * userRating, userRatedAt); `comments` every placeComments row for the store,
 * replies included.
 */
function computeInsights({
  range, since, now = new Date(), timeZone = null,
  events = [], customers = [], saves = [], comments = [],
  teamIds = [], google = null, followersCount = 0,
  venue = null, couponClaims = []
}) {
  const nowMs = now.getTime();
  const sinceIso = since.toISOString();
  const lapsedBefore = new Date(nowMs - LAPSED_DAYS * DAY_MS).toISOString();
  const inTeam = (userId) => teamIds.some((id) => isSameUser(id, userId));

  // --- Customers ----------------------------------------------------------
  const visits = events.filter(isVisit);
  const visitsByUser = new Map();
  visits.forEach((e) => visitsByUser.set(String(e.userId), (visitsByUser.get(String(e.userId)) || 0) + 1));
  const bucketByUser = new Map(customers.map((c) => [String(c.user && c.user.id), c]));

  let newCustomers = 0;
  visitsByUser.forEach((count, userId) => {
    const bucket = bucketByUser.get(userId);
    // Every purchase they ever made falls inside the period: new this period
    if (!bucket || (bucket.purchases || 0) <= count) newCustomers += 1;
  });
  const active = customers.filter((c) => !c.removed && (c.purchases || 0) >= 1);
  const repeaters = active.filter((c) => (c.purchases || 0) >= 2);
  const regulars = active.filter((c) => (c.purchases || 0) >= REGULAR_PURCHASES);
  const lapsed = active.filter((c) => c.lastScanAt && String(c.lastScanAt) < lapsedBefore);

  // --- Busiest times (store-local) -----------------------------------------
  const hours = new Array(24).fill(0);
  const days = new Array(7).fill(0);
  visits.forEach((e) => {
    const at = new Date(e.createdAt);
    if (Number.isNaN(at.getTime())) return;
    const clock = localClock(timeZone, at);
    hours[clock.hour] += 1;
    days[clock.weekday] += 1;
  });

  // --- Offers ---------------------------------------------------------------
  const redemptions = events.filter(isRedemption);
  const byOffer = new Map();
  redemptions.forEach((e) => {
    const key = e.offerId || e.offerTitle || 'other';
    const row = byOffer.get(key) || { offerId: e.offerId || null, title: e.offerTitle || 'Reward', redemptions: 0 };
    row.redemptions += 1;
    byOffer.set(key, row);
  });
  const offers = [...byOffer.values()].sort((a, b) => b.redemptions - a.redemptions);

  // --- FavCircles score -------------------------------------------------------
  const rated = saves.filter((s) => typeof s.userRating === 'number' && s.userRating >= 0 && s.userRating <= 10);
  const ratings = rated.map((s) => s.userRating);
  const recentSince = new Date(nowMs - TREND_DAYS * DAY_MS).toISOString();
  const priorSince = new Date(nowMs - 2 * TREND_DAYS * DAY_MS).toISOString();
  const ratedAt = (s) => String(s.userRatedAt || s.createdAt || '');
  const recentAvg = average(rated.filter((s) => ratedAt(s) >= recentSince).map((s) => s.userRating));
  const priorAvg = average(rated.filter((s) => ratedAt(s) >= priorSince && ratedAt(s) < recentSince).map((s) => s.userRating));
  const trend = recentAvg !== null && priorAvg !== null ? Math.round((recentAvg - priorAvg) * 10) / 10 : null;
  const recent = [...rated]
    .filter((s) => ratedAt(s))
    .sort((a, b) => ratedAt(b).localeCompare(ratedAt(a)))
    .slice(0, RECENT_RATINGS)
    .map((s) => ({ rating: s.userRating, at: ratedAt(s) }));
  const recommend = ratings.filter((r) => r >= RECOMMEND_MIN).length;

  // --- Comments -------------------------------------------------------------
  const visible = comments.filter((c) => c.moderationStatus !== 'removed' && c.moderationStatus !== 'under_review');
  const topLevel = visible.filter((c) => !c.parentCommentId);
  const teamRepliedTo = new Set(
    visible.filter((c) => c.parentCommentId && inTeam(c.userId)).map((c) => String(c.parentCommentId))
  );
  const awaiting = topLevel
    .filter((c) => !inTeam(c.userId) && !teamRepliedTo.has(String(c.id)))
    .sort((a, b) => String(b.createdAt || '').localeCompare(String(a.createdAt || '')));

  return {
    range,
    since: sinceIso,
    computedAt: now.toISOString(),
    customers: {
      visits: visits.length,
      visitors: visitsByUser.size,
      newCustomers,
      returningCustomers: visitsByUser.size - newCustomers,
      total: active.length,
      repeatRatePct: pct(repeaters.length, active.length),
      regulars: regulars.length,
      lapsed: lapsed.length,
      // Bring a friend (services/storeReferrals): first purchases that paid an inviter, this period
      referred: events.filter((e) => e.type === 'referral' && e.role === 'referrer').length
    },
    busiest: { hours, days },
    redemptions: redemptions.length,
    offers,
    score: {
      average: average(ratings),
      ratings: ratings.length,
      recommend,
      recommendPct: pct(recommend, ratings.length),
      trend,
      recent,
      google: google && typeof google.rating === 'number'
        ? { rating: google.rating, total: google.userRatingsTotal || 0 }
        : null
    },
    comments: {
      total: topLevel.length,
      inPeriod: topLevel.filter((c) => String(c.createdAt || '') >= sinceIso).length,
      awaitingReply: awaiting.length,
      awaiting: awaiting.slice(0, AWAITING_LISTED).map((c) => ({
        id: c.id, createdAt: c.createdAt || null, text: String(c.text || '').slice(0, 140), userId: c.userId || null
      }))
    },
    saves: new Set(saves.map((s) => s.addedBy).filter(Boolean)).size,
    followers: followersCount || 0,
    // Coupons (services/storeCoupons): per flyer coupon, scans → claims →
    // used, new customers, and who came in after claiming (all time)
    campaigns: venue ? require('./storeCoupons').campaignRows({ venue, claims: couponClaims, visits, now }) : [],
    // Posts (2026-11-14): what each offer, announcement or event reached
    // ("sent to N"), and how many distinct customers came in after it went
    posts: venue ? postReach(venue, visits) : []
  };
}

/** Every offer, announcement and event that alerted followers, newest first. Pure. */
function postReach(venue, visits) {
  const rows = [];
  (venue.offers || []).forEach((o) => rows.push({ id: o.offerId, kind: 'offer', title: o.title, alerted: o.alerted, createdAt: o.createdAt || null }));
  (venue.announcements || []).forEach((a) => rows.push({ id: a.announcementId, kind: a.event ? 'event' : 'announcement', title: a.title, alerted: a.alerted, createdAt: a.createdAt || null }));
  return rows
    .filter((r) => r.alerted && typeof r.alerted.sent === 'number')
    .map((r) => ({
      id: r.id, kind: r.kind, title: r.title, at: r.alerted.at || r.createdAt,
      sentTo: r.alerted.sent, audience: r.alerted.audience || 0,
      cameIn: new Set(visits.filter((v) => String(v.createdAt || '') > String(r.alerted.at || r.createdAt || '')).map((v) => String(v.userId))).size
    }))
    .sort((a, b) => String(b.at || '').localeCompare(String(a.at || '')))
    .slice(0, 20);
}

/** Everything the fold needs, read once. */
async function loadInputs(venue, since) {
  const { venueGlobalPlaceId, venueManagerIds } = require('./venueHelpers');
  const storeCustomers = require('./storeCustomers');
  const globalPlaceId = await venueGlobalPlaceId(venue);

  const eventsQuery = db().collection(STICKER_COLLECTIONS.REWARD_EVENTS)
    .where('venueId', '==', venue.venueId)
    .where('createdAt', '>=', since.toISOString())
    .orderBy('createdAt', 'desc')
    .limit(MAX_EVENTS);
  const [eventsSnap, customers, savesSnap, commentsSnap, globalDoc, ownerDoc, couponClaims] = await Promise.all([
    eventsQuery.get(),
    storeCustomers.listCustomers(venue),
    globalPlaceId
      ? db().collection(COLLECTIONS.PLACES).where('globalPlaceId', '==', globalPlaceId).where('deletedAt', '==', null)
        .select('addedBy', 'userRating', 'userRatedAt', 'createdAt').get()
      : Promise.resolve({ docs: [] }),
    globalPlaceId
      ? db().collection('placeComments').where('globalPlaceId', '==', globalPlaceId).get()
      : Promise.resolve({ docs: [] }),
    globalPlaceId ? db().collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).doc(globalPlaceId).get() : Promise.resolve(null),
    // The store has no time zone of its own; the owner is at the store, so theirs is the next best
    venue.timeZone || !venue.ownerUserId ? Promise.resolve(null) : db().collection(COLLECTIONS.USERS).doc(String(venue.ownerUserId)).get(),
    require('./storeCoupons').liveCoupons(venue).length
      ? require('./storeCoupons').claimsForVenue(venue.venueId).catch(() => [])
      : Promise.resolve([])
  ]);
  const globalData = globalDoc && globalDoc.exists ? globalDoc.data() : {};
  return {
    events: eventsSnap.docs.map((d) => ({ id: d.id, ...d.data() })),
    customers,
    saves: savesSnap.docs.map((d) => d.data()),
    comments: commentsSnap.docs.map((d) => ({ id: d.id, ...d.data() })),
    teamIds: [venue.ownerUserId, ...venueManagerIds(venue)].filter(Boolean),
    google: (globalData.googleData && typeof globalData.googleData.rating === 'number') ? globalData.googleData : null,
    followersCount: globalData.followersCount || 0,
    venue,
    couponClaims,
    timeZone: venue.timeZone || (ownerDoc && ownerDoc.exists && ownerDoc.data().notificationPreferences && ownerDoc.data().notificationPreferences.timezone) || null
  };
}

async function compute(venue, range, now = new Date()) {
  const since = new Date(now.getTime() - RANGE_DAYS[range] * DAY_MS);
  const inputs = await loadInputs(venue, since);
  return computeInsights({ range, since, now, ...inputs });
}

async function store(venue, range, data) {
  await db().collection(STICKER_COLLECTIONS.STICKER_VENUES).doc(venue.venueId)
    .update(`insightsCache.${range}`, { at: data.computedAt, data })
    .catch((error) => console.warn(`⚠️ insights cache write failed for ${venue.venueId}: ${error.message}`));
}

const refreshing = new Set(); // `${venueId}:${range}` while a background refresh runs

/**
 * The store's insights for `range` ('30d' | '90d' | '12m'). Fresh from the
 * venue's cache when under an hour old; a stale cache is answered at once
 * and refreshed behind the response; nothing cached computes now.
 */
async function getInsights(venue, range, now = new Date()) {
  const key = parseRange(range);
  const cached = venue.insightsCache && venue.insightsCache[key];
  if (cached && cached.at && cached.data) {
    const age = now.getTime() - new Date(cached.at).getTime();
    if (age < CACHE_TTL_MS) return { ...cached.data, stale: false };
    const lock = `${venue.venueId}:${key}`;
    if (!refreshing.has(lock)) {
      refreshing.add(lock);
      compute(venue, key).then((data) => store(venue, key, data))
        .catch((error) => console.error(`❌ insights refresh failed for ${venue.venueId}: ${error.message}`))
        .finally(() => refreshing.delete(lock));
    }
    return { ...cached.data, stale: true };
  }
  const data = await compute(venue, key, now);
  await store(venue, key, data);
  return { ...data, stale: false };
}

/** The two lines the monthly report email adds: score and repeat rate. Never throws. */
async function reportSummary(venue) {
  try {
    const data = await getInsights(venue, DEFAULT_RANGE);
    const campaigns = data.campaigns || [];
    const posts = data.posts || [];
    return {
      favScore: data.score.average,
      ratings: data.score.ratings,
      googleRating: data.score.google ? data.score.google.rating : null,
      repeatRatePct: data.customers.repeatRatePct,
      // Coupons and posts (2026-11-14), for the monthly report's two extra lines
      coupons: campaigns.length ? {
        count: campaigns.length,
        claimed: campaigns.reduce((n, c) => n + (c.claims || 0), 0),
        used: campaigns.reduce((n, c) => n + (c.used || 0), 0),
        newCustomers: campaigns.reduce((n, c) => n + (c.newCustomers || 0), 0)
      } : null,
      posts: posts.length ? {
        count: posts.length,
        sentTo: posts.reduce((n, p) => n + (p.sentTo || 0), 0),
        cameIn: posts.reduce((n, p) => n + (p.cameIn || 0), 0)
      } : null
    };
  } catch (error) {
    console.warn(`⚠️ insights summary skipped for ${venue.venueName}: ${error.message}`);
    return null;
  }
}

module.exports = {
  computeInsights, getInsights, reportSummary, parseRange, postReach,
  RANGE_DAYS, CACHE_TTL_MS, LAPSED_DAYS, REGULAR_PURCHASES, RECOMMEND_MIN
};
