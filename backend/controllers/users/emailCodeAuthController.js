// backend/controllers/users/emailCodeAuthController.js
// Sign in or sign up with a 6-digit emailed code (services/emailCodeService).
// The App Clip's email path; the response matches /auth/register and
// /auth/login so the same client models decode it.
const { emailCodeService } = require('../../services/emailCodeService');
const { finishNewAccount, authUserPayload } = require('../../services/newAccountService');
const { mintSessionToken, getTokenExpiresInSeconds } = require('../../services/sessionToken');
const { normalizeUserId } = require('../../services/idService');
const { sendServiceError } = require('../../utils/serviceError');

// @desc    Email a one-time sign-in code
// @route   POST /api/auth/email-code/start
// @access  Public (authLimiter + 5 codes per email per hour)
exports.startEmailCode = async (req, res) => {
  try {
    const { newAccount } = await emailCodeService().start(req.body && req.body.email);
    res.status(200).json({ success: true, newAccount });
  } catch (error) {
    sendServiceError(res, error, { log: '📧 Email code start failed', fallbackMessage: "Couldn't send a code. Please try again." });
  }
};

// @desc    Check the code: signs in, or creates the account (needs displayName)
// @route   POST /api/auth/email-code/verify
// @access  Public (authLimiter + 5 tries per code)
exports.verifyEmailCode = async (req, res) => {
  try {
    const body = req.body || {};
    const { user, isNew } = await emailCodeService().verify({
      email: body.email, code: body.code, displayName: body.displayName
    });
    const id = normalizeUserId(user.id);
    if (isNew) {
      const counts = await finishNewAccount({ ...user, id }, {
        ip: req.ip, provider: 'email_code', signupSource: body.signupSource, stickerCode: body.stickerCode
      });
      Object.assign(user, counts);
    }
    const token = mintSessionToken(id, user.email);
    res.status(isNew ? 201 : 200).json({
      success: true,
      token,
      refreshToken: token,
      expiresIn: getTokenExpiresInSeconds(),
      newAccount: isNew,
      user: authUserPayload(user, id)
    });
  } catch (error) {
    sendServiceError(res, error, { log: '📧 Email code verify failed', fallbackMessage: "Couldn't sign you in. Please try again." });
  }
};
