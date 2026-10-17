// The USDA farmers market directory has no photos, days or hours (Wes,
// 2026-10-17: "no images", "no detail around days and times"). Each market
// shown on the Locals tab is confirmed and filled in from two sources:
//   1. OpenStreetMap (free): is it there, its opening_hours, website.
//   2. Google Places, only for what OpenStreetMap lacks: confirming a market
//      it doesn't know, hours it doesn't have, the photo (fetched once and
//      kept), and closures (business_status, re-checked every 180 days).
// When both have hours and disagree, a recent OpenStreetMap edit wins,
// otherwise Google; the disagreement is logged to marketHoursConflicts.
// Answers live on the market's doc (`details`), re-checked after 60 days
// (hours change with the season), a no-match after 180. Only markets one of
// the sources confirms are shown (Wes: "if you can't confirm it, remove it").
const geofire = require('geofire-common');
const { getFirestore } = require('../../config/firebase');

const RECHECK_MS = 60 * 86400000;
const RECHECK_NO_MATCH_MS = 180 * 86400000;
const GOOGLE_CLOSURE_CHECK_MS = 180 * 86400000;
const OSM_FRESH_MS = 365 * 86400000;
const OVERPASS = ['https://overpass-api.de/api/interpreter', 'https://overpass.private.coffee/api/interpreter', 'https://overpass.kumi.systems/api/interpreter'];
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

const OSM_ORDER = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'];
const OSM_DAY = { Su: 0, Mo: 1, Tu: 2, We: 3, Th: 4, Fr: 5, Sa: 6 };
const OSM_DAYS = String.raw`(?:Mo|Tu|We|Th|Fr|Sa|Su)(?:-(?:Mo|Tu|We|Th|Fr|Sa|Su))?`;
const OSM_TIME = String.raw`\d{1,2}:\d{2}-\d{1,2}:\d{2}`;
const OSM_RULE = new RegExp(String.raw`^(${OSM_DAYS}(?:,${OSM_DAYS})*)?\s*(${OSM_TIME}(?:,\s*${OSM_TIME})*|off|closed)$`);

const hhmm = (t) => {
  const [h, m] = t.split(':');
  return h === '24' ? '0000' : `${h.padStart(2, '0')}${m}`;
};

/**
 * OpenStreetMap opening_hours ("We-Su 08:00-17:00", "Sa 08:00-12:30; PH off")
 * as Google-style periods, or null when it uses anything fancier (months,
 * weeks, sunrise…) — those markets get their hours from Google instead.
 */
function osmPeriods(text) {
  const value = String(text || '').trim();
  if (!value) return null;
  if (value === '24/7') return [{ open: { day: 0, time: '0000' } }];
  const byDay = new Map();
  for (const raw of value.split(';')) {
    const rule = raw.trim();
    if (!rule || /^PH\b/.test(rule)) continue;
    const m = rule.match(OSM_RULE);
    if (!m) return null;
    let days = [0, 1, 2, 3, 4, 5, 6];
    if (m[1]) {
      days = [];
      for (const part of m[1].split(',')) {
        const [from, to] = part.split('-');
        let k = OSM_ORDER.indexOf(from);
        const end = OSM_ORDER.indexOf(to || from);
        for (;;) {
          days.push(OSM_DAY[OSM_ORDER[k]]);
          if (k === end) break;
          k = (k + 1) % 7;
        }
      }
    }
    const spans = /^(off|closed)$/.test(m[2]) ? [] : m[2].split(',').map((t) => t.trim().split('-'));
    for (const d of days) byDay.set(d, spans);   // later rules override earlier ones
  }
  const periods = [];
  for (const [day, spans] of [...byDay.entries()].sort((a, b) => a[0] - b[0])) {
    for (const [from, to] of spans) {
      const open = hhmm(from);
      const close = hhmm(to);
      periods.push({ open: { day, time: open }, close: { day: close > open ? day : (day + 1) % 7, time: close } });
    }
  }
  return periods.length ? periods : null;
}

