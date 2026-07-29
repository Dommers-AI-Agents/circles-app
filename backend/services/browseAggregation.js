// backend/services/browseAggregation.js
//
// Pure aggregation for the location browse lens — no IO, no Firebase, so it's
// unit-testable in isolation. The controller does the Firestore reads and calls
// these to shape the response.
//
// Network-wide model:
//  - The State→City TREE is built from precomputed per-circle summaries
//    (mergeSummaries) so a Browse-open never scans the whole network. Counts are
//    per-save density ("how much is here"), which sum cleanly across circles.
//  - The CITY view (buildCityVenues) is a bounded live query over one city and
//    dedupes to unique VENUES (globalPlaceId), each carrying its savers (the
//    people who saved it) and rating.

const UNPLACED_KEY = '__unplaced__';
// Namespace prefix for country region keys ("country:CA"). Bare ISO2 would
// collide with US state codes — Ontario, CA is both a California city and a
// Canadian province — so countries never share the "city|ST" key format.
const COUNTRY_KEY_PREFIX = 'country:';

const venueKeyOf = (p) => p.globalPlaceId || p.id;

// ---- Tree from per-circle summaries -------------------------------------

// summaries: [{ cityCounts: {cityKey: n}, cityMeta: {cityKey:{city,stateCode,state}},
//               countryCounts: {countryCode: n}, countryMeta: {countryCode:{country}},
//               unplacedCount }]
// Returns { states: [{stateCode, state, count, cities:[...], isCountry?}], unplaced? }
//
// Countries ride in the same `states` list as US states, flagged isCountry with
// an empty `cities` array — a non-US place has a country but no parseable city
// (parseStateAndCity only knows US states), so the client lists its venues
// directly instead of drilling to a city level that would always be empty.
function mergeSummaries(summaries) {
  const states = new Map();
  const countries = new Map();
  let unplaced = 0;

  for (const s of summaries) {
    if (!s) continue;
    unplaced += s.unplacedCount || 0;
    const cityCounts = s.cityCounts || {};
    const cityMeta = s.cityMeta || {};
    for (const cityKey of Object.keys(cityCounts)) {
      const count = cityCounts[cityKey];
      if (!count) continue;
      const meta = cityMeta[cityKey] || {};
      const stateCode = meta.stateCode || cityKey.split('|')[1] || '??';

      let st = states.get(stateCode);
      if (!st) { st = { stateCode, state: meta.state || stateCode, count: 0, cities: new Map() }; states.set(stateCode, st); }
      if (meta.state) st.state = meta.state;
      st.count += count;

      let c = st.cities.get(cityKey);
      if (!c) { c = { city: meta.city || 'Unknown', cityKey, count: 0 }; st.cities.set(cityKey, c); }
      if (meta.city) c.city = meta.city;
      c.count += count;
    }

    const countryCounts = s.countryCounts || {};
    const countryMeta = s.countryMeta || {};
    for (const countryCode of Object.keys(countryCounts)) {
      const count = countryCounts[countryCode];
      if (!count) continue;
      const meta = countryMeta[countryCode] || {};
      let ct = countries.get(countryCode);
      if (!ct) { ct = { countryCode, country: meta.country || countryCode, count: 0 }; countries.set(countryCode, ct); }
      if (meta.country) ct.country = meta.country;
      ct.count += count;
    }
  }

  const stateList = [...states.values()]
    .map(st => ({
      stateCode: st.stateCode,
      state: st.state,
      count: st.count,
      cities: [...st.cities.values()].sort((a, b) => b.count - a.count || a.city.localeCompare(b.city))
    }));

  const countryList = [...countries.values()].map(ct => ({
    stateCode: ct.countryCode,
    state: ct.country,
    countryCode: ct.countryCode,
    isCountry: true,
    // The key to pass to the city-places endpoint. A state row has none — the
    // client drills into cities[] for that — so a country carries its own.
    cityKey: `${COUNTRY_KEY_PREFIX}${ct.countryCode}`,
    count: ct.count,
    cities: []
  }));

  // One list, sorted by size — a Canadian user sees Canada first rather than
  // after every US state they've saved in.
  const regions = [...stateList, ...countryList]
    .sort((a, b) => b.count - a.count || a.state.localeCompare(b.state));

  const result = { states: regions };
  if (unplaced > 0) result.unplaced = { cityKey: UNPLACED_KEY, count: unplaced };
  return result;
}

