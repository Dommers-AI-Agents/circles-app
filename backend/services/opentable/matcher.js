// backend/services/opentable/matcher.js
//
// Pure: which OpenTable restaurant (if any) is the place someone tapped
// Reserve on. A wrong match sends a diner to the wrong restaurant, which is
// worse than the search fallback, so it errs toward "no match": close by
// (≤ 150 m), the same name once "the", "&", punctuation and suffixes like
// "restaurant" are set aside, and the same street number when both sides
// have one.
const { distanceBetween } = require('geofire-common');

const MAX_DISTANCE_M = 150;
const STOP_WORDS = new Set([
  'the', 'and', 'a', 'an', 'of', 'at', 'on', 'in',
  'restaurant', 'restaurants', 'bar', 'grill', 'kitchen', 'cafe', 'bistro', 'eatery', 'tavern', 'lounge', 'co', 'company'
]);

const nameTokens = (name) => String(name || '')
  .toLowerCase()
  .normalize('NFKD').replace(/[̀-ͯ]/g, '')
  .replace(/&/g, ' and ')
  .replace(/['’`]/g, '')
  .replace(/[^a-z0-9]+/g, ' ')
  .split(' ')
  .filter((t) => t && !STOP_WORDS.has(t));

/** Stable key for a name: its meaningful tokens, sorted. */
const nameKey = (name) => [...new Set(nameTokens(name))].sort().join(' ');

const streetNumber = (address) => {
  const m = String(address || '').trim().match(/^(\d+[a-z]?)\b/i);
  return m ? m[1].toLowerCase() : null;
};

/**
 * How well two names agree (0…1): every word of the shorter name must be in
 * the longer one, and at least half of the longer name's words must be
 * covered, so "Pizza" never matches "Pizza Hut Express" next door.
 */
const nameOverlap = (a, b) => {
  const ta = new Set(nameTokens(a));
  const tb = new Set(nameTokens(b));
  if (!ta.size || !tb.size) return 0;
  const [small, large] = ta.size <= tb.size ? [ta, tb] : [tb, ta];
  let hit = 0;
  for (const t of small) if (large.has(t)) hit++;
  if (hit / large.size < 0.5) return 0;
  return hit / small.size;
};

/**
 * place: { name, address, lat, lng }
 * candidates: [{ rid, name, address, lat, lng, ... }]
 * Returns { candidate, distanceM, score } or null.
 */
const bestMatch = (place, candidates) => {
  if (!place || !Number.isFinite(place.lat) || !Number.isFinite(place.lng)) return null;
  const placeNumber = streetNumber(place.address);
  let best = null;
  for (const c of candidates || []) {
    if (!Number.isFinite(c.lat) || !Number.isFinite(c.lng)) continue;
    const distanceM = distanceBetween([place.lat, place.lng], [c.lat, c.lng]) * 1000;
    if (distanceM > MAX_DISTANCE_M) continue;
    // Chains add the location after a dash: "North Italia - Charlotte - South End"
    const brand = String(c.name || '').split(/\s+[-–—|]\s+/)[0];
    const overlap = Math.max(nameOverlap(place.name, c.name), nameOverlap(place.name, brand));
    if (overlap < 1) continue; // every meaningful word of the shorter name must appear
    const candidateNumber = streetNumber(c.address);
    if (placeNumber && candidateNumber && placeNumber !== candidateNumber) continue;
    const score = overlap * 1000 - distanceM + (placeNumber && placeNumber === candidateNumber ? 50 : 0);
    if (!best || score > best.score) best = { candidate: c, distanceM: Math.round(distanceM), score };
  }
  return best;
};

module.exports = { MAX_DISTANCE_M, nameTokens, nameKey, streetNumber, nameOverlap, bestMatch };