/** One Overpass query for every market that needs a look; null if Overpass is down. */
async function osmMarketsAround(markets, { budgetMs = 45000 } = {}) {
  if (markets.length === 0) return [];
  const around = markets.map((m) => `nwr["amenity"="marketplace"](around:${MAX_MATCH_METERS},${m.lat},${m.lng});`).join('');
  const query = `[out:json][timeout:25];(${around});out center tags meta;`;
  // The public Overpass servers are often busy: try each in turn within one
  // time budget (short when someone is waiting on the tab)
  const deadline = Date.now() + budgetMs;
  for (const endpoint of OVERPASS) {
    const left = deadline - Date.now();
    if (left < 1000) break;
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), Math.min(left, 20000));
    try {
      const res = await fetch(endpoint, {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded', 'User-Agent': 'FavCircles/1.0 (https://favcircles.com)' },
        body: new URLSearchParams({ data: query }),
        signal: controller.signal
      });
      if (res.ok) return ((await res.json()).elements || []).filter((e) => e.tags && e.tags.name);
      console.warn('[markets] overpass', endpoint, res.status);
    } catch (err) {
      console.warn('[markets] overpass failed:', err.message);
    } finally {
      clearTimeout(timer);
    }
  }
  return null;
}

/** The OpenStreetMap entry that is this market, as what we keep from it. */
function osmMatch(market, elements) {
  const el = (elements || []).find((e) => {
    const lat = e.lat != null ? e.lat : e.center && e.center.lat;
    const lng = e.lon != null ? e.lon : e.center && e.center.lon;
    return lat != null && isSameMarket(market, { name: e.tags.name, geometry: { location: { lat, lng } } });
  });
  if (!el) return null;
  return {
    osmId: `${el.type}/${el.id}`,
    editedAt: el.timestamp || null,
    website: el.tags.website || el.tags['contact:website'] || null,
    periods: osmPeriods(el.tags.opening_hours)
  };
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

/**
 * What Google says about one market, or { noMatch: true }. Skips the search
 * when the place is already known, and asks for photos only when we have none.
 */
async function googleLookUp(market, key, { googlePlaceId = null, wantPhoto = true } = {}) {
  let placeId = googlePlaceId;
  if (!placeId) {
    const find = await getJson(`${API}/findplacefromtext/json?${new URLSearchParams({
      input: market.name, inputtype: 'textquery', fields: 'place_id,name,geometry',
      locationbias: `circle:${MAX_MATCH_METERS}@${market.lat},${market.lng}`, key
    })}`);
    if (!find) return null;
    const candidate = (find.candidates || []).find((c) => isSameMarket(market, c));
    if (!candidate) return { noMatch: true };
    placeId = candidate.place_id;
  }
  const fields = ['opening_hours', 'website', 'business_status', 'url', ...(wantPhoto ? ['photos'] : [])].join(',');
  const details = await getJson(`${API}/details/json?${new URLSearchParams({ place_id: placeId, fields, language: 'en', key })}`);
  const result = details && details.result;
  if (!result) return null;
  let photoUrl = null;
  const ref = wantPhoto && result.photos && result.photos[0] && result.photos[0].photo_reference;
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
    googlePlaceId: placeId,
    photoUrl,
    website: result.website || null,
    closed: result.business_status === 'CLOSED_PERMANENTLY',
    periods: (result.opening_hours && result.opening_hours.periods) || null
  };
}

/**
 * Both sources folded into what the market shows. `osm` undefined = Overpass
 * was unreachable (not "not on OpenStreetMap"). Returns the new details, or
 * null to keep what we had.
 */
