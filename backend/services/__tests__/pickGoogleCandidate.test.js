// Refresh from Google matched Wes's Skiptown to an empty stub listing (the
// nearest) instead of Google's first pick, the real one 100 m away.
const { pickGoogleCandidate } = require('../googleEnrichment');

const at = (id, lat, lng) => ({ place_id: id, geometry: { location: { lat, lng } } });
const SAVE = [-80.8645747, 35.2088955];

it('keeps Google\'s first pick when it is near the save', () => {
  const real = at('real', 35.2097318, -80.8640665);
  const stub = at('stub', 35.2089182, -80.8645446);
  expect(pickGoogleCandidate([real, stub], SAVE).place_id).toBe('real');
});

it('takes the nearest when Google\'s first pick is in another town', () => {
  const far = at('far', 35.78, -78.64);
  const here = at('here', 35.2089, -80.8645);
  expect(pickGoogleCandidate([far, here], SAVE).place_id).toBe('here');
});

it('no location: Google\'s first pick; nothing: null', () => {
  expect(pickGoogleCandidate([at('a', 1, 1), at('b', 2, 2)], null).place_id).toBe('a');
  expect(pickGoogleCandidate([], SAVE)).toBeNull();
});
