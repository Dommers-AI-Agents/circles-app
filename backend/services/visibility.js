// services/visibility.js
//
// One place that decides who may see a circle, a place, or a moment.
//
// Before this module the same four-way check (owner / sharedWith / public /
// connected) was copy-pasted about fifteen times across the place, circle and
// video controllers, each copy drifting a little. Adding the Inner Circle tier
// to fifteen copies was not an option, so they all call in here now.
//
// The ladder, from most open to most closed:
//
//   public       anyone, including people who only follow you
//   followers    people who follow you (moments only — circles have no such tier)
//   myNetwork    accepted connections. The UI calls this "Connections".
//   innerCircle  the accepted connections you put on your Inner Circle list
//   private      you alone
//
// Two things sit outside the ladder:
//   * `followCircle` on a place means "whatever the circle says" — it adds no
//     restriction of its own.
//   * `sharedWith[]` on a circle is a per-item guest list. It grants access at
//     any tier, including private, and is independent of the ladder.
//
// Everything is evaluated at READ time against the owner's CURRENT list. Taking
// someone off your Inner Circle retracts what they could already see; nothing is
// snapshotted at write time.

const PRIVACY = {
  PUBLIC: 'public',
  FOLLOWERS: 'followers',
  CONNECTIONS: 'myNetwork',
  INNER_CIRCLE: 'innerCircle',
  PRIVATE: 'private'
};

// A place may also say "inherit the circle".
const FOLLOW_CIRCLE = 'followCircle';

// Tiers a circle may be set to, in picker order. Circles have no `followers`
// tier: following someone is one-way, so it earns the public tier and no more.
const CIRCLE_PRIVACY_LEVELS = [
  PRIVACY.PUBLIC,
  PRIVACY.CONNECTIONS,
  PRIVACY.INNER_CIRCLE,
  PRIVACY.PRIVATE
];

// Tiers a place may be set to.
const PLACE_PRIVACY_LEVELS = [FOLLOW_CIRCLE, ...CIRCLE_PRIVACY_LEVELS];

// Moments keep their own spelling on the wire for back-compat: `network` is
// what circles call `myNetwork`. We normalise on read rather than migrating
// several thousand placeVideos docs.
const MOMENT_PRIVACY_LEVELS = [
  PRIVACY.PUBLIC,
  PRIVACY.FOLLOWERS,
  'network',
  PRIVACY.INNER_CIRCLE,
  PRIVACY.PRIVATE
];

// Every spelling we have ever written, mapped onto the ladder. `friends` and
// `my_network` are pre-2026 values still sitting in old docs; `network` is the
// moment vocabulary. Anything not in here is unknown and fails closed.
const ALIASES = {
  public: PRIVACY.PUBLIC,
  followers: PRIVACY.FOLLOWERS,
  mynetwork: PRIVACY.CONNECTIONS,
  my_network: PRIVACY.CONNECTIONS,
  network: PRIVACY.CONNECTIONS,
  friends: PRIVACY.CONNECTIONS,
  innercircle: PRIVACY.INNER_CIRCLE,
  inner_circle: PRIVACY.INNER_CIRCLE,
  private: PRIVACY.PRIVATE,
  followcircle: FOLLOW_CIRCLE,
  follow_circle: FOLLOW_CIRCLE
};

/**
 * Map any stored privacy spelling onto the canonical ladder.
 * @returns {string|null} a PRIVACY value, FOLLOW_CIRCLE, or null if unrecognised.
 */
const normalizePrivacy = (value) => {
  if (typeof value !== 'string') return null;
  const key = value.trim().toLowerCase().replace(/[\s-]/g, '_');
  return ALIASES[key] || ALIASES[key.replace(/_/g, '')] || null;
};

/** The spelling a moment doc should be stored with. */
const toMomentPrivacy = (value) => {
  const tier = normalizePrivacy(value);
  return tier === PRIVACY.CONNECTIONS ? 'network' : tier;
};

// Apple sign-in ids arrive in two shapes ("000454.<uid>.2127" and the bare
// uid), so every id comparison and every set lookup goes through idService —
// the same normalisation placeReadService has always used. Comparing raw
// strings here would silently fail the owner check for those accounts.
const { normalizeUserId, isSameUser } = require('./idService');

const NO_RELATIONSHIPS = {
  connections: new Set(),
  following: new Set(),
  innerCircleGrantors: new Set()
};

/**
 * Can `viewer` see something owned by `ownerId` published at `privacy`?
 *
 * Tier-only: it knows nothing about guest lists or circle inheritance, so
 * callers layer those on. Unknown tiers, and tiers that need a context the
 * caller did not supply, deny — we would rather hide something than leak it.
 *
 * @param {string} ownerId
 * @param {string} privacy   any stored spelling
 * @param {string} viewerId
 * @param {object} ctx  the VIEWER's relationships, all keyed by the other
 *   person's id: `connections` (accepted both ways), `following` (people the
 *   viewer follows), `innerCircleGrantors` (people whose Inner Circle list
 *   contains the viewer). Built by services/viewerContext.js.
 */