async function refresh(market, prev, osm, { key, now, logConflict }) {
  const osmDown = osm === undefined;
  const osmHours = osm && osm.periods ? hoursFrom(osm.periods) : null;
  const needsPhoto = !(prev && prev.photoUrl) && !(prev && prev.photoTriedAt);
  const closureDue = !(prev && prev.googleCheckedAt) || now - Date.parse(prev.googleCheckedAt) > GOOGLE_CLOSURE_CHECK_MS;
  const askGoogle = key && (!osm || !osmHours || needsPhoto || closureDue);
  if (osmDown && prev) return null;   // try again next time rather than judge on one source

  let google = null;
  if (askGoogle) {
    google = await googleLookUp(market, key, { googlePlaceId: prev && prev.googlePlaceId, wantPhoto: needsPhoto });
    if (google === null && !osm) return null;   // Google errored and no OpenStreetMap: keep what we had
  }
  const googleFound = google && !google.noMatch;
  if (!osm && !googleFound) return { noMatch: true, checkedAt: new Date(now).toISOString() };

  const googleHours = googleFound && google.periods ? hoursFrom(google.periods) : null;
  let hours = osmHours || googleHours || { openingHours: (prev && prev.openingHours) || null, hoursSummary: (prev && prev.hoursSummary) || null };
  let hoursSource = osmHours ? 'osm' : googleHours ? 'google' : (prev && prev.hoursSource) || null;
  if (osmHours && googleHours && osmHours.hoursSummary !== googleHours.hoursSummary) {
    const osmRecent = osm.editedAt && now - Date.parse(osm.editedAt) < OSM_FRESH_MS;
    if (!osmRecent) { hours = googleHours; hoursSource = 'google'; }
    logConflict({ marketId: market.id, name: market.name, osm: osmHours.hoursSummary, osmEditedAt: osm.editedAt,
      google: googleHours.hoursSummary, chose: hoursSource, at: new Date(now).toISOString() });
  }
  return {
    osmId: (osm && osm.osmId) || null,
    googlePlaceId: (googleFound && google.googlePlaceId) || (prev && prev.googlePlaceId) || null,
    photoUrl: (googleFound && google.photoUrl) || (prev && prev.photoUrl) || null,
    photoTriedAt: needsPhoto && google ? new Date(now).toISOString() : (prev && prev.photoTriedAt) || null,
    website: (googleFound && google.website) || (osm && osm.website) || (prev && prev.website) || null,
    closed: googleFound ? google.closed : !!(prev && prev.closed),
    googleCheckedAt: google ? new Date(now).toISOString() : (prev && prev.googleCheckedAt) || null,
    ...hours,
    hoursSource,
    checkedAt: new Date(now).toISOString()
  };
}

function isStale(google, now) {
  if (!google || !google.checkedAt) return true;
  const age = now - Date.parse(google.checkedAt);
  return age > (google.noMatch ? RECHECK_NO_MATCH_MS : RECHECK_MS);
}

/** Markets with their details (refreshing the stale ones); closed and unconfirmed ones removed. */
async function withDetails(markets, { now = Date.now(), apiKey = process.env.GOOGLE_MAPS_API_KEY } = {}) {
  const db = getFirestore();
  // Older docs kept these under `google` (Google-only, 2026-10-17 morning)
  const prevOf = (m) => m.details || m.google || null;
  const logConflict = (row) => db.collection('marketHoursConflicts').doc(row.marketId).set(row, { merge: true })
    .catch((err) => console.warn('[markets] conflict log failed:', err.message));

  /** Look these up (one Overpass query, then Google where needed) and save them. */
  const lookUpAll = async (list, budgetMs) => {
    const found = new Map();
    const elements = await osmMarketsAround(list, { budgetMs });
    await Promise.all(list.map(async (market) => {
      try {
        const osm = elements === null ? undefined : osmMatch(market, elements);
        const details = await refresh(market, prevOf(market), osm, { key: apiKey, now, logConflict });
        if (!details) return;
        found.set(market.id, details);
        await db.collection('farmersMarkets').doc(market.id).set({ details }, { merge: true });
      } catch (err) {
        console.warn('[markets] lookup failed:', err.message);
      }
    }));
    return found;
  };

  const stale = markets.filter((m) => isStale(prevOf(m), now));
  // A market we've never looked up has to be confirmed before it can show;
  // one we know shows what we have while it refreshes in the background
  const fresh = await lookUpAll(stale.filter((m) => !prevOf(m)), 8000);
  const due = stale.filter((m) => prevOf(m));
  if (due.length) lookUpAll(due, 45000).catch((err) => console.warn('[markets] background refresh failed:', err.message));

  const enriched = markets.map((market) => {
    const details = fresh.get(market.id) || prevOf(market);
    // Only markets a source confirms are shown (Wes, 2026-10-17: "if you
    // can't confirm the market, remove it"); the USDA list has stale entries
    if (!details || details.noMatch || details.closed || !(details.googlePlaceId || details.osmId)) return null;
    const { google: _g, details: _d, ...rest } = market;
    return {
      ...rest,
      googlePlaceId: details.googlePlaceId || null,
      photoUrl: details.photoUrl || null,
      website: details.website || null,
      hoursSummary: details.hoursSummary || null,
      openingHours: details.openingHours || null,
      hoursSource: details.hoursSource || null,
      onOpenStreetMap: !!details.osmId
    };
  });
  // Two directory rows can be one market ("South End Farmers Market" /
  // "South End Market at Atherton"): keep the first
  const seen = new Set();
  return enriched.filter((m) => {
    if (!m) return false;
    const key = m.googlePlaceId || `${m.name}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}

module.exports = { withDetails, hoursFrom, isSameMarket, clock, osmPeriods, osmMatch, osmMarketsAround, refresh };
