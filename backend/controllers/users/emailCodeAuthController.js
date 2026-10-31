// backend/controllers/users/emailCodeAuthController.js
// Sign in or sign up with a 6-digit emailed code (services/emailCodeService).
// The App Clip's email path; the response matches /auth/register and
// /auth/login so the same client models decode it.
const { emailCodeService } = require('../../services/emailCodeService');
const { finishNewAccount, authUserPayload } = require('../../services/newAccountService');
const { mintSessionToken, getTokenExpiresInSeconds } = require('../../services/sessionToken');
const { normalizeUserId } = require('../../services/idService');
const { sendServiceError } = require('../../utils/serviceError');

// Welcome email once the address is proven (fire-and-forget)
const sendWelcome = (user) => {
  if (!user.email) return;
  require('../../services/emailService').sendWelcomeEmail(user.email, user.displayName)
    .catch((err) => console.error('Welcome email failed:', err.message));
};

/** The session response every route here sends (matches /auth/register) */
const sessionResponse = (user, id, extra = {}) => {
  const token = mintSessionToken(id, user.email);
  return {
    success: true,
    token,
    refreshToken: token,
    expiresIn: getTokenExpiresInSeconds(),
    ...extra,
    user: authUserPayload(user, id)
  };
};

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
    const { user, isNew, confirmedNow } = await emailCodeService().verify({
      email: body.email, code: body.code, displayName: body.displayName
    });
    const id = normalizeUserId(user.id);
    if (isNew) {
      const counts = await finishNewAccount({ ...user, id }, {
        ip: req.ip, provider: 'email_code', signupSource: body.signupSource, stickerCode: body.stickerCode
      });
      Object.assign(user, counts);
    } else if (confirmedNow) {
      sendWelcome(user);
    }
    res.status(isNew ? 201 : 200).json(sessionResponse(user, id, { newAccount: isNew }));
  } catch (error) {
    sendServiceError(res, error, { log: '📧 Email code verify failed', fallbackMessage: "Couldn't sign you in. Please try again." });
  }
};

// @desc    Instant sign-up: a new email gets an account now and confirms the
//          email later; an email with an account gets a code (409 VERIFY_REQUIRED)
// @route   POST /api/auth/email-instant
// @access  Public (authLimiter + 10 instant sign-ups per IP per hour)
exports.instantSignup = async (req, res) => {
  try {
    const body = req.body || {};
    const user = await emailCodeService().instant({ email: body.email, displayName: body.displayName, ip: req.ip });
    const id = normalizeUserId(user.id);
    const counts = await finishNewAccount({ ...user, id }, {
      ip: req.ip, provider: 'email_instant', signupSource: body.signupSource, stickerCode: body.stickerCode,
      sendWelcome: false
    });
    Object.assign(user, counts);
    res.status(201).json(sessionResponse(user, id, { newAccount: true, emailUnverified: true }));
  } catch (error) {
    sendServiceError(res, error, { log: '⚡ Instant sign-up failed', fallbackMessage: "Couldn't create your account. Please try again." });
  }
};

// @desc    The signed-in user confirms their own email with a code from
//          /email-code/start; keeps their session
// @route   POST /api/auth/email-code/confirm
// @access  Private
exports.confirmEmailCode = async (req, res) => {
  try {
    const { confirmedNow } = await emailCodeService().confirm({
      userId: req.user.uid, email: req.user.email, code: (req.body || {}).code
    });
    if (confirmedNow) {
      require('../../middleware/firebaseAuth').invalidateUserCache(req.user.uid);
      sendWelcome(req.user);
    }
    res.status(200).json({ success: true, emailUnverified: false });
  } catch (error) {
    sendServiceError(res, error, { log: '📧 Email confirm failed', fallbackMessage: "Couldn't confirm your email. Please try again." });
  }
};
