// services/activityPushPrefs.js
// Who gets a push about a connection's activity, and how often.
//
// The profile bell ("notify me about this person's activity") is ONE
// person's choice about the OTHER person. It used to be stored as one shared
// boolean on the connection, so turning on the bell for a friend also sent
// that friend a push for everything YOU did (Wes, 2026-10-16: adding three
// photos to Pasta & Provisions pushed 11 people three times each). It is now
// `activityNotifyUserIds`: the members who asked to hear about the other
// one. The old boolean can't say whose choice it was, so it no longer sends
// anything; people re-tap the bell.
const { getFirestore } = require('../config/firebase');
const { isSameUser } = require('./idService');

const db = getFirestore();

/** Does `recipientId` want pushes about the other member of this connection? */
const wantsActivityPush = (connection, recipientId) =>
  !!recipientId && (connection?.activityNotifyUserIds || []).some((id) => isSameUser(id, recipientId));

const PHOTO_PUSH_WINDOW_MS = 6 * 60 * 60 * 1000;

/**
 * One push per burst: claims the slot for (kind, actor, place) in the
 * current window. True for the first caller, false for the rest (adding six
 * photos is one thing to tell people about, not six). Fails open on a
 * Firestore error other than "already claimed": a missed throttle is better
 * than a missed notification.
 */
const claimPushSlot = async (kind, actorId, entityId, now = Date.now(), windowMs = PHOTO_PUSH_WINDOW_MS) => {
  const bucket = Math.floor(now / windowMs);
  const id = `${kind}_${actorId}_${entityId}_${bucket}`.replace(/[/]/g, '_');
  try {
    await db.collection('pushThrottle').doc(id).create({ kind, actorId, entityId, createdAt: new Date(now).toISOString() });
    return true;
  } catch (error) {
    if (error && (error.code === 6 || /already[_ ]exists/i.test(error.message || ''))) return false;
    console.warn(`[pushThrottle] ${id}: ${error.message}`);
    return true;
  }
};

module.exports = { wantsActivityPush, claimPushSlot, PHOTO_PUSH_WINDOW_MS };
