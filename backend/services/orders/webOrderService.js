// backend/services/orders/webOrderService.js — a store's public ordering
// page, order.favcircles.com/<slug> (Wes, 2026-10-28): the same menu and
// the same order queue as the app, for people without the app. Guest
// checkout (name + phone, email optional); the order's status link carries
// a signed token that can only ever read or cancel that one order.
const jwt = require('jsonwebtoken');
const { jwtSecret } = require('../../config/secrets');
const { getFirestore } = require('../../config/firebase');
const { ServiceError } = require('../../utils/serviceError');
const { GLOBAL_COLLECTIONS } = require('../../models/GlobalPlace');
const { isVenueBusinessLive } = require('../ownerSubscriptionService');
const dailyBudget = require('../dailyBudget');
const slugs = require('../venueSlugService');
const { hasMenu, offeringsLabel } = require('../venueStorefront');
const { formatHours } = require('../../utils/hoursText');
const rules = require('./orderRules');
const orders = require('./orderService');
const { cleanGuest, guestKeyFor, GUEST_LIMITS } = require('./guestRules');

const { OPEN } = rules;
const TOKEN_PURPOSE = 'web_order';
const TOKEN_TTL = '30d';

const secret = () => jwtSecret();

/** Which photo fronts the page: the owner's cover, else the first photo. */
const coverPhotoOf = (place) => {
  if (!place) return null;
  if (place.coverPhotoUrl) return place.coverPhotoUrl;
  const first = (place.photos || [])[0];
  return typeof first === 'string' ? first : (first && first.url) || null;
};

/**
 * The store behind a slug, or null when there's no page to show (unknown
 * slug, store gone, not on Business, no menu). A retired alias answers
 * { redirectTo } so old links still land.
 */
async function pageFor(slug, { db = getFirestore() } = {}) {
  const hit = await slugs.resolve(slug, { db });
  if (!hit) return null;
  const venue = await orders.loadVenue(db, hit.venueId).catch(() => null);
  if (!venue || venue.active === false) return null;
  if (hit.retired && venue.slug && venue.slug !== slug) return { redirectTo: venue.slug };
  if (!venue.slug || venue.slug !== slug) return null;
  const live = await isVenueBusinessLive(venue);
  // Every Business store has a page (Wes, 2026-11-09: it is the store's
  // website); the menu and ordering are sections of it when they exist
  if (!live) return null;
  let place = null;
  if (venue.globalPlaceId) {
    const doc = await db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).doc(venue.globalPlaceId).get().catch(() => null);
    place = doc && doc.exists ? doc.data() : null;
  }
  return { venue, place, live, ordering: rules.orderingFor(venue, { live }), isTestStore: venue.isTestStore === true };
}

const MAX_PHOTOS = 8;
const DESCRIPTION_MAX = 600;

/** The store's public photos, cover first, as URLs. */
const photosOf = (place) => {
  if (!place) return [];
  const list = (place.photos || [])
    .filter((p) => p && (typeof p === 'string' || (p.url && !p.removedAt && !p.isPrivate && p.hidden !== true)))
    .map((p) => (typeof p === 'string' ? p : p.url));
  const cover = coverPhotoOf(place);
  const ordered = cover ? [cover, ...list.filter((u) => u !== cover)] : list;
  return [...new Set(ordered)].slice(0, MAX_PHOTOS);
};

/** Live announcements (not expired), events first by date. */
const announcementsOf = (venue, now = new Date()) => {
  const nowIso = now.toISOString();
  return (venue.announcements || [])
    .filter((a) => a && a.title && (!a.expiresAt || String(a.expiresAt) > nowIso))
    .filter((a) => !a.event || !a.event.endsAt || String(a.event.endsAt) > nowIso || !a.event.startsAt || String(a.event.startsAt) > nowIso)
    .map((a) => ({
      title: a.title, message: a.message || null,
      event: a.event ? { startsAt: a.event.startsAt || null, localDate: a.event.localDate || null, localTime: a.event.localTime || null, isFree: a.event.isFree === true } : null
    }))
    .sort((a, b) => (a.event ? 0 : 1) - (b.event ? 0 : 1));
};

/** The store's FavCircles score and Google rating, from the hourly Insights cache (never computed on a page view). */
const scoreOf = (venue, place) => {
  const cached = venue.insightsCache && venue.insightsCache['30d'] && venue.insightsCache['30d'].data;
  const score = cached && cached.score;
  const g = (place && place.googleData) || {};
  const google = typeof g.rating === 'number' ? { rating: g.rating, total: g.userRatingsTotal || 0 } : null;
  if (!score && !google) return null;
  return {
    average: score && typeof score.average === 'number' ? score.average : null,
    ratings: (score && score.ratings) || 0,
    recommend: (score && score.recommend) || 0,
    google
  };
};

