// backend/services/connectionRequestPolicy.js
//
// What a connection request is allowed to do beyond "ask". Security audit
// 2026-10-01 found two abuses of POST /api/connections/invite:
//
// 1. The client could send `autoAccept: true` and become an ACCEPTED
//    connection of anyone, bypassing every "connections only" gate (network
//    circles, messaging, check-in recipients). The flag existed for invite
//    links, but those links carry nothing but the inviter's public uid, so the
//    server could not tell "opened Wes's link" from "typed Wes's uid".
//    A request is now accepted on the spot only when the TARGET demonstrably
//    invited the requester:
//      - the target already sent the requester a pending request (handled in
//        the controller by accepting that request), or
//      - the target emailed an app invite to the requester's address
//        (recorded here by the contact-invite endpoint), or
//      - the request carries an invite token the server signed for the
//        target (GET /api/connections/invite-token; for share links/QR).
//    Anything else becomes an ordinary pending request.
//
// 2. Request → decline → request again mailed and pushed the target every
//    time. Notifications for the same requester→target pair are now spaced at
//    least NOTIFY_COOLDOWN_MS apart; the request itself is still created so
//    the target can accept it from their Network tab.

const crypto = require('crypto');
const { getFirestore } = require('../config/firebase');
const { normalizeUserId } = require('./idService');
const { normalizeEmail } = require('../utils/emailAddress');

const INVITES = 'connectionInvites';
const REQUEST_LOG = 'connectionRequestLog';

const NOTIFY_COOLDOWN_MS = 24 * 60 * 60 * 1000;
// An emailed invite stays good for a generous install-and-sign-up window.
const EMAIL_INVITE_TTL_MS = 180 * 24 * 60 * 60 * 1000;

// ── Signed invite tokens ────────────────────────────────────────────────────
// HMAC of the inviter's uid under a key that never leaves the server. A
// dedicated INVITE_TOKEN_SECRET can be set (rotating it revokes every
// outstanding link); otherwise the key is derived from JWT_SECRET with a
// purpose string, so it can't be confused with any other HMAC we compute.
function inviteKey() {
  if (process.env.INVITE_TOKEN_SECRET) return process.env.INVITE_TOKEN_SECRET;
  const base = process.env.JWT_SECRET;
  if (!base) return null;
  return crypto.createHash('sha256').update(`${base}|favcircles-connect-invite-v1`).digest();
}

function signInviteToken(inviterId) {
  const key = inviteKey();
  const uid = normalizeUserId(inviterId);
  if (!key || !uid) return null;
  return crypto.createHmac('sha256', key).update(`connect-invite:v1:${uid}`).digest('base64url').slice(0, 32);
}

function verifyInviteToken(token, inviterId) {
  if (typeof token !== 'string' || token.length !== 32) return false;
  const expected = signInviteToken(inviterId);
  if (!expected) return false;
  return crypto.timingSafeEqual(Buffer.from(token), Buffer.from(expected));
}

// ── Emailed app invites ─────────────────────────────────────────────────────
// Keyed by inviter + a hash of the address, so the doc id answers "did X
// invite this email?" in one read and no plaintext address is stored.
const emailHash = (email) => crypto.createHash('sha256').update(normalizeEmail(email)).digest('hex').slice(0, 32);
const inviteDocId = (inviterId, email) => `${normalizeUserId(inviterId)}_${emailHash(email)}`;

async function recordEmailInvite(inviterId, email, now = new Date()) {
  if (!inviterId || !normalizeEmail(email)) return;
  await getFirestore().collection(INVITES).doc(inviteDocId(inviterId, email)).set({
    inviterId: normalizeUserId(inviterId),
    emailHash: emailHash(email),
    createdAt: now.toISOString()
  });
}

async function hasEmailInvite(inviterId, email, now = new Date()) {
  if (!inviterId || !normalizeEmail(email)) return false;
  const snap = await getFirestore().collection(INVITES).doc(inviteDocId(inviterId, email)).get();
  if (!snap.exists) return false;
  const at = Date.parse(snap.data().createdAt);
  return Number.isFinite(at) && now.getTime() - at <= EMAIL_INVITE_TTL_MS;
}

/** True when the target invited the requester (token or emailed invite). */
async function targetInvitedRequester({ targetId, requesterEmail, inviteToken }) {
  if (verifyInviteToken(inviteToken, targetId)) return true;
  try {
    return await hasEmailInvite(targetId, requesterEmail);
  } catch (error) {
    console.error('⚠️ Email-invite lookup failed:', error.message);
    return false;
  }
}

// ── Notification cooldown ───────────────────────────────────────────────────
/**
 * Claims the right to notify `targetId` about a request from `requesterId`.
 * Returns false when the pair was notified within the cooldown; otherwise
 * stamps the log and returns true. Fails open (a Firestore blip must not
 * silence a genuine first request).
 */
async function claimRequestNotification(requesterId, targetId, now = new Date()) {
  const db = getFirestore();
  const ref = db.collection(REQUEST_LOG).doc(`${normalizeUserId(requesterId)}_${normalizeUserId(targetId)}`);
  try {
    return await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const last = snap.exists ? Date.parse(snap.data().lastRequestNotifiedAt) : NaN;
      if (Number.isFinite(last) && now.getTime() - last < NOTIFY_COOLDOWN_MS) return false;
      tx.set(ref, {
        requesterId: normalizeUserId(requesterId),
        targetId: normalizeUserId(targetId),
        lastRequestNotifiedAt: now.toISOString(),
        notifyCount: ((snap.exists && snap.data().notifyCount) || 0) + 1
      });
      return true;
    });
  } catch (error) {
    console.error('⚠️ Connection-request cooldown check failed:', error.message);
    return true;
  }
}

module.exports = {
  signInviteToken,
  verifyInviteToken,
  recordEmailInvite,
  hasEmailInvite,
  targetInvitedRequester,
  claimRequestNotification,
  NOTIFY_COOLDOWN_MS,
  EMAIL_INVITE_TTL_MS
};
