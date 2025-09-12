const admin = require('firebase-admin');
const subscriptionLimitService = require('../services/subscriptionLimitService');
const { getTierForStatus } = require('../config/subscriptionLimits');
const { COLLECTIONS } = require('../models/FirestoreModels');

const db = admin.firestore();

// @desc    Debug subscription status for current user
// @route   GET /api/users/me/subscription/debug
// @access  Private
exports.debugSubscriptionStatus = async (req, res) => {
    try {
        const userId = req.user.uid;
        
        console.log(`🔍 SUBSCRIPTION DEBUG for user ${userId}`);
        
        const debugInfo = {
            userId,
            timestamp: new Date().toISOString(),
            steps: []
        };
        
        // Step 1: Get raw user data
        debugInfo.steps.push("1. Fetching user data from database...");
        const userRef = db.collection(COLLECTIONS.USERS).doc(userId);
        const userDoc = await userRef.get();
        
        if (!userDoc.exists) {
            debugInfo.error = "User document not found";
            return res.json({ success: false, debug: debugInfo });
        }
        
        const userData = userDoc.data();
        debugInfo.rawUserData = {
            subscriptionStatus: userData.subscriptionStatus,
            subscriptionExpiryDate: userData.subscriptionExpiryDate,
            appleOriginalTransactionId: userData.appleOriginalTransactionId,
            lastReceipt: userData.lastReceipt ? "Present" : "None",
            lastReceiptVerification: userData.lastReceiptVerification,
            trialStartDate: userData.trialStartDate,
            trialEndDate: userData.trialEndDate,
            onboardingCompleted: userData.onboardingCompleted
        };
        
        // Step 2: Get subscription data through service
        debugInfo.steps.push("2. Getting subscription data through service...");
        const subscriptionData = await subscriptionLimitService.getUserSubscriptionData(userId, true);
        debugInfo.subscriptionServiceData = subscriptionData;
        
        // Step 3: Get tier information
        debugInfo.steps.push("3. Determining subscription tier...");
        const tier = getTierForStatus(subscriptionData.subscriptionStatus);
        debugInfo.tier = {
            status: subscriptionData.subscriptionStatus,
            maxCircles: tier.MAX_CIRCLES,
            maxPlacesPerCircle: tier.MAX_PLACES_PER_CIRCLE,
            canExport: tier.CAN_EXPORT,
            canShareWithoutWatermark: tier.CAN_SHARE_WITHOUT_WATERMARK
        };
        
        // Step 4: Get circles information
        debugInfo.steps.push("4. Counting user circles...");
        const circlesSnapshot = await db.collection(COLLECTIONS.CIRCLES)
            .where('owner', '==', userId)
            .get();
            
        const circles = circlesSnapshot.docs.map(doc => ({
            id: doc.id,
            name: doc.data().name,
            isDefaultCircle: doc.data().isDefaultCircle,
            createdAt: doc.data().createdAt
        }));
        
        debugInfo.circles = {
            total: circles.length,
            defaultCircles: circles.filter(c => c.isDefaultCircle === true).length,
            customCircles: circles.filter(c => c.isDefaultCircle !== true).length,
            onlyHasDefaultCircles: circles.length > 0 && circles.every(c => c.isDefaultCircle === true),
            list: circles
        };
        
        // Step 5: Test the actual canCreateCircle logic
        debugInfo.steps.push("5. Testing canCreateCircle logic...");
        const canCreateResult = await subscriptionLimitService.canCreateCircle(userId);
        debugInfo.canCreateResult = canCreateResult;
        
        // Step 6: Analyze the issue
        debugInfo.steps.push("6. Analyzing potential issues...");
        debugInfo.analysis = {
            hasActiveStatus: subscriptionData.subscriptionStatus === 'active',
            hasUnlimitedCircles: tier.MAX_CIRCLES === Infinity,
            withinFreeLimit: circles.length < 6,
            qualifiesForNewUserBypass: circles.length <= 3 && debugInfo.circles.onlyHasDefaultCircles,
            shouldBeAbleToCreate: canCreateResult.canCreate
        };
        
        // Determine what's wrong
        if (!canCreateResult.canCreate && subscriptionData.subscriptionStatus === 'active') {
            debugInfo.issue = "PREMIUM USER BLOCKED: User has active subscription but is being limited";
        } else if (!canCreateResult.canCreate && circles.length > 6) {
            debugInfo.issue = "SUBSCRIPTION CHECK FAILING: User over limit but subscription check not working";
        } else if (canCreateResult.canCreate) {
            debugInfo.issue = "NO ISSUE DETECTED: User should be able to create circles";
        }
        
        console.log(`🔍 DEBUG COMPLETE for user ${userId}:`, JSON.stringify(debugInfo, null, 2));
        
        res.json({
            success: true,
            debug: debugInfo
        });
        
    } catch (error) {
        console.error('Subscription debug error:', error);
        res.status(500).json({
            success: false,
            error: 'Failed to debug subscription status',
            details: error.message
        });
    }
};