const canViewAtTier = (ownerId, privacy, viewerId, ctx) => {
  if (isSameUser(ownerId, viewerId)) return true;
  // A caller with no context can still be told about public content; every
  // narrower tier reads an empty relationship set and therefore denies.
  const rel = ctx || NO_RELATIONSHIPS;

  switch (normalizePrivacy(privacy)) {
    case PRIVACY.PUBLIC:
      return true;

    // Someone you are connected to is closer than someone who merely follows
    // you, so connections clear the followers bar too. The old moment feed
    // checked `following` alone and hid followers-tier moments from people who
    // were connected but had never tapped Follow.
    case PRIVACY.FOLLOWERS:
      return rel.following.has(normalizeUserId(ownerId)) || rel.connections.has(normalizeUserId(ownerId));

    case PRIVACY.CONNECTIONS:
      return rel.connections.has(normalizeUserId(ownerId));

    // Grantors are the people whose Inner Circle list contains the viewer.
    case PRIVACY.INNER_CIRCLE:
      return rel.innerCircleGrantors.has(normalizeUserId(ownerId));

    case PRIVACY.PRIVATE:
      return false;

    // `followCircle` has no meaning without a circle, and an unrecognised
    // value is a value we do not understand. Both deny.
    default:
      return false;
  }
};

/**
 * Can `viewerId` see this circle?
 * Owner, then the per-circle guest list, then the ladder.
 */
const canViewCircle = (circle, viewerId, ctx) => {
  if (!circle) return false;
  if (isSameUser(circle.owner, viewerId)) return true;
  if ((circle.sharedWith || []).some(id => isSameUser(id, viewerId))) return true;
  return canViewAtTier(circle.owner, circle.privacy, viewerId, ctx);
};

/**
 * Does the place's OWN privacy allow `viewerId` to see it?
 *
 * A place can only narrow what its circle already allows, never widen it, so
 * callers apply this AFTER `canViewCircle`. A place set to `followCircle` — the
 * default, and all the Add Place screen can produce — adds nothing.
 *
 * Callers that genuinely have no viewer context may omit `ctx`; every tier
 * above `public` then denies, which is the safe direction.
 */
const isPlaceVisibleToViewer = (place, viewerId, ctx) => {
  if (!place) return false;
  if (isSameUser(place.addedBy, viewerId)) return true;

  // No privacy field at all, or an explicit "inherit": the circle already
  // decided. A value we simply don't RECOGNISE is a different thing and must
  // deny — normalizePrivacy returns null for both, so check the raw field.
  const missing = place.privacy === undefined || place.privacy === null || place.privacy === '';
  if (missing) return true;

  const tier = normalizePrivacy(place.privacy);
  if (tier === FOLLOW_CIRCLE) return true;
  if (tier === null) return false;
  return canViewAtTier(place.addedBy, tier, viewerId, ctx);
};

/** Can `viewerId` see this moment? Moments carry their tier directly. */
const canViewMoment = (moment, viewerId, ctx) => {
  if (!moment) return false;
  const ownerId = moment.userId || moment.addedBy;
  if (isSameUser(ownerId, viewerId)) return true;
  return canViewAtTier(ownerId, moment.visibility, viewerId, ctx);
};

// ---------------------------------------------------------------------------
// Old-client write protection
//
// middleware/responseNormalizer.js shows `innerCircle` to clients that do not
// understand it as `private`. Those clients then echo the whole object back on
// save. Without a guard, opening and saving a circle on an old build would
// quietly collapse Inner Circle to Private.

const INNER_CIRCLE_HEADER = 'x-fc-inner-circle';

/** Does this request come from a build that understands the tier? */
const clientKnowsInnerCircle = (req) =>
  !!(req && req.headers && req.headers[INNER_CIRCLE_HEADER] === '1');

/**
 * The privacy value to actually store on an update.
 *
 * Only one case is special: an old client sending `private` for something we
 * told it was `private` but which is really `innerCircle`. We keep the stored
 * value. Any other incoming value is a deliberate choice by the person and is
 * honoured — including `public`, so nobody is ever trapped in a tier their app
 * cannot display. The guard can only preserve or narrow, never widen.
 */
const resolveIncomingPrivacy = ({ incoming, stored, req }) => {
  if (incoming === undefined || incoming === null || incoming === '') return stored;
  if (!clientKnowsInnerCircle(req)
      && normalizePrivacy(stored) === PRIVACY.INNER_CIRCLE
      && normalizePrivacy(incoming) === PRIVACY.PRIVATE) {
    return stored;
  }
  return incoming;
};

module.exports = {
  PRIVACY,
  INNER_CIRCLE_HEADER,
  clientKnowsInnerCircle,
  resolveIncomingPrivacy,
  FOLLOW_CIRCLE,
  CIRCLE_PRIVACY_LEVELS,
  PLACE_PRIVACY_LEVELS,
  MOMENT_PRIVACY_LEVELS,
  normalizePrivacy,
  toMomentPrivacy,
  canViewAtTier,
  canViewCircle,
  isPlaceVisibleToViewer,
  canViewMoment
};
