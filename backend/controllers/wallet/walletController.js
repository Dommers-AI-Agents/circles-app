// controllers/wallet/walletController.js
// Apple Wallet store cards: the customer's download, and the web service
// Wallet itself calls to register devices and fetch updated cards
// (Apple's "Adding a web service to update passes").
const wallet = require('../../services/wallet/walletPassService');
const { sendServiceError } = require('../../utils/serviceError');

const PKPASS = 'application/vnd.apple.pkpass';

// @route   GET /api/rewards/venues/:venueId/wallet-pass   (signed in)
exports.downloadPass = async (req, res) => {
  try {
    const pkpass = await wallet.passForCustomer(req.user.uid, req.params.venueId);
    res.setHeader('Content-Type', PKPASS);
    res.setHeader('Content-Disposition', 'attachment; filename="store-card.pkpass"');
    res.send(pkpass);
  } catch (error) {
    sendServiceError(res, error, { log: 'Wallet card', fallbackCode: 'WALLET_FAILED', fallbackMessage: 'Could not make the Wallet card' });
  }
};

// Wallet's own calls carry the pass type; a different one isn't ours
const ours = (req) => req.params.passTypeId === wallet.passTypeId();

// @route   POST /api/wallet/v1/devices/:deviceLibraryIdentifier/registrations/:passTypeId/:serial
exports.register = async (req, res) => {
  try {
    if (!ours(req) || !(await wallet.authorizedPass(req.params.serial, req.get('Authorization')))) return res.sendStatus(401);
    const status = await wallet.registerDevice({
      deviceLibraryIdentifier: req.params.deviceLibraryIdentifier,
      serial: req.params.serial,
      pushToken: req.body && req.body.pushToken
    });
    res.sendStatus(status);
  } catch (error) {
    console.error('⚠️ Wallet register failed:', error.message);
    res.sendStatus(500);
  }
};

// @route   DELETE /api/wallet/v1/devices/:deviceLibraryIdentifier/registrations/:passTypeId/:serial
exports.unregister = async (req, res) => {
  try {
    if (!ours(req) || !(await wallet.authorizedPass(req.params.serial, req.get('Authorization')))) return res.sendStatus(401);
    await wallet.unregisterDevice({ deviceLibraryIdentifier: req.params.deviceLibraryIdentifier, serial: req.params.serial });
    res.sendStatus(200);
  } catch (error) {
    console.error('⚠️ Wallet unregister failed:', error.message);
    res.sendStatus(500);
  }
};

// @route   GET /api/wallet/v1/devices/:deviceLibraryIdentifier/registrations/:passTypeId?passesUpdatedSince=
exports.updatedSerials = async (req, res) => {
  try {
    if (!ours(req)) return res.sendStatus(404);
    const result = await wallet.updatedSerials(req.params.deviceLibraryIdentifier, req.query.passesUpdatedSince);
    if (!result) return res.sendStatus(204);
    res.json(result);
  } catch (error) {
    console.error('⚠️ Wallet update list failed:', error.message);
    res.sendStatus(500);
  }
};

// @route   GET /api/wallet/v1/passes/:passTypeId/:serial
exports.latestPass = async (req, res) => {
  try {
    if (!ours(req)) return res.sendStatus(404);
    const record = await wallet.authorizedPass(req.params.serial, req.get('Authorization'));
    if (!record) return res.sendStatus(401);
    const since = req.get('If-Modified-Since');
    const updated = new Date(record.updatedAt);
    if (since && !Number.isNaN(updated.getTime()) && Math.floor(updated.getTime() / 1000) <= Math.floor(new Date(since).getTime() / 1000)) {
      return res.sendStatus(304);
    }
    const pkpass = await wallet.latestPass(record);
    res.setHeader('Content-Type', PKPASS);
    if (!Number.isNaN(updated.getTime())) res.setHeader('Last-Modified', updated.toUTCString());
    res.send(pkpass);
  } catch (error) {
    console.error('⚠️ Wallet pass fetch failed:', error.message);
    res.sendStatus(500);
  }
};

// @route   POST /api/wallet/v1/log   (Wallet reports its own errors here)
exports.log = (req, res) => {
  const logs = Array.isArray(req.body && req.body.logs) ? req.body.logs.slice(0, 20) : [];
  logs.forEach((line) => console.warn('[wallet-log]', String(line).slice(0, 500)));
  res.sendStatus(200);
};
