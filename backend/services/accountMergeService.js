// Folds one user account into another. Two accounts of the same human
// (email signup then Apple sign-in, or an Apple id whose old data was
// orphaned and re-attached) become one, with every reference pointing at
// the survivor and nothing deleted outright.
//
// Rules, learned the hard way:
// - The OLDER account survives, whichever way the caller passed the ids. The
//   caller is usually signed into the new empty one, and letting it win
//   renamed a two-year account "Apple User" behind a relay email.
// - References are rewritten, never dropped: circles, places, comments,
//   check-ins, moments, activities, messages, notifications, connections,
//   shares, likes, the follow graph, Inner Circle lists.
// - The new account's untouched (empty) default circles are not carried over,
//   and a welcome connection request that duplicates one the survivor already
//   has is folded, not doubled.
// - Entitlements the survivor lacks (an Apple subscription attached to the
//   new account by receipt verification) carry over.
// - dryRun returns the plan without writing; re-running a partial merge
//   resumes cleanly because every query only matches docs still pointing at
//   the merged id.
const { getFirestore } = require('../config/firebase');
const { COLLECTIONS, serializeDoc } = require('../models/FirestoreModels');
const { ServiceError } = require('../utils/serviceError');
const { newId } = require('../utils/ids');

const db = getFirestore();

const ENTITLEMENT_FIELDS = [
  'subscriptionStatus', 'subscriptionTier', 'subscriptionExpiryDate', 'subscriptionEnvironment',
  'appleOriginalTransactionId', 'trialStartDate', 'trialEndDate', 'lastReceiptVerification'
];

const dedupe = (ids) => [...new Set(ids)];

/** The account that survives: older createdAt, else the one passed first. */
function chooseSurvivor(a, b) {
  const ta = Date.parse(a.createdAt || '') || Infinity;
  const tb = Date.parse(b.createdAt || '') || Infinity;
  return tb < ta ? { primary: b, secondary: a, swapped: true } : { primary: a, secondary: b, swapped: false };
}

function mergedUserFields(primary, secondary, now) {
  const fields = {
    alternateEmails: dedupe([
      ...(primary.alternateEmails || []),
      ...(secondary.alternateEmails || []),
      ...(secondary.email ? [secondary.email] : [])
    ]).filter((email) => email && email !== primary.email),
    linkedProviders: { ...(primary.linkedProviders || {}), ...(secondary.linkedProviders || {}) },
    displayName: primary.displayName || secondary.displayName,
    profilePicture: primary.profilePicture || secondary.profilePicture,
    firstName: primary.firstName || secondary.firstName,
    lastName: primary.lastName || secondary.lastName,
    phoneNumber: primary.phoneNumber || secondary.phoneNumber,
    bio: primary.bio || secondary.bio,
    location: primary.location || secondary.location,
    // Neither account should follow itself after the fold
    followers: dedupe([...(primary.followers || []), ...(secondary.followers || [])])
      .filter((id) => id !== primary.id && id !== secondary.id),
    following: dedupe([...(primary.following || []), ...(secondary.following || [])])
      .filter((id) => id !== primary.id && id !== secondary.id),
    deviceTokens: dedupe([...(primary.deviceTokens || []), ...(secondary.deviceTokens || [])]),
    pinnedPlaces: dedupe([...(primary.pinnedPlaces || []), ...(secondary.pinnedPlaces || [])]).slice(0, 6),
    notificationPreferences: primary.notificationPreferences || secondary.notificationPreferences,
    updatedAt: now
  };
  fields.followersCount = fields.followers.length;
  fields.followingCount = fields.following.length;
  for (const key of ENTITLEMENT_FIELDS) {
    if (primary[key] == null && secondary[key] != null) fields[key] = secondary[key];
  }
  return fields;
}

/**
 * @param {object} args
 * @param {string} args.primaryId   the account the caller wants to keep (advisory)
 * @param {string} args.secondaryId the account to fold in
 * @param {boolean} [args.dryRun]   plan only
 * @returns {Promise<{primaryId, secondaryId, swapped, counts, mergedData, primaryUser}>}
 */
