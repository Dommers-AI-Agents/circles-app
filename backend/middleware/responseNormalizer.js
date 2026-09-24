// backend/middleware/responseNormalizer.js
// Two response-shape safeguards, applied by wrapping res.json:
//
// 1. Error key mirroring. Error responses are split between
//    {success:false, message:...} (most controllers) and
//    {success:false, error:...} (rewards/subscription/referral/auth). Clients
//    have repeatedly shown generic text because they read the key a given
//    endpoint didn't use. Every non-2xx JSON object gets BOTH keys.
//
// 2. Moment visibility back-compat. Older app builds have a strict
//    VideoVisibility enum without the 'followers' tier and fail to decode ANY
//    moment tagged that way — which silently empties the entire moments feed
//    ("No moments yet"). Until those versions age out, downgrade the wire
//    value to 'network' (a value every shipped version decodes) for clients
//    that don't advertise followers support via the X-FC-Moments-Followers
//    header. Access control is unaffected: the server enforces visibility from
//    the STORED value, not this display copy.
//
// 3. Inner Circle back-compat, same idea but bigger blast radius. Circle and
//    Place decode `privacy` with a STRICT, non-optional Swift enum
//    (Models/Circle.swift `try container.decode(PrivacyLevel.self, ...)`), so a
//    single 'innerCircle' anywhere in a circles response throws mid-decode and
//    empties the WHOLE list on every shipped build. Clients that understand the
//    tier send X-FC-Inner-Circle: 1; everyone else sees 'private'.
//
//    Downgrading to 'private' rather than 'myNetwork' is deliberate: a stale
//    client mislabelling something as more private than it is costs a confusing
//    badge, while the other direction would tell someone their content is
//    narrower than it really is. Never round a privacy label outwards.

const FOLLOWERS_HEADER = 'x-fc-moments-followers';
const INNER_CIRCLE_HEADER = 'x-fc-inner-circle';

// Only touch video/reel responses — 'visibility' is a moment-only field in
// this API (circles/places use 'privacy'), and this keeps the walk off every
// other endpoint's payload.
const isMomentPath = (path) => path.includes('video') || path.includes('reel');

// Unlike the moments walk this cannot be path-scoped: `privacy` rides on
// circles, places, dashboard, browse, map, profile and suggestion payloads.
// Clients that advertise support skip the walk entirely and pay nothing.
function downgradeInnerCircle(node, depth = 0) {
  // Dashboard payloads nest circles[] -> placesWithDetails[] -> user objects.
  if (depth > 8 || node === null || typeof node !== 'object') return;
  if (Array.isArray(node)) {
    for (const item of node) downgradeInnerCircle(item, depth + 1);
    return;
  }
  if (node.privacy === 'innerCircle') node.privacy = 'private';
  if (node.visibility === 'innerCircle') node.visibility = 'private';
  for (const key of Object.keys(node)) {
    const value = node[key];
    if (value && typeof value === 'object') downgradeInnerCircle(value, depth + 1);
  }
}

function downgradeFollowersVisibility(node, depth = 0) {
  if (depth > 6 || node === null || typeof node !== 'object') return;
  if (Array.isArray(node)) {
    for (const item of node) downgradeFollowersVisibility(item, depth + 1);
    return;
  }
  if (node.visibility === 'followers') node.visibility = 'network';
  for (const key of Object.keys(node)) {
    const value = node[key];
    if (value && typeof value === 'object') downgradeFollowersVisibility(value, depth + 1);
  }
}

// The nearby check-in banner is switched off app-wide (Wes, 2026-09-24: it
// fires on region entry, so a drive past saved places is a burst of buzzes).
// Builds already installed mirror `notificationPreferences.locationPrompts`
// into the device gate on every profile load, so forcing it false here turns
// the banner off on phones that will never see the new build. Nothing is
// written to the user record; flip PROXIMITY_BANNERS_ENABLED and it is back.
const bannersOff = () => process.env.PROXIMITY_BANNERS_ENABLED === '0';
const isUserPath = (path) => path.includes('/users') || path.includes('/auth');
function forceLocationPromptsOff(node, depth = 0) {
  if (!node || typeof node !== 'object' || depth > 4) return;
  if (Array.isArray(node)) {
    for (const item of node) forceLocationPromptsOff(item, depth + 1);
    return;
  }
  const prefs = node.notificationPreferences;
  if (prefs && typeof prefs === 'object' && !Array.isArray(prefs)) prefs.locationPrompts = false;
  for (const key of ['user', 'data', 'users', 'primaryAccount']) {
    if (node[key] && typeof node[key] === 'object') forceLocationPromptsOff(node[key], depth + 1);
  }
}

module.exports = (req, res, next) => {
  const originalJson = res.json.bind(res);
  const clientKnowsFollowers = req.headers[FOLLOWERS_HEADER] === '1';
  const clientKnowsInnerCircle = req.headers[INNER_CIRCLE_HEADER] === '1';
  const momentPath = isMomentPath(req.path || '');
  const userPath = isUserPath(req.originalUrl || req.path || '');

  res.json = (body) => {
    if (res.statusCode >= 400 && body && typeof body === 'object' && !Array.isArray(body)) {
      if (typeof body.message === 'string' && body.error === undefined) {
        body.error = body.message;
      } else if (typeof body.error === 'string' && body.message === undefined) {
        body.message = body.error;
      }
    } else if (res.statusCode < 400 && body && typeof body === 'object') {
      if (momentPath && !clientKnowsFollowers) downgradeFollowersVisibility(body);
      if (!clientKnowsInnerCircle) downgradeInnerCircle(body);
      if (userPath && bannersOff()) forceLocationPromptsOff(body);
    }
    return originalJson(body);
  };
  next();
};

module.exports.forceLocationPromptsOff = forceLocationPromptsOff;
