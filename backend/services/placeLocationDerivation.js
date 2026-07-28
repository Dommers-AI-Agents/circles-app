// backend/services/placeLocationDerivation.js
//
// Derive State / City (and, when available, neighborhood) for a place from data
// it ALREADY has — primarily the stored address string. This is free (no
// geocoding API call, which also sidesteps the disabled Geocoding API in prod)
// and covers the vast majority of US places, since Apple/Google both return a
// full "…, City, ST ZIP, United States" address.
//
// Neighborhood is NOT reliably present in an address string; it comes from a
// placemark subLocality (Apple) or a Google `neighborhood` component. We keep
// the field and accept it as an optional signal (populated when a caller
// forwards it); Part 3's "densest neighborhood" degrades to city when sparse.
//
// Places whose address can't be resolved to a US state fall into the `Unplaced`
// bucket (placed:false) so their pins are never lost from the location lens.

const US_STATES = {
  AL: 'Alabama', AK: 'Alaska', AZ: 'Arizona', AR: 'Arkansas', CA: 'California',
  CO: 'Colorado', CT: 'Connecticut', DE: 'Delaware', FL: 'Florida', GA: 'Georgia',
  HI: 'Hawaii', ID: 'Idaho', IL: 'Illinois', IN: 'Indiana', IA: 'Iowa',
  KS: 'Kansas', KY: 'Kentucky', LA: 'Louisiana', ME: 'Maine', MD: 'Maryland',
  MA: 'Massachusetts', MI: 'Michigan', MN: 'Minnesota', MS: 'Mississippi',
  MO: 'Missouri', MT: 'Montana', NE: 'Nebraska', NV: 'Nevada', NH: 'New Hampshire',
  NJ: 'New Jersey', NM: 'New Mexico', NY: 'New York', NC: 'North Carolina',
  ND: 'North Dakota', OH: 'Ohio', OK: 'Oklahoma', OR: 'Oregon', PA: 'Pennsylvania',
  RI: 'Rhode Island', SC: 'South Carolina', SD: 'South Dakota', TN: 'Tennessee',
  TX: 'Texas', UT: 'Utah', VT: 'Vermont', VA: 'Virginia', WA: 'Washington',
  WV: 'West Virginia', WI: 'Wisconsin', WY: 'Wyoming',
  DC: 'District of Columbia', PR: 'Puerto Rico', VI: 'U.S. Virgin Islands',
  GU: 'Guam'
};

const NAME_TO_CODE = Object.entries(US_STATES).reduce((acc, [code, name]) => {
  acc[name.toLowerCase()] = code;
  return acc;
}, {});

const UNPLACED = Object.freeze({
  state: null, stateCode: null, city: null, cityKey: null,
  neighborhood: null, source: null, placed: false
});

// Strip a trailing country and collapse whitespace.
function cleanAddress(address) {
  return String(address || '')
    .replace(/,?\s*(United States of America|United States|U\.?S\.?A\.?|U\.?S\.?)\s*$/i, '')
    .replace(/\s+/g, ' ')
    .trim();
}

// Pull { stateCode, cityFromSegment } out of address comma-segments.
function parseStateAndCity(address) {
  const cleaned = cleanAddress(address);
  if (!cleaned) return { stateCode: null, city: null };

  const parts = cleaned.split(',').map(p => p.trim()).filter(Boolean);
  if (!parts.length) return { stateCode: null, city: null };

  // Find the segment carrying the state (from the end — it's near the tail).
  for (let i = parts.length - 1; i >= 0; i--) {
    const part = parts[i];

    // "NC 28269" | "NC" | "NC 28269-1234"  (optionally with a leading city word)
    const codeMatch = part.match(/\b([A-Z]{2})\b(?:\s+\d{5}(?:-\d{4})?)?$/);
    if (codeMatch && US_STATES[codeMatch[1]]) {
      const stateCode = codeMatch[1];
      // City: the text before the code on the same segment, else the prior segment.
      const before = part.slice(0, codeMatch.index).replace(/[,\s]+$/, '').trim();
      const city = before || (i > 0 ? parts[i - 1] : null);
      return { stateCode, city: city || null };
    }

    // Full state name as its own segment ("North Carolina")
    const asName = NAME_TO_CODE[part.toLowerCase()];
    if (asName) {
      const city = i > 0 ? parts[i - 1] : null;
      return { stateCode: asName, city: city || null };
    }
  }

  return { stateCode: null, city: null };
}

function titleCaseCity(city) {
  if (!city) return null;
  // Addresses are already well-cased; just trim stray tokens (e.g. a zip that
  // slipped in) and normalize spacing.
  return city.replace(/\s+\d{5}(-\d{4})?$/, '').replace(/\s+/g, ' ').trim() || null;
}

// signals: { address, location?, neighborhood? }
// Returns { state, stateCode, city, cityKey, neighborhood, source, placed }.
function deriveLocation(signals = {}) {
  const { address, neighborhood } = signals;
  const { stateCode, city: rawCity } = parseStateAndCity(address);

  if (!stateCode) {
    // Couldn't resolve a state from the address. Keep any forwarded
    // neighborhood but mark as Unplaced so the lens still lists it.
    return { ...UNPLACED, neighborhood: neighborhood || null };
  }

  const city = titleCaseCity(rawCity);
  const cityKey = city ? `${city.toLowerCase()}|${stateCode}` : null;

  return {
    state: US_STATES[stateCode],
    stateCode,
    city,
    cityKey,
    neighborhood: neighborhood || null,
    source: 'address',
    placed: true
  };
}

module.exports = { deriveLocation, US_STATES, cleanAddress, parseStateAndCity };
