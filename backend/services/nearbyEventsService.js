// The Locals tab's "Happening nearby" (Wes, 2026-10-15): events from stores
// on FavCircles, free library programs, and concerts/games/shows from
// Ticketmaster, soonest first — plus the nearest farmers markets (USDA).
// Each source caches on its own (services/localEvents/*); a source that is
// down just drops out. Never throws.
const geofire = require('geofire-common');
const ticketmaster = require('./localEvents/ticketmaster');
const library = require('./localEvents/library');
const storeEvents = require('./localEvents/storeEvents');
const farmersMarkets = require('./localEvents/farmersMarkets');
const { cached } = require('./localEvents/cache');
const coverageGaps = require('./localEvents/coverageGaps');

const MAX_EVENTS = 30;
const MAX_TICKETMASTER = 14;
const MAX_LIBRARY = 10;
// A busy library day shouldn't bury tonight's shows
const MAX_LIBRARY_PER_DAY = 3;
// Library programs are for the branches near you, not the whole county
const LIBRARY_RADIUS_M = 10 * 1609.344;

const withDistance = (event, lat, lng) => ({
  ...event,
  distanceMeters: Number.isFinite(event.lat) && Number.isFinite(event.lng)
    ? Math.round(geofire.distanceBetween([lat, lng], [event.lat, event.lng]) * 1000)
    : null
});

const startKey = (event) => `${event.startLocalDate} ${event.startLocalTime || '99'}`;
const bySoonest = (a, b) => startKey(a).localeCompare(startKey(b))
  || (a.distanceMeters ?? Infinity) - (b.distanceMeters ?? Infinity);

/**
 * One row per thing to go to: a show running every night keeps its next
 * date; a library program held at several branches keeps the nearest one.
 */
function dedupe(events, keyOf) {
  const seen = new Set();
  return events.filter((event) => {
    const key = keyOf(event);
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

const normName = (name) => String(name || '').toLowerCase().replace(/[^a-z0-9]/g, '');
// Every story time is the same outing; one is plenty
const programKey = (event) => (/story ?time/i.test(event.name) ? 'storytime' : normName(event.name));

/** Started more than an hour ago (when the source gives a real start). */
const isPast = (event, now) => {
  const start = event.startUtc ? Date.parse(event.startUtc) : NaN;
  return Number.isFinite(start) && start < now.getTime() - 3600000;
};

/** Merge the sources' lists into the tab's list (pure, tested). */
function mergeEvents({ store = [], tm = [], lib = [] }, lat, lng, now = new Date()) {
  const near = (list) => list.filter((event) => !isPast(event, now)).map((event) => withDistance(event, lat, lng));

  const tmRows = dedupe(near(tm).sort(bySoonest), (e) => `${normName(e.name)}|${normName(e.venueName)}`)
    .slice(0, MAX_TICKETMASTER);

  const libRows = near(lib)
    .filter((e) => e.distanceMeters === null || e.distanceMeters <= LIBRARY_RADIUS_M)
    .sort((a, b) => bySoonest(a, b));
  const libNearestFirst = [...libRows].sort((a, b) => (a.distanceMeters ?? Infinity) - (b.distanceMeters ?? Infinity));
  const keepLib = new Set(dedupe(libNearestFirst, (e) => e.seriesId || programKey(e)).map((e) => e.id));
  const libPicked = libRows.filter((e) => keepLib.has(e.id));
  const perDay = new Map();
  const libFinal = dedupe(libPicked, programKey).filter((e) => {
    const count = perDay.get(e.startLocalDate) || 0;
    perDay.set(e.startLocalDate, count + 1);
    return count < MAX_LIBRARY_PER_DAY;
  }).slice(0, MAX_LIBRARY);

  // Stores on FavCircles always make the list
  const storeRows = near(store).sort(bySoonest);
  const others = [...tmRows, ...libFinal].sort(bySoonest).slice(0, Math.max(0, MAX_EVENTS - storeRows.length));
  return [...storeRows, ...others].sort(bySoonest).map(({ seriesId, ...event }) => event);
}

/** Who to credit under the list. */
function attributionFor(events, markets) {
  const names = [];
  if (events.some((e) => e.source === 'ticketmaster')) names.push('Ticketmaster');
  for (const e of events) {
    if (e.source === 'library' && !names.includes(e.sourceName)) names.push(e.sourceName);
  }
  const parts = [];
  if (names.length) parts.push(`Events from ${names.join(' and ')}`);
  if (markets.length) parts.push('Farmers markets from the USDA directory');
  return parts.join(' · ') || null;
}

const settle = (promise, label) => promise.catch((err) => {
  console.warn(`[nearbyEvents] ${label} failed:`, err.message);
  return [];
});

/** Everything for the Locals tab's "Happening nearby" around (lat, lng). */
async function getLocalFeed(lat, lng, { now = new Date() } = {}) {
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return { events: [], markets: [], attribution: null };
  const cell = geofire.geohashForLocation([lat, lng], 5);
  const [store, tm, lib, markets] = await Promise.all([
    settle(storeEvents.eventsNear(lat, lng, { now }), 'store events'),
    settle(ticketmaster.eventsNear(lat, lng, { now }), 'Ticketmaster'),
    settle(library.eventsNear(lat, lng, { now }), 'library'),
    settle(cached(`fm2_${cell}`, { memoryMs: 6 * 3600000, storeMs: 24 * 3600000, now: now.getTime() },
      () => farmersMarkets.marketsNear(lat, lng)), 'farmers markets')
  ]);
  const events = mergeEvents({ store, tm, lib }, lat, lng, now);
  // No library programs near this spot: note it for the weekly report of
  // places to add a library system next
  if (!events.some((e) => e.source === 'library')) coverageGaps.recordGap(lat, lng);
  const nearMarkets = markets.map((m) => ({
    ...m,
    distanceMeters: Math.round(geofire.distanceBetween([lat, lng], [m.lat, m.lng]) * 1000)
  })).sort((a, b) => a.distanceMeters - b.distanceMeters);
  return { events, markets: nearMarkets, attribution: attributionFor(events, nearMarkets) };
}

/** Events only (the 2026-10-15 builds read just this). */
async function getNearbyEvents(lat, lng, options) {
  return (await getLocalFeed(lat, lng, options)).events;
}

module.exports = { getLocalFeed, getNearbyEvents, mergeEvents, attributionFor };