/** Earn here: the rate and the first reward, while the loyalty program is live. */
const earnOf = async (venue) => {
  const { venueLoyaltyStatus } = require('../ownerSubscriptionService');
  const status = await venueLoyaltyStatus(venue).catch(() => ({ active: false }));
  if (!status.active) return null;
  const rewardService = require('../rewardService');
  const progress = require('../rewardProgress');
  const { activeOffers } = require('../venueHelpers');
  const first = progress.firstReward(activeOffers(venue));
  return {
    earnRate: rewardService.effectiveEarnRate(venue),
    savePoints: rewardService.effectiveSavePoints(venue),
    firstReward: first ? { title: first.title, pointsCost: first.pointsCost } : null,
    offers: progress.rewardLadder(activeOffers(venue)).slice(0, 6)
  };
};

/** The store's buttons (Reserve, Order, Catering, Book, Menu): links the owner set, minus the ones hidden. */
const actionsOf = (venue) => {
  const { ACTION_KEYS, ACTION_LABELS } = require('../venueStorefront');
  const s = (venue.storefront && venue.storefront.actions) || {};
  const hidden = new Set(Array.isArray(s.hide) ? s.hide : []);
  return ACTION_KEYS.filter((k) => s[k] && !hidden.has(k)).map((k) => ({ key: k, label: ACTION_LABELS[k], url: String(s[k]) }));
};

/** Everything the store page shows beyond the menu: the website parts (2026-11-09). */
async function siteProjection(venue, place, { live = true } = {}) {
  const loc = (place && place.location) || venue.location || null;
  const coords = loc && Array.isArray(loc.coordinates) ? { latitude: loc.coordinates[1], longitude: loc.coordinates[0] }
    : loc && typeof loc.lat === 'number' ? { latitude: loc.lat, longitude: loc.lng }
      : loc && typeof loc.latitude === 'number' ? { latitude: loc.latitude, longitude: loc.longitude } : null;
  return {
    description: String((place && place.description) || venue.description || '').trim().slice(0, DESCRIPTION_MAX) || null,
    photos: photosOf(place),
    announcements: announcementsOf(venue),
    score: scoreOf(venue, place),
    earn: live ? await earnOf(venue) : null,
    actions: actionsOf(venue),
    waitlist: require('../waitlistService').waitlistFor(venue, { live }),
    location: coords
  };
}

/** The stores with a public page, for the sitemap: active, on Business, with a slug, not test stores. */
async function sitemapSlugs({ db = getFirestore() } = {}) {
  const snap = await db.collection('stickerVenues').where('active', '==', true).get();
  const out = [];
  for (const doc of snap.docs) {
    const v = { venueId: doc.id, ...doc.data() };
    if (!v.slug || v.isTestStore === true) continue;
    if (!(await isVenueBusinessLive(v))) continue;
    out.push({ slug: v.slug, updatedAt: v.updatedAt || null });
  }
  return out.sort((a, b) => a.slug.localeCompare(b.slug));
}

/** What the page and menu.json carry. Nothing private: no codes, no team, no keys. */
function projection(venue, place, { live = true, ordering = null } = {}) {
  const g = (place && place.googleData) || {};
  const menu = venue.storefront && venue.storefront.menu;
  return {
    slug: venue.slug,
    name: venue.venueName || venue.placeName || 'This store',
    address: venue.placeAddress || (place && place.address) || null,
    phone: g.phone || (place && place.phone) || null,
    website: g.website || (place && place.website) || null,
    coverPhotoUrl: coverPhotoOf(place),
    hours: formatHours(g.openingHours || (place && place.openingHours) || null),
    category: venue.category || null,
    offeringsLabel: offeringsLabel(venue.category),
    ordering: live ? ordering : null,
    menu: {
      sections: ((menu && menu.sections) || []).map((s) => ({
        id: s.id, name: s.name,
        items: (s.items || []).map((i) => ({ id: i.id, name: i.name, price: i.price || null, description: i.description || null, tags: i.tags || [] }))
      })).filter((s) => s.items.length),
      updatedAt: (menu && menu.updatedAt) || null
    },
    globalPlaceId: venue.globalPlaceId || null,
    isTestStore: venue.isTestStore === true
  };
}

// ---------------------------------------------------------------- tokens

/** A token that can read and cancel one order; `protect` rejects any token with a purpose. */
function signOrderToken(orderId) {
  return jwt.sign({ orderId, purpose: TOKEN_PURPOSE }, secret(), { expiresIn: TOKEN_TTL });
}

