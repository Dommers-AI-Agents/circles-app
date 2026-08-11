const admin = require('firebase-admin');
const axios = require('axios');
const subscriptionLimitService = require('../services/subscriptionLimitService');
const ownerSubscriptionService = require('../services/ownerSubscriptionService');
const { invalidateUserCache } = require('../middleware/firebaseAuth');

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

        // Extract receipt entries.
        //
        // Apple's latest_receipt_info carries the account's FULL transaction
        // history, oldest first, potentially spanning BOTH subscription
        // families (consumer premium and FavCircles Business). The old code
        // took [0] — the oldest entry — which marked fresh resubscriptions as
        // 'expired'; and processing only one entry meant whichever family it
        // belonged to starved the other of updates. Process the NEWEST entry
        // of EACH family independently.
        const receiptEntries = verificationData.latest_receipt_info
            || verificationData.receipt?.in_app
            || [];
        if (receiptEntries.length === 0) {
            return res.status(400).json({
                success: false,
                error: 'No valid subscription found in receipt'
            });
        }

        const now = Date.now();
        const entryStatus = (entry) => {
            const expiresDateMs = parseInt(entry.expires_date_ms);
            const isTrialPeriod = entry.is_trial_period === 'true';
            const status = expiresDateMs > now
                ? (isTrialPeriod ? 'trial' : 'active')
                : 'expired';
            return { expiresDateMs, isTrialPeriod, status };
        };

        const sorted = [...receiptEntries].sort(
            (a, b) => parseInt(b.expires_date_ms || 0) - parseInt(a.expires_date_ms || 0)
        );
        const businessEntry = sorted.find(e => ownerSubscriptionService.isBusinessProduct(e.product_id)) || null;
        const consumerEntry = sorted.find(e => !ownerSubscriptionService.isBusinessProduct(e.product_id)) || null;
        // The newest transaction overall is the purchase that triggered this
        // sync — its family decides the response shape.
        const newestOverall = sorted[0];

        // ---- Business (store-owner) family: owner* fields ONLY ----
        let businessResponse = null;
        if (businessEntry) {
            const b = entryStatus(businessEntry);
            const environment = verificationData.environment || 'Production';
            const ownerRef = admin.firestore().collection('users').doc(userId);
            const existing = (await ownerRef.get()).data() || {};

            // Sandbox guard, mirroring the consumer family: a dev/TestFlight
            // build signed into a sandbox Apple ID must never overwrite a real
            // paid owner entitlement (sandbox subs expire in minutes).
            const ownerWasProduction =
                (existing.ownerSubscriptionEnvironment || 'Production') === 'Production';
            if (environment === 'Sandbox' && ownerWasProduction && existing.ownerOriginalTransactionId) {
                console.warn(`🧪 Ignoring SANDBOX business receipt for ${userId}: production owner entitlement on file`);
                businessResponse = {
                    scope: 'business',
                    status: existing.ownerSubscriptionStatus,
                    expiryDate: existing.ownerSubscriptionExpiryDate,
                    productId: existing.ownerSubscriptionProductId,
                    venueId: existing.ownerSubscriptionVenueId || null,
                    ignored: 'sandbox_receipt_for_production_account'
                };
            } else {

            // The subscription covers exactly ONE venue. Bind the venue the
            // client purchased for, but only when it's this user's venue and
            // either no binding exists yet or this is a brand-new subscription
            // (new original transaction) — a routine re-verify from another
            // store's paywall must never silently move premium between stores.
            let venueBinding = existing.ownerSubscriptionVenueId || null;
            const requestedVenueId = req.body.venueId || null;
            const isNewSubscription =
                existing.ownerOriginalTransactionId !== businessEntry.original_transaction_id;
            if (requestedVenueId && (!venueBinding || isNewSubscription)) {
                const venueDoc = await admin.firestore()
                    .collection('stickerVenues').doc(requestedVenueId).get();
                if (venueDoc.exists && venueDoc.data().ownerUserId === userId) {
                    venueBinding = requestedVenueId;
                } else {
                    console.warn(`🏪 Business verify: ignoring venueId ${requestedVenueId} — not owned by ${userId}`);
                }
            }

            // Self-heal: an active subscription that was never bound (the
            // purchase-time verify failed, or a restore/launch sync carried no
            // venueId) is useless. If the owner has exactly one physical
            // venue, bind it — there is nothing else it could mean.
            if (!venueBinding && (b.status === 'active' || b.status === 'trial')) {
                const ownedSnap = await admin.firestore()
                    .collection('stickerVenues')
                    .where('ownerUserId', '==', userId)
                    .limit(10).get();
                const physical = ownedSnap.docs.filter(d => d.data().isVirtual !== true);
                if (physical.length === 1) {
                    venueBinding = physical[0].id;
                    console.warn(`🏪 Self-heal: bound unbound business sub for ${userId} to their only venue ${venueBinding}`);
                }
            }

            // A webhook-granted billing-retry grace period outlives a receipt
            // whose newest entry is the already-lapsed period — re-verifies on
            // launch must not stomp it back to 'expired' mid-retry.
            let finalStatus = b.status;
            let finalExpiryIso = new Date(b.expiresDateMs).toISOString();
            const storedOwnerExpiry = existing.ownerSubscriptionExpiryDate
                ? new Date(existing.ownerSubscriptionExpiryDate) : null;
            if (existing.ownerSubscriptionStatus === 'grace_period' &&
                storedOwnerExpiry && storedOwnerExpiry > new Date() &&
                b.expiresDateMs <= storedOwnerExpiry.getTime()) {
                finalStatus = 'grace_period';
                finalExpiryIso = storedOwnerExpiry.toISOString();
            }

            await ownerRef.set({
                ownerSubscriptionStatus: finalStatus,
                ownerSubscriptionExpiryDate: finalExpiryIso,
                ownerSubscriptionProductId: businessEntry.product_id,
                ownerOriginalTransactionId: businessEntry.original_transaction_id,
                ownerSubscriptionVenueId: venueBinding,
                ownerSubscriptionEnvironment: environment,
                lastOwnerReceiptVerification: new Date().toISOString()
            }, { merge: true });
            invalidateUserCache(userId);

            // Admin alert on the signup transition only: a routine re-verify
            // (same transaction, already active) stays silent.
            const wasBusinessActive = ['active', 'trial', 'grace_period'].includes(existing.ownerSubscriptionStatus);
            if ((b.status === 'active' || b.status === 'trial') && (isNewSubscription || !wasBusinessActive)) {
                require('../services/notificationService').notifyAdminPremiumSignup({
                    scope: 'business',
                    userId,
                    userName: existing.displayName || null,
                    userEmail: existing.email || null,
                    productId: businessEntry.product_id,
                    status: b.status,
                    venueId: venueBinding
                }).catch((e) => console.error('⚠️ Business signup admin alert failed:', e.message));

                // Benefits walkthrough to the new subscriber — fire-and-forget
                if (existing.email) {
                    (async () => {
                        let venueName = null;
                        if (venueBinding) {
                            const vDoc = await admin.firestore()
                                .collection('stickerVenues').doc(venueBinding).get();
                            if (vDoc.exists) venueName = vDoc.data().venueName || null;
                        }
                        await require('../services/emailService')
                            .sendBusinessWelcomeEmail(existing.email, existing.displayName || null, venueName);
                    })().catch((e) => console.error('⚠️ Business welcome email failed:', e.message));
                }
            }
            businessResponse = {
                scope: 'business',
                status: finalStatus,
                expiryDate: finalExpiryIso,
                autoRenewEnabled: businessEntry.auto_renew_status === '1',
                productId: businessEntry.product_id,
                venueId: venueBinding
            };
            } // end sandbox-guard else
        }

        // ---- Consumer premium family ----
        let consumerResponse = null;
        if (consumerEntry) {
            const c = entryStatus(consumerEntry);
            const userRef = admin.firestore().collection('users').doc(userId);
            const environment = verificationData.environment || 'Production';
            const updateData = {
                subscriptionStatus: c.status,
                subscriptionExpiryDate: new Date(c.expiresDateMs).toISOString(),
                lastReceiptVerification: new Date().toISOString(),
                appleOriginalTransactionId: consumerEntry.original_transaction_id,
                subscriptionEnvironment: environment
            };

            const existingDoc = await userRef.get();
            const existingData = existingDoc.data() || {};
            const existingExpiry = existingData.subscriptionExpiryDate ? new Date(existingData.subscriptionExpiryDate) : null;
            const hasManualPremium = (existingData.manuallyVerified === true || existingData.isPremium === true) &&
                (!existingExpiry || existingExpiry > new Date());

            // A device signed into a SANDBOX App Store account must never
            // touch a real, paid entitlement. Sandbox subscriptions live for
            // minutes, so letting one through overwrites the production
            // transaction id and expiry, and the sandbox EXPIRED webhook then
            // marks a paying customer expired. (This happened to the owner
            // account on 2026-08-07 from a dev build signed into a tester
            // Apple ID.)
            const isSandbox = environment === 'Sandbox';
            const wasProduction = (existingData.subscriptionEnvironment || 'Production') === 'Production';
            const hadRealEntitlement = !!existingData.appleOriginalTransactionId || hasManualPremium;
            if (isSandbox && wasProduction && hadRealEntitlement) {
                console.warn(`🧪 Ignoring SANDBOX receipt for ${userId}: production entitlement already on file`);
                return res.status(200).json({
                    success: true,
                    ignored: 'sandbox_receipt_for_production_account',
                    subscription: {
                        status: existingData.subscriptionStatus,
                        expiryDate: existingData.subscriptionExpiryDate
                    }
                });
            }

            // Never let a stale/expired device receipt downgrade a manually
            // verified premium user — keep their existing status and expiry
            if (hasManualPremium && c.status !== 'active' && c.status !== 'trial') {
                delete updateData.subscriptionStatus;
                delete updateData.subscriptionExpiryDate;
            }

            // A webhook-granted billing-retry grace period outlives a receipt
            // whose newest entry is the lapsed period — don't stomp it.
            if (existingData.subscriptionStatus === 'grace_period' &&
                existingExpiry && existingExpiry > new Date() &&
                c.expiresDateMs <= existingExpiry.getTime()) {
                delete updateData.subscriptionStatus;
                delete updateData.subscriptionExpiryDate;
            }

            // If it's a trial, record trial dates
            if (c.isTrialPeriod && c.status === 'trial' && !existingData.trialStartDate) {
                updateData.trialStartDate = new Date(parseInt(consumerEntry.purchase_date_ms)).toISOString();
                updateData.trialEndDate = new Date(c.expiresDateMs).toISOString();
            }

            await userRef.set(updateData, { merge: true });
            invalidateUserCache(userId);

            // Admin alert on the signup transition only (new subscriber, or a
            // lapsed one coming back) — never on routine re-verifies.
            const wasConsumerActive = ['active', 'trial'].includes(existingData.subscriptionStatus);
            const isNewConsumerSub =
                existingData.appleOriginalTransactionId !== consumerEntry.original_transaction_id;
            if ((c.status === 'active' || c.status === 'trial') && (isNewConsumerSub || !wasConsumerActive)) {
                require('../services/notificationService').notifyAdminPremiumSignup({
                    scope: 'consumer',
                    userId,
                    userName: existingData.displayName || null,
                    userEmail: existingData.email || null,
                    productId: consumerEntry.product_id,
                    status: c.status
                }).catch((e) => console.error('⚠️ Premium signup admin alert failed:', e.message));

                // Benefits walkthrough to the new subscriber — fire-and-forget
                if (existingData.email) {
                    require('../services/emailService')
                        .sendPremiumWelcomeEmail(existingData.email, existingData.displayName || null, { isTrial: c.status === 'trial' })
                        .catch((e) => console.error('⚠️ Premium welcome email failed:', e.message));
                }
            }

            const userData = (await userRef.get()).data();
            consumerResponse = {
                status: userData.subscriptionStatus,
                expiryDate: userData.subscriptionExpiryDate,
                trialStartDate: userData.trialStartDate,
                trialEndDate: userData.trialEndDate,
                autoRenewEnabled: consumerEntry.auto_renew_status === '1',
                productId: consumerEntry.product_id
            };
        }

        // Respond with the family the user just acted on; both families'
        // Firestore state is already up to date regardless.
        const primary = ownerSubscriptionService.isBusinessProduct(newestOverall.product_id)
            ? (businessResponse || consumerResponse)
            : (consumerResponse || businessResponse);
        res.json({ success: true, subscription: primary });

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

