const admin = require('firebase-admin');
const axios = require('axios');

// Supported Product IDs
// - com.favcircles.circles.premium.subscription.monthly ($2.99/month)
// - com.favcircles.circles.premium.subscription.annual ($29.99/year)

// Apple App Store Server API configuration
const APPLE_VERIFY_RECEIPT_URL = process.env.NODE_ENV === 'production' 
    ? 'https://buy.itunes.apple.com/verifyReceipt'
    : 'https://sandbox.itunes.apple.com/verifyReceipt';

const APPLE_SHARED_SECRET = process.env.APPLE_SHARED_SECRET || '';

// @desc    Verify Apple receipt and update subscription status
// @route   POST /api/users/subscription/verify
// @access  Private
exports.verifySubscription = async (req, res) => {
    try {
        const { receipt, transactionId, productId, originalTransactionId, purchaseDate, expirationDate } = req.body;
        const userId = req.userId;

        if (!receipt) {
            return res.status(400).json({
                success: false,
                error: 'Receipt data is required'
            });
        }

        // Verify receipt with Apple
        const verificationResponse = await axios.post(APPLE_VERIFY_RECEIPT_URL, {
            'receipt-data': receipt,
            'password': APPLE_SHARED_SECRET,
            'exclude-old-transactions': true
        });

        const verificationData = verificationResponse.data;

        if (verificationData.status !== 0) {
            console.error('Receipt verification failed:', verificationData.status);
            return res.status(400).json({
                success: false,
                error: 'Invalid receipt'
            });
        }

        // Extract latest receipt info
        const latestReceiptInfo = verificationData.latest_receipt_info?.[0] || verificationData.receipt?.in_app?.[0];
        
        if (!latestReceiptInfo) {
            return res.status(400).json({
                success: false,
                error: 'No valid subscription found in receipt'
            });
        }

        // Determine subscription status
        const now = Date.now();
        const expiresDateMs = parseInt(latestReceiptInfo.expires_date_ms);
        const isActive = expiresDateMs > now;
        const isTrialPeriod = latestReceiptInfo.is_trial_period === 'true';
        
        let subscriptionStatus = 'none';
        if (isActive) {
            subscriptionStatus = isTrialPeriod ? 'trial' : 'active';
        } else {
            subscriptionStatus = 'expired';
        }

        // Update user's subscription info in Firestore
        const userRef = admin.firestore().collection('users').doc(userId);
        const updateData = {
            subscriptionStatus,
            subscriptionExpiryDate: new Date(expiresDateMs).toISOString(),
            lastReceiptVerification: new Date().toISOString()
        };

        // If it's a trial, record trial dates
        if (isTrialPeriod && subscriptionStatus === 'trial') {
            const userData = await userRef.get();
            if (!userData.data()?.trialStartDate) {
                updateData.trialStartDate = new Date(parseInt(latestReceiptInfo.purchase_date_ms)).toISOString();
                updateData.trialEndDate = new Date(expiresDateMs).toISOString();
            }
        }

        await userRef.update(updateData);

        // Fetch updated user data
        const updatedUser = await userRef.get();
        const userData = updatedUser.data();

        res.json({
            success: true,
            subscription: {
                status: userData.subscriptionStatus,
                expiryDate: userData.subscriptionExpiryDate,
                trialStartDate: userData.trialStartDate,
                trialEndDate: userData.trialEndDate,
                autoRenewEnabled: latestReceiptInfo.auto_renew_status === '1',
                productId: latestReceiptInfo.product_id
            }
        });

    } catch (error) {
        console.error('Subscription verification error:', error);
        res.status(500).json({
            success: false,
            error: 'Failed to verify subscription'
        });
    }
};

// @desc    Get subscription status
// @route   GET /api/users/subscription/status
// @access  Private
exports.getSubscriptionStatus = async (req, res) => {
    try {
        const userId = req.userId;
        
        const userDoc = await admin.firestore().collection('users').doc(userId).get();
        
        if (!userDoc.exists) {
            return res.status(404).json({
                success: false,
                error: 'User not found'
            });
        }

        const userData = userDoc.data();
        
        // Check if subscription is expired
        let status = userData.subscriptionStatus || 'none';
        if (userData.subscriptionExpiryDate) {
            const expiryDate = new Date(userData.subscriptionExpiryDate);
            if (expiryDate < new Date() && status !== 'none') {
                status = 'expired';
                // Update status in database
                await userDoc.ref.update({ subscriptionStatus: 'expired' });
            }
        }

        res.json({
            success: true,
            subscription: {
                status,
                expiryDate: userData.subscriptionExpiryDate,
                trialStartDate: userData.trialStartDate,
                trialEndDate: userData.trialEndDate,
                autoRenewEnabled: false, // Will be updated from receipt verification
                productId: null
            }
        });

    } catch (error) {
        console.error('Get subscription status error:', error);
        res.status(500).json({
            success: false,
            error: 'Failed to get subscription status'
        });
    }
};

// @desc    Update subscription status (webhook from App Store)
// @route   POST /api/users/subscription/webhook
// @access  Public (with verification)
exports.handleSubscriptionWebhook = async (req, res) => {
    try {
        // This would handle App Store Server Notifications
        // For now, we'll acknowledge receipt
        res.status(200).send();
        
        // TODO: Implement App Store Server Notification handling
        // - Verify the notification is from Apple
        // - Parse the notification type
        // - Update user subscription status accordingly
        
    } catch (error) {
        console.error('Webhook error:', error);
        res.status(500).json({
            success: false,
            error: 'Webhook processing failed'
        });
    }
};

// @desc    Start free trial (for testing)
// @route   POST /api/users/subscription/trial
// @access  Private
exports.startFreeTrial = async (req, res) => {
    try {
        const userId = req.userId;
        
        // Check if user already had a trial
        const userDoc = await admin.firestore().collection('users').doc(userId).get();
        const userData = userDoc.data();
        
        if (userData.trialStartDate) {
            return res.status(400).json({
                success: false,
                error: 'Free trial already used'
            });
        }

        // Set trial period
        const trialStartDate = new Date();
        const trialEndDate = new Date();
        trialEndDate.setMonth(trialEndDate.getMonth() + 2); // 2-month trial

        await userDoc.ref.update({
            subscriptionStatus: 'trial',
            trialStartDate: trialStartDate.toISOString(),
            trialEndDate: trialEndDate.toISOString(),
            subscriptionExpiryDate: trialEndDate.toISOString()
        });

        res.json({
            success: true,
            subscription: {
                status: 'trial',
                expiryDate: trialEndDate.toISOString(),
                trialStartDate: trialStartDate.toISOString(),
                trialEndDate: trialEndDate.toISOString(),
                autoRenewEnabled: false,
                productId: latestReceiptInfo.product_id || 'com.favcircles.circles.premium.subscription.monthly'
            }
        });

    } catch (error) {
        console.error('Start trial error:', error);
        res.status(500).json({
            success: false,
            error: 'Failed to start trial'
        });
    }
};