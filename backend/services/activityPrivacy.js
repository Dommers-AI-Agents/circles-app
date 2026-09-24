// backend/services/activityPrivacy.js
//
// "Who can see my activity": one account-level grid of audience × activity
// category, on top of every item's own privacy.
//
// A row is shown to a viewer when BOTH hold: the item's privacy already
// allows them (the per-item gates, unchanged) and the actor's grid has a
// checked column the viewer qualifies for. The viewer qualifies for
// `innerCircle` when on one of the actor's lists (and still connected),
// for `myNetwork` when an accepted connection, for `public` always — so a
// closer relationship never sees less than a farther one. An actor always
// sees their own rows; a venue actor (`place_<id>`) is not a person and is
// never gated here.
//
// Absent grid, or absent category, means every column checked: the whole
// thing is opt-in narrowing, and rolling it out changed nobody's feed.

const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');
const { canViewCircle, canViewMoment, isPlaceVisibleToViewer } = require('./visibility');
const { isSameUser, normalizeUserId } = require('./idService');
const { ServiceError } = require('../utils/serviceError');

const AUDIENCES = ['public', 'myNetwork', 'innerCircle'];
const CATEGORIES = ['checkIns', 'photos', 'moments', 'savedPlaces', 'likesComments', 'circles'];

// Activity type → grid row. Anything not listed (venue rows, legacy types) is
// judged by the item gates alone.
const ACTIVITY_CATEGORY = {
  check_in: 'checkIns',
  photo_uploaded: 'photos',
  video_uploaded: 'moments',
  place_added: 'savedPlaces',
  place_liked: 'likesComments',
  place_commented: 'likesComments',
  comment_liked: 'likesComments',
  global_place_liked: 'likesComments',
  video_liked: 'likesComments',
  circle_liked: 'likesComments',
  circle_commented: 'likesComments',
  circle_created: 'circles'
};

const GETALL_CHUNK = 100;

const allTrue = () => Object.fromEntries(AUDIENCES.map((a) => [a, true]));

const defaultActivityPrivacy = () => Object.fromEntries(CATEGORIES.map((c) => [c, allTrue()]));

/** Whatever is stored → a full grid. Missing or malformed cells read as true. */
const normalizeActivityPrivacy = (raw) => {
  const grid = defaultActivityPrivacy();
  if (!raw || typeof raw !== 'object') return grid;
  for (const category of CATEGORIES) {
    const row = raw[category];
    if (!row || typeof row !== 'object') continue;
    for (const audience of AUDIENCES) {
      if (typeof row[audience] === 'boolean') grid[category][audience] = row[audience];
    }
  }
  return grid;
};

/**
 * A client-supplied grid → a full normalized grid, or a 400. Strict on
 * purpose: an unknown key is a client bug worth hearing about, not a value
 * to silently drop and then "save" as if it took.
 */
const validateActivityPrivacy = (body) => {
  const bad = (message, details) => new ServiceError(400, 'ACTIVITY_PRIVACY_INVALID', message, details);
  if (!body || typeof body !== 'object' || Array.isArray(body)) throw bad('activityPrivacy must be an object.');
  for (const key of Object.keys(body)) {
    if (!CATEGORIES.includes(key)) throw bad(`Unknown activity category "${key}".`, { key });
  }
  const grid = defaultActivityPrivacy();
  for (const category of CATEGORIES) {
    const row = body[category];
    if (row === undefined) throw bad(`Missing activity category "${category}".`, { key: category });
    if (!row || typeof row !== 'object' || Array.isArray(row)) throw bad(`"${category}" must be an object.`, { key: category });
    for (const key of Object.keys(row)) {
      if (!AUDIENCES.includes(key)) throw bad(`Unknown audience "${key}" in "${category}".`, { key: `${category}.${key}` });
    }
    for (const audience of AUDIENCES) {
      if (typeof row[audience] !== 'boolean') throw bad(`"${category}.${audience}" must be true or false.`, { key: `${category}.${audience}` });
      grid[category][audience] = row[audience];
    }
  }
  return grid;
};

const allowedAudiences = (settings, category) =>
  ({ ...allTrue(), ...((settings && settings[category]) || {}) });

const isVenueActor = (actorId) => typeof actorId === 'string' && actorId.startsWith('place_');

/**
 * Every column the viewer qualifies for with this actor, or null for the
 * actor themself. The viewer context's grantor set is already intersected
 * with connections (viewerContext.js), so `innerCircle` implies `myNetwork`.
 */
const qualifyingAudiences = (viewerCtx, actorId) => {
  if (!viewerCtx) return ['public'];
  if (viewerCtx.viewerId && isSameUser(actorId, viewerCtx.viewerId)) return null;
  const actor = normalizeUserId(actorId);
  const out = ['public'];
  if (viewerCtx.connections && viewerCtx.connections.has(actor)) out.push('myNetwork');
  if (viewerCtx.innerCircleGrantors && viewerCtx.innerCircleGrantors.has(actor)) out.push('innerCircle');
  return out;
};

const categoryOf = (activity) => (activity && ACTIVITY_CATEGORY[activity.type]) || null;

/** The grid half of the decision. */
const canViewActivity = (activity, viewerId, viewerCtx, settingsByActor) => {
  if (!activity) return false;
  if (isSameUser(activity.actorId, viewerId)) return true;
  if (isVenueActor(activity.actorId)) return true;
  const category = categoryOf(activity);
  if (!category) return true;
  const allowed = allowedAudiences(settingsByActor && settingsByActor.get(String(activity.actorId)), category);
  const qualifying = qualifyingAudiences(viewerCtx, activity.actorId);
  if (qualifying === null) return true;
  return qualifying.some((audience) => allowed[audience]);
};

