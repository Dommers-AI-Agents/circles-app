const express = require('express');
const router = express.Router();
const { protect } = require('../middleware/firebaseAuth');
const { 
    generateReferralCode,
    applyReferralCode,
    getReferralStatus,
    claimReferralRewards
} = require('../controllers/referralController');

// All routes are protected
router.use(protect);

// Generate or get user's referral code
router.post('/generate', generateReferralCode);

// Apply referral code (during signup)
router.post('/apply', applyReferralCode);

// Get referral status and stats
router.get('/status', getReferralStatus);

// Claim accumulated referral rewards
router.post('/claim', claimReferralRewards);

module.exports = router;