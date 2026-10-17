// The USDA farmers market directory has no photos, days or hours (Wes,
// 2026-10-17: "no images", "no detail around days and times"). Each market
// shown on the Local tab is looked up once with Google Places — its place,
// one photo (re-hosted), weekly hours, website, and whether it closed — and
// the answer is kept on the market's doc: re-checked after 60 days (hours
// change with the season), a no-match after 180. About $0.05 a market each
// time, so a few cents per market every two months.
const geofire = require('geofire-common');
const { getFirestore } = require('../../config/firebase');

const RECHECK_MS = 60 * 86400000;
const RECHECK_NO_MATCH_MS = 180 * 86400000;
const MAX_MATCH_METERS = 500;
const API = 'https://maps.googleapis.com/maps/api/place';

const DAY_NAMES = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

/** "0800" → "8 AM", "1330" → "1:30 PM" */
function clock(hhmm) {
  const h = parseInt(String(hhmm).slice(0, 2), 10);
  const m = String(hhmm).slice(2, 4);
  if (!Number.isFinite(h)) return '';
  const hour12 = h % 12 === 0 ? 12 : h % 12;
  return `${hour12}${m && m !== '00' ? `:${m}` : ''} ${h < 12 ? 'AM' : 'PM'}`;
}

/** Google opening_hours.periods → the app's OpeningHour rows + a short line */
function hoursFrom(periods) {
  if (!Array.isArray(periods) || periods.length === 0) return { openingHours: null, hoursSummary: null };
  // Open around the clock: one period, open Sunday 0000, no close
  if (periods.length === 1 && !periods[0].close) return { openingHours: null, hoursSummary: 'Open 24 hours' };
  const openingHours = periods
    .filter((p) => p.open && Number.isInteger(p.open.day))
    .map((p) => ({
      day: p.open.day,
      open: `${String(p.open.time).slice(0, 2)}:${String(p.open.time).slice(2, 4)}`,
      close: p.close ? `${String(p.close.time).slice(0, 2)}:${String(p.close.time).slice(2, 4)}` : null,
      isClosed: false
    }));
  // Group days with the same hours: "Sat 8 AM–12 PM", "Tue, Thu 3–7 PM"
  const byHours = new Map();
  for (const p of periods) {
    if (!p.open) continue;
    const label = p.close ? `${clock(p.open.time)}–${clock(p.close.time)}` : `from ${clock(p.open.time)}`;
    if (!byHours.has(label)) byHours.set(label, []);
    byHours.get(label).push(p.open.day);
  }
  const hoursSummary = [...byHours.entries()]
    .map(([label, days]) => `${[...new Set(days)].sort((a, b) => a - b).map((d) => DAY_NAMES[d]).join(', ')} ${label}`)
    .join(' · ');
  return { openingHours, hoursSummary };
}

const words = (s) => new Set(String(s || '').toLowerCase().replace(/[^a-z0-9 ]/g, ' ').split(/\s+/)
  .filter((w) => w.length > 2 && !['the', 'and', 'farmers', 'farmer', 'market', 'markets'].includes(w)));

/** The Google result is this market: close by, and a shared name word (or a market at all). */
function isSameMarket(market, candidate) {
  const loc = candidate.geometry && candidate.geometry.location;
  if (!loc) return false;
  const meters = geofire.distanceBetween([market.lat, market.lng], [loc.lat, loc.lng]) * 1000;
  if (meters > MAX_MATCH_METERS) return false;
  const a = words(market.name);
  const b = words(candidate.name);
  const shared = [...a].some((w) => b.has(w));
  return shared || (a.size === 0 && /market/i.test(candidate.name || ''));
}

async function getJson(url) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 6000);
  try {
    const res = await fetch(url, { signal: controller.signal });
    return res.ok ? await res.json() : null;
  } finally {
    clearTimeout(timer);
  }
}

/** One market's Google details, or { noMatch: true }. */
async function lookUp(market, key) {
  const find = await getJson(`${API}/findplacefromtext/json?${new URLSearchParams({
    input: market.name, inputtype: 'textquery', fields: 'place_id,name,geometry',
    locationbias: `circle:${MAX_MATCH_METERS}@${market.lat},${market.lng}`, key
  })}`);
  if (!find) return null;
  const candidate = (find.candidates || []).find((c) => isSameMarket(market, c));
  if (!candidate) return { noMatch: true };
  const details = await getJson(`${API}/details/json?${new URLSearchParams({
    place_id: candidate.place_id, fields: 'opening_hours,photos,website,business_status,url', language: 'en', key
  })}`);
  const result = details && details.result;
  if (!result) return null;
  let photoUrl = null;
  const ref = result.photos && result.photos[0] && result.photos[0].photo_reference;
  if (ref) {
    try {
      const { downloadAndUploadMultipleImages } = require('../storage');
      const { uploadedUrls } = await downloadAndUploadMultipleImages([`${API}/photo?maxwidth=800&photoreference=${ref}&key=${key}`]);
      photoUrl = (uploadedUrls && uploadedUrls[0]) || null;
    } catch (err) {
      console.warn('[markets] photo re-host failed:', err.message);
    }
  }
  return {
    googlePlaceId: candidate.place_id,
    photoUrl,
    website: result.website || null,
    mapsUrl: result.url || null,
    closed: result.business_status === 'CLOSED_PERMANENTLY',
    ...hoursFrom(result.opening_hours && result.opening_hours.periods)
  };
}

function isStale(google, now) {
  if (!google || !google.checkedAt) return true;
  const age = now - Date.parse(google.checkedAt);
  return age > (google.noMatch ? RECHECK_NO_MATCH_MS : RECHECK_MS);
}

/** Markets with their Google details (looking up the stale ones), closed ones removed. */
async function withDetails(markets, { now = Date.now(), apiKey = process.env.GOOGLE_MAPS_API_KEY } = {}) {
  const db = getFirestore();
  const enriched = await Promise.all(markets.map(async (market) => {
    let google = market.google || null;
    if (apiKey && isStale(google, now)) {
      try {
        const found = await lookUp(market, apiKey);
        if (found) {
          google = { ...found, checkedAt: new Date(now).toISOString() };
          db.collection('farmersMarkets').doc(market.id).set({ google }, { merge: true })
            .catch((err) => console.warn('[markets] save failed:', err.message));
        }
      } catch (err) {
        console.warn('[markets] lookup failed:', err.message);
      }
    }
    if (google && google.closed) return null;
    const { google: _drop, ...rest } = market;
    return {
      ...rest,
      googlePlaceId: (google && google.googlePlaceId) || null,
      photoUrl: (google && google.photoUrl) || null,
      website: (google && google.website) || null,
      hoursSummary: (google && google.hoursSummary) || null,
      openingHours: (google && google.openingHours) || null
    };
  }));
  // Two directory rows can be one market on Google ("South End Farmers
  // Market" / "South End Market at Atherton"): keep the first
  const seen = new Set();
  return enriched.filter((m) => {
    if (!m) return false;
    if (!m.googlePlaceId) return true;
    if (seen.has(m.googlePlaceId)) return false;
    seen.add(m.googlePlaceId);
    return true;
  });
}

module.exports = { withDetails, hoursFrom, isSameMarket, clock };