// Build a single circle's summary shape from its (placed) place docs — used by
// the rebuild/build-summaries path. Counts saves; dedup is not applied here on
// purpose (tree counts are density).
function summarizeCirclePlaces(places) {
  const cityCounts = {};
  const cityMeta = {};
  const countryCounts = {};
  const countryMeta = {};
  let unplacedCount = 0;
  for (const p of places) {
    if (p.deletedAt) continue;
    if (p.stateCode && p.cityKey) {
      cityCounts[p.cityKey] = (cityCounts[p.cityKey] || 0) + 1;
      cityMeta[p.cityKey] = { city: p.city || 'Unknown', stateCode: p.stateCode, state: p.state || p.stateCode };
      continue;
    }
    // No US state, but a recognized country — placed at the country level
    // rather than dumped in Unplaced, which is what the map's region chips
    // already do for these.
    if (p.countryCode) {
      countryCounts[p.countryCode] = (countryCounts[p.countryCode] || 0) + 1;
      countryMeta[p.countryCode] = { country: p.country || p.countryCode };
      continue;
    }
    unplacedCount++;
  }
  return { cityCounts, cityMeta, countryCounts, countryMeta, unplacedCount };
}

// ---- City venues (bounded live query) -----------------------------------

// places: save docs in one city (may include several savers of the same venue).
// opts: { circleNameById: Map, userById: Map(id->{id,displayName,profilePicture}),
//         ratingByVenue: Map(globalPlaceId->number), currentUserId }
function buildCityVenues(places, opts = {}) {
  const { circleNameById, userById, ratingByVenue, currentUserId } = opts;
  const byVenue = new Map();

  for (const p of places) {
    const vk = venueKeyOf(p);
    let v = byVenue.get(vk);
    if (!v) {
      v = {
        globalPlaceId: p.globalPlaceId || null,
        placeId: p.id,
        name: p.name,
        category: p.category || 'other',
        address: p.address || '',
        neighborhood: p.neighborhood || null,
        city: p.city || null,
        state: p.state || null,
        stateCode: p.stateCode || null,
        location: p.location || null,
        rating: (ratingByVenue && p.globalPlaceId && ratingByVenue.get(p.globalPlaceId)) || null,
        circles: [],
        savers: [],
        savedByMe: false,
        _circleIds: new Set(),
        _saverIds: new Set()
      };
      byVenue.set(vk, v);
    }
    if (p.circleId && !v._circleIds.has(p.circleId)) {
      v._circleIds.add(p.circleId);
      v.circles.push({ id: p.circleId, name: (circleNameById && circleNameById.get(p.circleId)) || 'Circle' });
    }
    if (p.addedBy && !v._saverIds.has(p.addedBy)) {
      v._saverIds.add(p.addedBy);
      const u = userById && userById.get(p.addedBy);
      v.savers.push({
        id: p.addedBy,
        name: (u && u.displayName) || 'Someone',
        profilePicture: (u && u.profilePicture) || null
      });
      if (currentUserId && p.addedBy === currentUserId) v.savedByMe = true;
    }
  }

  return [...byVenue.values()].map(({ _circleIds, _saverIds, ...v }) => v);
}

// The neighborhood with the most pins (null when sparse -> callers fall back to city).
function densestNeighborhood(venues) {
  const counts = new Map();
  for (const v of venues) {
    if (!v.neighborhood) continue;
    counts.set(v.neighborhood, (counts.get(v.neighborhood) || 0) + 1);
  }
  let top = null, topN = 0;
  for (const [n, c] of counts) if (c > topN) { top = n; topN = c; }
  return top ? { neighborhood: top, count: topN } : null;
}

module.exports = {
  mergeSummaries,
  summarizeCirclePlaces,
  buildCityVenues,
  densestNeighborhood,
  venueKeyOf,
  UNPLACED_KEY,
  COUNTRY_KEY_PREFIX
};
