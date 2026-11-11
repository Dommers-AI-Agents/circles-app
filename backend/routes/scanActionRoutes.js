// routes/scanActionRoutes.js — /api/scan-actions (Scan Actions QR codes)
const express = require('express');
const { protect, optionalProtect } = require('../middleware/firebaseAuth');
const { perUserLimit } = require('../middleware/security');
const controller = require('../controllers/scanActions/scanActionController');

const router = express.Router();

// A QR per place shown at the table is cheap, but not hundreds a minute
const createLimit = perUserLimit({ bucket: 'scan-action-create', windowMs: 60 * 60 * 1000, max: 120 });
const completeLimit = perUserLimit({ bucket: 'scan-action-complete', windowMs: 60 * 60 * 1000, max: 120 });

router.post('/', protect, createLimit, controller.createAction);
// The "show me how" guides (Help → Show Someone How); before /:code
router.get('/guides', controller.listGuides);
router.get('/:code', optionalProtect, controller.resolveAction);
router.post('/:code/complete', protect, completeLimit, controller.completeAction);

module.exports = router;
