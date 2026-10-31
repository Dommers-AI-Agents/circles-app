// backend/services/newAccountService.js
// What every brand-new account gets once its user doc exists, whichever way
// it signed up (email + password, or an emailed one-time code): App Clip
// attribution, onboarding (deferred for clip signups so the in-store first
// impression isn't blocked), the bot-pattern watch and the welcome email.
// Also the user payload every auth response returns.
const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');
const OnboardingService = require('./onboardingService');

const CLIP_CODE = /^[A-Za-z0-9]{6}$/;

/** A clip signup carries its sticker code; only then is it attributed. */
const isClipSignup = ({ signupSource, stickerCode } = {}) =>
  signupSource === 'app_clip' && CLIP_CODE.test(String(stickerCode || ''));

/**
 * Runs the new-account steps. `user` is the created user doc plus `id`.
 * Returns { circlesCount, placesCount } (0 for clip signups: the clip never
 * renders them and their onboarding runs in the background).
 */
async function finishNewAccount(user, { ip, provider, signupSource, stickerCode, client, sendWelcome = true } = {}) {
  const userId = user.id;
  const clip = isClipSignup({ signupSource, stickerCode });
  if (clip) {
    // Analytics only — points still flow through /api/rewards/scan
    await require('./rewardService').attributeClipSignup(userId, stickerCode);
  }

  let circlesCount = 0;
  let placesCount = 0;
  try {
    // The user's city (from a geocoded zipcode) keeps the sample place local
    const userCity = (user.location || '').split(',')[0].trim();
    const cityArg = userCity ? { city: userCity } : null;
    if (clip) {
      OnboardingService.completeUserOnboarding(userId, cityArg)
        .catch((err) => console.error(`❌ Deferred clip onboarding failed for ${userId}:`, err));
    } else {
      const onboarding = await OnboardingService.completeUserOnboarding(userId, cityArg, {
        skipSamplePlace: OnboardingService.firstFavoriteReplacesSample(client)
      });
      if (onboarding.success) {
        const circles = await getFirestore().collection(COLLECTIONS.CIRCLES).where('owner', '==', userId).get();
        circlesCount = circles.size;
        circles.forEach((doc) => { placesCount += doc.data().placesCount || 0; });
      }
    }

    // Bot-pattern watch (alerts the admin, never blocks)
    require('./signupMonitor').recordSignup({ ip, email: user.email, provider, userId });
    // Welcome email (fire-and-forget; never blocks signup). Not for an
    // instant account nobody has confirmed yet: it goes when they confirm.
    if (user.email && sendWelcome) {
      require('./emailService').sendWelcomeEmail(user.email, user.displayName)
        .catch((err) => console.error('Welcome email failed:', err.message));
    }
  } catch (error) {
    // A failed onboarding never fails the signup
    console.error(`❌ Onboarding failed for user ${userId}:`, error);
  }
  return { circlesCount, placesCount };
}

/** The `user` object in every auth response (register, login, email code). */
const authUserPayload = (user, id) => ({
  _id: id, // Always the normalized id
  email: user.email,
  displayName: user.displayName,
  firstName: user.firstName || null,
  lastName: user.lastName || null,
  phoneNumber: user.phoneNumber || null,
  profilePicture: user.profilePicture || null,
  bio: user.bio || null,
  location: user.location || null,
  friends: user.friends || [],
  friendRequests: user.friendRequests || [],
  followersCount: user.followersCount || 0,
  followingCount: user.followingCount || 0,
  circlesCount: user.circlesCount || 0,
  placesCount: user.placesCount || 0,
  createdAt: user.createdAt,
  // An instant App Clip account whose email isn't confirmed yet: the app
  // asks for the emailed code (POST /auth/email-code/confirm)
  emailUnverified: user.emailUnverified === true
});

module.exports = { isClipSignup, finishNewAccount, authUserPayload };
