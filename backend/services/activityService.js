// backend/services/activityService.js
// Barrel for the activity trackers, split by domain into services/activity/
// (Phase 6). Every existing import site keeps working; put new trackers in
// the matching submodule, and never require this barrel from inside one.

// resolvePlacePhoto is an internal helper shared between submodules, not
// part of the service's public surface.
const { resolvePlacePhoto: _internal, ...core } = require('./activity/core');

module.exports = {
  ...core,
  ...require('./activity/circles'),
  ...require('./activity/places'),
  ...require('./activity/media'),
  ...require('./activity/social'),
  ...require('./activity/stats'),
};
