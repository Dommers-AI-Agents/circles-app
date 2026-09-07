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
// `extraFields` exists for surfaces where a field is deliberately shared:
// connections and conversation participants keep `email` because the iOS
// Messages screens (SelectConnection, AddParticipants, GroupConversation
// Settings) display a partner's email — a mutual, consented relationship.

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
function projectPublicUser(user, extraFields = []) {
  if (!user || typeof user !== 'object') return user;
  const projected = {};
  for (const field of [...PUBLIC_USER_FIELDS, ...extraFields]) {
    if (user[field] !== undefined) projected[field] = user[field];
  }
  return projected;
}

module.exports = { projectPublicUser, PUBLIC_USER_FIELDS };
