// Free library programs (story times, workshops, concerts, author talks).
// Each library system in config/eventFeeds.js names its calendar type:
// BiblioCommons (here), LibCal (libcal.js) or Maricopa County's site
// (mcldaz.js). One list per system every few hours, shared by everyone;
// each user gets the branches near them (nearbyEventsService).
const { cached, fetchJson } = require('./cache');
const { LIBRARY_FEEDS } = require('../../config/eventFeeds');
const { SERVICE_PROGRAM, NOT_AN_OUTING, stripHtml, dayKey } = require('./libraryCommon');
const { loadLibcal } = require('./libcal');
const { loadMcld } = require('./mcldaz');
const geofire = require('geofire-common');

const GATEWAY = 'https://gateway.bibliocommons.com/v2/libraries';
const WINDOW_DAYS = 3;
// The gateway answers at most 50 per page whatever limit says
const PAGE_SIZE = 50;
const MAX_PAGES = 5;

/** One page of the BiblioCommons gateway's search → the shared event shape. */
function normalizePage(payload, feed) {
  const ids = payload?.events?.results;
  const entities = payload?.entities || {};
  if (!Array.isArray(ids)) return [];
  const images = entities.images || {};
  const locations = entities.locations || {};
  return ids.map((id) => {
    const raw = entities.events?.[id];
    const def = raw?.definition;
    if (!def || def.isCancelled || !def.title || !def.start) return null;
    // All-day items are displays and exhibits, not something to go to;
    // programs with no branch are online
    if (!def.start.includes('T') || !def.branchLocationId) return null;
    if (SERVICE_PROGRAM.test(def.title) || NOT_AN_OUTING.test(def.title)) return null;
    const [date, time] = def.start.split('T');
    const branch = locations[def.branchLocationId] || {};
    const point = branch.mapLocation?.centrePoint || {};
    const address = branch.address || {};
    const image = images[def.featuredImageId];
    const description = stripHtml(def.description);
    return {
      id: `lib_${feed.libraryId}_${raw.id}`,
      seriesId: raw.seriesId || null,
      source: 'library',
      sourceName: feed.name,
      name: stripHtml(def.title),
      message: description ? description.slice(0, 280) : null,
      startLocalDate: date,
      startLocalTime: time.length === 5 ? `${time}:00` : time,
      startUtc: raw.indexStart || null,
      venueName: branch.name || feed.name,
      venueAddress: [address.number, address.street].filter(Boolean).join(' ') || null,
      city: address.city || null,
      lat: Number.isFinite(point.lat) ? point.lat : null,
      lng: Number.isFinite(point.lng) ? point.lng : null,
      category: 'Library',
      imageUrl: image?.url || null,
      url: `https://${feed.libraryId}.bibliocommons.com/events/${raw.id}`,
      priceMin: null,
      priceMax: null,
      currency: null,
      // Library programs are free unless the listing says it's ticketed
      isFree: /ticketed/i.test(description) ? null : true
    };
  }).filter(Boolean);
}

async function loadBiblioCommons(feed, { fromDay, toDay }) {
  const pageOf = (page) => fetchJson(`${GATEWAY}/${feed.libraryId}/events/search?${new URLSearchParams({
    startDate: fromDay, endDate: toDay, limit: String(PAGE_SIZE), page: String(page)
  })}`, { label: feed.name, timeoutMs: 5000 });
  const first = await pageOf(1);
  if (!first) return null;
  const pages = Math.min(first?.events?.pagination?.pages || 1, MAX_PAGES);
  const rest = await Promise.all(Array.from({ length: pages - 1 }, (_, i) => pageOf(i + 2)));
  return [first, ...rest].filter(Boolean).flatMap((payload) => normalizePage(payload, feed));
}

const LOADERS = { bibliocommons: loadBiblioCommons, libcal: loadLibcal, mcldaz: loadMcld };

/** Library systems whose service area covers (lat, lng). */
function feedsNear(lat, lng) {
  return LIBRARY_FEEDS.filter((feed) =>
    geofire.distanceBetween([lat, lng], [feed.center.lat, feed.center.lng]) / 1.609344 <= feed.radiusMiles
  );
}

const feedKey = (feed) => feed.libraryId || feed.host;

async function eventsNear(lat, lng, { now = new Date() } = {}) {
  const lists = await Promise.all(feedsNear(lat, lng).map((feed) => {
    const load = LOADERS[feed.type || 'bibliocommons'];
    if (!load) return [];
    const window = {
      fromDay: dayKey(now, feed.timeZone),
      toDay: dayKey(new Date(now.getTime() + WINDOW_DAYS * 86400000), feed.timeZone)
    };
    return cached(`lib_${feedKey(feed).replace(/\./g, '_')}_${now.toISOString().slice(0, 10)}_${Math.floor(now.getUTCHours() / 3)}`,
      { memoryMs: 30 * 60 * 1000, storeMs: 3 * 60 * 60 * 1000, now: now.getTime() },
      () => load(feed, window));
  }));
  return lists.flat();
}

module.exports = { eventsNear, normalizePage, feedsNear, stripHtml };
