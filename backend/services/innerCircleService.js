// services/innerCircleService.js
//
// The Inner Circle list: one curated set of people per user, reused by every
// circle, place, moment and check-in that picks the Inner Circle tier. Stored
// as `users/{uid}.innerCircle` — an array of uids.
//
// Two rules give the feature its shape:
//
//  1. Only accepted connections may be on the list. A stranger cannot be handed
//     private access, and if a connection ends the grant ends with it.
//  2. Access is decided at READ time against the CURRENT list. Removing someone
//     retracts everything they could already see — there is no snapshot taken
//     when a circle is created.
//
// Reads go the other way round from what you would expect. Rather than asking
// "who is on this owner's list" for every owner in a feed, we ask once, for the
// viewer: "whose list am I on?" That is a single array-contains query on a
// single-field index, and it yields the set the visibility gate needs.

const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');
const { getConnectedUserIds, getInnerCircleGrantorIds } = require('../utils/networkAccess');

const db = getFirestore();

// Large enough that nobody realistic hits it, small enough that the list still
// means something and the user doc stays far from Firestore's 1MB ceiling.
const MAX_INNER_CIRCLE = 150;

const asIdArray = (value) =>
  Array.isArray(value) ? value.filter(id => typeof id === 'string' && id.length > 0).map(String) : [];

/** The owner's own list. */
const getInnerCircle = async (userId) => {
  const doc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
  return doc.exists ? asIdArray(doc.data().innerCircle) : [];
};

class InnerCircleError extends Error {
  constructor(message, code = 'INNER_CIRCLE_INVALID') {
    super(message);
    this.name = 'InnerCircleError';
    this.code = code;
  }
}

/**
 * Replace the whole list. Rejects anyone who is not an accepted connection so
 * the invariant can never be broken from the API side.
 *
 * @returns {Promise<string[]>} the stored list
 */
const setInnerCircle = async (userId, requestedIds) => {
  const wanted = [...new Set(asIdArray(requestedIds))].filter(id => id !== String(userId));

  if (wanted.length > MAX_INNER_CIRCLE) {
    throw new InnerCircleError(
      `An Inner Circle can hold up to ${MAX_INNER_CIRCLE} people.`,
      'INNER_CIRCLE_TOO_LARGE'
    );
  }

  const connected = await getConnectedUserIds(userId);
  const notConnected = wanted.filter(id => !connected.has(id));
  if (notConnected.length > 0) {
    throw new InnerCircleError(
      'You can only add people you are connected with.',
      'INNER_CIRCLE_NOT_CONNECTED'
    );
  }

  await db.collection(COLLECTIONS.USERS).doc(userId).update({
    innerCircle: wanted,
    updatedAt: new Date().toISOString()
  });
  return wanted;
};

/** Add one person, keeping the list a set. */
const addToInnerCircle = async (userId, targetId) => {
  const current = await getInnerCircle(userId);
  if (current.includes(String(targetId))) return current;
  return setInnerCircle(userId, [...current, targetId]);
};

/** Remove one person. Their access is gone on the next read. */
const removeFromInnerCircle = async (userId, targetId) => {
  const current = await getInnerCircle(userId);
  const next = current.filter(id => id !== String(targetId));
  if (next.length === current.length) return current;
  // Straight to the doc: a removal can never break the connected-only rule, and
  // re-validating would fail for exactly the case we are cleaning up after.
  await db.collection(COLLECTIONS.USERS).doc(userId).update({
    innerCircle: next,
    updatedAt: new Date().toISOString()
  });
  return next;
};

/**
 * Called when two people stop being connected, in either direction. The grant
 * cannot outlive the connection that qualified it, so both lists are cleaned.
 * Safe to call when neither list mentions the other.
 */
const revokeMutualGrants = async (userId, otherUserId) => {
  await Promise.all([
    removeFromInnerCircle(userId, otherUserId),
    removeFromInnerCircle(otherUserId, userId)
  ]);
};

module.exports = {
  MAX_INNER_CIRCLE,
  InnerCircleError,
  getInnerCircle,
  getInnerCircleGrantorIds,
  setInnerCircle,
  addToInnerCircle,
  removeFromInnerCircle,
  revokeMutualGrants
};
