// services/starterPushService.js — first-week pushes (new-user audit, Wes
// 2026-10-09). At 6 PM their time on days 1, 2 and 5 after signup, ONE push
// about the next step they haven't taken yet — nothing if they already did it.
// Days 2 and 5 grow the map (Wes, 2026-11-16): they name real places saved
// near them and real people to follow (services/starterGrow), and open
// My Network → Discover, which lists both. Rides the "Did you know" channel
// (type did_you_know, `tips` preference), so anyone who turned tips off never
// gets these. Each step is sent at most once.
const { getFirestore, FieldValue } = require('../config/firebase');
const { COLLECTIONS, createNotification, validateNotification } = require('../models/FirestoreModels');
const { localClock } = require('../utils/localClock');
const { defaultFollowIds, chosenFollowCount } = require('./defaultAccounts');

const db = () => getFirestore();
const DAY = 24 * 60 * 60 * 1000;
const SEND_HOUR = 18;
const WRAPPER_TYPE = 'did_you_know';

/** A map this full, following this many, doesn't need growing */
const GROWN_PLACES = 5;
const GROWN_FOLLOWING = 3;
const GROW_DAYS = new Set([2, 5]);

/**
 * Pure (tested): the push for `dayNumber` (whole days since signup), or null.
 * `picks` (days 2 and 5): what services/starterGrow found near them.
 */
function starterPushFor(dayNumber, progress, picks) {
  const p = progress || {};
  const places = p.realPlaces || 0;
  if (dayNumber === 1 && places === 0) {
    return { key: 'starter_push_map', type: 'starter_map', title: 'Your map is waiting 🗺️',
      body: 'Save the first place you love — it takes ten seconds, and it starts your personal map.' };
  }
  if (GROW_DAYS.has(dayNumber)) {
    if (places >= GROWN_PLACES && (p.followingOthers || 0) >= GROWN_FOLLOWING) return null;
    const named = require('./starterGrow').growCopy(picks);
    const title = dayNumber === 2
      ? 'Places and people near you 👀'
      : (places > 0 && places < GROWN_PLACES ? `Your map has ${places} place${places === 1 ? '' : 's'} — grow it` : 'More to explore near you 🗺️');
    const fallback = dayNumber === 2
      ? 'Follow a few people and every favorite on their map shows up on yours.'
      : `Your map has ${places} place${places === 1 ? '' : 's'}. A few more and it's worth exploring.`;
    // starter_follow opens My Network → Discover (every app version routes it)
    return { key: `starter_push_grow_${dayNumber}`, type: 'starter_follow', title, body: named || fallback };
  }
  return null;
}

async function progressFor(user, defaults) {
  const places = await db().collection(COLLECTIONS.PLACES).where('addedBy', '==', user.id).limit(6).get();
  const realPlaces = places.docs.map(d => d.data()).filter(p => !p.isSamplePlace && !p.deletedAt).length;
  const followingOthers = chosenFollowCount(user.following, defaults);
  return { realPlaces, followingOthers };
}

/** The hourly task: everyone 1–5 whole days old whose clock reads 6 PM. */
async function run({ now = new Date(), dryRun = false } = {}) {
  const since = new Date(now.getTime() - 6 * DAY).toISOString();
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
      if (dayNumber !== 1 && !GROW_DAYS.has(dayNumber)) continue;
      const sent = user.starterPushes || [];
      const progress = await progressFor(user, defaults);
      // Look up places and people only when a grow push is still due today
      const growDue = GROW_DAYS.has(dayNumber) && !sent.includes(`starter_push_grow_${dayNumber}`)
        && !(progress.realPlaces >= GROWN_PLACES && progress.followingOthers >= GROWN_FOLLOWING);
      const picks = growDue ? await require('./starterGrow').growPicks(user) : null;
      const push = starterPushFor(dayNumber, progress, picks);
      if (!push || sent.includes(push.key)) continue;
      results.previews.push({ userId: user.id, key: push.key, title: push.title, body: push.body });
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
