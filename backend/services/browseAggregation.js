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

const venueKeyOf = (p) => p.globalPlaceId || p.id;

// ---- Tree from per-circle summaries -------------------------------------

// summaries: [{ cityCounts: {cityKey: n}, cityMeta: {cityKey:{city,stateCode,state}}, unplacedCount }]
// Returns { states: [{stateCode, state, count, cities:[{city,cityKey,count}]}], unplaced? }
function mergeSummaries(summaries) {
  const states = new Map();
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
  }

  const stateList = [...states.values()]
    .map(st => ({
      stateCode: st.stateCode,
      state: st.state,
      count: st.count,
      cities: [...st.cities.values()].sort((a, b) => b.count - a.count || a.city.localeCompare(b.city))
    }))
    .sort((a, b) => b.count - a.count || a.state.localeCompare(b.state));

  const result = { states: stateList };
  if (unplaced > 0) result.unplaced = { cityKey: UNPLACED_KEY, count: unplaced };
  return result;
}

// Build a single circle's summary shape from its (placed) place docs — used by
// the rebuild/build-summaries path. Counts saves; dedup is not applied here on
// purpose (tree counts are density).
function summarizeCirclePlaces(places) {
  const cityCounts = {};
  const cityMeta = {};
  let unplacedCount = 0;
  for (const p of places) {
    if (p.deletedAt) continue;
    if (!p.stateCode || !p.cityKey) { unplacedCount++; continue; }
    cityCounts[p.cityKey] = (cityCounts[p.cityKey] || 0) + 1;
    cityMeta[p.cityKey] = { city: p.city || 'Unknown', stateCode: p.stateCode, state: p.state || p.stateCode };
  }
  return { cityCounts, cityMeta, unplacedCount };
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
  UNPLACED_KEY
};