function verifyOrderToken(token, orderId) {
  try {
    const decoded = jwt.verify(String(token || ''), secret(), { algorithms: ['HS256'] });
    return decoded.purpose === TOKEN_PURPOSE && decoded.orderId === String(orderId);
  } catch (e) {
    return false;
  }
}

const base = () => process.env.ORDER_PAGE_BASE_URL || 'https://order.favcircles.com';
const statusUrl = (orderId, token = signOrderToken(orderId)) => `${base()}/o/${orderId}?t=${token}`;

/** The status JSON a guest polls: their order plus the store's phone; never the guest record. */
function guestView(orderId, o, venuePhone = null) {
  const v = orders.view(orderId, o);
  return { ...v, slug: o.slug || null, venuePhone };
}

// ------------------------------------------------------------------ place

/**
 * Guest checkout. `honeypot` is the hidden form field bots fill in: a
 * filled one is quietly ignored (nothing written, bare success).
 */
async function placeGuest({ slug, guest, items, note, pickup, honeypot }, { db = getFirestore(), now = new Date() } = {}) {
  if (honeypot) return { ignored: true };
  const page = await pageFor(slug, { db });
  if (!page || page.redirectTo) throw new ServiceError(404, 'store_not_found', 'That store isn’t taking online orders.');
  if (!page.ordering) throw new ServiceError(409, 'ordering_off', 'This store isn’t taking online orders right now.');
  const customer = cleanGuest(guest);
  // Validate the cart before any limit is spent
  rules.priceCart(page.venue.storefront.menu, items);
  rules.pickupFor(pickup, { leadMinutes: page.ordering.leadMinutes, now });
  const guestKey = guestKeyFor(customer.phone);

  const open = await db.collection(orders.ORDERS).where('guestKey', '==', guestKey).where('status', 'in', [...OPEN]).get();
  if (open.size >= GUEST_LIMITS.openPerPhone) {
    throw new ServiceError(429, 'too_many_open', 'You have a few orders in progress. Pick those up first.');
  }
  const budget = await dailyBudget.consume('webOrderPlace', guestKey);
  if (!budget.allowed) throw new ServiceError(429, 'order_limit', 'That’s a lot of orders for one day. Try again tomorrow.');

  const made = await orders.createOrder(page.venue, {
    ordering: page.ordering, customerId: null, customerName: customer.name, customer, guestKey, channel: 'web', items, note, pickup
  }, { db, now });
  // The slug rides on the doc so the status page can offer "Order again"
  await db.collection(orders.ORDERS).doc(made.orderId).update({ slug: page.venue.slug }).catch(() => {});
  const token = signOrderToken(made.orderId);
  const url = statusUrl(made.orderId, token);
  require('./orderEmails').sendGuestPlaced(made.orderId, made.order, url)
    .catch((e) => console.error('order: guest receipt failed', e.message));
  return { order: guestView(made.orderId, { ...made.order, slug: page.venue.slug }, projection(page.venue, page.place).phone), token, statusUrl: url };
}

async function loadGuestOrder(orderId, token, { db }) {
  if (!verifyOrderToken(token, orderId)) throw new ServiceError(404, 'order_not_found', 'That order wasn’t found.');
  const doc = await db.collection(orders.ORDERS).doc(String(orderId)).get();
  if (!doc.exists) throw new ServiceError(404, 'order_not_found', 'That order wasn’t found.');
  const o = doc.data();
  if (!orders.isGuest(o)) throw new ServiceError(404, 'order_not_found', 'That order wasn’t found.');
  return o;
}

async function venuePhoneFor(o, { db }) {
  if (!o.globalPlaceId) return null;
  const doc = await db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).doc(o.globalPlaceId).get().catch(() => null);
  const g = doc && doc.exists ? (doc.data().googleData || {}) : {};
  return g.phone || null;
}

async function status(orderId, token, { db = getFirestore() } = {}) {
  const o = await loadGuestOrder(orderId, token, { db });
  return guestView(orderId, o, await venuePhoneFor(o, { db }));
}

async function cancel(orderId, token, { db = getFirestore() } = {}) {
  const o = await loadGuestOrder(orderId, token, { db });
  await orders.cancelAsGuest(orderId, { db });
  const fresh = await db.collection(orders.ORDERS).doc(String(orderId)).get();
  return guestView(orderId, fresh.data(), await venuePhoneFor(o, { db }));
}

module.exports = { TOKEN_PURPOSE, pageFor, projection, siteProjection, sitemapSlugs, photosOf, announcementsOf, scoreOf, actionsOf, signOrderToken, verifyOrderToken, statusUrl, guestView, placeGuest, status, cancel };
