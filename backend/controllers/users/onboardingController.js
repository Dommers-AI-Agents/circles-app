// backend/controllers/users/onboardingController.js
// tutorial status, app-open stamps, onboarding retry
// Split out of firebaseUserController.js (handlers unchanged).
const { getFirestore } = require('../../config/firebase');
const { FieldValue } = require('firebase-admin/firestore');
const { COLLECTIONS } = require('../../models/FirestoreModels');
const { normalizeUserId } = require('../../services/idService');

const db = getFirestore();

// @desc    Get tutorial status for current user
// @route   GET /api/users/me/tutorial-status
// @access  Private
exports.getTutorialStatus = async (req, res, next) => {
  try {
    const userId = normalizeUserId(req.user.uid);
    
    const userRef = db.collection(COLLECTIONS.USERS).doc(userId);
    const userDoc = await userRef.get();
    
    if (!userDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'User not found'
      });
    }
    
    const userData = userDoc.data();
    
    res.status(200).json({
      success: true,
      hasCompletedTutorial: userData.hasCompletedTutorial || false,
      onboardingCompleted: userData.onboardingCompleted || false
    });
  } catch (error) {
    console.error('Error getting tutorial status:', error);
    next(error);
  }
};

// @desc    Mark tutorial as completed
// @route   POST /api/users/me/complete-tutorial
// @access  Private
exports.completeTutorial = async (req, res, next) => {
  try {
    const userId = normalizeUserId(req.user.uid);
    
    const userRef = db.collection(COLLECTIONS.USERS).doc(userId);
    const userDoc = await userRef.get();
    
    if (!userDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'User not found'
      });
    }
    
    await userRef.update({
      hasCompletedTutorial: true,
      updatedAt: new Date().toISOString()
    });
    
    console.log(`✅ Tutorial marked as completed for user ${userId}`);
    
    res.status(200).json({
      success: true,
      message: 'Tutorial marked as completed'
    });
  } catch (error) {
    console.error('Error completing tutorial:', error);
    next(error);
  }
};

// @desc    Record an app open (launch or return to foreground). Powers
//          "did this user quietly come back" insight that API traffic alone
//          can't show — first/last open timestamps, a lifetime open counter,
//          and the client version/platform they're on.
// @route   POST /api/users/me/app-open
// @access  Private
exports.recordAppOpen = async (req, res, next) => {
  try {
    const userId = normalizeUserId(req.user.uid);
    const now = new Date().toISOString();
    const { appVersion, build, platform, latitude, longitude } = req.body || {};

    const updates = {
      lastActive: now,
      lastAppOpenAt: now,
      appOpenCount: FieldValue.increment(1)
    };
    if (!req.user.firstAppOpenAt) updates.firstAppOpenAt = now;
    if (appVersion) updates.appVersion = String(appVersion).slice(0, 32);
    if (build) updates.appBuild = String(build).slice(0, 32);
    if (platform) updates.appPlatform = String(platform).slice(0, 16);

    // The app shares a location fix once permission is granted — the signal
    // signup never has
    const hasCoords = typeof latitude === 'number' && typeof longitude === 'number' &&
      Math.abs(latitude) <= 90 && Math.abs(longitude) <= 180 && !(latitude === 0 && longitude === 0);
    if (hasCoords) {
      updates.lastKnownLocation = { latitude, longitude };
    }

    await db.collection(COLLECTIONS.USERS).doc(userId).update(updates);
    res.status(200).json({ success: true });

    // Deferred starter place: users who signed up without location got three
    // empty circles — seed the sample now that we know where they are.
    // Fire-and-forget after the response.
    if (hasCoords) {
      require('../../services/onboardingService')
        .seedSamplePlaceIfMissing(userId, { latitude, longitude })
        .catch(() => {});
    }
  } catch (error) {
    console.error('Error recording app open:', error);
    next(error);
  }
};

// @desc    Retry onboarding for current user
// @route   POST /api/users/me/complete-onboarding
// @access  Private
exports.retryOnboarding = async (req, res, next) => {
  try {
    const userId = normalizeUserId(req.user.uid);
    const OnboardingService = require('../../services/onboardingService');
    
    // Check if user already has circles
    const circlesSnapshot = await db.collection(COLLECTIONS.CIRCLES)
      .where('owner', '==', userId)
      .limit(1)
      .get();
    
    if (!circlesSnapshot.empty) {
      return res.status(400).json({
        success: false,
        message: 'User already has circles'
      });
    }
    
    // Run onboarding
    const result = await OnboardingService.completeUserOnboarding(userId);
    
    if (result.success) {
      res.status(200).json({
        success: true,
        message: 'Onboarding completed successfully',
        circlesCreated: result.circlesCreated
      });
    } else {
      res.status(500).json({
        success: false,
        message: 'Onboarding failed',
        error: result.error
      });
    }
  } catch (error) {
    console.error('Error retrying onboarding:', error);
    next(error);
  }
};
