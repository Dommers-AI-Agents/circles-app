const express = require('express');
const router = express.Router();
const { protect } = require('../middleware/firebaseAuth');
const {
    verifySubscription,
    getSubscriptionStatus,
    handleSubscriptionWebhook,
    startFreeTrial,
    getUserUsageStats
} = require('../controllers/subscriptionController');

// Protected routes (require authentication)
router.post('/verify', protect, verifySubscription);
router.get('/status', protect, getSubscriptionStatus);
router.get('/usage', protect, getUserUsageStats);

// Development/testing route
if (process.env.NODE_ENV !== 'production') {
    router.post('/trial', protect, startFreeTrial);
}

// Public webhook endpoint for App Store notifications
router.post('/webhook', handleSubscriptionWebhook);

module.exports = router;