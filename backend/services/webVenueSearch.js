// backend/services/webVenueSearch.js — venue search for the web app's Add
// Place (GET /api/places/web-search).
//
// The iOS app finds venues with Apple MapKit on the phone; a browser has no
// such thing, so the web app asks here. The source is Photon
// (photon.komoot.io), a free geocoder over OpenStreetMap data. It is a shared
// public service with a fair-use policy, so this is a polite client: a
// User-Agent that says who is calling (no personal data), a 5 s timeout, and
// a 10-minute in-memory cache keyed by the rounded query + location so typing
// the same thing twice costs one call. Results are OpenStreetMap data
// (© OpenStreetMap contributors, ODbL): the app shows that credit.
//
// A venue found here carries no Google or Apple id. Saving it goes through
// placeSaveService like any typed place: Google is looked up by name at save
// time, and a place nothing can vouch for waits for review (placeApproval).
const { ServiceError } = require('../utils/serviceError');
const { isPlaceCategory } = require('../config/placeCategories');

const PHOTON_URL = 'https://photon.komoot.io/api/';
const USER_AGENT = 'FavCircles-WebApp/1.0 (+https://favcircles.com; place search)';
const TIMEOUT_MS = 5000;
const CACHE_TTL_MS = 10 * 60 * 1000;
const CACHE_MAX = 500;
const MIN_QUERY = 3;
const MAX_QUERY = 120;
const RESULT_LIMIT = 10;
// Photon ranks an exact name anywhere in the world above a near match next
// door (a search for "amelies" from Charlotte leads with Greece), so with a
// location it is asked for more and the nearest are kept.
const ASK_LIMIT_NEAR = 25;
const ATTRIBUTION = '© OpenStreetMap contributors';

const set = (...values) => new Set(values);

// OSM key → value → the app's category id (config/placeCategories.js).
// '*' is the key's default. Never 'home' or 'work': only the person picks those.
const OSM_CATEGORIES = {
  amenity: [
    ['restaurant', set('restaurant', 'fast_food', 'food_court', 'ice_cream')],
    ['cafe', set('cafe')],
    ['bar', set('bar', 'pub', 'biergarten', 'nightclub')],
    ['entertainment', set('cinema', 'theatre', 'casino', 'arts_centre', 'music_venue', 'events_venue', 'planetarium', 'community_centre')],
    ['healthcare', set('hospital', 'clinic', 'doctors', 'dentist', 'pharmacy', 'veterinary')],
    ['education', set('school', 'university', 'college', 'library', 'kindergarten', 'language_school', 'music_school')],
    ['finance', set('bank', 'atm', 'bureau_de_change')],
    ['transport', set('fuel', 'parking', 'bus_station', 'ferry_terminal', 'car_rental', 'charging_station', 'taxi', 'bicycle_rental')],
    ['service', set('post_office', 'car_wash', 'townhall', 'courthouse', 'police', 'fire_station', 'childcare', 'coworking_space')],
    ['fitness', set('gym')],
    ['retail', set('marketplace')]
  ],
  shop: [
    ['cafe', set('coffee', 'bakery', 'pastry', 'tea')],
    ['service', set('hairdresser', 'beauty', 'laundry', 'dry_cleaning', 'car_repair', 'tailor', 'massage', 'tattoo', 'travel_agency', 'funeral_directors', 'locksmith')],
    ['retail', '*']
  ],
  tourism: [
    ['hotel', set('hotel', 'motel', 'hostel', 'guest_house', 'apartment', 'resort', 'chalet')],
    ['attraction', set('attraction', 'museum', 'gallery', 'viewpoint', 'zoo', 'theme_park', 'aquarium', 'artwork')],
    ['outdoor', set('camp_site', 'picnic_site', 'caravan_site')]
  ],
  leisure: [
    ['fitness', set('fitness_centre', 'sports_centre', 'swimming_pool', 'fitness_station', 'dance', 'ice_rink', 'climbing')],
    ['outdoor', set('park', 'garden', 'nature_reserve', 'playground', 'dog_park', 'golf_course', 'pitch', 'marina', 'beach_resort', 'track')],
    ['entertainment', set('bowling_alley', 'amusement_arcade', 'escape_game', 'miniature_golf', 'stadium', 'water_park', 'trampoline_park')]
  ],
  craft: [
    ['bar', set('brewery', 'winery', 'distillery')],
    ['service', '*']
  ],
  historic: [['attraction', '*']],
  natural: [['outdoor', '*']],
  healthcare: [['healthcare', '*']],
  office: [['service', '*']],
  aeroway: [['transport', set('aerodrome', 'terminal')]],
  railway: [['transport', set('station', 'halt', 'tram_stop')]],
  public_transport: [['transport', '*']]
};

