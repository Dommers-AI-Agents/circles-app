const admin = require('firebase-admin');
const { COLLECTIONS } = require('../models/FirestoreModels');

const db = admin.firestore();

/**
 * TEMPORARY manual subscription verification endpoint
 * Used only for confirmed premium subscribers whose iOS app failed to send subscription data
 * This is a stopgap solution while iOS app subscription flow is fixed
 */

// @desc    Manual subscription verification for confirmed premium users
// @route   POST /api/subscriptions/manual-verify
// @access  Private (Development only)
exports.manualVerifySubscription = async (req, res) => {
    try {
        // Only allow in development or with special override
        if (process.env.NODE_ENV === 'production' && !process.env.ALLOW_MANUAL_SUBSCRIPTION) {
            return res.status(403).json({
                success: false,
                error: 'Manual subscription verification not allowed in production'
            });
        }
        
        const userId = req.user.uid;
        const { confirmed, appleSubscriptionId, reason } = req.body;
        
        if (!confirmed) {
            return res.status(400).json({
                success: false,
                error: 'Must confirm this is a verified premium subscriber'
            });
        }
        
        if (!reason) {
            return res.status(400).json({
                success: false,
                error: 'Must provide reason for manual verification'
            });
        }
        
        console.log(`🚨 MANUAL SUBSCRIPTION VERIFICATION for user ${userId}`);
        console.log(`   Reason: ${reason}`);
        console.log(`   Apple ID: ${appleSubscriptionId || 'Not provided'}`);
        
        // Get user document
        const userRef = db.collection(COLLECTIONS.USERS).doc(userId);
        const userDoc = await userRef.get();
        
        if (!userDoc.exists) {
            return res.status(404).json({
                success: false,
                error: 'User not found'
            });
        }
        
        const userData = userDoc.data();
        
        // Set subscription to active with manual verification flag
        const updateData = {
            subscriptionStatus: 'active',
            subscriptionExpiryDate: null, // Null for ongoing subscription
            manuallyVerified: true,
            manualVerificationReason: reason,
            manualVerificationDate: new Date().toISOString(),
            lastReceiptVerification: new Date().toISOString()
        };
        
        if (appleSubscriptionId) {
            updateData.appleOriginalTransactionId = appleSubscriptionId;
        }
        
        await userRef.update(updateData);
        
        console.log(`✅ User ${userId} manually verified as premium subscriber`);
        console.log(`   Previous status: ${userData.subscriptionStatus || 'none'}`);
        console.log(`   New status: active (manually verified)`);
        
        // Log this action for audit trail
        await db.collection('subscriptionAuditLog').add({
            userId,
            action: 'manual_verification',
            previousStatus: userData.subscriptionStatus || 'none',
            newStatus: 'active',
            reason,
            appleSubscriptionId: appleSubscriptionId || null,
            timestamp: new Date(),
            performedBy: 'system'
        });
        
        res.json({
            success: true,
            message: 'Subscription manually verified',
            status: 'active',
            note: 'This is a temporary fix. iOS app subscription flow needs to be updated.'
        });
        
    } catch (error) {
        console.error('Manual subscription verification error:', error);
        res.status(500).json({
            success: false,
            error: 'Failed to manually verify subscription',
            details: error.message
        });
    }
};

// @desc    Check if user needs manual verification
// @route   GET /api/subscriptions/needs-manual-check
// @access  Private
exports.checkNeedsManualVerification = async (req, res) => {
    try {
        const userId = req.user.uid;
        
        const userRef = db.collection(COLLECTIONS.USERS).doc(userId);
        const userDoc = await userRef.get();
        
        if (!userDoc.exists) {
            return res.status(404).json({ success: false, error: 'User not found' });
        }
        
        const userData = userDoc.data();
        
        // Count circles
        const circlesSnapshot = await db.collection(COLLECTIONS.CIRCLES)
            .where('owner', '==', userId)
            .get();
        
        const circleCount = circlesSnapshot.size;
        const hasSubscription = userData.subscriptionStatus === 'active';
        const isOverFreeLimit = circleCount > 6;
        
        const needsManualCheck = isOverFreeLimit && !hasSubscription;
        
        res.json({
            success: true,
            userId,
            needsManualCheck,
            analysis: {
                circleCount,
                hasActiveSubscription: hasSubscription,
                isOverFreeLimit,
                subscriptionStatus: userData.subscriptionStatus || 'none',
                hasAppleTransactionId: !!userData.appleOriginalTransactionId,
                manuallyVerified: userData.manuallyVerified || false
            },
            instructions: needsManualCheck ? [
                'You appear to be a premium user but your subscription is not showing in our backend.',
                'This usually means the iOS app failed to send your Apple subscription data.',
                'Please try logging out and back in to refresh your subscription status.',
                'If that doesn\'t work, contact support for manual verification.'
            ] : null
        });
        
    } catch (error) {
        console.error('Check manual verification error:', error);
        res.status(500).json({
            success: false,
            error: 'Failed to check verification status'
        });
    }
};