// backend/services/webPush.js
// Browser notifications for the web app (app.favcircles.com), 2026-11-26.
// A browser's subscription is NOT a device token: it lives in its own
// collection (webPushSubscriptions), never in users.deviceTokens. Email
// rules read deviceTokens to decide who has the app (emailFallback
// pushReachable, storeWebEmails isWebOnly); a browser subscription must not
// switch off the store emails a web customer signed up for.
//
// Sent beside the phone push from notificationService.sendToUser, under the
// same per-type switches and quiet hours. Needs WEB_PUSH_PUBLIC_KEY and
// WEB_PUSH_PRIVATE_KEY (a VAPID pair); without them every call is a no-op.
const crypto = require('crypto');
const { getFirestore } = require('../config/firebase');
const { ServiceError } = require('../utils/serviceError');

const COLLECTION = 'webPushSubscriptions';
const MAX_PER_USER = 10;
const WEB_APP_URL = 'https://app.favcircles.com';

const db = () => getFirestore();
const publicKey = () => process.env.WEB_PUSH_PUBLIC_KEY || null;
const enabled = () => !!(process.env.WEB_PUSH_PUBLIC_KEY && process.env.WEB_PUSH_PRIVATE_KEY);

let client = null;
const webPush = () => {
  if (!client) {
    client = require('web-push');
    client.setVapidDetails(process.env.WEB_PUSH_SUBJECT || 'https://favcircles.com/support.html',
      process.env.WEB_PUSH_PUBLIC_KEY, process.env.WEB_PUSH_PRIVATE_KEY);
  }
  return client;
};

const idFor = (endpoint) => crypto.createHash('sha256').update(String(endpoint)).digest('hex');
const safeId = (value) => (/^[A-Za-z0-9_-]{1,200}$/.test(String(value || '')) ? String(value) : null);

/**
 * Pure: the web app page a notification opens, from the ids its data
 * carries. Mirrors the app's tap destinations (Logic/NotificationTapRouter).
 */
const webPathFor = (notification) => {
  const data = (notification && notification.data) || {};
  const type = String((notification && notification.type) || data.type || '');
  const conversation = safeId(data.conversationId);
  const place = safeId(data.globalPlaceId) || safeId(data.placeId);
  const user = safeId(data.fromUserId) || safeId(data.userId);
  const circle = safeId(data.circleId);
  if (conversation || type === 'new_message') return conversation ? `/messages/${conversation}` : '/messages';
  if (/^(connection_request|follow_request)/.test(type)) return '/people';
  if (type === 'store_alert' || type === 'store_nudge') return place ? `/place/${place}` : '/rewards';
  if (/^(new_follower|connection_accepted|follow_request_accepted)/.test(type) && user) return `/user/${user}`;
  if (place) return `/place/${place}`;
  if (circle) return `/circle/${circle}`;
  if (user) return `/user/${user}`;
  return '/notifications';
};

/** Pure: what the service worker shows. Small: push payloads cap near 4 KB. */
const payloadFor = (notification) => ({
  title: String(notification.title || 'FavCircles').slice(0, 120),
  body: String(notification.body || '').slice(0, 300),
  url: webPathFor(notification),
  // One banner per conversation / place; others stack
  tag: String((notification.data && (notification.data.conversationId || notification.data.placeId)) || notification.type || 'favcircles').slice(0, 64)
});

/** Pure: a browser's PushSubscription JSON, checked. Throws ServiceError 400. */
const cleanSubscription = (raw) => {
  const endpoint = raw && typeof raw.endpoint === 'string' ? raw.endpoint.trim() : '';
  const keys = (raw && raw.keys) || {};
  let host = '';
  try { host = new URL(endpoint).protocol === 'https:' ? new URL(endpoint).host : ''; } catch (e) { host = ''; }
  if (!host || endpoint.length > 1000 || typeof keys.p256dh !== 'string' || typeof keys.auth !== 'string'
    || keys.p256dh.length > 200 || keys.auth.length > 100) {
    throw new ServiceError(400, 'BAD_SUBSCRIPTION', "That browser's notification details aren't valid.");
  }
  return { endpoint, keys: { p256dh: keys.p256dh, auth: keys.auth } };
};

/** Save this browser for this person (a browser belongs to whoever signed in last). */
async function subscribe(userId, raw, { userAgent = null } = {}) {
  if (!enabled()) throw new ServiceError(503, 'WEB_PUSH_OFF', 'Browser notifications are not available right now.');
  const subscription = cleanSubscription(raw);
  const now = new Date().toISOString();
  await db().collection(COLLECTION).doc(idFor(subscription.endpoint)).set({
    userId, ...subscription, userAgent: userAgent ? String(userAgent).slice(0, 300) : null, createdAt: now, updatedAt: now
  });
  // Keep the newest few per person
  const mine = await db().collection(COLLECTION).where('userId', '==', userId).get();
  const extra = mine.docs.sort((a, b) => String(b.data().updatedAt).localeCompare(String(a.data().updatedAt))).slice(MAX_PER_USER);
  await Promise.all(extra.map((doc) => doc.ref.delete()));
  return { subscribed: true };
}

async function unsubscribe(userId, endpoint) {
  if (!endpoint) return { subscribed: false };
  const ref = db().collection(COLLECTION).doc(idFor(endpoint));
  const doc = await ref.get();
  if (doc.exists && doc.data().userId === userId) await ref.delete();
  return { subscribed: false };
}

/** Every browser of this person forgets them (account deletion). */
async function removeAllForUser(userId) {
  const mine = await db().collection(COLLECTION).where('userId', '==', userId).get();
  await Promise.all(mine.docs.map((doc) => doc.ref.delete()));
  return mine.size;
}

/**
 * Send to every browser this person turned notifications on in. Never
 * throws. A browser that says the subscription is gone (404/410) is dropped.
 */
async function sendToUser(userId, notification) {
  if (!enabled()) return { sent: 0 };
  try {
    const mine = await db().collection(COLLECTION).where('userId', '==', userId).get();
    if (mine.empty) return { sent: 0 };
    const payload = JSON.stringify(payloadFor(notification));
    const results = await Promise.all(mine.docs.map(async (doc) => {
      const { endpoint, keys } = doc.data();
      try {
        await webPush().sendNotification({ endpoint, keys }, payload, { TTL: 24 * 60 * 60, urgency: 'normal' });
        return true;
      } catch (error) {
        if (error && (error.statusCode === 404 || error.statusCode === 410)) await doc.ref.delete().catch(() => {});
        else console.warn(`🌐 Web push to ${userId} failed: ${error && (error.statusCode || error.message)}`);
        return false;
      }
    }));
    return { sent: results.filter(Boolean).length };
  } catch (error) {
    console.warn(`🌐 Web push for ${userId} failed: ${error.message}`);
    return { sent: 0 };
  }
}

module.exports = {
  COLLECTION, WEB_APP_URL, publicKey, enabled, webPathFor, payloadFor, cleanSubscription,
  subscribe, unsubscribe, removeAllForUser, sendToUser
};
