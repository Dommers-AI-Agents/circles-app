// services/circleAccess.js
//
// "May this viewer open this circle?" for endpoints that hold exactly one
// circle — liking a place, reading its comments, editing venue fields.
//
// Every one of those endpoints used to carry its own copy of the same block:
// owner, sharedWith, public, and a pair of connection queries for myNetwork.
// Seven copies in placeSocialController alone, plus more in placeController,
// each with its own slightly different wording and its own chance of being
// missed when a tier is added.
//
// Cheaper than services/viewerContext.js on purpose: it resolves only the
// relationship the circle's own tier actually needs, so a public circle on a
// public profile costs no reads at all and only an Inner Circle one costs two.

const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');
const { normalizePrivacy, PRIVACY } = require('./visibility');
const { isSameUser } = require('./idService');
const { listsFrom } = require('./innerCircleLists');
const { isPrivateProfile } = require('./profilePrivacy');

const db = getFirestore();

const listIncludes = (list, userId) => (list || []).some(id => isSameUser(id, userId));

/** Accepted connection in either direction (shared helper, utils/networkAccess). */
const areConnected = (a, b) => require('../utils/networkAccess').areConnected(a, b);

/** Does `viewerId` follow `ownerId`? (one user-doc read, shared per request) */
const isFollowing = async (viewerId, ownerId) => {
  const doc = await require('../utils/networkAccess').getUserDocOnce(viewerId);
  return listIncludes(doc.exists ? doc.data().following : [], ownerId);
};

/**
 * @param {object} circle   the circle doc (serialized or raw)
 * @param {string} viewerId
 * @returns {Promise<boolean>}
 */
const canViewCircleFor = async (circle, viewerId) => {
  if (!circle || !viewerId) return false;
  if (isSameUser(circle.owner, viewerId)) return true;
  // The per-circle guest list wins at every tier, including private.
  if (listIncludes(circle.sharedWith, viewerId)) return true;

  const tier = normalizePrivacy(circle.privacy);
  // Public: anyone, unless the owner's profile is private — then followers
  // and connections only (services/profilePrivacy.js).
  if (tier === PRIVACY.PUBLIC) {
    if (!isPrivateProfile(circle.owner)) return true;
    return (await isFollowing(viewerId, circle.owner)) || areConnected(viewerId, circle.owner);
  }
  // private, followCircle (meaningless on a circle) and anything we don't
  // recognise all stop here.
  if (tier !== PRIVACY.CONNECTIONS && tier !== PRIVACY.INNER_CIRCLE) return false;

  if (!(await areConnected(viewerId, circle.owner))) return false;
  if (tier === PRIVACY.CONNECTIONS) return true;

  // Inner Circle: being connected is necessary but not sufficient. When the
  // circle names one of the owner's lists, only that list counts.
  const ownerDoc = await db.collection(COLLECTIONS.USERS).doc(String(circle.owner)).get();
  if (!ownerDoc.exists) return false;
  const listId = circle.audienceListId || null;
  if (!listId) return listIncludes(ownerDoc.data().innerCircle, viewerId);
  const named = listsFrom(ownerDoc.data()).find(list => list.id === listId);
  return !!named && listIncludes(named.userIds, viewerId);
};

/**
 * For the pages a share link opens (no sign-in needed): a public circle opens
 * for anyone when its owner's profile is public; on a private profile only
 * for a signed-in follower or connection.
 */
const canOpenPublicCircle = async (circle, viewerId) => {
  if (!circle || !isPrivateProfile(circle.owner)) return true;
  if (!viewerId) return false;
  return canViewCircleFor(circle, viewerId);
};

/**
 * How many places a connection would find in this circle: not trashed, and
 * not narrowed to Inner Circle or Private (an unset or "followCircle" place
 * inherits the circle, so it counts). Connecting never shows fewer places
 * than the locked card promised.
 */
const countConnectionPlaces = async (circleId) => {
  const snap = await db.collection(COLLECTIONS.PLACES)
    .where('circleId', '==', circleId)
    .select('deletedAt', 'privacy')
    .get();
  return snap.docs.filter(doc => {
    const d = doc.data();
    if (d.deletedAt) return false;
    const tier = normalizePrivacy(d.privacy);
    return tier !== PRIVACY.INNER_CIRCLE && tier !== PRIVACY.PRIVATE;
  }).length;
};

/**
 * A Connections circle as a viewer who isn't connected sees it on the
 * owner's profile (Wes, 2026-10-17): greyed and locked, so they know there is
 * more and ask to connect instead of only following. Name, cover and place
 * count only — never places, guests, editors or the description. The detail
 * endpoint still refuses it.
 *
 * A private profile's Public circles are locked the same way for anyone who
 * doesn't follow them (Wes, 2026-11-02): `lockedReason` 'follow' instead of
 * 'connect', so the app offers Follow.
 *
 * @param {object} circle  the serialized circle (`_id`, ISO dates)
 * @param {number} placesCount
 * @param {'connect'|'follow'} reason
 */
const lockedCircleStub = (circle, placesCount, reason = 'connect') => ({
  _id: circle._id,
  name: circle.name,
  coverImage: circle.coverImage || null,
  owner: circle.owner,
  privacy: reason === 'follow' ? PRIVACY.PUBLIC : PRIVACY.CONNECTIONS,
  category: circle.category,
  customCategoryId: circle.customCategoryId || null,
  createdAt: circle.createdAt,
  updatedAt: circle.updatedAt,
  placesCount,
  places: [],
  placesWithDetails: [],
  locked: true,
  lockedReason: reason
});

module.exports = { canViewCircleFor, canOpenPublicCircle, areConnected, lockedCircleStub, countConnectionPlaces };