// Named things that are not places to save: roads, towns, borders, rivers
const NOT_VENUES = set('highway', 'place', 'boundary', 'waterway');

/** An OSM tag (key=value) as one of the app's category ids; 'other' when unknown. Pure. */
function categoryFor(osmKey, osmValue) {
  const rules = OSM_CATEGORIES[String(osmKey || '')];
  if (!rules) return 'other';
  const value = String(osmValue || '');
  for (const [category, values] of rules) {
    if (values === '*' || values.has(value)) return isPlaceCategory(category) ? category : 'other';
  }
  return 'other';
}

/** One line: "4321 Park Road, Charlotte, North Carolina 28209". Pure. */
function addressLine(props = {}) {
  const street = [props.housenumber, props.street].filter(Boolean).join(' ');
  const region = [props.state, props.postcode].filter(Boolean).join(' ');
  const parts = [
    street || props.locality || props.district || '',
    props.city || props.county || '',
    region,
    props.countrycode && props.countrycode !== 'US' ? props.country : ''
  ].map((part) => String(part || '').trim()).filter(Boolean);
  return parts.filter((part, index) => parts.indexOf(part) === index).join(', ');
}

/** A Photon feature as the app's venue result, or null when it isn't one. Pure. */
function mapFeature(feature) {
  const props = (feature && feature.properties) || {};
  const coordinates = feature && feature.geometry && feature.geometry.coordinates;
  const name = typeof props.name === 'string' ? props.name.replace(/\s+/g, ' ').trim() : '';
  if (!name || NOT_VENUES.has(props.osm_key)) return null;
  if (!Array.isArray(coordinates) || coordinates.length < 2) return null;
  const [lng, lat] = coordinates.map(Number);
  if (!Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat) > 90 || Math.abs(lng) > 180) return null;
  if (!props.osm_id) return null;
  return {
    name,
    // A save needs an address: a feature OSM has none for gets its coordinates
    address: addressLine(props) || `${lat.toFixed(5)}, ${lng.toFixed(5)}`,
    location: { type: 'Point', coordinates: [lng, lat] },
    category: categoryFor(props.osm_key, props.osm_value),
    source: 'osm',
    osmId: `${props.osm_type || 'N'}${props.osm_id}`
  };
}

/**
 * A Photon answer as venue results. Photon lists one OSM object once per tag
 * (amenity=cafe and shop=bakery for the same café): kept once, with the first
 * tag that maps to a real category. Pure.
 */
function mapFeatures(json) {
  const features = json && Array.isArray(json.features) ? json.features : [];
  const byId = new Map();
  for (const feature of features) {
    const venue = mapFeature(feature);
    if (!venue) continue;
    const seen = byId.get(venue.osmId);
    if (!seen) byId.set(venue.osmId, venue);
    else if (seen.category === 'other' && venue.category !== 'other') seen.category = venue.category;
  }
  return [...byId.values()];
}

const cleanQuery = (q) => String(q || '').replace(/\s+/g, ' ').trim().slice(0, MAX_QUERY);

const coordinate = (value, max) => {
  const number = typeof value === 'number' ? value : parseFloat(value);
  return Number.isFinite(number) && Math.abs(number) <= max ? number : null;
};

/** Where the search is centred, or null when lat/lng are missing or wrong. Pure. */
function originOf(lat, lng) {
  const origin = { lat: coordinate(lat, 90), lng: coordinate(lng, 180) };
  return origin.lat === null || origin.lng === null ? null : origin;
}

