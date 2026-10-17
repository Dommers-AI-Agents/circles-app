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

/**
 * @param {object[]} places          Wes's save records ({ id, ...data })
 * @param {Set<string>} publicCircleIds  his circles anyone may see
 * @param {() => number} [random]  injectable for tests
 * @returns {object|null} the place to suggest, or null when none qualifies
 *   (better no welcome suggestion than a bad one)
 */
const pickWelcomePlace = (places, publicCircleIds, random = Math.random) => {
  const eligible = places.filter(p => p && p.name && !p.deletedAt
    && publicCircleIds.has(p.circleId)
    && OPEN_PLACE_TIERS.has(p.privacy)
    && !(p.tags || []).some(t => WANT_TO_GO.has(String(t).toLowerCase()))
    && !isStreetAddressName(p.name, p.address));
  if (eligible.length === 0) return null;
  // His own rating first (0–10), then a photo, then a place to discover
  const score = p => (Number(p.userRating) || 0) * 10
    + ((p.photos && p.photos.length) ? 30 : 0)
    + (DISCOVERY_CATEGORIES.has(String(p.category || '').toLowerCase()) ? 10 : 0);
  // Many saves tie at the top (rated 10 with a photo): pick one of those at
  // random so new users don't all get the same place
  const top = Math.max(...eligible.map(score));
  const best = eligible.filter(p => score(p) === top);
  return best[Math.floor(random() * best.length)] || best[0];
};

module.exports = { pickWelcomePlace, isStreetAddressName };
