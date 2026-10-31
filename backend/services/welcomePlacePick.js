// Which of Wes's saves a new user gets as their welcome suggestion
// (onboardingService.sendWelcomeSuggestion). It's their first look at the app,
// so it has to be a real favorite anyone may see — a place, not "600 Fifth
// Ave" from a want-to-go import (Wes, 2026-10-17).

const STREET_SUFFIX = '(?:st|street|ave|avenue|blvd|boulevard|rd|road|dr|drive|ln|lane|way|pl|place|ct|court|pkwy|parkway|hwy|highway|ter|terrace|cir|circle|sq|square|plaza|broadway)';
const DIRECTION = '(?:n|s|e|w|ne|nw|se|sw|north|south|east|west)';
// "600 Fifth Ave", "121 W Trade St", "1600 Broadway", "35-12 31st Ave N"
const STREET_LINE = new RegExp(`^\\d+[a-z]?(?:-\\d+)?\\s+(?:${DIRECTION}\\.?\\s+)?[\\w.' ]*?\\b${STREET_SUFFIX}\\.?(?:\\s+${DIRECTION}\\.?)?$`, 'i');

const normalize = (s) => String(s || '').toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();

/**
 * True when a save's name is just a street address: it reads like one, or it
 * is the first line of its own address and starts with a house number.
 */
const isStreetAddressName = (name, address) => {
  const n = String(name || '').trim();
  if (!n) return false;
  if (STREET_LINE.test(n)) return true;
  const firstLine = normalize(String(address || '').split(',')[0]);
  return /^\d/.test(n) && firstLine !== '' && normalize(n) === firstLine;
};

const WANT_TO_GO = new Set(['want-to-go', 'want to go', 'wanttogo']);
// Places worth discovering, ahead of services, hotels and the rest: a tire
// shop is a fine save but a poor first impression
const DISCOVERY_CATEGORIES = new Set(['restaurant', 'bar', 'cafe', 'coffee', 'bakery', 'dessert', 'nightlife',
  'outdoor', 'park', 'entertainment', 'attraction', 'museum', 'retail', 'shopping']);
const OPEN_PLACE_TIERS = new Set([undefined, null, '', 'followCircle', 'public']);

const { DEFAULT_LOCATION } = require('../config/defaultLocation');

const NEARBY_KM = 80;

/** [lat, lng] from a save's GeoJSON point or a { latitude, longitude } pair. */
const latLng = (loc) => {
  if (!loc) return null;
  if (Array.isArray(loc.coordinates) && loc.coordinates.length === 2) return [loc.coordinates[1], loc.coordinates[0]];
  if (typeof loc.latitude === 'number' && typeof loc.longitude === 'number') return [loc.latitude, loc.longitude];
  return null;
};

const distanceKm = ([lat1, lng1], [lat2, lng2]) => {
  const toRad = (d) => (d * Math.PI) / 180;
  const a = Math.sin(toRad(lat2 - lat1) / 2) ** 2
    + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(toRad(lng2 - lng1) / 2) ** 2;
  return 2 * 6371 * Math.asin(Math.sqrt(a));
};

/**
 * @param {object[]} places          Wes's save records ({ id, ...data })
 * @param {Set<string>} publicCircleIds  his circles anyone may see
 * @param {object} [options]
 * @param {{latitude:number, longitude:number}} [options.near]  the new user's
 *   location. Places within 80 km of it first; then within 80 km of
 *   Charlotte, the default location (config/defaultLocation.js), which is
 *   also where an unknown location starts; then anywhere
 * @param {Map<string, number>} [options.sentCounts]  how many times each
 *   place has gone out as a welcome suggestion; the least-sent go first
 * @param {() => number} [options.random]  injectable for tests
 * @returns {object|null} the place to suggest, or null when none qualifies
 *   (better no welcome suggestion than a bad one)
 */
const pickWelcomePlace = (places, publicCircleIds, { near = null, sentCounts = new Map(), random = Math.random } = {}) => {
  let eligible = places.filter(p => p && p.name && !p.deletedAt
    && publicCircleIds.has(p.circleId)
    && OPEN_PLACE_TIERS.has(p.privacy)
    && !(p.tags || []).some(t => WANT_TO_GO.has(String(t).toLowerCase()))
    && !isStreetAddressName(p.name, p.address));
  // Somewhere they can actually go: near them, else near Charlotte
  const within = (center) => eligible.filter(p => {
    const there = latLng(p.location);
    return there && distanceKm(center, there) <= NEARBY_KM;
  });
  for (const center of [latLng(near), latLng(DEFAULT_LOCATION)]) {
    if (!center) continue;
    const nearby = within(center);
    if (nearby.length) { eligible = nearby; break; }
  }
  if (eligible.length === 0) return null;
  // Every real favorite with a photo (rated 8+), so the welcome rotates
  // across many places instead of the same top few (Wes, 2026-10-31: new
  // users kept getting The Blind Pig). None → the best-scoring ones.
  let pool = eligible.filter(p => (Number(p.userRating) || 0) >= 8 && p.photos && p.photos.length);
  if (pool.length === 0) {
    // His own rating first (0–10), then a photo, then a place to discover
    const score = p => (Number(p.userRating) || 0) * 10
      + ((p.photos && p.photos.length) ? 30 : 0)
      + (DISCOVERY_CATEGORIES.has(String(p.category || '').toLowerCase()) ? 10 : 0);
    const top = Math.max(...eligible.map(score));
    pool = eligible.filter(p => score(p) === top);
  }
  // The least-sent first, then one of those at random
  const sent = (p) => sentCounts.get(p.id) || 0;
  const fewest = Math.min(...pool.map(sent));
  const best = pool.filter(p => sent(p) === fewest);
  return best[Math.floor(random() * best.length)] || best[0];
};

module.exports = { pickWelcomePlace, isStreetAddressName };