async function mergeAccounts({ primaryId, secondaryId, dryRun = false, mergedBy = null, via = 'unknown' }) {
  if (!primaryId || !secondaryId) throw new ServiceError(400, 'missing_ids', 'Both account ids are required');
  if (primaryId === secondaryId) throw new ServiceError(400, 'same_account', 'Cannot merge an account with itself');

  const [docA, docB] = await Promise.all([
    db.collection(COLLECTIONS.USERS).doc(primaryId).get(),
    db.collection(COLLECTIONS.USERS).doc(secondaryId).get()
  ]);
  if (!docA.exists || !docB.exists) throw new ServiceError(404, 'not_found', 'One or both accounts not found');
  const a = serializeDoc(docA);
  const b = serializeDoc(docB);
  if (a.mergedInto || b.mergedInto) throw new ServiceError(409, 'already_merged', 'One of these accounts was already merged');

  const { primary, secondary, swapped } = chooseSurvivor(a, b);
  const P = primary.id;
  const S = secondary.id;
  const now = new Date().toISOString();

  const ops = [];            // { ref, update } applied at the end
  const counts = {};
  const remap = async (name, query, buildUpdate) => {
    const snap = await query.get();
    for (const doc of snap.docs) ops.push({ ref: doc.ref, update: buildUpdate(doc) });
    counts[name] = (counts[name] || 0) + snap.size;
  };
  const remapArray = async (name, query, field, extra = null, skipIds = []) => {
    const snap = await query.get();
    for (const doc of snap.docs) {
      // The two user docs are written last from mergedUserFields, never here
      if (skipIds.includes(doc.id)) continue;
      const current = field.split('.').reduce((obj, key) => (obj || {})[key], doc.data()) || [];
      const remapped = dedupe(current.map((id) => (id === S ? P : id)));
      ops.push({ ref: doc.ref, update: { [field]: remapped, ...(extra ? extra(remapped) : {}) } });
    }
    counts[name] = (counts[name] || 0) + snap.size;
  };

  // Circles: the new account's untouched defaults (flagged default, not one
  // live place) carry nothing and are folded away; every other circle moves.
  const secondaryCircles = await db.collection(COLLECTIONS.CIRCLES).where('owner', '==', S).get();
  const secondaryPlaces = await db.collection(COLLECTIONS.PLACES).where('addedBy', '==', S).get();
  const livePlacesByCircle = new Map();
  for (const doc of secondaryPlaces.docs) {
    const p = doc.data();
    if (!p.deletedAt && p.circleId) livePlacesByCircle.set(p.circleId, (livePlacesByCircle.get(p.circleId) || 0) + 1);
  }
  counts.circlesMoved = 0;
  counts.defaultCirclesFolded = 0;
  for (const doc of secondaryCircles.docs) {
    const c = doc.data();
    const untouchedDefault = c.isDefaultCircle === true && !c.deletedAt && !livePlacesByCircle.get(doc.id);
    if (untouchedDefault) {
      ops.push({ ref: doc.ref, update: { deletedAt: now, deletedViaMerge: true, updatedAt: now } });
      counts.defaultCirclesFolded += 1;
    } else {
      ops.push({ ref: doc.ref, update: { owner: P, updatedAt: now } });
      counts.circlesMoved += 1;
    }
  }
  for (const doc of secondaryPlaces.docs) ops.push({ ref: doc.ref, update: { addedBy: P, updatedAt: now } });
  counts.places = secondaryPlaces.size;

  // Authorship
  await remap('comments', db.collection(COLLECTIONS.PLACE_COMMENTS).where('userId', '==', S), () => ({ userId: P }));
  await remap('checkIns', db.collection(COLLECTIONS.CHECK_INS).where('userId', '==', S), () => ({ userId: P }));
  await remap('moments', db.collection(COLLECTIONS.PLACE_VIDEOS).where('userId', '==', S), () => ({ userId: P }));
  await remap('activities', db.collection(COLLECTIONS.ACTIVITIES).where('actorId', '==', S), () => ({ actorId: P }));
  await remap('messages', db.collection('messages').where('senderId', '==', S), () => ({ senderId: P }));
  await remap('notifications', db.collection(COLLECTIONS.NOTIFICATIONS).where('userId', '==', S), () => ({ userId: P }));

  // Connections: a request that duplicates one the survivor already has
  // (Wes's welcome request goes to every new account) is folded, not doubled.
  const survivorConnections = await db.collection(COLLECTIONS.CONNECTIONS).where('userId', '==', P).get();
  const survivorConnectionsIn = await db.collection(COLLECTIONS.CONNECTIONS).where('connectedUserId', '==', P).get();
  const survivorPeers = new Set([
    ...survivorConnections.docs.map((d) => d.data().connectedUserId),
    ...survivorConnectionsIn.docs.map((d) => d.data().userId)
  ]);
  counts.connections = 0;
  counts.connectionsFolded = 0;
  for (const [field, other] of [['userId', 'connectedUserId'], ['connectedUserId', 'userId']]) {
    const snap = await db.collection(COLLECTIONS.CONNECTIONS).where(field, '==', S).get();
    for (const doc of snap.docs) {
      const peer = doc.data()[other];
      if (peer === P || survivorPeers.has(peer)) {
        // Tombstone, never a new status: the app decodes status strictly, and
        // an unknown value once emptied a whole connections list.
        ops.push({ ref: doc.ref, update: { deletedAt: now, deletedViaMerge: true } });
        counts.connectionsFolded += 1;
      } else {
        ops.push({ ref: doc.ref, update: { [field]: P } });
        counts.connections += 1;
      }
    }
  }

  // Array memberships: circle shares, venue likes/contributors, social graph, Inner Circle
  await remapArray('sharedCircles', db.collection(COLLECTIONS.CIRCLES).where('sharedWith', 'array-contains', S), 'sharedWith');
  await remapArray('venueLikes', db.collection('globalPlaces').where('likes', 'array-contains', S), 'likes',
    (likes) => ({ likesCount: likes.length }));
  await remapArray('venueContributions',
    db.collection('globalPlaces').where('userContributions.contributors', 'array-contains', S), 'userContributions.contributors');
  const both = [P, S];
  await remapArray('followerRefs', db.collection(COLLECTIONS.USERS).where('followers', 'array-contains', S), 'followers', null, both);
  await remapArray('followingRefs', db.collection(COLLECTIONS.USERS).where('following', 'array-contains', S), 'following', null, both);
  await remapArray('innerCircleRefs', db.collection(COLLECTIONS.USERS).where('innerCircle', 'array-contains', S), 'innerCircle', null, both);

  // Another user's followers array that named both ids collapses to the
  // survivor via dedupe above.
  const mergedData = mergedUserFields(primary, secondary, now);

  const plan = { primaryId: P, secondaryId: S, swapped, counts, mergedData, operations: ops.length };
  if (dryRun) return { ...plan, primaryUser: { ...primary, ...mergedData } };

  await applyOps(ops);

  // User docs last, so a crash mid-remap leaves the merge re-runnable rather
  // than half-marked
  const primaryRef = db.collection(COLLECTIONS.USERS).doc(P);
  const secondaryRef = db.collection(COLLECTIONS.USERS).doc(S);
  await db.runTransaction(async (tx) => {
    tx.update(primaryRef, mergedData);
    tx.update(secondaryRef, { mergedInto: P, mergedAt: now, active: false, updatedAt: now });
  });
  const primaryUser = serializeDoc(await primaryRef.get());
  // The audit record. Until this existed the only trace of a merge was
  // `mergedInto` on the ghost — no who, no where from, no what moved. A merge
  // rewrites another person's data; it has to be answerable for.
  const mergeId = newId();
  const auditRef = db.collection('accountMerges').doc(mergeId);
  await auditRef.set({
    primaryId: P, secondaryId: S, swapped, counts, operations: ops.length,
    mergedBy: mergedBy || null, via, mergedAt: now,
    primaryEmail: primary.email || null, secondaryEmail: secondary.email || null
  });
  console.log(`✅ Merged ${S} into ${P} (by ${mergedBy || 'unknown'} via ${via}, audit ${mergeId})`, counts);
  return { ...plan, primaryUser, mergeId };
}

/** Batched writes (450/commit, under Firestore's 500 limit). */
async function applyOps(ops) {
  if (typeof db.batch !== 'function') {
    for (const op of ops) await op.ref.update(op.update);
    return;
  }
  for (let i = 0; i < ops.length; i += 450) {
    const batch = db.batch();
    for (const op of ops.slice(i, i + 450)) batch.update(op.ref, op.update);
    await batch.commit();
  }
}

module.exports = { mergeAccounts, chooseSurvivor, mergedUserFields };
