// controllers/users/birthdayController.js
// The person's birthday, month and day only (2026-11-09): stores where they
// earn rewards can send a birthday treat (services/storeAutomations). The
// date itself is never shown to a store — the server does the matching.
const { getFirestore, FieldValue } = require('../../config/firebase');
const { COLLECTIONS } = require('../../models/FirestoreModels');
const { normalizeBirthday } = require('../../services/storeAutomations');
const { sendServiceError } = require('../../utils/serviceError');

// @route   GET /api/users/me/birthday
exports.get = async (req, res) => {
  try {
    const doc = await getFirestore().collection(COLLECTIONS.USERS).doc(req.user.uid).get();
    res.json({ success: true, data: { birthday: (doc.exists && doc.data().birthday) || null } });
  } catch (error) {
    sendServiceError(res, error, { log: '❌ Failed to read birthday', fallbackMessage: 'Failed to read birthday' });
  }
};

// @route   PUT /api/users/me/birthday   body: { birthday: "MM-DD" | null }
exports.set = async (req, res) => {
  try {
    const birthday = normalizeBirthday(req.body ? req.body.birthday : null);
    await getFirestore().collection(COLLECTIONS.USERS).doc(req.user.uid)
      .update({ birthday: birthday === null ? FieldValue.delete() : birthday });
    res.json({ success: true, data: { birthday } });
  } catch (error) {
    sendServiceError(res, error, { log: '❌ Failed to save birthday', fallbackMessage: 'Failed to save birthday' });
  }
};
