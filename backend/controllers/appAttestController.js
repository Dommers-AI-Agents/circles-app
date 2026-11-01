// controllers/appAttestController.js — App Attest key registration (2026-11-01)
const appAttest = require('../services/appAttest/appAttestService');
const { sendServiceError } = require('../utils/serviceError');

// @route   GET /api/attest/challenge   (signed in)
exports.challenge = (req, res) => {
  res.json({ success: true, data: { challenge: appAttest.issueChallenge() } });
};

// @route   POST /api/attest/register  { keyId, attestation (base64), challenge }
exports.register = async (req, res) => {
  try {
    const { keyId, attestation, challenge } = req.body || {};
    const data = await appAttest.registerKey({ userId: req.user.uid, keyId, attestation, challenge });
    res.status(201).json({ success: true, data });
  } catch (error) {
    sendServiceError(res, error, { log: 'App Attest register', fallbackCode: 'ATTEST_FAILED', fallbackMessage: 'Could not verify this device' });
  }
};
