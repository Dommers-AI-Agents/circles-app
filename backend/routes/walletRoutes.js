// backend/routes/walletRoutes.js
// The web service Apple Wallet calls for FavCircles store cards. Public:
// each call carries "Authorization: ApplePass <token>" for its own pass.
const express = require('express');
const rateLimit = require('express-rate-limit');
const wallet = require('../controllers/wallet/walletController');

const router = express.Router();
router.use(rateLimit({ windowMs: 15 * 60 * 1000, max: 300 }));

router.post('/v1/devices/:deviceLibraryIdentifier/registrations/:passTypeId/:serial', wallet.register);
router.delete('/v1/devices/:deviceLibraryIdentifier/registrations/:passTypeId/:serial', wallet.unregister);
router.get('/v1/devices/:deviceLibraryIdentifier/registrations/:passTypeId', wallet.updatedSerials);
router.get('/v1/passes/:passTypeId/:serial', wallet.latestPass);
router.post('/v1/log', wallet.log);

module.exports = router;
