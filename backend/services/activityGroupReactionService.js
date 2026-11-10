// backend/services/activityGroupReactionService.js
// One heart for a whole group row (Wes, 2026-10-31: "let users heart or
// like group activities rather than just each individual activity"). The
// feed collapses a burst of one person's activities into one row; a reaction
// on that row lands on every activity in it, with ONE notification ("reacted
// 👍 to 5 of your activities") and at most one FavCoin nickel, instead of a
// push per activity.
const { getFirestore, FieldValue } = require('../config/firebase');
const { ServiceError } = require('../utils/serviceError');
const {
  COLLECTIONS, createActivityReaction, validateActivityReaction, createNotification, validateNotification
} = require('../models/FirestoreModels');

const MAX_GROUP = 50;

function cleanIds(activityIds) {
  if (!Array.isArray(activityIds)) return [];
  return [...new Set(activityIds.filter((id) => typeof id === 'string' && id.trim()).map((id) => id.trim()))];
}

/** The notification line for a group reaction: names the first activity
 *  ("…to your check-in at Ed's Tavern and 4 more"). */
function groupReactionBody(name, emoji, count, activity = null) {
  return require('./activity/describe').reactionBody(name, emoji, activity, count);
}

/**
 * Adds (or switches to) `emoji` on every activity, or removes the caller's
 * reaction from every activity when `remove` is true. All activities must
 * belong to one person (a feed group is one person's burst).
 * Returns { results: [{ activityId, emoji|null }], newCount, actorId, piggyBank }.
 */
async function reactToGroup({ userId, activityIds, emoji, remove = false }, deps = {}) {
  const db = deps.db || getFirestore();
  const ids = cleanIds(activityIds);
  if (ids.length === 0) throw new ServiceError(400, 'missing_activities', 'Pick at least one activity.');
  if (ids.length > MAX_GROUP) throw new ServiceError(400, 'too_many_activities', `At most ${MAX_GROUP} activities at once.`);

  const activityDocs = await db.getAll(...ids.map((id) => db.collection(COLLECTIONS.ACTIVITIES).doc(id)));
  const live = activityDocs.filter((d) => d.exists);
  if (live.length === 0) throw new ServiceError(404, 'activity_not_found', 'Activity not found');
  const actorIds = new Set(live.map((d) => d.data().actorId));
  if (actorIds.size > 1) throw new ServiceError(400, 'mixed_group', 'A group belongs to one person.');
  const actorId = [...actorIds][0];

  const reactionRefs = live.map((d) => db.collection(COLLECTIONS.ACTIVITY_REACTIONS).doc(`${d.id}_${userId}`));
  const existing = await db.getAll(...reactionRefs);
  const now = new Date().toISOString();
  const batch = db.batch();
  const results = [];
  const newlyReacted = [];
  const activityById = new Map(live.map((d) => [d.id, d.data()]));

  if (remove) {
    live.forEach((doc, i) => {
      if (existing[i].exists) {
        batch.delete(reactionRefs[i]);
        batch.update(doc.ref, { reactionCount: FieldValue.increment(-1), updatedAt: now });
      }
      results.push({ activityId: doc.id, emoji: null });
    });
    await batch.commit();
    return { results, newCount: 0, actorId, piggyBank: null };
  }

  const userDoc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
  if (!userDoc.exists) throw new ServiceError(404, 'user_not_found', 'User not found');
  const user = userDoc.data();
  const userName = user.displayName || user.firstName || 'User';

  for (let i = 0; i < live.length; i += 1) {
    const doc = live[i];
    const reactionData = { activityId: doc.id, userId, emoji, userName, userPhoto: user.profilePicture || null };
    const errors = validateActivityReaction(reactionData);
    if (errors.length) throw new ServiceError(400, 'invalid_reaction', errors[0]);
    if (existing[i].exists) {
      batch.update(reactionRefs[i], { emoji, updatedAt: now });
    } else {
      batch.set(reactionRefs[i], createActivityReaction(reactionData));
      batch.update(doc.ref, { reactionCount: FieldValue.increment(1), updatedAt: now });
      newlyReacted.push(doc.id);
    }
    results.push({ activityId: doc.id, emoji });
  }
  await batch.commit();

  let piggyBank = null;
  if (newlyReacted.length && actorId !== userId) {
    require('./funnelService').stampFunnelMilestone(userId, 'firstReactionAt');
    // One nickel for the group, tied to one of the reactions (removing it
    // inside the window reverses the earn, as for a single reaction)
    piggyBank = await require('./piggyBankService').credit({
      userId, eventType: 'activity_reaction', sourceRef: { activityId: newlyReacted[0] }
    });
    await notifyOnce(db, { actorId, userId, user, userName, emoji, activityIds: newlyReacted,
      firstActivity: activityById.get(newlyReacted[0]) }, deps);
  }
  return { results, newCount: newlyReacted.length, actorId, piggyBank };
}

async function notifyOnce(db, { actorId, userId, user, userName, emoji, activityIds, firstActivity }, deps) {
  const sse = deps.sseService || require('./sseService');
  const push = deps.notificationService || require('./notificationService');
  const body = groupReactionBody(userName, emoji, activityIds.length, firstActivity);
  // The tap opens what the first activity was about
  const { target } = require('./activity/describe').describeActivity(firstActivity);
  const notificationData = createNotification({
    userId: actorId,
    type: 'activity_reaction',
    title: 'New Reaction',
    body,
    data: {
      activityId: activityIds[0],
      ...target,
      activityIds,
      fromUserId: userId,
      fromUserName: userName,
      fromUserPhoto: user.profilePicture || null,
      emoji
    }
  });
  if (validateNotification(notificationData).length === 0) {
    const ref = await db.collection(COLLECTIONS.NOTIFICATIONS).add(notificationData);
    sse.notifyUser(actorId, 'new_notification', {
      notificationId: ref.id, type: 'activity_reaction', title: notificationData.title, body, data: notificationData.data
    });
  }
  await push.sendToUser(actorId, {
    type: 'activity_reaction',
    title: 'New Reaction',
    body,
    data: { activityId: activityIds[0], ...target, userId, emoji }
  });
}

module.exports = { reactToGroup, groupReactionBody, MAX_GROUP };
