// services/badgeService.js
//
// What the number on the app icon means.
//
// It used to mean nothing in particular: every push carried a hardcoded
// `badge: 1`, which on iOS SETS the badge rather than incrementing it, so any
// push at all produced a 1 — including "someone in your network added a place",
// which is never written to the Notifications list. The badge pointed at
// something the app had no way to show, and nothing ever cleared it.
//
// The rule now: the badge counts things that are WAITING FOR YOU and that you
// can actually open — unread messages, connection requests you haven't
// answered, and unread rows in the Notifications list. A push that leaves no
// trace in any of those carries no badge at all (see BADGE_WORTHY below), and
// omitting the key leaves whatever is on the icon untouched.

const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');

const db = getFirestore();

/**
 * Push types that leave something behind to come back to.
 *
 * Everything here either lands in the Notifications list (the `validTypes`
 * allowlist in FirestoreModels) or shows up as an unread message or a pending
 * request. Anything NOT here is a banner and nothing more: worth interrupting
 * for once, not worth a dot that persists until it's dealt with.
 */
const BADGE_WORTHY = new Set([
  'new_message',
  'connection_request',
  'connection_accepted',
  'place_like',
  'place_comment',
  'new_follower',
  'activity_reaction',
  'activity_comment',
  'check_in',
  'new_suggestion',
  'moment_tag',
  'circle_invite',
  'store_claim',
  'store_claim_approved',
  'premium_signup',
  'did_you_know'
]);

const shouldBadge = (type) => BADGE_WORTHY.has(type);

/**
 * How many things are waiting for this user.
 *
 * Three independent reads in parallel. Counting is deliberately cheap and
 * approximate in one respect: a conversation the user has open right now still
 * counts until they read it, which is the same thing the Messages tab shows.
 *
 * @returns {Promise<number>}
 */
const computeBadgeCount = async (userId) => {
  if (!userId) return 0;
  try {
    const [messages, requests, notifications] = await Promise.all([
      db.collection(COLLECTIONS.MESSAGE_READS)
        .where('userId', '==', userId)
        .where('isRead', '==', false)
        .get(),
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('connectedUserId', '==', userId)
        .where('status', '==', 'pending')
        .get(),
      // The Notifications list — the surface the badge sends people to.
      // This was missing entirely, so a like or a comment never counted.
      db.collection(COLLECTIONS.NOTIFICATIONS)
        .where('userId', '==', userId)
        .where('read', '==', false)
        .get()
    ]);
    return messages.size + requests.size + notifications.size;
  } catch (error) {
    // A badge is never worth failing a send over.
    console.error('🔔 Failed to compute badge count:', error.message);
    return 0;
  }
};

module.exports = { BADGE_WORTHY, shouldBadge, computeBadgeCount };
