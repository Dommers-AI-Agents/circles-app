// backend/services/browseAggregation.js
//
// Pure aggregation for the location browse lens — no IO, no Firebase, so it's
// unit-testable in isolation. The controller does the Firestore reads and calls
// these to shape the response.
//
// Counts are per unique VENUE (globalPlaceId): a venue saved to multiple circles
// is one pin with multiple source-circle chips.

const UNPLACED_KEY = '__unplaced__';

const venueKeyOf = (p) => p.globalPlaceId || p.id;

// State -> City tree with unique-venue counts.
function buildLocationTree(places) {
  const states = new Map();
  const unplaced = new Set();

  for (const p of places) {
    const vk = venueKeyOf(p);
    if (!p.stateCode) { unplaced.add(vk); continue; }

    let s = states.get(p.stateCode);
    if (!s) {
      s = { stateCode: p.stateCode, state: p.state || p.stateCode, venues: new Set(), cities: new Map() };
      states.set(p.stateCode, s);
    }
    s.venues.add(vk);

    const cityKey = p.cityKey || `${(p.city || 'unknown').toLowerCase()}|${p.stateCode}`;
    let c = s.cities.get(cityKey);
    if (!c) { c = { city: p.city || 'Unknown', cityKey, venues: new Set() }; s.cities.set(cityKey, c); }
    c.venues.add(vk);
  }

  const stateList = [...states.values()]
    .map(s => ({
      stateCode: s.stateCode,
      state: s.state,
      count: s.venues.size,
      cities: [...s.cities.values()]
        .map(c => ({ city: c.city, cityKey: c.cityKey, count: c.venues.size }))
        .sort((a, b) => b.count - a.count || a.city.localeCompare(b.city))
    }))
    .sort((a, b) => b.count - a.count || a.state.localeCompare(b.state));

  const result = { states: stateList };
  if (unplaced.size > 0) {
    result.unplaced = { cityKey: UNPLACED_KEY, count: unplaced.size };
  }
  return result;
}

// Group a city's saves into venues, each carrying its set of source circles.
function buildCityVenues(places, circleNameById) {
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
        circles: [],
        _circleIds: new Set()
      };
      byVenue.set(vk, v);
    }
    if (p.circleId && !v._circleIds.has(p.circleId)) {
      v._circleIds.add(p.circleId);
      v.circles.push({ id: p.circleId, name: (circleNameById && circleNameById.get(p.circleId)) || 'Circle' });
    }
  }
  return [...byVenue.values()].map(({ _circleIds, ...v }) => v);
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

module.exports = { buildLocationTree, buildCityVenues, densestNeighborhood, venueKeyOf, UNPLACED_KEY };
