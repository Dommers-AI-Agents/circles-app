// Deleting an account (App Store guideline 5.1.1(v)).
//
// The iOS app has sent DELETE /api/users/me for a long time, but the route
// never existed, so "Delete account" always failed (security audit
// 2026-10-01). This removes the person's own data and their traces in other
// people's documents, and never deletes anything that belongs to someone
// else:
//   - their saves, circles, comments, check-ins, moments, activities,
//     reward points and FavCoin entries, suggestions sent or received,
//     notifications, connections, blocks, passkeys, widget documents;
//   - their messages (the conversations stay for the other people);
//   - their likes, follows, Inner Circle entries and circle shares in other
//     people's documents;
//   - care check-ins they run or answer end; family seats they hold go;
//   - their photos on shared venue records, their video files, their
//     profile picture;
//   - the user document and their Firebase Auth record(s).
// Money records (postcard / Fridge Mail orders) are kept: they are
// transaction records we must retain, and hold no profile beyond the id.
const { getFirestore, getAuth, getStorage, admin } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');
const { PIGGY_COLLECTIONS } = require('../models/PiggyBankModels');
const { deleteImage } = require('./storage');

const BATCH = 400;

function makeDeleter(db) {
  const counts = {};
  const bump = (key, n) => { counts[key] = (counts[key] || 0) + n; };

  /** Deletes every doc a query returns, in batches. */
  async function deleteAll(key, query) {
    for (;;) {
      const snap = await query.limit(BATCH).get();
      if (snap.empty) return;
      const batch = db.batch();
      snap.docs.forEach((d) => batch.delete(d.ref));
      await batch.commit();
      bump(key, snap.size);
      if (snap.size < BATCH) return;
    }
  }

  /** Applies `patchFor(doc)` (an update object, or null to skip) to every doc a query returns. */
  async function updateAll(key, query, patchFor) {
    const snap = await query.get();
    for (let i = 0; i < snap.docs.length; i += BATCH) {
      const batch = db.batch();
      let n = 0;
      for (const d of snap.docs.slice(i, i + BATCH)) {
        const patch = patchFor(d);
        if (patch) { batch.update(d.ref, patch); n++; }
      }
      if (n) { await batch.commit(); bump(key, n); }
    }
  }

  return { counts, deleteAll, updateAll };
}

/**
 * Deletes account `uid`. Returns per-area counts. Safe to re-run: every
 * step is "delete/remove what still matches".
 */
