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
// relationship the circle's own tier actually needs, so a public circle costs
// no reads at all and only an Inner Circle one costs two.

const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');
const { normalizePrivacy, PRIVACY } = require('./visibility');
const { isSameUser } = require('./idService');
const { listsFrom } = require('./innerCircleLists');

const db = getFirestore();

const listIncludes = (list, userId) => (list || []).some(id => isSameUser(id, userId));

/** Accepted connection in either direction. */
const areConnected = async (a, b) => {
  const [outgoing, incoming] = await Promise.all([
    db.collection(COLLECTIONS.CONNECTIONS)
      .where('userId', '==', a).where('connectedUserId', '==', b)
      .where('status', '==', 'accepted').get(),
    db.collection(COLLECTIONS.CONNECTIONS)
      .where('userId', '==', b).where('connectedUserId', '==', a)
      .where('status', '==', 'accepted').get()
  ]);
  return !outgoing.empty || !incoming.empty;
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
  if (tier === PRIVACY.PUBLIC) return true;
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

module.exports = { canViewCircleFor, areConnected };
