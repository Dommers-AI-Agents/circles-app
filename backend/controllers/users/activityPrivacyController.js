// backend/controllers/users/activityPrivacyController.js
// "Who can see my activity": the owner's account-level audience × category
// grid. Read and replaced whole, like notification preferences. The grid is
// enforced in services/activityPrivacy.js on every activity surface.
const { getFirestore } = require('../../config/firebase');
const { COLLECTIONS } = require('../../models/FirestoreModels');
const { normalizeActivityPrivacy, validateActivityPrivacy } = require('../../services/activityPrivacy');
const { sendServiceError } = require('../../utils/serviceError');
const cacheInvalidationService = require('../../services/cacheInvalidationService');

const fail = (res, error) => sendServiceError(res, error, {
  log: '[activityPrivacy] request failed', fallbackCode: 'activity_privacy_failed',
  fallbackMessage: 'Something went wrong with your activity privacy.'
});

// @route GET /api/users/me/activity-privacy
exports.getMyActivityPrivacy = async (req, res) => {
  try {
    const doc = await getFirestore().collection(COLLECTIONS.USERS).doc(req.user.uid).get();
    const stored = doc.exists ? doc.data().activityPrivacy : null;
    res.json({ success: true, data: { activityPrivacy: normalizeActivityPrivacy(stored) } });
  } catch (error) { fail(res, error); }
};

// @route PUT /api/users/me/activity-privacy   body: { activityPrivacy: <full grid> }
exports.replaceMyActivityPrivacy = async (req, res) => {
  try {
    const grid = validateActivityPrivacy((req.body || {}).activityPrivacy);
    await getFirestore().collection(COLLECTIONS.USERS).doc(req.user.uid)
      .update({ activityPrivacy: grid, updatedAt: new Date().toISOString() });
    cacheInvalidationService.onUserProfileUpdated(req.user.uid, { activityPrivacy: true });
    res.json({ success: true, data: { activityPrivacy: grid } });
  } catch (error) { fail(res, error); }
};
