// backend/services/publicUserProjection.js
//
// The single allowlist for embedding one user's record inside data served to
// OTHER users (feed actors, comment authors, discovery cards, suggestion
// senders, connection/conversation partners).
//
// Before this existed, those embeds shipped the ENTIRE user document — email,
// phone number, Apple receipt blobs, device tokens, notification preferences,
// follower graphs — to every client that could see the surface (found
// 2026-09-08 while building the Android client). Clients only ever rendered
// name/photo/counts, so nothing visible changes; the private fields simply
// stop leaving the server.
//
// iOS decode-compatibility (verified against Models/User.swift): the custom
// decoder REQUIRES only `_id`/`id` and `displayName`; every other field is
// decodeIfPresent. Keep those two present and anything may be dropped.
//
// `extraFields` exists for surfaces where a field is deliberately shared.
// Connections no longer pass `email` (security audit 2026-10-01): the
// connections list handed every connection's — and every followed user's —
// address to the caller, and iOS only used it as a grey subtitle / search
// key in the Messages pickers (no "email this person" feature). Don't re-add it.
//
// `location` honours the user's "Show my city" switch
// (preferences.showLocation === false): hidden from everyone except the user
// themself. A hidden card also carries the LOCATION_HIDDEN symbol so later
// enrichment (userCardEnrichment.decorateUserCards) doesn't backfill an
// assumed city — symbols never reach the JSON response.
const { isSameUser } = require('./idService');

const LOCATION_HIDDEN = Symbol('locationHidden');

const PUBLIC_USER_FIELDS = [
  '_id', 'id',
  'displayName', 'firstName', 'lastName',
  'profilePicture', 'hasCustomProfilePicture',
  'bio', 'location', 'createdAt', 'lastActive',
  'followersCount', 'followingCount', 'connectionsCount',
  'placesCount', 'circlesCount',
  'isVerified', 'username', 'isFakeProfile',
  'isBusiness', 'storefront',
];

/**
 * Project a serialized user doc down to its public card. Returns a NEW object;
 * callers may attach per-viewer enrichment (connectionStatus, isFollowing,
 * followsYou, discoveryType, distance, matchType, ...) onto the result.
 */
function projectPublicUser(user, extraFields = [], { viewerId = null } = {}) {
  if (!user || typeof user !== 'object') return user;
  const projected = {};
  for (const field of [...PUBLIC_USER_FIELDS, ...extraFields]) {
    if (user[field] !== undefined) projected[field] = user[field];
  }
  const isSelf = viewerId && isSameUser(user.id || user._id, viewerId);
  if (!isSelf && user.preferences && user.preferences.showLocation === false) {
    projected.location = null;
    projected[LOCATION_HIDDEN] = true;
  }
  return projected;
}

module.exports = { projectPublicUser, PUBLIC_USER_FIELDS, LOCATION_HIDDEN };
