const admin = require('firebase-admin');
const axios = require('axios');
const subscriptionLimitService = require('../services/subscriptionLimitService');
const ownerSubscriptionService = require('../services/ownerSubscriptionService');

// Supported Product IDs
// Consumer premium:
// - com.favcircles.circles.premium.subscription.monthly ($2.99/month)
// - com.favcircles.circles.premium.annual ($29.99/year)
// Store-owner business (separate subscription group; tracked on owner* fields,
// never on the consumer subscriptionStatus):
// - com.favcircles.circles.business.subscription.monthly
// - com.favcircles.circles.business.subscription.annual

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
        const userId = req.user?.uid || req.userId; // Check both req.user.uid and req.userId

        if (!userId) {
            return res.status(401).json({
                success: false,
                error: 'User ID not found in request'
            });
        }

        if (!receipt) {
            return res.status(400).json({
                success: false,
                error: 'Receipt data is required'
            });
        }

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
            // Provide more specific error messages
            let errorMessage = 'Invalid receipt';
            switch (verificationData.status) {
                case 21000: errorMessage = 'The request to the App Store was not made using the HTTP POST request method.'; break;
                case 21001: errorMessage = 'This receipt is from the test environment.'; break;
                case 21002: errorMessage = 'The receipt data is malformed.'; break;
                case 21003: errorMessage = 'The receipt could not be authenticated.'; break;
                case 21004: errorMessage = 'The shared secret does not match the shared secret on file for your account.'; break;
                case 21005: errorMessage = 'The receipt server is not currently available.'; break;
                case 21006: errorMessage = 'This receipt is valid but the subscription has expired.'; break;
                case 21008: errorMessage = 'This receipt is from the production environment, but it was sent to the test environment.'; break;
            }
            return res.status(400).json({
                success: false,
                error: errorMessage
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

        // Business (store-owner) receipts update the owner* fields ONLY —
        // buying the business tier must never touch consumer premium state,
        // and vice versa
        if (ownerSubscriptionService.isBusinessProduct(latestReceiptInfo.product_id)) {
            const ownerRef = admin.firestore().collection('users').doc(userId);

            // The subscription covers exactly ONE venue. Bind the venue the
            // client purchased for, but only when it's this user's venue and
            // either no binding exists yet or this is a brand-new subscription
            // (new original transaction) — a routine re-verify from another
            // store's paywall must never silently move premium between stores.
            const existing = (await ownerRef.get()).data() || {};
            let venueBinding = existing.ownerSubscriptionVenueId || null;
            const requestedVenueId = req.body.venueId || null;
            const isNewSubscription =
                existing.ownerOriginalTransactionId !== latestReceiptInfo.original_transaction_id;
            if (requestedVenueId && (!venueBinding || isNewSubscription)) {
                const venueDoc = await admin.firestore()
                    .collection('stickerVenues').doc(requestedVenueId).get();
                if (venueDoc.exists && venueDoc.data().ownerUserId === userId) {
                    venueBinding = requestedVenueId;
                } else {
                    console.warn(`🏪 Business verify: ignoring venueId ${requestedVenueId} — not owned by ${userId}`);
                }
            }

            await ownerRef.update({
                ownerSubscriptionStatus: subscriptionStatus,
                ownerSubscriptionExpiryDate: new Date(expiresDateMs).toISOString(),
                ownerSubscriptionProductId: latestReceiptInfo.product_id,
                ownerOriginalTransactionId: latestReceiptInfo.original_transaction_id,
                ownerSubscriptionVenueId: venueBinding,
                lastOwnerReceiptVerification: new Date().toISOString()
            });
            return res.json({
                success: true,
                subscription: {
                    scope: 'business',
                    status: subscriptionStatus,
                    expiryDate: new Date(expiresDateMs).toISOString(),
                    autoRenewEnabled: latestReceiptInfo.auto_renew_status === '1',
                    productId: latestReceiptInfo.product_id,
                    venueId: venueBinding
                }
            });
        }

        // Update user's subscription info in Firestore
        const userRef = admin.firestore().collection('users').doc(userId);
        const updateData = {
            subscriptionStatus,
            subscriptionExpiryDate: new Date(expiresDateMs).toISOString(),
            lastReceiptVerification: new Date().toISOString(),
            appleOriginalTransactionId: latestReceiptInfo.original_transaction_id
        };

        // Never let a stale/expired device receipt downgrade a manually verified
        // premium user — keep their existing status and expiry
        const existingDoc = await userRef.get();
        const existingData = existingDoc.data() || {};
        const existingExpiry = existingData.subscriptionExpiryDate ? new Date(existingData.subscriptionExpiryDate) : null;
        const hasManualPremium = (existingData.manuallyVerified === true || existingData.isPremium === true) &&
            (!existingExpiry || existingExpiry > new Date());

        if (hasManualPremium && subscriptionStatus !== 'active' && subscriptionStatus !== 'trial') {
            delete updateData.subscriptionStatus;
            delete updateData.subscriptionExpiryDate;
        }

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
        const userId = req.user?.uid || req.userId; // Check both req.user.uid and req.userId
        
        if (!userId) {
            return res.status(401).json({
                success: false,
                error: 'User ID not found in request'
            });
        }
        
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
        const expiryDate = userData.subscriptionExpiryDate ? new Date(userData.subscriptionExpiryDate) : null;
        // Manually verified premium users (isPremium/manuallyVerified) stay active
        // until their expiry date regardless of receipt state
        const hasManualPremium = (userData.manuallyVerified === true || userData.isPremium === true) &&
            (!expiryDate || expiryDate > new Date());

        if (hasManualPremium) {
            status = 'active';
            if (userData.subscriptionStatus !== 'active') {
                await userDoc.ref.update({ subscriptionStatus: 'active' });
            }
        } else if (expiryDate && expiryDate < new Date() && status !== 'none') {
            status = 'expired';
            // Update status in database
            await userDoc.ref.update({ subscriptionStatus: 'expired' });
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
// Decode a JWS segment's payload without verification. Only used for the
// INNER transaction/renewal JWS after the outer envelope's signature has been
// verified — Apple signs the envelope over the inner tokens.
function decodeJwsPayload(jws) {
    if (!jws || typeof jws !== 'string') return null;
    const parts = jws.split('.');
    if (parts.length !== 3) return null;
    try {
        return JSON.parse(Buffer.from(parts[1], 'base64url').toString());
    } catch (e) {
        return null;
    }
}

// Verify an App Store Server Notification V2 envelope: ES256 signature against
// the x5c leaf certificate, each chain link signed by its parent, and an
// Apple-issued root. (Pinning the exact Apple Root CA G3 fingerprint via
// Apple's official app-store-server-library is the eventual upgrade.)
function verifyAppleJws(signedPayload) {
    const crypto = require('crypto');
    const jwt = require('jsonwebtoken');
    const header = JSON.parse(Buffer.from(signedPayload.split('.')[0], 'base64url').toString());
    const x5c = header.x5c || [];
    if (!x5c.length) throw new Error('no x5c certificate chain in header');
    const toPem = (der) => `-----BEGIN CERTIFICATE-----\n${der.match(/.{1,64}/g).join('\n')}\n-----END CERTIFICATE-----`;
    const certs = x5c.map((der) => new crypto.X509Certificate(toPem(der)));
    for (let i = 0; i < certs.length - 1; i++) {
        if (!certs[i].verify(certs[i + 1].publicKey)) throw new Error(`certificate chain broken at link ${i}`);
    }
    const root = certs[certs.length - 1];
    if (!/Apple/.test(root.subject)) throw new Error('chain does not terminate at an Apple root');
    const leafKey = certs[0].publicKey.export({ type: 'spki', format: 'pem' });
    return jwt.verify(signedPayload, leafKey, { algorithms: ['ES256'] });
}

exports.handleSubscriptionWebhook = async (req, res) => {
    try {
        // Acknowledge receipt immediately (Apple requires 200 response)
        res.status(200).send();
        
        const { signedPayload } = req.body;
        
        if (!signedPayload) {
            console.error('No signed payload in webhook');
            return;
        }

        let payload;
        try {
            payload = verifyAppleJws(signedPayload);
        } catch (e) {
            console.error('🍎 Webhook rejected — signature verification failed:', e.message);
            return;
        }

        const { notificationType, subtype, data } = payload;
        // V2 notifications carry signedTransactionInfo/signedRenewalInfo (each
        // its own JWS); the old transactionInfo names never existed in V2, so
        // the previous destructure dropped every real notification.
        const transaction = decodeJwsPayload(data && (data.signedTransactionInfo || data.transactionInfo));
        const renewal = decodeJwsPayload(data && (data.signedRenewalInfo || data.renewalInfo));

        if (!transaction) {
            console.error(`🍎 Webhook ${notificationType}: no decodable transaction info`);
            return;
        }

        const { originalTransactionId, expiresDate, productId } = transaction;
        console.log(`🍎 Webhook: ${notificationType} ${subtype || ''} | product=${productId} | origTx=${originalTransactionId} | expires=${expiresDate ? new Date(Number(expiresDate)).toISOString() : '-'}`);

        // Business (store-owner) notifications update owner* fields on the
        // user found by the owner transaction id — fully separate from the
        // consumer premium path below
        if (ownerSubscriptionService.isBusinessProduct(productId)) {
            await handleBusinessWebhook({ notificationType, originalTransactionId, expiresDate, renewal });
            return;
        }

        // Find user by original transaction ID
        const usersSnapshot = await admin.firestore()
            .collection('users')
            .where('appleOriginalTransactionId', '==', originalTransactionId)
            .limit(1)
            .get();
        
        if (usersSnapshot.empty) {
            console.log('No user found for transaction:', originalTransactionId);
            // Store the transaction ID for later matching when user verifies receipt
            await admin.firestore().collection('pendingSubscriptions').doc(originalTransactionId).set({
                notificationType,
                productId,
                expiresDate,
                processedAt: new Date().toISOString()
            });
            return;
        }

        const userDoc = usersSnapshot.docs[0];
        const userId = userDoc.id;
        
        // Process based on notification type
        let updateData = {};
        
        switch (notificationType) {
            case 'SUBSCRIBED':
            case 'DID_RENEW':
                updateData = {
                    subscriptionStatus: 'active',
                    subscriptionExpiryDate: new Date(Number(expiresDate)).toISOString(),
                    lastWebhookReceived: new Date().toISOString()
                };
                break;
                
            case 'DID_FAIL_TO_RENEW':
                // Check if in grace period
                if (renewal && renewal.gracePeriodExpiresDate) {
                    updateData = {
                        subscriptionStatus: 'grace_period',
                        gracePeriodExpiryDate: new Date(Number(renewal.gracePeriodExpiresDate)).toISOString(),
                        lastWebhookReceived: new Date().toISOString()
                    };
                    break;
                }
                updateData = {
                    subscriptionStatus: 'expired',
                    lastWebhookReceived: new Date().toISOString()
                };
                break;
                
            case 'EXPIRED':
                updateData = {
                    subscriptionStatus: 'expired',
                    subscriptionExpiryDate: new Date(Number(expiresDate)).toISOString(),
                    lastWebhookReceived: new Date().toISOString()
                };
                break;
                
            case 'GRACE_PERIOD_EXPIRED':
                updateData = {
                    subscriptionStatus: 'expired',
                    gracePeriodExpiryDate: null,
                    lastWebhookReceived: new Date().toISOString()
                };
                break;
                
            case 'REFUND':
            case 'REVOKE':
                updateData = {
                    subscriptionStatus: 'cancelled',
                    lastWebhookReceived: new Date().toISOString()
                };
                break;
                
            default:
                console.log('Unhandled notification type:', notificationType);
        }
        
        if (Object.keys(updateData).length > 0) {
            await admin.firestore().collection('users').doc(userId).update(updateData);
            console.log(`Updated user ${userId} subscription status via webhook`);
        }
        
    } catch (error) {
        console.error('Webhook processing error:', error);
        // Still return 200 to prevent Apple from retrying
    }
};

// Business-subscription webhook handling: same notification types as consumer,
// mapped onto the owner* fields.
async function handleBusinessWebhook({ notificationType, originalTransactionId, expiresDate, renewal }) {
    const usersSnapshot = await admin.firestore()
        .collection('users')
        .where('ownerOriginalTransactionId', '==', originalTransactionId)
        .limit(1)
        .get();

    if (usersSnapshot.empty) {
        console.log('No user found for business transaction:', originalTransactionId);
        await admin.firestore().collection('pendingSubscriptions').doc(`business_${originalTransactionId}`).set({
            scope: 'business',
            notificationType,
            expiresDate,
            processedAt: new Date().toISOString()
        });
        return;
    }

    let updateData = {};
    switch (notificationType) {
        case 'SUBSCRIBED':
        case 'DID_RENEW':
            updateData = {
                ownerSubscriptionStatus: 'active',
                ownerSubscriptionExpiryDate: new Date(Number(expiresDate)).toISOString()
            };
            break;
        case 'DID_FAIL_TO_RENEW': {
            if (renewal && renewal.gracePeriodExpiresDate) {
                updateData = {
                    ownerSubscriptionStatus: 'grace_period',
                    ownerSubscriptionExpiryDate: new Date(Number(renewal.gracePeriodExpiresDate)).toISOString()
                };
            } else {
                updateData = { ownerSubscriptionStatus: 'expired' };
            }
            break;
        }
        case 'EXPIRED':
        case 'GRACE_PERIOD_EXPIRED':
            updateData = {
                ownerSubscriptionStatus: 'expired',
                ownerSubscriptionExpiryDate: new Date(Number(expiresDate)).toISOString()
            };
            break;
        case 'REFUND':
        case 'REVOKE':
            updateData = { ownerSubscriptionStatus: 'cancelled' };
            break;
        default:
            console.log('Unhandled business notification type:', notificationType);
            return;
    }

    updateData.lastOwnerWebhookReceived = new Date().toISOString();
    await usersSnapshot.docs[0].ref.update(updateData);
    console.log(`Updated user ${usersSnapshot.docs[0].id} business subscription via webhook (${notificationType})`);
}

// @desc    Start free trial (for testing)
// @route   POST /api/users/subscription/trial
// @access  Private
exports.startFreeTrial = async (req, res) => {
    try {
        const userId = req.user?.uid || req.userId; // Check both req.user.uid and req.userId
        
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
                productId: 'com.favcircles.circles.premium.subscription.monthly'
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

// @desc    Get user's usage statistics and limits
// @route   GET /api/users/subscription/usage
// @access  Private
exports.getUserUsageStats = async (req, res) => {
    try {
        const userId = req.user?.uid || req.userId;
        
        if (!userId) {
            return res.status(401).json({
                success: false,
                error: 'User ID not found in request'
            });
        }
        
        // Get usage statistics from the subscription limit service
        const usageStats = await subscriptionLimitService.getUserUsageStats(userId);
        
        res.json({
            success: true,
            usage: usageStats
        });
        
    } catch (error) {
        console.error('Get usage stats error:', error);
        res.status(500).json({
            success: false,
            error: 'Failed to get usage statistics'
        });
    }
};