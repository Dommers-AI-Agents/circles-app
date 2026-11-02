// services/followRequestService.js
//
// Following a PRIVATE profile takes the owner's yes (Wes, 2026-11-02), like
// Instagram. A public profile is still one tap. A connection already sees
// everything a follower does, so connected people never need to ask.
//
// One doc per asker and owner in `followRequests` (id `<requester>__<target>`):
// { requesterId, targetId, createdAt }. Accepting writes the follow itself
// (both arrays and counts, as POST /users/:id/follow does) and deletes the
// doc; declining or cancelling just deletes it. Turning the profile public
// accepts everything still waiting.

const { getFirestore } = require('../config/firebase');
const { FieldValue } = require('firebase-admin/firestore');
const { COLLECTIONS } = require('../models/FirestoreModels');
const { normalizeUserId } = require('./idService');
const { ServiceError } = require('../utils/serviceError');

const db = () => getFirestore();
const col = () => db().collection(COLLECTIONS.FOLLOW_REQUESTS);
const docId = (requesterId, targetId) => `${normalizeUserId(requesterId)}__${normalizeUserId(targetId)}`;

/** Ask to follow. Idempotent: asking twice leaves one request. */
async function request(requesterId, targetId, requesterName) {
  const ref = col().doc(docId(requesterId, targetId));
  const existing = await ref.get();
  if (existing.exists) return { requested: true, alreadyRequested: true };
  await ref.set({
    requesterId: normalizeUserId(requesterId),
    targetId: normalizeUserId(targetId),
    createdAt: new Date().toISOString()
  });
  require('./notifyQuiet').sendInBackground(targetId, {
    type: 'follow_request',
    title: 'Follow request',
    body: `${requesterName || 'Someone'} asked to follow you`,
    data: { type: 'follow_request', fromUserId: normalizeUserId(requesterId), fromUserName: requesterName || '' }
  });
  return { requested: true, alreadyRequested: false };
}

/** Is `requesterId` waiting on `targetId`? */
async function isPending(requesterId, targetId) {
  if (!requesterId || !targetId) return false;
  return (await col().doc(docId(requesterId, targetId)).get()).exists;
}

/** The asker takes it back. */
async function cancel(requesterId, targetId) {
  await col().doc(docId(requesterId, targetId)).delete();
}

/** Requests waiting on `targetId`, newest first, with each asker's public card. */
async function listIncoming(targetId) {
  const snap = await col().where('targetId', '==', normalizeUserId(targetId)).get();
  const rows = snap.docs.map((d) => d.data()).sort((a, b) => String(b.createdAt).localeCompare(String(a.createdAt)));
  if (!rows.length) return [];
  const refs = rows.map((r) => db().collection(COLLECTIONS.USERS).doc(r.requesterId));
  const docs = await db().getAll(...refs);
  const { projectPublicUser } = require('./publicUserProjection');
  return rows.map((r, i) => docs[i].exists
    ? { requesterId: r.requesterId, createdAt: r.createdAt, user: projectPublicUser({ _id: docs[i].id, ...docs[i].data() }, [], { viewerId: targetId }) }
    : null).filter(Boolean);
}

/**
 * The owner says yes: the asker now follows them. Returns false when there
 * was nothing to accept (already answered or cancelled).
 */
async function accept(targetId, requesterId, { notify = true } = {}) {
  const target = normalizeUserId(targetId);
  const requester = normalizeUserId(requesterId);
  const ref = col().doc(docId(requester, target));
  const usersCol = db().collection(COLLECTIONS.USERS);
  const accepted = await db().runTransaction(async (tx) => {
    const [reqDoc, requesterDoc, targetDoc] = await Promise.all([
      tx.get(ref), tx.get(usersCol.doc(requester)), tx.get(usersCol.doc(target))
    ]);
    if (!reqDoc.exists) return false;
    tx.delete(ref);
    if (!requesterDoc.exists || !targetDoc.exists) return false;
    if ((requesterDoc.data().following || []).includes(target)) return false;
    const now = new Date().toISOString();
    tx.update(requesterDoc.ref, { following: FieldValue.arrayUnion(target), followingCount: FieldValue.increment(1), updatedAt: now });
    tx.update(targetDoc.ref, { followers: FieldValue.arrayUnion(requester), followersCount: FieldValue.increment(1), updatedAt: now });
    return { targetName: targetDoc.data().displayName || 'They' };
  });
  if (!accepted) return false;

  // Same first-follow dime as a one-tap follow (deduped per pair)
  await require('./piggyBankService').credit({
    userId: requester, eventType: 'user_followed', sourceRef: { followedUserId: target }
  });
  if (notify) {
    require('./notifyQuiet').sendInBackground(requester, {
      type: 'follow_request_accepted',
      title: 'Follow request accepted',
      body: `${accepted.targetName} accepted your follow request`,
      data: { type: 'follow_request_accepted', fromUserId: target, fromUserName: accepted.targetName }
    });
  }
  const sse = require('./sseService');
  sse.notifyUser(requester, 'following_added', { targetUserId: target });
  sse.notifyUser(target, 'follower_added', { followerId: requester });
  return true;
}

/** The owner says no. Nobody is told. */
async function decline(targetId, requesterId) {
  const ref = col().doc(docId(requesterId, targetId));
  if (!(await ref.get()).exists) throw new ServiceError(404, 'not_found', 'That request is no longer waiting.');
  await ref.delete();
}

/** Turning a profile public lets everyone waiting in (each is told). */
async function acceptAll(targetId) {
  const snap = await col().where('targetId', '==', normalizeUserId(targetId)).get();
  let count = 0;
  for (const d of snap.docs) {
    if (await accept(targetId, d.data().requesterId, { notify: true })) count += 1;
  }
  return count;
}

/** Remove every request between two people, either direction (blocking). */
async function clearBetween(a, b) {
  await Promise.all([col().doc(docId(a, b)).delete(), col().doc(docId(b, a)).delete()]);
}

/** Remove every request to or from someone (account deletion). */
async function clearAllFor(userId) {
  const id = normalizeUserId(userId);
  const [asTarget, asRequester] = await Promise.all([
    col().where('targetId', '==', id).get(),
    col().where('requesterId', '==', id).get()
  ]);
  const docs = [...asTarget.docs, ...asRequester.docs];
  for (let i = 0; i < docs.length; i += 400) {
    const batch = db().batch();
    docs.slice(i, i + 400).forEach((d) => batch.delete(d.ref));
    await batch.commit();
  }
}

module.exports = { request, isPending, cancel, listIncoming, accept, decline, acceptAll, clearBetween, clearAllFor };
