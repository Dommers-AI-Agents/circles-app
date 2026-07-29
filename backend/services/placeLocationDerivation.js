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

// Country display name by ISO2 code, plus the name variants that show up at
// the tail of Apple/Google formatted addresses. Only countries actually seen
// in addresses matter — unknown tails just leave country null.
const COUNTRIES = {
  US: 'United States', CA: 'Canada', MX: 'Mexico', GB: 'United Kingdom',
  FR: 'France', IT: 'Italy', ES: 'Spain', PT: 'Portugal', DE: 'Germany',
  NL: 'Netherlands', BE: 'Belgium', CH: 'Switzerland', AT: 'Austria',
  IE: 'Ireland', IS: 'Iceland', DK: 'Denmark', NO: 'Norway', SE: 'Sweden',
  FI: 'Finland', GR: 'Greece', HR: 'Croatia', CZ: 'Czechia', PL: 'Poland',
  HU: 'Hungary', TR: 'Türkiye', JP: 'Japan', KR: 'South Korea', CN: 'China',
  TW: 'Taiwan', HK: 'Hong Kong', SG: 'Singapore', TH: 'Thailand',
  VN: 'Vietnam', ID: 'Indonesia', MY: 'Malaysia', PH: 'Philippines',
  IN: 'India', AE: 'United Arab Emirates', IL: 'Israel', EG: 'Egypt',
  ZA: 'South Africa', MA: 'Morocco', KE: 'Kenya', AU: 'Australia',
  NZ: 'New Zealand', FJ: 'Fiji', BR: 'Brazil', AR: 'Argentina', CL: 'Chile',
  PE: 'Peru', CO: 'Colombia', EC: 'Ecuador', CR: 'Costa Rica', PA: 'Panama',
  GT: 'Guatemala', BZ: 'Belize', DO: 'Dominican Republic', JM: 'Jamaica',
  BS: 'Bahamas', BB: 'Barbados', CU: 'Cuba', AW: 'Aruba', CW: 'Curaçao',
  KY: 'Cayman Islands', TC: 'Turks and Caicos Islands', VG: 'British Virgin Islands',
  LC: 'Saint Lucia', AG: 'Antigua and Barbuda', BM: 'Bermuda'
};

const COUNTRY_NAME_TO_CODE = Object.entries(COUNTRIES).reduce((acc, [code, name]) => {
  acc[name.toLowerCase()] = code;
  return acc;
}, {
  // Variants beyond the canonical display names
  'usa': 'US', 'united states of america': 'US', 'u.s.': 'US', 'u.s.a.': 'US',
  'uk': 'GB', 'england': 'GB', 'scotland': 'GB', 'wales': 'GB',
  'northern ireland': 'GB', 'great britain': 'GB',
  'turkey': 'TR', 'czech republic': 'CZ', 'south korea': 'KR',
  'republic of korea': 'KR', 'viet nam': 'VN', 'the bahamas': 'BS',
  'the netherlands': 'NL', 'holland': 'NL', 'uae': 'AE'
});

// The country named at the tail of the address, or null when unrecognized.
function parseCountry(address) {
  const stripped = stripLocationHint(address);
  const parts = stripped.split(',').map(p => p.trim()).filter(Boolean);
  if (!parts.length) return null;
  const code = COUNTRY_NAME_TO_CODE[parts[parts.length - 1].toLowerCase()];
  return code ? { country: COUNTRIES[code], countryCode: code } : null;
}

const UNPLACED = Object.freeze({
  state: null, stateCode: null, city: null, cityKey: null,
  neighborhood: null, source: null, placed: false,
  country: null, countryCode: null
});

// Some clients append a "📍 6.1 mi from current location" hint line after the
// address — drop it (and anything after it) before parsing.
function stripLocationHint(address) {
  return String(address || '').split('📍')[0].trim();
}

// Strip a trailing country and collapse whitespace.
function cleanAddress(address) {
  return stripLocationHint(address)
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
    // Couldn't resolve a US state. Still worth naming the country ("…, SK
    // S7K 2C7, Canada") — the country lens groups these; marked Unplaced only
    // for the US-state lens.
    const abroad = parseCountry(address);
    return {
      ...UNPLACED,
      neighborhood: neighborhood || null,
      country: abroad ? abroad.country : null,
      countryCode: abroad ? abroad.countryCode : null,
      source: abroad ? 'address' : null
    };
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
    placed: true,
    country: COUNTRIES.US,
    countryCode: 'US'
  };
}

module.exports = { deriveLocation, US_STATES, COUNTRIES, cleanAddress, parseStateAndCity, parseCountry };
