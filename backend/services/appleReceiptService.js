const axios = require('axios');
const admin = require('firebase-admin');

// Apple App Store Server API configuration
const APPLE_VERIFY_RECEIPT_URL = process.env.NODE_ENV === 'production' 
    ? 'https://buy.itunes.apple.com/verifyReceipt'
    : 'https://sandbox.itunes.apple.com/verifyReceipt';

const APPLE_SHARED_SECRET = process.env.APPLE_SHARED_SECRET || '';

class AppleReceiptService {
    /**
     * Verify subscription status with Apple using stored transaction ID
     * @param {string} userId - The user's ID
     * @returns {Promise<Object>} Subscription status from Apple
     */
    async verifySubscriptionStatus(userId) {
        try {
            // Get user data to check for Apple transaction ID
            const userRef = admin.firestore().collection('users').doc(userId);
            const userDoc = await userRef.get();
            
            if (!userDoc.exists) {
                console.log(`User ${userId} not found`);
                return null;
            }
            
            const userData = userDoc.data();
            
            // Check if user has an Apple subscription (has original transaction ID)
            if (!userData.appleOriginalTransactionId) {
                console.log(`User ${userId} has no Apple transaction ID`);
                return null;
            }
            
            // If we have a recent receipt, try to verify it
            if (userData.lastReceipt) {
                return await this.verifyReceipt(userData.lastReceipt, userId);
            }
            
            // No recent receipt available, but we know they had a subscription
            // Return current stored status (backend will need to wait for next app sync)
            console.log(`User ${userId} has transaction ID but no recent receipt`);
            return {
                status: userData.subscriptionStatus || 'none',
                expiryDate: userData.subscriptionExpiryDate,
                needsAppSync: true
            };
            
        } catch (error) {
            console.error('Error verifying subscription status:', error);
            return null;
        }
    }
    
    /**
     * Verify a receipt with Apple
     * @param {string} receipt - Base64 encoded receipt
     * @param {string} userId - The user's ID
     * @returns {Promise<Object>} Verification result
     */
    async verifyReceipt(receipt, userId) {
        try {
            // Verify receipt with Apple
            let verificationResponse = await axios.post(APPLE_VERIFY_RECEIPT_URL, {
                'receipt-data': receipt,
                'password': APPLE_SHARED_SECRET,
                'exclude-old-transactions': true
            });

            let verificationData = verificationResponse.data;

            // If status is 21007, it means sandbox receipt was sent to production
            // Retry with sandbox URL
            if (verificationData.status === 21007) {
                console.log('Sandbox receipt detected, retrying with sandbox URL...');
                verificationResponse = await axios.post('https://sandbox.itunes.apple.com/verifyReceipt', {
                    'receipt-data': receipt,
                    'password': APPLE_SHARED_SECRET,
                    'exclude-old-transactions': true
                });
                verificationData = verificationResponse.data;
            }

            if (verificationData.status !== 0) {
                console.error('Receipt verification failed:', verificationData.status);
                return null;
            }

            // Extract latest receipt info
            const latestReceiptInfo = verificationData.latest_receipt_info?.[0] || verificationData.receipt?.in_app?.[0];
            
            if (!latestReceiptInfo) {
                console.log('No valid subscription found in receipt');
                return null;
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
            
            // Store the latest receipt for future verification
            if (userId && verificationData.latest_receipt) {
                const userRef = admin.firestore().collection('users').doc(userId);
                await userRef.update({
                    lastReceipt: verificationData.latest_receipt,
                    lastReceiptVerification: new Date().toISOString()
                });
            }

            return {
                status: subscriptionStatus,
                expiryDate: new Date(expiresDateMs).toISOString(),
                isTrialPeriod,
                productId: latestReceiptInfo.product_id,
                originalTransactionId: latestReceiptInfo.original_transaction_id,
                autoRenewEnabled: latestReceiptInfo.auto_renew_status === '1'
            };
            
        } catch (error) {
            console.error('Error verifying receipt:', error);
            return null;
        }
    }
    
    /**
     * Update user's subscription status in Firestore
     * @param {string} userId - The user's ID
     * @param {Object} subscriptionData - Subscription data from Apple
     */
    async updateUserSubscription(userId, subscriptionData) {
        try {
            const userRef = admin.firestore().collection('users').doc(userId);
            const updateData = {
                subscriptionStatus: subscriptionData.status,
                subscriptionExpiryDate: subscriptionData.expiryDate,
                lastReceiptVerification: new Date().toISOString(),
                appleOriginalTransactionId: subscriptionData.originalTransactionId
            };

            // If it's a trial, record trial dates
            if (subscriptionData.isTrialPeriod && subscriptionData.status === 'trial') {
                const userData = await userRef.get();
                if (!userData.data()?.trialStartDate) {
                    updateData.trialStartDate = new Date().toISOString();
                    updateData.trialEndDate = subscriptionData.expiryDate;
                }
            }

            await userRef.update(updateData);
            console.log(`✅ Updated subscription status for user ${userId}: ${subscriptionData.status}`);
            
            return true;
        } catch (error) {
            console.error('Error updating user subscription:', error);
            return false;
        }
    }
}

module.exports = new AppleReceiptService();