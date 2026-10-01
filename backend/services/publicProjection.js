// services/publicProjection.js
//
// What one person's data looks like when it is handed to SOMEONE ELSE.
//
// The security audit of 2026-10-01 found the same leak in many shapes: a
// handler builds a user card or returns a raw document, and private fields
// (email, phone, invitee lists, private notes, exact distance) ride along
// because nobody listed what should go out. These helpers are allowlists —
// a new field on the source doc stays private until someone adds it here.
//
// Pure functions only (no Firestore), so every rule is table-tested.

const { normalizePrivacy, PRIVACY } = require('./visibility');

/**
 * The "added by" / attribution card for another user: who they are, never
 * how to reach them. Email used to be included on every card (audit
 * 2026-10-01), including on the unauthenticated public-circle endpoint.
 */
const publicUserSummary = (userData) => ({
  id: userData.id,
  displayName: userData.displayName || 'Unknown User',
  profilePicture: userData.profilePicture
});

/** "Show my city" switched off hides the location line from everyone else. */
const visibleLocation = (userData) =>
  (userData && userData.preferences && userData.preferences.showLocation === false)
    ? null
    : (userData ? userData.location : null);

// ---------------------------------------------------------------------------
// User search

const MIN_SEARCH_LENGTH = 2;
const MAX_SEARCH_RESULTS = 25;

/**
 * Does `user` match the (already lower-cased, trimmed) search term?
 *
 * Names only. Matching email or phone digits turned search into a lookup
 * oracle — type a number or address, learn whether (and who) it belongs to
 * (audit 2026-10-01). Finding people by contact details is the contacts
 * matcher's job, which works from the caller's own address book.
 */
const matchesUserSearch = (user, term) => {
  if (!user || !term) return false;
  const fields = [user.displayName, user.firstName, user.lastName];
  if (fields.some(v => typeof v === 'string' && v.toLowerCase().includes(term))) return true;
  const words = typeof user.displayName === 'string' ? user.displayName.toLowerCase().split(' ') : [];
  return words.some(w => w.startsWith(term));
};

/** Relevance: exact name, name prefix, a word in the name, then the rest. */
const searchRelevanceRank = (user, term) => {
  const name = (user.displayName || '').toLowerCase();
  if (name === term) return 0;
  if (name.startsWith(term)) return 1;
  if (name.split(' ').some(w => w.startsWith(term))) return 2;
  return 3;
};

// ---------------------------------------------------------------------------
// Circles

// Fields an anonymous visitor to a PUBLIC circle may see. Deliberately absent:
// sharedWith (can hold invitees' ids or emails), editors, followers, likes
// (user-id lists — the social graph), activeShares/shareSettings, and the
// `places` id list (it names places whose own privacy hides them).
const PUBLIC_CIRCLE_FIELDS = [
  '_id', 'id', 'name', 'description', 'coverImage', 'owner', 'creatorName',
  'privacy', 'category', 'customCategoryId', 'location', 'tags',
  'placesCount', 'likesCount', 'commentsCount', 'showOnMap',
  'createdAt', 'updatedAt'
];

const publicCircleFields = (circle) => {
  const out = {};
  for (const key of PUBLIC_CIRCLE_FIELDS) {
    if (circle[key] !== undefined) out[key] = circle[key];
  }
  return out;
};

// ---------------------------------------------------------------------------
// Moments

const isModerationHidden = (video) =>
  video.moderationStatus === 'under_review' || video.moderationStatus === 'removed';

/**
 * May this moment be shown to someone we know nothing about — a share link
 * opened in a browser, a link-preview crawler, the no-login details route?
 * Only public, live, un-moderated moments (audit 2026-10-01: these surfaces
 * served the place name/address and thumbnail of private moments).
 */
const isPubliclyViewableMoment = (video) => {
  if (!video) return false;
  if (video.deletedAt !== null && video.deletedAt !== undefined) return false;
  if (isModerationHidden(video)) return false;
  if (video.uploadStatus && video.uploadStatus !== 'ready') return false;
  return normalizePrivacy(video.visibility) === PRIVACY.PUBLIC;
};

// ---------------------------------------------------------------------------
// Distance

/**
 * Coarse distance for "people near you". Returning the exact distance to
 * 0.1 km from a caller-chosen origin let anyone triangulate another user's
 * last GPS fix (audit 2026-10-01). The app labels anything under 1 km as
 * "Near you", so the nearest bucket is 0.5; the rest read "5 km", "25 km"
 * and "100 km" (the nearby query already drops anyone past 160 km).
 */
const coarseDistanceKm = (km) => {
  if (!Number.isFinite(km) || km < 0) return null;
  if (km < 1) return 0.5;
  if (km <= 5) return 5;
  if (km <= 25) return 25;
  return 100;
};

module.exports = {
  publicUserSummary,
  visibleLocation,
  MIN_SEARCH_LENGTH,
  MAX_SEARCH_RESULTS,
  matchesUserSearch,
  searchRelevanceRank,
  publicCircleFields,
  isModerationHidden,
  isPubliclyViewableMoment,
  coarseDistanceKm
};
