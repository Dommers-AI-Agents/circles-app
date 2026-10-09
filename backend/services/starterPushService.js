// services/starterPushService.js — first-week pushes (new-user audit, Wes
// 2026-10-09). At 6 PM their time on days 1, 2 and 4 after signup, ONE push
// about the next step they haven't taken yet — nothing if they already did it.
// Rides the "Did you know" channel (type did_you_know, `tips` preference), so
// anyone who turned tips off never gets these. Each step is sent at most once.
const { getFirestore, FieldValue } = require('../config/firebase');
const { COLLECTIONS, createNotification, validateNotification } = require('../models/FirestoreModels');
const { localClock } = require('../utils/localClock');
const { defaultFollowIds, chosenFollowCount } = require('./defaultAccounts');

const db = () => getFirestore();
const DAY = 24 * 60 * 60 * 1000;
const SEND_HOUR = 18;
const WRAPPER_TYPE = 'did_you_know';

/** Pure (tested): the push for `dayNumber` (whole days since signup), or null. */
function starterPushFor(dayNumber, progress) {
  const p = progress || {};
  if (dayNumber === 1 && (p.realPlaces || 0) === 0) {
    return { key: 'starter_push_map', type: 'starter_map', title: 'Your map is waiting 🗺️',
      body: 'Save the first place you love — it takes ten seconds, and it starts your personal map.' };
  }
  if (dayNumber === 2 && (p.followingOthers || 0) < 3) {
    return { key: 'starter_push_follow', type: 'starter_follow', title: 'See what your friends love 👀',
      body: 'Follow a few people and every favorite on their map shows up on yours.' };
  }
  if (dayNumber === 4 && (p.realPlaces || 0) < 3) {
    return { key: 'starter_push_more', type: 'starter_map', title: 'Add a couple more favorites',
      body: `Your map has ${p.realPlaces || 0} place${p.realPlaces === 1 ? '' : 's'}. A few more and it's worth exploring.` };
  }
  return null;
}

async function progressFor(user, defaults) {
  const places = await db().collection(COLLECTIONS.PLACES).where('addedBy', '==', user.id).limit(6).get();
  const realPlaces = places.docs.map(d => d.data()).filter(p => !p.isSamplePlace && !p.deletedAt).length;
  const followingOthers = chosenFollowCount(user.following, defaults);
  return { realPlaces, followingOthers };
}

/** The hourly task: everyone 1–5 days old whose clock reads 6 PM. */
async function run({ now = new Date(), dryRun = false } = {}) {
  const since = new Date(now.getTime() - 5 * DAY).toISOString();
  const snap = await db().collection(COLLECTIONS.USERS).where('createdAt', '>=', since).get();
  const defaults = await defaultFollowIds(db());
  const notificationService = require('./notificationService');
  const results = { candidates: snap.size, sent: 0, previews: [] };
  for (const doc of snap.docs) {
    const user = { id: doc.id, ...doc.data() };
    try {
      if ((user.notificationPreferences || {}).tips === false) continue;
      if (localClock((user.notificationPreferences || {}).timezone, now).hour !== SEND_HOUR) continue;
      const dayNumber = Math.floor((now.getTime() - Date.parse(user.createdAt)) / DAY);
      const push = starterPushFor(dayNumber, await progressFor(user, defaults));
      if (!push || (user.starterPushes || []).includes(push.key)) continue;
      results.previews.push({ userId: user.id, key: push.key });
      if (dryRun) continue;
      // Claim first, so a re-run of the hour can't double-send
      await doc.ref.update({ starterPushes: FieldValue.arrayUnion(push.key) });
      const data = { type: push.type, starterKey: push.key };
      const row = createNotification({ userId: user.id, type: WRAPPER_TYPE, title: push.title, body: push.body, data });
      if (validateNotification(row).length === 0) await db().collection(COLLECTIONS.NOTIFICATIONS).add(row);
      await notificationService.sendToUser(user.id, { type: WRAPPER_TYPE, title: push.title, body: push.body, data });
      results.sent += 1;
    } catch (error) {
      console.error(`🌱 starter push failed for ${user.id}:`, error.message);
    }
  }
  console.log(`🌱 Starter pushes: ${results.sent} sent of ${results.candidates} new accounts${dryRun ? ' (dry run)' : ''}`);
  return results;
}

module.exports = { run, starterPushFor };