// Apple Root CA - G3 DER SHA-256 (https://www.apple.com/certificateauthority/).
// The ONLY trust anchor an App Store Server Notification chain may terminate
// at. The previous check (`/Apple/.test(root.subject)`) accepted any
// self-signed root that merely *named itself* Apple — i.e. anyone could forge
// a chain and flip arbitrary subscriptions.
const APPLE_ROOT_CA_G3_SHA256 = '63343ABFB89A6A03EBB57E9B3F5FA7BE7C4F5C756F3017B3A8C488C3653E9179';
const EXPECTED_BUNDLE_ID = 'com.favcircles.circles';

// Verify an App Store Server Notification V2 envelope: ES256 signature against
// the x5c leaf certificate, each chain link signed by its parent, chain
// validity dates, a root pinned to Apple Root CA G3, and our own bundle id.
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
    const rootFingerprint = (root.fingerprint256 || '').replace(/:/g, '').toUpperCase();
    if (rootFingerprint !== APPLE_ROOT_CA_G3_SHA256) {
        throw new Error('chain does not terminate at the pinned Apple Root CA G3');
    }
    const now = new Date();
    for (const cert of certs) {
        if (now < new Date(cert.validFrom) || now > new Date(cert.validTo)) {
            throw new Error('certificate in chain is expired or not yet valid');
        }
    }
    const leafKey = certs[0].publicKey.export({ type: 'spki', format: 'pem' });
    const payload = jwt.verify(signedPayload, leafKey, { algorithms: ['ES256'] });
    const bundleId = payload && payload.data && payload.data.bundleId;
    if (bundleId && bundleId !== EXPECTED_BUNDLE_ID) {
        throw new Error(`notification is for foreign bundleId ${bundleId}`);
    }
    return payload;
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

        const notificationEnvironment = (data && data.environment)
            || (transaction && transaction.environment)
            || 'Production';

        // Business (store-owner) notifications update owner* fields on the
        // user found by the owner transaction id — fully separate from the
        // consumer premium path below
        if (ownerSubscriptionService.isBusinessProduct(productId)) {
            await handleBusinessWebhook({
                notificationType, originalTransactionId, expiresDate, renewal,
                environment: notificationEnvironment
            });
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
        const userData = userDoc.data() || {};

        // Sandbox notifications must not touch a production entitlement. A dev
        // build signed into a tester Apple ID generates real Apple webhooks —
        // and sandbox subscriptions expire in minutes, so an EXPIRED for a test
        // purchase would mark a paying customer expired.
        const storedEnvironment = userData.subscriptionEnvironment || 'Production';
        if (notificationEnvironment === 'Sandbox' && storedEnvironment === 'Production') {
            console.warn(`🧪 Ignoring SANDBOX ${notificationType} for ${userId} — account holds a production entitlement`);
            return;
        }

        // Apple retries and can deliver out of order: a stale EXPIRED landing
        // after a DID_RENEW must not kill a renewed subscription. Downgrades
        // whose expiry is OLDER than what we already have on file are stale.
        const notifExpiryMs = expiresDate ? Number(expiresDate) : null;
        const storedExpiryMs = userData.subscriptionExpiryDate
            ? Date.parse(userData.subscriptionExpiryDate) : null;
        const isStaleDowngrade = notifExpiryMs && storedExpiryMs && notifExpiryMs < storedExpiryMs;

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
                if (isStaleDowngrade) {
                    console.log(`🍎 Ignoring stale ${notificationType} for ${userId} (older than stored expiry)`);
                    return;
                }
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
                if (isStaleDowngrade) {
                    console.log(`🍎 Ignoring stale EXPIRED for ${userId} (older than stored expiry)`);
                    return;
                }
                updateData = {
                    subscriptionStatus: 'expired',
                    lastWebhookReceived: new Date().toISOString()
                };
                // GRACE_PERIOD_EXPIRED-style events can arrive without an
                // expiresDate — never write new Date(NaN)
                if (notifExpiryMs) {
                    updateData.subscriptionExpiryDate = new Date(notifExpiryMs).toISOString();
                }
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
            // A manual premium grant outranks Apple's view of the world — it's
            // set by hand precisely for accounts whose receipts don't tell the
            // truth (comped, staff, migrated). Let the webhook record dates and
            // metadata, but never demote the status.
            const hasManualPremium = userData.manuallyVerified === true || userData.isPremium === true;
            const downgrades = ['expired', 'cancelled', 'grace_period'];
            if (hasManualPremium && downgrades.includes(updateData.subscriptionStatus)) {
                console.log(`🛡️ Webhook ${notificationType} would downgrade manually-verified ${userId} — keeping status`);
                delete updateData.subscriptionStatus;
            }
            if (Object.keys(updateData).length > 0) {
                await admin.firestore().collection('users').doc(userId).update(updateData);
                invalidateUserCache(userId);
                console.log(`Updated user ${userId} subscription status via webhook (${notificationType})`);
            }
        }
        
    } catch (error) {
        console.error('Webhook processing error:', error);
        // Still return 200 to prevent Apple from retrying
    }
};

