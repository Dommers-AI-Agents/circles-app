// backend/services/opentable/linkService.js
//
// Where a Reserve tap should land: the restaurant's own OpenTable page when
// the synced directory has it, else OpenTable's search near the place.
// Either way the link carries our referral ID (OPENTABLE_REF_ID) once
// OpenTable issues one, so they can count the diners we send.
const { geohashQueryBounds } = require('geofire-common');
const { getFirestore } = require('../../config/firebase');
const { COLLECTION } = require('./directorySync');
const { bestMatch, MAX_DISTANCE_M } = require('./matcher');

const SEARCH_URL = 'https://www.opentable.com/s';
const CACHE_MS = 6 * 60 * 60 * 1000;
const CACHE_MAX = 2000;
const cache = new Map(); // key -> { at, match }

const refId = () => (process.env.OPENTABLE_REF_ID || '').trim();

const withRef = (url) => {
  const ref = refId();
  if (!ref) return url;
  const u = new URL(url);
  u.searchParams.set('ref', ref);
  return u.toString();
};

/** Pure: OpenTable's own search, the fallback when there's no match. */
const searchUrl = ({ name, lat, lng }) => {
  const u = new URL(SEARCH_URL);
  if (name) u.searchParams.set('term', name);
  if (Number.isFinite(lat) && Number.isFinite(lng)) {
    u.searchParams.set('latitude', String(lat));
    u.searchParams.set('longitude', String(lng));
  }
  u.searchParams.set('covers', '2');
  return u.toString();
};

const nearby = async (lat, lng) => {
  const bounds = geohashQueryBounds([lat, lng], MAX_DISTANCE_M);
  const snaps = await Promise.all(bounds.map(([start, end]) =>
    getFirestore().collection(COLLECTION).orderBy('geohash').startAt(start).endAt(end).limit(50).get()));
  const out = [];
  for (const snap of snaps) snap.forEach((d) => { const x = d.data(); if (x.active !== false) out.push(x); });
  return out;
};

/** { url, matched, rid } for one place. Never throws: a lookup failure falls back to search. */
const resolve = async ({ name, address, lat, lng }) => {
  const place = { name, address, lat, lng };
  let match = null;
  if (Number.isFinite(lat) && Number.isFinite(lng) && name) {
    const key = `${lat.toFixed(4)},${lng.toFixed(4)}|${String(name).toLowerCase()}`;
    const hit = cache.get(key);
    if (hit && Date.now() - hit.at < CACHE_MS) {
      match = hit.match;
    } else {
      try {
        const found = bestMatch(place, await nearby(lat, lng));
        match = found && found.candidate.profileUrl
          ? { rid: found.candidate.rid, profileUrl: found.candidate.profileUrl, distanceM: found.distanceM }
          : null;
        if (cache.size >= CACHE_MAX) cache.delete(cache.keys().next().value);
        cache.set(key, { at: Date.now(), match });
      } catch (e) {
        console.warn(`🍽️ OpenTable lookup failed, using search: ${e.message}`);
      }
    }
  }
  if (match) return { url: withRef(match.profileUrl), matched: true, rid: match.rid };
  return { url: withRef(searchUrl(place)), matched: false, rid: null };
};

/** Counts taps for the revenue-share conversation. No user id, fire-and-forget. */
const logClick = ({ matched, rid }) => {
  getFirestore().collection('partnerClicks').add({
    provider: 'opentable', matched, rid: rid || null, hasRef: Boolean(refId()), at: new Date().toISOString()
  }).catch((e) => console.warn(`🍽️ partner click log failed: ${e.message}`));
};

const _clearCacheForTests = () => cache.clear();

module.exports = { searchUrl, withRef, resolve, logClick, _clearCacheForTests };