/** Cache key: the query without case, the location rounded to ~1 km. Pure. */
function cacheKey(q, origin) {
  const where = origin ? `${origin.lat.toFixed(2)},${origin.lng.toFixed(2)}` : 'anywhere';
  return `${cleanQuery(q).toLowerCase()}|${where}`;
}

/** Metres between two { lat, lng } points (haversine). Pure. */
function metersBetween(a, b) {
  const rad = (d) => (d * Math.PI) / 180;
  const h = Math.sin(rad(b.lat - a.lat) / 2) ** 2
    + Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(rad(b.lng - a.lng) / 2) ** 2;
  return 2 * 6371000 * Math.asin(Math.min(1, Math.sqrt(h)));
}

/**
 * The `limit` venues nearest `origin`, nearest first; Photon's own order
 * (and its first `limit`) when there is no origin. Pure.
 */
function nearestFirst(venues, origin, limit = RESULT_LIMIT) {
  if (!origin) return venues.slice(0, limit);
  return venues
    .map((venue, index) => {
      const [lng, lat] = venue.location.coordinates;
      return { venue, index, meters: metersBetween(origin, { lat, lng }) };
    })
    .sort((a, b) => a.meters - b.meters || a.index - b.index)
    .slice(0, limit)
    .map(({ venue }) => venue);
}

function photonUrl(q, origin) {
  const params = new URLSearchParams({ q, limit: String(origin ? ASK_LIMIT_NEAR : RESULT_LIMIT), lang: 'en' });
  if (origin) {
    params.set('lat', String(origin.lat));
    params.set('lon', String(origin.lng));
  }
  return `${PHOTON_URL}?${params.toString()}`;
}

const cache = new Map(); // key → { at, venues }

function remember(key, venues, now) {
  if (cache.size >= CACHE_MAX) {
    for (const [k, entry] of cache) {
      if (now - entry.at >= CACHE_TTL_MS) cache.delete(k);
    }
    // Still full of fresh entries: drop the oldest (Map keeps insertion order)
    while (cache.size >= CACHE_MAX) cache.delete(cache.keys().next().value);
  }
  cache.set(key, { at: now, venues });
}

/**
 * Venues matching `q`, nearest to (lat, lng) first when given.
 * Refuses with ServiceError: 400 QUERY_TOO_SHORT, 502 VENUE_SEARCH_UNAVAILABLE.
 * `deps.fetch` / `deps.now` are for tests.
 */
async function searchVenues({ q, lat, lng } = {}, deps = {}) {
  const query = cleanQuery(q);
  if (query.length < MIN_QUERY) {
    throw new ServiceError(400, 'QUERY_TOO_SHORT', `Type at least ${MIN_QUERY} letters to search`);
  }
  const origin = originOf(lat, lng);
  const now = (deps.now || Date.now)();
  const key = cacheKey(query, origin);
  const hit = cache.get(key);
  if (hit && now - hit.at < CACHE_TTL_MS) return hit.venues;

  const fetchImpl = deps.fetch || fetch;
  let json;
  try {
    const response = await fetchImpl(photonUrl(query, origin), {
      headers: { 'User-Agent': USER_AGENT, Accept: 'application/json' },
      signal: AbortSignal.timeout(TIMEOUT_MS)
    });
    if (!response.ok) throw new Error(`Photon answered ${response.status}`);
    json = await response.json();
  } catch (error) {
    // Not cached: the next try asks again
    console.warn(`[web-venue-search] ${error.message}`);
    throw new ServiceError(502, 'VENUE_SEARCH_UNAVAILABLE', "Place search isn't answering right now. Try again in a moment, or add the place by hand.");
  }
  const venues = nearestFirst(mapFeatures(json), origin);
  remember(key, venues, now);
  return venues;
}

const clearCache = () => cache.clear();

module.exports = {
  searchVenues, mapFeatures, mapFeature, nearestFirst, categoryFor, addressLine, cacheKey, originOf, clearCache,
  ATTRIBUTION, USER_AGENT, MIN_QUERY, CACHE_TTL_MS
};
