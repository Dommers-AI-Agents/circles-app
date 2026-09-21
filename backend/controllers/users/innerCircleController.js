// backend/controllers/users/innerCircleController.js
//
// Managing the viewer's own Inner Circle list. The rules — connections only,
// capped, read-time evaluation — live in services/innerCircleService.js; this
// file is the HTTP shell around them.

const { getFirestore } = require('../../config/firebase');
const { COLLECTIONS, serializeDoc } = require('../../models/FirestoreModels');
const { projectPublicUser } = require('../../services/publicUserProjection');
const {
  MAX_INNER_CIRCLE,
  MAX_LISTS,
  InnerCircleError,
  getInnerCircle,
  setInnerCircle,
  addToInnerCircle,
  removeFromInnerCircle,
  getInnerCircleLists,
  createInnerCircleList,
  updateInnerCircleList,
  deleteInnerCircleList
} = require('../../services/innerCircleService');

const db = getFirestore();

/**
 * Hydrate ids into the public user cards the list screen renders. getAll keeps
 * the owner's curated order and sidesteps the 30-value 'in' cap.
 */
const hydrate = async (userIds) => {
  if (userIds.length === 0) return [];
  const docs = await db.getAll(...userIds.map(id => db.collection(COLLECTIONS.USERS).doc(id)));
  return docs
    .filter(doc => doc.exists)
    .map(doc => projectPublicUser(serializeDoc(doc)));
};

const respond = async (res, userIds) => {
  res.status(200).json({
    success: true,
    data: { maxSize: MAX_INNER_CIRCLE, userIds, users: await hydrate(userIds) }
  });
};

/**
 * Every list, each with its people hydrated. One read for all of them: the
 * lists overlap often enough that fetching per list would ask for the same
 * person several times.
 */
const respondWithLists = async (res, lists) => {
  const everyone = [...new Set(lists.flatMap(list => list.userIds))];
  const users = await hydrate(everyone);
  const byId = new Map(users.map(user => [user.id, user]));
  res.status(200).json({
    success: true,
    data: {
      maxSize: MAX_INNER_CIRCLE,
      maxLists: MAX_LISTS,
      lists: lists.map(list => ({
        id: list.id,
        name: list.name,
        userIds: list.userIds,
        users: list.userIds.map(id => byId.get(id)).filter(Boolean)
      })),
      // What a client that predates named lists reads: the first list.
      userIds: lists.length ? lists[0].userIds : [],
      users: lists.length ? lists[0].userIds.map(id => byId.get(id)).filter(Boolean) : []
    }
  });
};

const handleError = (res, next, error, action) => {
  if (error instanceof InnerCircleError) {
    const status = error.code === 'INNER_CIRCLE_NO_LIST' ? 404 : 400;
    return res.status(status).json({ success: false, code: error.code, message: error.message });
  }
  console.error(`Error ${action} inner circle:`, error);
  return next(error);
};

// @desc    The viewer's Inner Circle list
// @route   GET /api/users/me/inner-circle
// @access  Private
const getMyInnerCircle = async (req, res, next) => {
  try {
    await respond(res, await getInnerCircle(req.user.uid));
  } catch (error) {
    handleError(res, next, error, 'reading');
  }
};

// @desc    Replace the whole list (what the picker's Done button sends)
// @route   PUT /api/users/me/inner-circle
// @access  Private
const replaceMyInnerCircle = async (req, res, next) => {
  try {
    const { userIds } = req.body;
    if (!Array.isArray(userIds)) {
      return res.status(400).json({ success: false, message: 'userIds must be an array' });
    }
    await respond(res, await setInnerCircle(req.user.uid, userIds));
  } catch (error) {
    handleError(res, next, error, 'replacing');
  }
};

// @desc    Add one person
// @route   POST /api/users/me/inner-circle/:userId
// @access  Private
const addMyInnerCircleMember = async (req, res, next) => {
  try {
    await respond(res, await addToInnerCircle(req.user.uid, req.params.userId));
  } catch (error) {
    handleError(res, next, error, 'adding to');
  }
};

// @desc    Remove one person. Their access is gone on the next read.
// @route   DELETE /api/users/me/inner-circle/:userId
// @access  Private
const removeMyInnerCircleMember = async (req, res, next) => {
  try {
    await respond(res, await removeFromInnerCircle(req.user.uid, req.params.userId));
  } catch (error) {
    handleError(res, next, error, 'removing from');
  }
};

// @desc    Every named list the viewer keeps
// @route   GET /api/users/me/inner-circle/lists
// @access  Private
const getMyInnerCircleLists = async (req, res, next) => {
  try {
    await respondWithLists(res, await getInnerCircleLists(req.user.uid));
  } catch (error) {
    handleError(res, next, error, 'reading lists of');
  }
};

// @desc    Start a new named list
// @route   POST /api/users/me/inner-circle/lists
// @access  Private
const createMyInnerCircleList = async (req, res, next) => {
  try {
    const { name, userIds } = req.body || {};
    await respondWithLists(res, await createInnerCircleList(req.user.uid, { name, userIds }));
  } catch (error) {
    handleError(res, next, error, 'creating a list in');
  }
};

// @desc    Rename a list, change who is on it, or both
// @route   PUT /api/users/me/inner-circle/lists/:listId
// @access  Private
const updateMyInnerCircleList = async (req, res, next) => {
  try {
    const { name, userIds } = req.body || {};
    await respondWithLists(res, await updateInnerCircleList(req.user.uid, req.params.listId, { name, userIds }));
  } catch (error) {
    handleError(res, next, error, 'updating a list in');
  }
};

// @desc    Delete a list. Whatever was shared with it stops being visible.
// @route   DELETE /api/users/me/inner-circle/lists/:listId
// @access  Private
const deleteMyInnerCircleList = async (req, res, next) => {
  try {
    await respondWithLists(res, await deleteInnerCircleList(req.user.uid, req.params.listId));
  } catch (error) {
    handleError(res, next, error, 'deleting a list in');
  }
};

module.exports = {
  getMyInnerCircleLists,
  createMyInnerCircleList,
  updateMyInnerCircleList,
  deleteMyInnerCircleList,
  getMyInnerCircle,
  replaceMyInnerCircle,
  addMyInnerCircleMember,
  removeMyInnerCircleMember
};
