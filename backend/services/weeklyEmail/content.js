// Everything the weekly email shows beyond the summary numbers (Wes,
// 2026-10-19: "It doesn't hurt to add a lot more info that someone can just
// scroll down through. Like info about a few widgets each week, new
// features."). Each part is gathered on its own and a failure just leaves
// that section out — the email never fails because one section did.
const { getFirestore } = require('../../config/firebase');
const { COLLECTIONS } = require('../../models/FirestoreModels');
const { WIDGETS } = require('../../config/widgetCatalog');
const WHATS_NEW = require('../../config/whatsNew');
const TIPS = require('../../config/weeklyTips');
const { normalizePrivacy, PRIVACY } = require('../visibility');
const { allowedAudiences } = require('../activityPrivacy');

/** Where gatherUserStats leaves the week's network saves for the email (never serialized). */
const NETWORK_PLACES = Symbol('networkPlaces');

const APP_STORE_LOOKUP = 'https://itunes.apple.com/lookup?bundleId=com.favcircles.circles&country=us';
const MAX_NETWORK_PLACES = 6;
const WHATS_NEW_DAYS = 30;

// ---------- pure helpers ----------

/** -1 / 0 / 1 for "1.4.0" vs "1.4.1"; missing parts are 0. */
function compareVersions(a, b) {
  const pa = String(a || '0').split('.').map((n) => parseInt(n, 10) || 0);
  const pb = String(b || '0').split('.').map((n) => parseInt(n, 10) || 0);
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    if ((pa[i] || 0) !== (pb[i] || 0)) return (pa[i] || 0) < (pb[i] || 0) ? -1 : 1;
  }
  return 0;
}

/** Weeks since 1970 — the rotation index for widgets and tips. */
const weekIndex = (now) => Math.floor(now.getTime() / (7 * 86400000));

/**
 * Recent features people can actually get: an entry waits until its build is
 * in the App Store, and someone on an older build is told to update.
 */
function whatsNewFor({ userVersion, storeVersion, now = new Date(), entries = WHATS_NEW, limit = 4 }) {
  const cutoff = now.getTime() - WHATS_NEW_DAYS * 86400000;
  return entries
    .filter((e) => Date.parse(e.date) >= cutoff)
    .filter((e) => !e.minVersion || (storeVersion && compareVersions(e.minVersion, storeVersion) <= 0))
    .slice(0, limit)
    .map((e) => ({ ...e, needsUpdate: !!(e.minVersion && userVersion && compareVersions(userVersion, e.minVersion) < 0) }));
}

/** Three widgets a week, rotating, skipping the ones they already use. */
function widgetSpotlight({ usedIds = new Set(), now = new Date(), catalog = WIDGETS, count = 3 }) {
  const ids = Object.keys(catalog).sort();
  const fresh = ids.filter((id) => !usedIds.has(id));
  const pool = fresh.length >= count ? fresh : ids;
  const start = (weekIndex(now) * count) % pool.length;
  const picks = [];
  for (let i = 0; i < Math.min(count, pool.length); i++) picks.push(pool[(start + i) % pool.length]);
  return picks.map((id) => ({ id, ...catalog[id] }));
}

const tipFor = (now = new Date(), tips = TIPS) => tips[weekIndex(now) % tips.length];

/**
 * A friend's save may be shown to this viewer: not private or list-only,
 * not in a private circle, and their "Who can see my activity" lets
 * connections see saved places.
 */
function canShowNetworkSave(place, circle, saverSettings) {
  // A place's own tier: none / "follow the circle" defers to the circle;
  // anything unrecognised is treated as private, as everywhere else
  const hasOwn = place.privacy !== undefined && place.privacy !== null && place.privacy !== '';
  const own = hasOwn ? normalizePrivacy(place.privacy) : null;
  if (hasOwn && (own === null || own === PRIVACY.PRIVATE || own === PRIVACY.INNER_CIRCLE)) return false;
  if (!circle || circle.deletedAt) return false;
  const circleTier = normalizePrivacy(circle.privacy);
  if (circleTier === PRIVACY.PRIVATE || circleTier === PRIVACY.INNER_CIRCLE) return false;
  const allowed = allowedAudiences(saverSettings, 'savedPlaces');
  return !!(allowed.public || allowed.myNetwork);
}

// ---------- gatherers ----------

let storeVersionCache = null;
async function appStoreVersion({ fetcher = fetch } = {}) {
  if (storeVersionCache && Date.now() - storeVersionCache.at < 6 * 3600000) return storeVersionCache.version;
  try {
    const res = await fetcher(APP_STORE_LOOKUP, { signal: AbortSignal.timeout(5000) });
    const body = await res.json();
    const version = body && body.results && body.results[0] ? body.results[0].version : null;
    if (version) storeVersionCache = { version, at: Date.now() };
    return version;
  } catch (e) {
    return storeVersionCache ? storeVersionCache.version : null;
  }
}

