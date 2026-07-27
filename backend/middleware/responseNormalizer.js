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

const FOLLOWERS_HEADER = 'x-fc-moments-followers';

// Only touch video/reel responses — 'visibility' is a moment-only field in
// this API (circles/places use 'privacy'), and this keeps the walk off every
// other endpoint's payload.
const isMomentPath = (path) => path.includes('video') || path.includes('reel');

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

module.exports = (req, res, next) => {
  const originalJson = res.json.bind(res);
  const clientKnowsFollowers = req.headers[FOLLOWERS_HEADER] === '1';
  const momentPath = isMomentPath(req.path || '');

  res.json = (body) => {
    if (res.statusCode >= 400 && body && typeof body === 'object' && !Array.isArray(body)) {
      if (typeof body.message === 'string' && body.error === undefined) {
        body.error = body.message;
      } else if (typeof body.error === 'string' && body.message === undefined) {
        body.message = body.error;
      }
    } else if (res.statusCode < 400 && momentPath && !clientKnowsFollowers && body && typeof body === 'object') {
      downgradeFollowersVisibility(body);
    }
    return originalJson(body);
  };
  next();
};