/**
 * The item half: exactly what the network feed always did, in one place so
 * the dashboard, homescreen, realtime push and at-place list can't drift.
 *
 * - moments: judged by the viewer's relationship to the moment OWNER (the
 *   uploader, or for a like the moment's owner, not the liker); rows written
 *   before the stamp existed fall through as public.
 * - check-ins: no circle to hang privacy on, so the audience rides on the row;
 *   a named list reaches that list only.
 * - everything else: the circle it happened in, then the place's own tier.
 * `circlesById` may be null when the caller fetched no circles; a row that
 * references a circle is then withheld rather than guessed at.
 */
const passesItemGates = (activity, viewerId, viewerCtx, circlesById) => {
  const meta = activity.metadata || {};
  if (isSameUser(activity.actorId, viewerId)) return true;

  if (activity.type === 'video_uploaded' || activity.type === 'video_liked') {
    if (meta.momentVisibility && meta.momentOwnerId && !isSameUser(meta.momentOwnerId, viewerId)) {
      return canViewMoment({ userId: meta.momentOwnerId, visibility: meta.momentVisibility }, viewerId, viewerCtx);
    }
    return true;
  }

  if (activity.type === 'check_in' && meta.checkInAudience === 'innerCircle') {
    const actor = normalizeUserId(activity.actorId);
    if (meta.audienceListId) {
      const lists = viewerCtx.innerCircleLists && viewerCtx.innerCircleLists.get(actor);
      return !!(lists && lists.has(meta.audienceListId));
    }
    return !!(viewerCtx.innerCircleGrantors && viewerCtx.innerCircleGrantors.has(actor));
  }

  const circleId = activity.targetType === 'circle' ? activity.targetId : activity.circleId;
  if (!circleId) return true;
  const circle = circlesById && circlesById.get(circleId);
  if (!circle) return false;
  if (!canViewCircle(circle, viewerId, viewerCtx)) return false;

  if (meta.placePrivacy) {
    return isPlaceVisibleToViewer(
      { addedBy: activity.actorId, privacy: meta.placePrivacy, audienceListId: meta.placeAudienceListId || null },
      viewerId,
      viewerCtx
    );
  }
  return true;
};

/** Item gate ∧ grid, per row; anything that throws is withheld, as before. */
const filterActivitiesForViewer = ({ activities, viewerId, viewerCtx, circlesById, settingsByActor, skipItemGates = false }) =>
  (activities || []).filter((activity) => {
    try {
      // `skipItemGates` is for rows a cache already item-gated when it was
      // built; only the grid is re-judged.
      return (skipItemGates || passesItemGates(activity, viewerId, viewerCtx, circlesById))
        && canViewActivity(activity, viewerId, viewerCtx, settingsByActor);
    } catch (error) {
      console.error('Error checking activity privacy:', error);
      return false;
    }
  });

/** Grids off user docs a caller already fetched (raw or serialized). */
const activityPrivacyFromUserDocs = (docsById) => {
  const out = new Map();
  const entries = docsById instanceof Map ? docsById.entries() : Object.entries(docsById || {});
  for (const [id, doc] of entries) {
    if (!doc) continue;
    const data = typeof doc.data === 'function' ? doc.data() : doc;
    if (data && data.activityPrivacy) out.set(String(id), normalizeActivityPrivacy(data.activityPrivacy));
  }
  return out;
};

/**
 * Grids for actors the caller has NOT already loaded: one field-masked getAll
 * per 100 ids. Venue actors and seeded ids are skipped. Only actors with a
 * stored grid land in the map; everyone else reads as all-allowed.
 */
const loadActivityPrivacyByActor = async (actorIds, { seed } = {}) => {
  const out = new Map(seed || []);
  const db = getFirestore();
  const wanted = [...new Set((actorIds || []).filter(Boolean).map(String))]
    .filter((id) => !isVenueActor(id) && !out.has(id));
  for (let i = 0; i < wanted.length; i += GETALL_CHUNK) {
    const chunk = wanted.slice(i, i + GETALL_CHUNK);
    const refs = chunk.map((id) => db.collection(COLLECTIONS.USERS).doc(id));
    const docs = await db.getAll(...refs, { fieldMask: ['activityPrivacy'] });
    docs.forEach((doc) => {
      if (doc.exists && doc.data().activityPrivacy) out.set(doc.id, normalizeActivityPrivacy(doc.data().activityPrivacy));
    });
  }
  return out;
};

/**
 * The write-time counterpart, for fan-outs (connection rows, pushes, targeted
 * SSE) that go to the actor's CONNECTIONS: whether one recipient may be told
 * about something in `category`. `innerCircleIds` are the actor's list
 * members (the flat union). Every recipient here is a connection, so
 * `myNetwork` alone admits them all.
 */
const fanOutAllows = (settings, category, innerCircleIds) => {
  const allowed = allowedAudiences(settings, category);
  if (allowed.public || allowed.myNetwork) return () => true;
  if (!allowed.innerCircle) return () => false;
  const list = new Set((innerCircleIds || []).map(String));
  return (userId) => list.has(String(userId));
};

module.exports = {
  AUDIENCES,
  CATEGORIES,
  ACTIVITY_CATEGORY,
  defaultActivityPrivacy,
  normalizeActivityPrivacy,
  validateActivityPrivacy,
  allowedAudiences,
  isVenueActor,
  qualifyingAudiences,
  categoryOf,
  canViewActivity,
  passesItemGates,
  filterActivitiesForViewer,
  activityPrivacyFromUserDocs,
  loadActivityPrivacyByActor,
  fanOutAllows
};