// Business-subscription webhook handling: same notification types as consumer,
// mapped onto the owner* fields.
async function handleBusinessWebhook({ notificationType, originalTransactionId, expiresDate, renewal, environment }) {
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

    const userDoc = usersSnapshot.docs[0];
    const userData = userDoc.data() || {};

    // Sandbox events must never touch a production owner entitlement (a
    // sandbox test sub expires in minutes and would lock a paying store).
    const storedOwnerEnvironment = userData.ownerSubscriptionEnvironment || 'Production';
    if ((environment || 'Production') === 'Sandbox' && storedOwnerEnvironment === 'Production') {
        console.warn(`🧪 Ignoring SANDBOX business ${notificationType} for ${userDoc.id} — production owner entitlement on file`);
        return;
    }

    // Out-of-order retries: a downgrade older than the stored expiry is stale.
    const notifExpiryMs = expiresDate ? Number(expiresDate) : null;
    const storedExpiryMs = userData.ownerSubscriptionExpiryDate
        ? Date.parse(userData.ownerSubscriptionExpiryDate) : null;
    const isStaleDowngrade = notifExpiryMs && storedExpiryMs && notifExpiryMs < storedExpiryMs;

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
            if (isStaleDowngrade) {
                console.log(`🍎 Ignoring stale business ${notificationType} for ${userDoc.id}`);
                return;
            }
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
            if (isStaleDowngrade) {
                console.log(`🍎 Ignoring stale business ${notificationType} for ${userDoc.id}`);
                return;
            }
            updateData = { ownerSubscriptionStatus: 'expired' };
            // GRACE_PERIOD_EXPIRED can arrive without expiresDate — never
            // write new Date(NaN) (it throws and loses the whole update)
            if (notifExpiryMs) {
                updateData.ownerSubscriptionExpiryDate = new Date(notifExpiryMs).toISOString();
            }
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
    await userDoc.ref.update(updateData);
    invalidateUserCache(userDoc.id);
    console.log(`Updated user ${userDoc.id} business subscription via webhook (${notificationType})`);
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

        require('../services/notificationService').notifyAdminPremiumSignup({
            scope: 'consumer',
            userId,
            userName: userData.displayName || null,
            userEmail: userData.email || null,
            productId: 'com.favcircles.circles.premium.subscription.monthly',
            status: 'trial'
        }).catch((e) => console.error('⚠️ Trial signup admin alert failed:', e.message));

        if (userData.email) {
            require('../services/emailService')
                .sendPremiumWelcomeEmail(userData.email, userData.displayName || null, { isTrial: true })
                .catch((e) => console.error('⚠️ Trial welcome email failed:', e.message));
        }

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