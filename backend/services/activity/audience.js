// backend/services/activity/audience.js
//
// Who may be TOLD about something that happened in a circle.
//
// Read gates decide what a feed request is allowed to return. This decides the
// other half: which connections get a row written onto their connection doc, an
// SSE event, or a push. Those are fan-outs — once sent they cannot be taken
// back — so they are deliberately stricter than the read gate, and anything we
// are unsure about simply is not sent.
//
// Before the Inner Circle tier this was two hardcoded lines ("public or
// myNetwork → tell every connection; private → tell nobody"), repeated in
// places.js and circles.js.

const { getFirestore } = require('../../config/firebase');
const { COLLECTIONS } = require('../../models/FirestoreModels');
const { normalizePrivacy, PRIVACY } = require('../visibility');

const db = getFirestore();

/**
 * @param {object} circleData  the raw circle doc
 * @param {string} ownerId     whoever performed the action (the circle's owner
 *                             or one of its editors)
 * @returns {Promise<{emits: boolean, allows: (userId: string) => boolean, tier: string}>}
 *   `emits` is false when nobody but the owner could ever see it, so callers
 *   can skip the whole block. `allows` filters individual recipients.
 */
const circleAudience = async (circleData, ownerId) => {
  // A circle doc with no privacy field predates the setting; treat it as the
  // closed end rather than guessing it was meant to be public.
  const tier = normalizePrivacy(circleData && circleData.privacy) || PRIVACY.PRIVATE;
  const sharedWith = new Set(((circleData && circleData.sharedWith) || []).map(String));

  if (tier === PRIVACY.PUBLIC || tier === PRIVACY.CONNECTIONS) {
    return { tier, emits: true, allows: () => true };
  }

  if (tier === PRIVACY.INNER_CIRCLE) {
    // The list lives on the owner, not the circle, so that editing it
    // retroactively changes who can see every circle set to this tier.
    const ownerDoc = await db.collection(COLLECTIONS.USERS).doc(String(ownerId)).get();
    const list = new Set(((ownerDoc.exists && ownerDoc.data().innerCircle) || []).map(String));
    const allowed = new Set([...list, ...sharedWith]);
    return { tier, emits: allowed.size > 0, allows: (userId) => allowed.has(String(userId)) };
  }

  // Private: nobody, unless this particular circle has a guest list.
  return {
    tier,
    emits: sharedWith.size > 0,
    allows: (userId) => sharedWith.has(String(userId))
  };
};

/**
 * Narrow a circle's audience by a PLACE's own privacy.
 *
 * A place can only restrict further than its circle, so this intersects: an
 * Inner Circle place inside a Connections circle reaches the owner's list, not
 * every connection. Without it the fan-out asked the circle only, and pushed a
 * deliberately narrowed save to everyone.
 *
 * @param {object} audience  the result of circleAudience
 * @param {object} place     the save record (may be undefined — then unchanged)
 * @param {string} ownerId   whoever saved it
 */
const narrowedByPlace = async (audience, place, ownerId) => {
  const tier = normalizePrivacy(place && place.privacy);
  const guests = new Set(((place && place.sharedWith) || []).map(String));

  // followCircle (the default), public and myNetwork add nothing of their own:
  // the circle already decided. Only the two closed tiers narrow.
  if (tier !== PRIVACY.INNER_CIRCLE && tier !== PRIVACY.PRIVATE) return audience;

  if (tier === PRIVACY.PRIVATE) {
    // Named guests still hear about it — that is what naming them means.
    return {
      tier,
      emits: guests.size > 0,
      allows: (userId) => guests.has(String(userId))
    };
  }

  const ownerDoc = await db.collection(COLLECTIONS.USERS).doc(String(ownerId)).get();
  const list = new Set(((ownerDoc.exists && ownerDoc.data().innerCircle) || []).map(String));
  const allowed = new Set([...list, ...guests]);
  const allows = (userId) => guests.has(String(userId))
    || (audience.allows(userId) && list.has(String(userId)));
  return { tier, emits: allowed.size > 0, allows };
};

module.exports = { circleAudience, narrowedByPlace };
