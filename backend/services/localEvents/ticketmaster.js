// Concerts, sports, theater and family shows from the Ticketmaster
// Discovery API (free key, 5,000 calls/day). Cached per ~5 km cell per day.
const geofire = require('geofire-common');
const { cached, fetchJson } = require('./cache');

const API_URL = 'https://app.ticketmaster.com/discovery/v2/events.json';
const RADIUS_MILES = 25;
const WINDOW_DAYS = 14;
const SKIP_STATUSES = new Set(['cancelled', 'canceled', 'postponed', 'offsale']);

/** The 16:9 image closest to 640 px wide (rows are ~100 pt). */
function pickImage(images) {
  if (!Array.isArray(images) || images.length === 0) return null;
  const wide = images.filter((img) => img && img.ratio === '16_9' && img.url);
  const pool = wide.length ? wide : images.filter((img) => img && img.url);
  if (!pool.length) return null;
  return pool.reduce((best, img) =>
    Math.abs((img.width || 0) - 640) < Math.abs((best.width || 0) - 640) ? img : best
  ).url;
}

/** One Ticketmaster event → the shared event shape; null when unshowable. */
function normalizeEvent(raw) {
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
    id: `tm_${raw.id}`,
    source: 'ticketmaster',
    sourceName: 'Ticketmaster',
    name: String(raw.name),
    startLocalDate: start.localDate,
    startLocalTime: start.timeTBA || start.noSpecificTime ? null : (start.localTime || null),
    startUtc: start.dateTime || null,
    venueName: venue.name || null,
    venueAddress: venue.address?.line1 || null,
    city: venue.city?.name || null,
    lat: hasCoords ? lat : null,
    lng: hasCoords ? lng : null,
    category: genre && genre !== 'Undefined' ? genre : (segment && segment !== 'Undefined' ? segment : null),
    imageUrl: pickImage(raw.images),
    url: String(raw.url),
    priceMin: Number.isFinite(price?.min) ? price.min : null,
    priceMax: Number.isFinite(price?.max) ? price.max : null,
    currency: price?.currency || null,
    isFree: price && price.max === 0 ? true : null
  };
}

function normalizeEvents(payload) {
  const raw = payload?._embedded?.events;
  if (!Array.isArray(raw)) return [];
  return raw.map(normalizeEvent).filter(Boolean);
}

/** Ticketmaster wants second precision with a Z. */
const tmTime = (date) => date.toISOString().replace(/\.\d{3}Z$/, 'Z');

async function eventsNear(lat, lng, { now = new Date(), apiKey = process.env.TICKETMASTER_API_KEY } = {}) {
  if (!apiKey) return [];
  const key = `tm_${geofire.geohashForLocation([lat, lng], 5)}_${now.toISOString().slice(0, 10)}`;
  return cached(key, { memoryMs: 30 * 60 * 1000, storeMs: 6 * 60 * 60 * 1000, now: now.getTime() }, async () => {
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
    const payload = await fetchJson(`${API_URL}?${params}`, { label: 'Ticketmaster' });
    return payload ? normalizeEvents(payload) : null;
  });
}

module.exports = { eventsNear, normalizeEvents, normalizeEvent, pickImage };