async function deleteAccount(uid, { db = getFirestore(), auth = getAuth(), storage = getStorage() } = {}) {
  const userRef = db.collection(COLLECTIONS.USERS).doc(uid);
  const userSnap = await userRef.get();
  if (!userSnap.exists) return { deleted: false, counts: {} };
  const user = userSnap.data();
  const { counts, deleteAll, updateAll } = makeDeleter(db);
  const FieldValue = admin.firestore.FieldValue;
  const now = new Date().toISOString();

  // 0. Lock the account first: every session stops working right away
  // (protect rejects `banned`), even if a later step fails and is retried.
  await userRef.update({ banned: true, deletionStartedAt: now });

  // 1. Their own content
  await deleteAll('saves', db.collection(COLLECTIONS.PLACES).where('addedBy', '==', uid));
  await deleteAll('circles', db.collection(COLLECTIONS.CIRCLES).where('owner', '==', uid));
  await deleteAll('comments', db.collection(COLLECTIONS.PLACE_COMMENTS).where('userId', '==', uid));
  await deleteAll('checkIns', db.collection(COLLECTIONS.CHECK_INS).where('userId', '==', uid));
  // Rewards and FavCoins, suggestions they sent or received, sign-in
  // challenges (a deleted test account left these behind, 2026-10-29)
  await deleteAll('rewardEvents', db.collection(COLLECTIONS.REWARD_EVENTS).where('userId', '==', uid));
  await deleteAll('coinLedger', db.collection(PIGGY_COLLECTIONS.LEDGER).where('userId', '==', uid));
  await deleteAll('suggestions', db.collection(COLLECTIONS.SUGGESTIONS).where('userId', '==', uid));
  await deleteAll('suggestions', db.collection(COLLECTIONS.SUGGESTIONS).where('recipientId', '==', uid));
  await deleteAll('signInChallenges', db.collection('webauthnChallenges').where('uid', '==', uid));
  await deleteAll('moments', db.collection(COLLECTIONS.PLACE_VIDEOS).where('userId', '==', uid));
  await deleteAll('activities', db.collection(COLLECTIONS.ACTIVITIES).where('actorId', '==', uid));
  await deleteAll('notifications', db.collection(COLLECTIONS.NOTIFICATIONS).where('userId', '==', uid));
  // …and the ones they caused in other people's bells ("X started following
  // you", requests, likes): a deleted person mustn't keep showing up there
  await deleteAll('notificationsFrom', db.collection(COLLECTIONS.NOTIFICATIONS).where('data.fromUserId', '==', uid));
  await deleteAll('notificationsFrom', db.collection(COLLECTIONS.NOTIFICATIONS).where('data.followerId', '==', uid));
  await deleteAll('connections', db.collection(COLLECTIONS.CONNECTIONS).where('userId', '==', uid));
  await deleteAll('connections', db.collection(COLLECTIONS.CONNECTIONS).where('connectedUserId', '==', uid));
  await deleteAll('blocks', db.collection(COLLECTIONS.BLOCKS).where('blockerId', '==', uid));
  await deleteAll('blocks', db.collection(COLLECTIONS.BLOCKS).where('blockedUserId', '==', uid));
  await deleteAll('passkeys', db.collection(COLLECTIONS.WEBAUTHN_CREDENTIALS).where('userId', '==', uid));
  await deleteAll('messages', db.collection('messages').where('senderId', '==', uid));
  await deleteAll('checkInStats', userRef.collection(COLLECTIONS.CHECK_IN_STATS));
  // Widget documents are keyed `${uid}_${widgetId}`
  const docId = admin.firestore.FieldPath.documentId();
  await deleteAll('widgetDocs', db.collection(COLLECTIONS.WIDGET_DATA).where(docId, '>=', `${uid}_`).where(docId, '<', `${uid}_`));

  // 2. Their traces in other people's documents
  await updateAll('conversations', db.collection('conversations').where('participants', 'array-contains', uid),
    () => ({ participants: FieldValue.arrayRemove(uid), updatedAt: now }));
  await updateAll('sharedCircles', db.collection(COLLECTIONS.CIRCLES).where('sharedWith', 'array-contains', uid),
    () => ({ sharedWith: FieldValue.arrayRemove(uid) }));
  await updateAll('venueLikes', db.collection('globalPlaces').where('likes', 'array-contains', uid),
    () => ({ likes: FieldValue.arrayRemove(uid), likesCount: FieldValue.increment(-1) }));
  for (const field of ['followers', 'following', 'innerCircle', 'blockedUsers', 'blockedBy']) {
    await updateAll(`${field}Refs`, db.collection(COLLECTIONS.USERS).where(field, 'array-contains', uid),
      (d) => (d.id === uid ? null : {
        [field]: FieldValue.arrayRemove(uid),
        ...(field === 'followers' ? { followersCount: FieldValue.increment(-1) } : {}),
        ...(field === 'following' ? { followingCount: FieldValue.increment(-1) } : {})
      }));
  }

  // 3. Care check-ins: plans they run or answer end; seats they hold go
  const plans = db.collection(COLLECTIONS.CARE_PLANS);
  for (const field of ['ownerId', 'parentId']) {
    await updateAll('carePlansEnded', plans.where(field, '==', uid), () => ({ status: 'ended', endedAt: now, endedReason: 'account_deleted' }));
  }
  for (const field of ['watcherIds', 'pendingWatcherIds']) {
    await updateAll('careSeats', plans.where(field, 'array-contains', uid), (d) => ({
      watchers: (d.data().watchers || []).filter((w) => w.userId !== uid),
      watcherIds: FieldValue.arrayRemove(uid),
      pendingWatcherIds: FieldValue.arrayRemove(uid)
    }));
  }

  // 3b. Events (Party Bus): events they coordinate end; they leave the rest;
  // their event photos and tags go (photo files are deleted in step 4's way)
  const events = db.collection(COLLECTIONS.EVENTS);
  await updateAll('eventsEnded', events.where('hostId', '==', uid), () => ({ deletedAt: now, joinOpen: false }));
  await updateAll('eventSeats', events.where('memberIds', 'array-contains', uid), (d) => {
    // The whole map rewritten without them (a dotted field path would break
    // on legacy ids that contain dots)
    const members = { ...(d.data().members || {}) };
    delete members[uid];
    return { memberIds: FieldValue.arrayRemove(uid), pendingInviteIds: FieldValue.arrayRemove(uid), members };
  });
  await updateAll('eventInvites', events.where('pendingInviteIds', 'array-contains', uid), () => ({
    pendingInviteIds: FieldValue.arrayRemove(uid)
  }));
  // 3c. Clubs: clubs they own end; they leave the rest (organizer seats and
  // the member map rewritten without them); their posts and replies go
  const clubs = db.collection(COLLECTIONS.CLUBS);
  await updateAll('clubsEnded', clubs.where('ownerId', '==', uid), () => ({ deletedAt: now, joinOpen: false }));
  await updateAll('clubSeats', clubs.where('memberIds', 'array-contains', uid), (d) => {
    const members = { ...(d.data().members || {}) };
    delete members[uid];
    return { memberIds: FieldValue.arrayRemove(uid), organizerIds: FieldValue.arrayRemove(uid), members };
  });
  await deleteAll('clubPosts', db.collection(COLLECTIONS.CLUB_POSTS).where('authorId', '==', uid));
  await deleteAll('clubReplies', db.collection(COLLECTIONS.CLUB_REPLIES).where('authorId', '==', uid));
  await deleteAll('eventPhotos', db.collection(COLLECTIONS.EVENT_PHOTOS).where('uploaderId', '==', uid));
  await deleteAll('eventPlaces', db.collection(COLLECTIONS.EVENT_PLACES).where('taggedById', '==', uid));

  // 3d. Can I Pet Dat Dog: their dog cards, Dog Park posts (with the pets and
  // comments on them) and daily sends go; their pets and comments on other
  // people's posts go too, taking the counts down with them
  await deleteAll('dogProfiles', db.collection(COLLECTIONS.DOG_PROFILES).where('ownerId', '==', uid));
  // A pet or comment on someone else's post takes that post's count down
  // (on their own posts the post itself goes below)
  const dogTraces = [
    { key: 'dogPets', col: COLLECTIONS.DOG_PETS, by: 'userId', postOwner: 'authorId', count: 'petCount' },
    { key: 'dogComments', col: COLLECTIONS.DOG_COMMENTS, by: 'authorId', postOwner: 'postAuthorId', count: 'commentCount' }
  ];
  for (const t of dogTraces) {
    const mine = await db.collection(t.col).where(t.by, '==', uid).get();
    for (const d of mine.docs) {
      if (d.data()[t.postOwner] !== uid && d.data().postId) {
        await db.collection(COLLECTIONS.DOG_POSTS).doc(String(d.data().postId))
          .update({ [t.count]: FieldValue.increment(-1) }).catch(() => {});
      }
      await d.ref.delete();
      counts[t.key] = (counts[t.key] || 0) + 1;
    }
  }
  await deleteAll('dogPetsOnTheirPosts', db.collection(COLLECTIONS.DOG_PETS).where('authorId', '==', uid));
  await deleteAll('dogCommentsOnTheirPosts', db.collection(COLLECTIONS.DOG_COMMENTS).where('postAuthorId', '==', uid));
  await deleteAll('dogPosts', db.collection(COLLECTIONS.DOG_POSTS).where('authorId', '==', uid));
  await deleteAll('dogDailySends', db.collection(COLLECTIONS.DOG_DAILY_SENDS).where('userId', '==', uid));

  // 4. Files: their photos on shared venue records, video files, profile picture
  const contributed = await db.collection('globalPlaces').where('userContributions.contributors', 'array-contains', uid).get();
  for (const venue of contributed.docs) {
    const photos = venue.data().photos || [];
    const mine = photos.filter((p) => p && p.uploadedBy === uid);
    await venue.ref.update({
      ...(mine.length ? { photos: photos.filter((p) => !(p && p.uploadedBy === uid)) } : {}),
      'userContributions.contributors': FieldValue.arrayRemove(uid)
    });
    for (const p of mine) await deleteImage(p.url);
    if (mine.length) counts.venuePhotos = (counts.venuePhotos || 0) + mine.length;
  }
  try {
    const bucketName = process.env.FIREBASE_STORAGE_BUCKET || `${process.env.FIREBASE_PROJECT_ID}.appspot.com`;
    await storage.bucket(bucketName).deleteFiles({ prefix: `videos/${uid}/` });
    await storage.bucket(bucketName).deleteFiles({ prefix: `dogs/${uid}/` });
  } catch (e) {
    console.warn(`[account-delete] video files for ${uid}: ${e.message}`);
  }
  if (user.profilePicture) await deleteImage(user.profilePicture);

  // 5. Sign-in records, then the user document itself
  const authIds = new Set([uid, ...Object.values(user.linkedProviders || {})].filter((id) => typeof id === 'string'));
  for (const id of authIds) {
    try { await auth.deleteUser(id); counts.authRecords = (counts.authRecords || 0) + 1; } catch (_) { /* not a Firebase Auth id */ }
  }
  await userRef.delete();
  await db.collection('accountDeletions').doc(uid).set({ deletedAt: now, counts });
  return { deleted: true, counts };
}

module.exports = { deleteAccount };
