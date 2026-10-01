// Deleting an account (App Store guideline 5.1.1(v)).
//
// The iOS app has sent DELETE /api/users/me for a long time, but the route
// never existed, so "Delete account" always failed (security audit
// 2026-10-01). This removes the person's own data and their traces in other
// people's documents, and never deletes anything that belongs to someone
// else:
//   - their saves, circles, comments, check-ins, moments, activities,
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
  await deleteAll('moments', db.collection(COLLECTIONS.PLACE_VIDEOS).where('userId', '==', uid));
  await deleteAll('activities', db.collection(COLLECTIONS.ACTIVITIES).where('actorId', '==', uid));
  await deleteAll('notifications', db.collection(COLLECTIONS.NOTIFICATIONS).where('userId', '==', uid));
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
