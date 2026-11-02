const express = require('express');
const { protect } = require('../middleware/firebaseAuth');
const { getNextSteps, recordEvents } = require('../controllers/nextStepController');

const router = express.Router();
router.use(protect);
router.get('/', getNextSteps);
router.post('/events', recordEvents);
module.exports = router;
