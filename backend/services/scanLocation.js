// services/scanLocation.js
//
// Was the phone at the store when it scanned the register code? (Wes,
// 2026-11-02: rewards are small giveaways on the honor system — the check
// stops earning from home with a photo of the sticker; it doesn't try to tell
// the counter from the parking lot, which phone GPS can't.)
//
//   'near'   the phone's fix is within reach of the store → earns
//   'far'    clearly elsewhere (or the App Clip's Apple check said so) → no points
//   'off'    the customer kept location off → still earns, marked for the owner
//   'unknown' no usable fix and no "off" (older apps, GPS timed out, a fix too
//            vague to judge such as Approximate Location, the clip couldn't
//            tell, a store with no map point) → earns, as before. A failed
//            check never turns an honest customer away (Wes, 2026-11-03);
//            only a good fix clearly away from the store does.
//
// Reach = SCAN_RADIUS_M plus the fix's own uncertainty (capped), so a poor
// indoor fix never turns a regular away.

const { distanceMeters } = require('../utils/photoCapture');

const SCAN_RADIUS_M = 300;
const MAX_ACCURACY_SLACK_M = 500;

/** {latitude, longitude} or null, whichever shape a store or phone point came in. */
const pointOf = (location) => {
  if (!location) return null;
  if (Array.isArray(location.coordinates) && location.coordinates.length === 2) {
    const [longitude, latitude] = location.coordinates.map(Number);
    return Number.isFinite(latitude) && Number.isFinite(longitude) ? { latitude, longitude } : null;
  }
  const latitude = Number(location.latitude ?? location.lat ?? location._latitude);
  const longitude = Number(location.longitude ?? location.lng ?? location._longitude);
  return Number.isFinite(latitude) && Number.isFinite(longitude) ? { latitude, longitude } : null;
};

/** The phone's fix from a scan body: `{ location: {latitude, longitude, accuracy}, locationOff }`. */
const phoneFix = (body) => {
  const point = pointOf(body && body.location);
  if (!point) return null;
  const accuracy = Number(body.location.accuracy);
  return { ...point, accuracy: Number.isFinite(accuracy) && accuracy > 0 ? accuracy : 0 };
};

/** 'near' | 'far' | 'off' | 'unknown' for a register scan (see top). */
function scanLocationCheck(body, venue) {
  if (body && body.atStore === false) return 'far';
  // A fix vaguer than the slack we allow can't say where the phone is
  const raw = phoneFix(body);
  const fix = raw && raw.accuracy <= MAX_ACCURACY_SLACK_M ? raw : null;
  const store = pointOf(venue && venue.location);
  if (fix && store) {
    const reach = SCAN_RADIUS_M + fix.accuracy;
    return distanceMeters(fix.latitude, fix.longitude, store.latitude, store.longitude) <= reach ? 'near' : 'far';
  }
  if (!raw && body && body.locationOff === true) return 'off';
  if (body && body.atStore === true) return 'near';
  return 'unknown';
}

module.exports = { scanLocationCheck, pointOf, SCAN_RADIUS_M };
