// Where the app assumes someone is when it doesn't know (Wes, 2026-10-17):
// FavCircles starts in Charlotte, so a new user without a location fix sees
// Charlotte places, maps and suggestions, not New York or San Francisco.
const DEFAULT_LOCATION = Object.freeze({
  name: 'Charlotte, NC',
  latitude: 35.2271,
  longitude: -80.8431
});

module.exports = { DEFAULT_LOCATION };
