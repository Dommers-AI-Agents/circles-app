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
  InnerCircleError,
  getInnerCircle,
  setInnerCircle,
  addToInnerCircle,
  removeFromInnerCircle
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

const handleError = (res, next, error, action) => {
  if (error instanceof InnerCircleError) {
    return res.status(400).json({ success: false, code: error.code, message: error.message });
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

module.exports = {
  getMyInnerCircle,
  replaceMyInnerCircle,
  addMyInnerCircleMember,
  removeMyInnerCircleMember
};
