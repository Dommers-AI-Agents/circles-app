// backend/services/googleAddressGuard.js — Google answers a business search
// with a street address entry when it can't match the name ("Uptown Yolk
// Cafe" → "116 W Catherine St", 2026-10-23). Such an entry is not a venue:
// it must never name one, and its id must never become a venue's
// googlePlaceId (every business at that address would then merge into it).
// Pure.

// Google types that mean "a place on the map that is only an address"
const ADDRESS_TYPES = new Set([
  'street_address', 'premise', 'subpremise', 'route', 'intersection',
  'street_number', 'postal_code', 'plus_code', 'geocode'
]);

/** True when Google's types say this is an address, not a business. */
function isAddressOnly(types) {
  if (!Array.isArray(types) || types.length === 0) return false;
  if (types.includes('establishment') || types.includes('point_of_interest')) return false;
  return types.some((t) => ADDRESS_TYPES.has(t));
}

const norm = (s) => String(s || '').toLowerCase()
  .replace(/[^a-z0-9]+/g, ' ').trim();

/**
 * True when `name` is just the street line of `address` ("116 W Catherine
 * St" for "116 W Catherine St, Charlotte, NC 28203, USA").
 */
function isStreetLineName(name, address) {
  const n = norm(name);
  if (!n || !/^\d/.test(n)) return false;
  const streetLine = norm(String(address || '').split(',')[0]);
  return !!streetLine && n === streetLine;
}

module.exports = { isAddressOnly, isStreetLineName };
