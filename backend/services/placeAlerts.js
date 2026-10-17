// services/placeAlerts.js
// Store alerts (Wes, 2026-10-17): followers can turn on a bell for a place,
// and the store's new offers, announcements and events then push to them.
// Off by default: following is silent, the bell is the opt-in.
//
// The bell lives on the canonical globalPlaces record as `alertFollowerIds`
// (a subset of `followers`, changed in one transaction, same rule as follows
// and likes). Only NEW posts push, never edits, and a store reaches its
// followers at most once a day; the post still lands in their feed and on
// Locals either way. Quiet hours and the "Stores you follow" switch in
// Settings are honoured by notificationService.
const { getFirestore, FieldValue } = require('../config/firebase');
const { GLOBAL_COLLECTIONS } = require('../models/GlobalPlace');
const notificationService = require('./notificationService');
const { claimPushSlot } = require('./activityPushPrefs');

const db = getFirestore();
const STORE_ALERT_WINDOW_MS = 24 * 60 * 60 * 1000;

class PlaceAlertError extends Error {
  constructor(status, message) { super(message); this.status = status; }
}

/** Who gets alerts: followers with the bell on (never someone who unfollowed). */
const alertAudience = (placeData) => {
  const followers = new Set((placeData && placeData.followers) || []);
  return ((placeData && placeData.alertFollowerIds) || []).filter((id) => followers.has(id));
};

/** Turn the bell on or off for `userId`. Only a follower can turn it on. */
async function setAlerts(globalPlaceRef, userId, on) {
  return db.runTransaction(async (tx) => {
    const doc = await tx.get(globalPlaceRef);
    if (!doc.exists) throw new PlaceAlertError(404, 'Place not found');
    const data = doc.data();
    if (on && !(data.followers || []).includes(userId)) {
      throw new PlaceAlertError(409, 'Follow this place first to get its alerts');
    }
    tx.update(globalPlaceRef, {
      alertFollowerIds: on ? FieldValue.arrayUnion(userId) : FieldValue.arrayRemove(userId)
    });
    const ids = new Set(data.alertFollowerIds || []);
    if (on) ids.add(userId); else ids.delete(userId);
    return { alertsOn: on, alertFollowersCount: alertAudience({ ...data, alertFollowerIds: [...ids] }).length };
  });
}

/** "Pasta & Provisions: Half-price wine tonight" */
const alertText = (placeName, kind, title, message) => {
  const name = String(placeName || 'A place you follow').trim();
  const headline = String(title || '').trim();
  const body = kind === 'offer'
    ? `New reward: ${headline}`
    : (String(message || '').trim() || headline);
  return { title: kind === 'offer' ? name : `${name}: ${headline}`, body };
};

/**
 * Push a new offer/announcement/event to the store's bell-on followers.
 * Returns { audience, sent, throttled }. Never throws (the post must not fail
 * because a push did).
 */
async function alertFollowers({ globalPlaceId, placeName, kind, title, message, now = Date.now() }) {
  try {
    if (!globalPlaceId) return { audience: 0, sent: 0, throttled: false };
    const doc = await db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).doc(globalPlaceId).get();
    if (!doc.exists) return { audience: 0, sent: 0, throttled: false };
    const audience = alertAudience(doc.data());
    if (!audience.length) return { audience: 0, sent: 0, throttled: false };
    if (!(await claimPushSlot('store_alert', globalPlaceId, 'followers', now, STORE_ALERT_WINDOW_MS))) {
      return { audience: audience.length, sent: 0, throttled: true };
    }
    const text = alertText(placeName || doc.data().name, kind, title, message);
    const results = await Promise.all(audience.map((userId) =>
      notificationService.sendToUser(userId, {
        type: 'store_alert',
        title: text.title,
        body: text.body,
        data: { type: 'store_alert', placeId: globalPlaceId, kind }
      }).catch((error) => ({ success: false, error: error.message }))));
    return { audience: audience.length, sent: results.filter((r) => r && r.success).length, throttled: false };
  } catch (error) {
    console.error(`[store_alert] ${globalPlaceId}: ${error.message}`);
    return { audience: 0, sent: 0, throttled: false };
  }
}

module.exports = { setAlerts, alertFollowers, alertAudience, alertText, PlaceAlertError, STORE_ALERT_WINDOW_MS };