async function usedWidgetIds(db, userId) {
  const docId = require('firebase-admin').firestore.FieldPath.documentId();
  const snap = await db.collection(COLLECTIONS.WIDGET_DATA)
    .where(docId, '>=', `${userId}_`).where(docId, '<', `${userId}_`).select().get();
  return new Set(snap.docs.map((d) => d.id.slice(userId.length + 1).split('_')[0]));
}

/** What they did themselves this week. */
async function ownWeek(db, userId, windowStart) {
  const [saves, checkIns] = await Promise.all([
    db.collection(COLLECTIONS.PLACES).where('addedBy', '==', userId).select('createdAt', 'deletedAt').get(),
    db.collection(COLLECTIONS.CHECK_INS).where('userId', '==', userId).select('createdAt').get()
  ]);
  const inWeek = (d) => String(d.data().createdAt || '') >= windowStart;
  return {
    saved: saves.docs.filter((d) => inWeek(d) && !d.data().deletedAt).length,
    checkIns: checkIns.docs.filter(inWeek).length
  };
}

const photoOf = (save, venue) => {
  const first = (list) => (Array.isArray(list) ? list : []).map((p) => (typeof p === 'string' ? p : p && p.url)).find(Boolean);
  return first(save.photos) || (venue && (venue.coverPhotoUrl || first(venue.photos))) || null;
};

/** The week's network saves this viewer may see, newest first, with photo and who saved it. */
async function networkPlacesFor(db, viewerId, candidates) {
  const fresh = (candidates || []).filter((c) => !c.data.deletedAt)
    .sort((a, b) => String(b.data.createdAt).localeCompare(String(a.data.createdAt)))
    .slice(0, 30);
  if (fresh.length === 0) return [];
  const get = async (col, ids) => {
    const unique = [...new Set(ids.filter(Boolean))];
    const docs = unique.length ? await db.getAll(...unique.map((id) => db.collection(col).doc(id))) : [];
    return new Map(docs.filter((d) => d.exists).map((d) => [d.id, d.data()]));
  };
  const [circles, savers, venues] = await Promise.all([
    get(COLLECTIONS.CIRCLES, fresh.map((c) => c.data.circleId)),
    get(COLLECTIONS.USERS, fresh.map((c) => c.data.addedBy)),
    get('globalPlaces', fresh.map((c) => c.data.globalPlaceId))
  ]);
  const out = [];
  for (const { id, data } of fresh) {
    const saver = savers.get(data.addedBy);
    if (!saver || !canShowNetworkSave(data, circles.get(data.circleId), saver.activityPrivacy)) continue;
    const venue = venues.get(data.globalPlaceId);
    out.push({
      id,
      name: (venue && venue.name) || data.name || 'A place',
      category: (venue && venue.category) || data.category || null,
      city: (venue && venue.city) || data.city || null,
      photo: photoOf(data, venue),
      savedBy: saver.displayName || 'A friend',
      rating: Number.isFinite(data.userRating) ? data.userRating : null
    });
    if (out.length >= MAX_NETWORK_PLACES) break;
  }
  return out;
}

/** Events and markets near them, from the Locals tab's own (cached) feed. */
async function localsFor(user) {
  const { effectiveCoords } = require('../userCardEnrichment');
  const coords = await effectiveCoords(user.id, user);
  if (!coords) return null;
  const { getLocalFeed } = require('../nearbyEventsService');
  const feed = await getLocalFeed(coords.latitude, coords.longitude);
  const events = (feed.events || []).slice(0, 3).map((e) => ({
    name: e.name, date: e.startLocalDate, time: e.startLocalTime || null, venue: e.venueName || null,
    image: e.imageUrl || null, url: e.url || null
  }));
  const markets = (feed.markets || []).slice(0, 2).map((m) => ({
    name: m.name, hours: m.hoursSummary || null, image: m.photoUrl || null, address: m.address || null
  }));
  if (events.length === 0 && markets.length === 0) return null;
  return { events, markets, attribution: feed.attribution || null };
}

/** All the extra sections; any that fails is simply left out. */
async function gatherExtras(user, stats, { now = new Date(), db = getFirestore() } = {}) {
  const userId = user.id;
  const settle = (p) => p.then((v) => v, (e) => { console.warn(`[weekly-email] section failed for ${userId}: ${e.message}`); return null; });
  const [own, network, used, storeVersion, locals] = await Promise.all([
    settle(ownWeek(db, userId, stats.windowStart || new Date(now.getTime() - 7 * 86400000).toISOString())),
    settle(networkPlacesFor(db, userId, stats[NETWORK_PLACES])),
    settle(usedWidgetIds(db, userId)),
    settle(appStoreVersion()),
    settle(localsFor(user))
  ]);
  return {
    own,
    networkPlaces: network || [],
    widgets: widgetSpotlight({ usedIds: used || new Set(), now }),
    whatsNew: whatsNewFor({ userVersion: user.appVersion || null, storeVersion, now }),
    locals,
    tip: tipFor(now)
  };
}

module.exports = {
  NETWORK_PLACES, gatherExtras, compareVersions, whatsNewFor, widgetSpotlight, tipFor, canShowNetworkSave, networkPlacesFor
};
