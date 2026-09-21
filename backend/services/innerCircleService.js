// services/innerCircleService.js
//
// Inner Circle lists: named sets of people, reused by every circle, place,
// moment and check-in that picks the Inner Circle tier. The shape and the
// two fields that hold it are described in services/innerCircleLists.js.
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
const {
  DEFAULT_LIST_ID, DEFAULT_LIST_NAME, MAX_LISTS, asIdArray, cleanName, listsFrom, unionOf
} = require('./innerCircleLists');

const db = getFirestore();

// Large enough that nobody realistic hits it, small enough that the list still
// means something and the user doc stays far from Firestore's 1MB ceiling.
const MAX_INNER_CIRCLE = 150;

class InnerCircleError extends Error {
  constructor(message, code = 'INNER_CIRCLE_INVALID') {
    super(message);
    this.name = 'InnerCircleError';
    this.code = code;
  }
}

const userRef = (userId) => db.collection(COLLECTIONS.USERS).doc(String(userId));

const readLists = async (userId) => {
  const doc = await userRef(userId).get();
  return doc.exists ? listsFrom(doc.data()) : [];
};

/**
 * Store the lists, and with them the flat union that the reverse lookup
 * reads. The two are written together, always, because a union that lags
 * behind the lists is either a leak or a disappearance.
 */
const writeLists = async (userId, lists) => {
  await userRef(userId).update({
    innerCircles: lists,
    innerCircle: unionOf(lists),
    updatedAt: new Date().toISOString()
  });
  return lists;
};

/** The connected-only rule, applied to one list's membership. */
const vetMembers = async (userId, requestedIds, { tooLargeCode = 'INNER_CIRCLE_TOO_LARGE', strangerCode = 'INNER_CIRCLE_NOT_CONNECTED' } = {}) => {
  const wanted = asIdArray(requestedIds).filter(id => id !== String(userId));
  if (wanted.length > MAX_INNER_CIRCLE) {
    throw new InnerCircleError(`An Inner Circle can hold up to ${MAX_INNER_CIRCLE} people.`, tooLargeCode);
  }
  if (wanted.length === 0) return wanted;
  const connected = await getConnectedUserIds(userId);
  if (wanted.some(id => !connected.has(id))) {
    throw new InnerCircleError('You can only add people you are connected with.', strangerCode);
  }
  return wanted;
};

// MARK: - Named lists

/** Every list this user keeps. Always at least the default once they have one. */
const getInnerCircleLists = async (userId) => readLists(userId);

const createInnerCircleList = async (userId, { name, userIds } = {}) => {
  const lists = await readLists(userId);
  if (lists.length >= MAX_LISTS) {
    throw new InnerCircleError(`You can keep up to ${MAX_LISTS} lists.`, 'INNER_CIRCLE_TOO_MANY_LISTS');
  }
  const members = await vetMembers(userId, userIds);
  const id = `ic_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 8)}`;
  const next = [...lists, { id, name: cleanName(name, `List ${lists.length + 1}`), userIds: members }];
  await writeLists(userId, next);
  return next;
};

/** Rename a list, change who is on it, or both. */
const updateInnerCircleList = async (userId, listId, { name, userIds } = {}) => {
  const lists = await readLists(userId);
  const index = lists.findIndex(list => list.id === listId);
  if (index < 0) throw new InnerCircleError('That list is gone.', 'INNER_CIRCLE_NO_LIST');
  const next = [...lists];
  const members = userIds === undefined ? next[index].userIds : await vetMembers(userId, userIds);
  next[index] = {
    ...next[index],
    name: name === undefined ? next[index].name : cleanName(name, next[index].name),
    userIds: members
  };
  await writeLists(userId, next);
  return next;
};

/**
 * Delete a list. Anything that was shared with it stops being visible to
 * those people, which is the point — access is decided at read time against
 * the list as it is now.
 */
const deleteInnerCircleList = async (userId, listId) => {
  const lists = await readLists(userId);
  const next = lists.filter(list => list.id !== listId);
  if (next.length === lists.length) throw new InnerCircleError('That list is gone.', 'INNER_CIRCLE_NO_LIST');
  await writeLists(userId, next);
  return next;
};

// MARK: - The default list (what a client that knows nothing of lists edits)

/** The owner's first list, flattened — the shape older clients expect. */
const getInnerCircle = async (userId) => {
  const lists = await readLists(userId);
  return lists.length ? lists[0].userIds : [];
};

/**
 * Replace the first list's membership. Rejects anyone who is not an accepted
 * connection so the invariant can never be broken from the API side.
 *
 * @returns {Promise<string[]>} the stored list
 */
const setInnerCircle = async (userId, requestedIds) => {
  const members = await vetMembers(userId, requestedIds);
  const lists = await readLists(userId);
  const next = lists.length
    ? [{ ...lists[0], userIds: members }, ...lists.slice(1)]
    : [{ id: DEFAULT_LIST_ID, name: DEFAULT_LIST_NAME, userIds: members }];
  await writeLists(userId, next);
  return members;
};

/** Add one person to the first list, keeping it a set. */
const addToInnerCircle = async (userId, targetId) => {
  const current = await getInnerCircle(userId);
  if (current.includes(String(targetId))) return current;
  return setInnerCircle(userId, [...current, targetId]);
};

/**
 * Remove one person from EVERY list. Revocation has to be total — a grant
 * that survived on a second list would be invisible to the person revoking
 * it — so this is not the mirror of `addToInnerCircle`.
 *
 * Straight to the doc: a removal can never break the connected-only rule,
 * and re-validating would fail for exactly the case we are cleaning up after.
 */
const removeFromInnerCircle = async (userId, targetId) => {
  const lists = await readLists(userId);
  const target = String(targetId);
  const next = lists.map(list => ({ ...list, userIds: list.userIds.filter(id => id !== target) }));
  const changed = next.some((list, i) => list.userIds.length !== lists[i].userIds.length);
  if (!changed) return lists.length ? lists[0].userIds : [];
  await writeLists(userId, next);
  return next.length ? next[0].userIds : [];
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

/**
 * Validate a guest list (a circle's or a place's `sharedWith`) before storing.
 *
 * Same rule as the Inner Circle: you can only hand private access to someone
 * you are connected with. Returns the cleaned list; throws InnerCircleError
 * naming the problem so the API can pass it straight to the user.
 */
const validateGuestList = async (ownerId, requestedIds) => {
  const wanted = asIdArray(requestedIds).filter(id => id !== String(ownerId));
  if (wanted.length === 0) return [];
  const connected = await getConnectedUserIds(ownerId);
  if (wanted.some(id => !connected.has(id))) {
    throw new InnerCircleError('You can only share with people you are connected with.', 'SHARED_WITH_NOT_CONNECTED');
  }
  return wanted;
};

module.exports = {
  validateGuestList,
  MAX_INNER_CIRCLE,
  MAX_LISTS,
  getInnerCircleLists,
  createInnerCircleList,
  updateInnerCircleList,
  deleteInnerCircleList,
  InnerCircleError,
  getInnerCircle,
  getInnerCircleGrantorIds,
  setInnerCircle,
  addToInnerCircle,
  removeFromInnerCircle,
  revokeMutualGrants
};
