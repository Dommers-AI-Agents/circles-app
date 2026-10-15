// Nearby events for the Specials tab's "Happening nearby" section
// (Wes, 2026-10-15): concerts, sports, theater and family shows within
// 25 miles over the next two weeks, from the Ticketmaster Discovery API.
//
// Cached per ~5 km cell per day (memory 30 min, Firestore 6 h) so the free
// 5,000 calls/day quota is never close and repeat opens are instant. Never
// throws: no key, a timeout or an upstream error all mean "no events".
const geofire = require('geofire-common');
const { getFirestore } = require('../config/firebase');

const API_URL = 'https://app.ticketmaster.com/discovery/v2/events.json';
const CACHE_COLLECTION = 'nearbyEventsCache';
const RADIUS_MILES = 25;
const WINDOW_DAYS = 14;
const MAX_EVENTS = 20;
const FETCH_TIMEOUT_MS = 4000;
const MEMORY_TTL_MS = 30 * 60 * 1000;
const STORE_TTL_MS = 6 * 60 * 60 * 1000;
const SKIP_STATUSES = new Set(['cancelled', 'canceled', 'postponed', 'offsale']);

const memory = new Map();

/** The 16:9 image closest to 640 px wide (cards are ~120 pt). */
function pickImage(images) {
  if (!Array.isArray(images) || images.length === 0) return null;
  const wide = images.filter((img) => img && img.ratio === '16_9' && img.url);
  const pool = wide.length ? wide : images.filter((img) => img && img.url);
  if (!pool.length) return null;
  return pool.reduce((best, img) =>
    Math.abs((img.width || 0) - 640) < Math.abs((best.width || 0) - 640) ? img : best
  ).url;
}

/** One Ticketmaster event → the app's shape; null when it can't be shown. */
function normalizeEvent(raw, origin) {
  if (!raw || !raw.id || !raw.name || !raw.url) return null;
  const status = String(raw.dates?.status?.code || '').toLowerCase();
  if (SKIP_STATUSES.has(status)) return null;
  const start = raw.dates?.start || {};
  if (!start.localDate) return null;
  const venue = raw._embedded?.venues?.[0] || {};
  const lat = parseFloat(venue.location?.latitude);
  const lng = parseFloat(venue.location?.longitude);
  const hasCoords = Number.isFinite(lat) && Number.isFinite(lng);
  const classification = raw.classifications?.[0] || {};
  const genre = classification.genre?.name;
  const segment = classification.segment?.name;
  const price = Array.isArray(raw.priceRanges) ? raw.priceRanges[0] : null;
  return {
    id: String(raw.id),
    name: String(raw.name),
    startLocalDate: start.localDate,
    startLocalTime: start.timeTBA || start.noSpecificTime ? null : (start.localTime || null),
    startUtc: start.dateTime || null,
    venueName: venue.name || null,
    venueAddress: venue.address?.line1 || null,
    city: venue.city?.name || null,
    lat: hasCoords ? lat : null,
    lng: hasCoords ? lng : null,
    distanceMeters: hasCoords && origin
      ? Math.round(geofire.distanceBetween([origin.lat, origin.lng], [lat, lng]) * 1000)
      : null,
    category: genre && genre !== 'Undefined' ? genre : (segment && segment !== 'Undefined' ? segment : null),
    imageUrl: pickImage(raw.images),
    url: String(raw.url),
    priceMin: Number.isFinite(price?.min) ? price.min : null,
    priceMax: Number.isFinite(price?.max) ? price.max : null,
    currency: price?.currency || null
  };
}

/**
 * Normalized, deduped (a show running every night keeps only its next
 * date), soonest first, capped.
 */
