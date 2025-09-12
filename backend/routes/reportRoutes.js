const express = require('express');
const router = express.Router();
const { protect } = require('../middleware/firebaseAuth');
const {
  reportUser,
  reportContent,
  getReports,
  updateReportStatus
} = require('../controllers/reportController');

// Report routes
router.post('/user', protect, reportUser);
router.post('/content', protect, reportContent);
router.get('/', protect, getReports);
router.put('/:id', protect, updateReportStatus);

module.exports = router;