function normalizeEvents(payload, origin) {
  const raw = payload?._embedded?.events;
  if (!Array.isArray(raw)) return [];
  const seen = new Set();
  const events = [];
  for (const item of raw) {
    const event = normalizeEvent(item, origin);
    if (!event) continue;
    const key = `${event.name.toLowerCase()}|${(event.venueName || '').toLowerCase()}`;
    if (seen.has(key)) continue;
    seen.add(key);
    events.push(event);
  }
  events.sort((a, b) =>
    `${a.startLocalDate} ${a.startLocalTime || '99'}`.localeCompare(`${b.startLocalDate} ${b.startLocalTime || '99'}`)
  );
  return events.slice(0, MAX_EVENTS);
}

/** Ticketmaster wants second precision with a Z. */
function tmTime(date) {
  return date.toISOString().replace(/\.\d{3}Z$/, 'Z');
}

async function fetchFromTicketmaster(lat, lng, apiKey, now) {
  const params = new URLSearchParams({
    apikey: apiKey,
    latlong: `${lat},${lng}`,
    radius: String(RADIUS_MILES),
    unit: 'miles',
    startDateTime: tmTime(now),
    endDateTime: tmTime(new Date(now.getTime() + WINDOW_DAYS * 86400000)),
    sort: 'date,asc',
    size: '50',
    includeTBA: 'no',
    includeTest: 'no',
    locale: '*'
  });
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);
  try {
    const res = await fetch(`${API_URL}?${params}`, { signal: controller.signal });
    if (!res.ok) {
      console.warn(`[nearbyEvents] Ticketmaster answered ${res.status}`);
      return null;
    }
    return await res.json();
  } finally {
    clearTimeout(timer);
  }
}

/**
 * Events near (lat, lng). Distances are measured from the caller even when
 * the list came from the cell's cache.
 */
async function getNearbyEvents(lat, lng, { now = new Date(), apiKey = process.env.TICKETMASTER_API_KEY } = {}) {
  if (!apiKey || !Number.isFinite(lat) || !Number.isFinite(lng)) return [];
  const origin = { lat, lng };
  const cell = geofire.geohashForLocation([lat, lng], 5);
  const key = `${cell}_${now.toISOString().slice(0, 10)}`;

  const withDistances = (events) => events.map((event) => ({
    ...event,
    distanceMeters: event.lat !== null && event.lng !== null
      ? Math.round(geofire.distanceBetween([origin.lat, origin.lng], [event.lat, event.lng]) * 1000)
      : null
  }));

  const inMemory = memory.get(key);
  if (inMemory && now.getTime() - inMemory.at < MEMORY_TTL_MS) return withDistances(inMemory.events);

  const db = getFirestore();
  const ref = db.collection(CACHE_COLLECTION).doc(key);
  try {
    const doc = await ref.get();
    const data = doc.exists ? doc.data() : null;
    if (data && Array.isArray(data.events) && data.fetchedAtMs && now.getTime() - data.fetchedAtMs < STORE_TTL_MS) {
      memory.set(key, { at: now.getTime(), events: data.events });
      return withDistances(data.events);
    }
  } catch (err) {
    console.warn('[nearbyEvents] cache read failed:', err.message);
  }

  let payload = null;
  try {
    payload = await fetchFromTicketmaster(lat, lng, apiKey, now);
  } catch (err) {
    console.warn('[nearbyEvents] Ticketmaster request failed:', err.name === 'AbortError' ? 'timeout' : err.message);
  }
  if (!payload) {
    // Hold off five minutes before asking again (a bad key or an outage
    // shouldn't cost a call per tab open)
    memory.set(key, { at: now.getTime() - MEMORY_TTL_MS + 5 * 60 * 1000, events: [] });
    return [];
  }

  const events = normalizeEvents(payload, origin);
  memory.set(key, { at: now.getTime(), events });
  ref.set({
    events,
    fetchedAtMs: now.getTime(),
    expiresAt: new Date(now.getTime() + STORE_TTL_MS)
  }).catch((err) => console.warn('[nearbyEvents] cache write failed:', err.message));
  return withDistances(events);
}

module.exports = {
  getNearbyEvents,
  normalizeEvents,
  normalizeEvent,
  pickImage,
  _memory: memory
};
