// backend/services/adminHandoff.js
//
// Opening the admin dashboard from the app without typing a password. The
// app (already signed in, and an admin) asks for a one-time code; it opens
// /admin#handoff=<code>; the page trades the code for a short-lived token.
// The code lives 60 s, works once, and only its hash is stored, so a code
// seen in a log or a screenshot is useless a minute later. The page gets
// its own 12-hour token, never the app's long-lived one.
const crypto = require('crypto');
const { getFirestore } = require('../config/firebase');
const { ServiceError } = require('../utils/serviceError');

const COLLECTION = 'adminHandoffs';
const CODE_TTL_MS = 60 * 1000;

// Keyed with the server secret, so stored hashes are useless without it
const hash = (value) => crypto.createHmac('sha256', process.env.JWT_SECRET || '').update(String(value)).digest('hex');
const { signDashboardToken } = require('../middleware/adminDashboardAuth');
const sameHash = (a, b) => {
  const x = Buffer.from(String(a)); const y = Buffer.from(String(b));
  return x.length === y.length && crypto.timingSafeEqual(x, y);
};
const db = () => getFirestore();

const issue = async (uid) => {
  const code = crypto.randomBytes(24).toString('base64url');
  await db().collection(COLLECTION).doc(hash(code)).set({
    uid, createdAt: new Date().toISOString(), expiresAt: new Date(Date.now() + CODE_TTL_MS).toISOString()
  });
  return { code, url: `https://api.favcircles.com/admin#handoff=${code}`, expiresInSeconds: CODE_TTL_MS / 1000 };
};

const redeem = async (code) => {
  if (!code || String(code).length < 20) throw new ServiceError(400, 'BAD_CODE', 'That sign-in link is not valid.');
  const ref = db().collection(COLLECTION).doc(hash(code));
  const uid = await db().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new ServiceError(401, 'CODE_USED', 'That sign-in link was already used. Open the dashboard from the app again.');
    const data = snap.data();
    tx.delete(ref); // single use, whatever happens next
    if (Date.parse(data.expiresAt) < Date.now()) throw new ServiceError(401, 'CODE_EXPIRED', 'That sign-in link expired. Open the dashboard from the app again.');
    return data.uid;
  });
  const user = await db().collection('users').doc(uid).get();
  if (!user.exists || user.data().isSuperUser !== true) throw new ServiceError(403, 'NOT_ADMIN', "This account isn't an admin.");
  return { token: signDashboardToken(uid) };
};

module.exports = { issue, redeem, hash, CODE_TTL_MS };

// ---- Email code: sign in to the dashboard without a password.
// An admin enters their email; a 6-digit code (10 min, single use, 5 tries)
// is emailed; the page trades it for the same 12-hour token. Requests for
// unknown or non-admin addresses get the same answer and no email, so the
// form can't be used to find out who is an admin.
const EMAIL_CODES = 'adminEmailCodes';
const EMAIL_CODE_TTL_MS = 10 * 60 * 1000;
const RESEND_GAP_MS = 60 * 1000;
const MAX_TRIES = 5;
const GUARD = 'adminEmailCodeGuards';
const MAX_CODES_PER_DAY = 10;
const MAX_FAILURES_PER_DAY = 10;
const LOCK_MS = 24 * 60 * 60 * 1000;

/** Per-email limits across codes: 10 codes a day; 10 wrong guesses locks it for 24 h. */
const guardFor = async (email) => {
  const ref = db().collection(GUARD).doc(hash(`guard:${email}`));
  const snap = await ref.get();
  const today = new Date().toISOString().slice(0, 10);
  const data = snap.exists ? snap.data() : {};
  const fresh = data.day === today ? data : { day: today, requests: 0, failures: 0, lockedUntil: data.lockedUntil || null };
  return { ref, data: fresh, locked: Boolean(fresh.lockedUntil && Date.parse(fresh.lockedUntil) > Date.now()) };
};

const findAdminByEmail = async (email) => {
  const snap = await db().collection('users').where('email', '==', email).limit(5).get();
  const doc = snap.docs.find((d) => d.data().isSuperUser === true && !d.data().isDeleted);
  return doc ? { uid: doc.id, user: doc.data() } : null;
};

const requestEmailCode = async (rawEmail) => {
  const email = String(rawEmail || '').trim().toLowerCase();
  if (!email.includes('@')) throw new ServiceError(400, 'BAD_EMAIL', 'Enter the email on your FavCircles account.');
  const admin = await findAdminByEmail(email);
  if (!admin) return { sent: true };
  const guard = await guardFor(email);
  if (guard.locked || guard.data.requests >= MAX_CODES_PER_DAY) {
    console.warn(`🔑 Admin email code refused for ${admin.uid}: ${guard.locked ? 'locked' : 'daily limit'}`);
    return { sent: true };
  }
  const ref = db().collection(EMAIL_CODES).doc(hash(email));
  const prior = await ref.get();
  if (prior.exists && Date.now() - Date.parse(prior.data().createdAt) < RESEND_GAP_MS) return { sent: true };
  const code = String(crypto.randomInt(0, 1000000)).padStart(6, '0');
  await guard.ref.set({ ...guard.data, requests: guard.data.requests + 1 }, { merge: true });
  await ref.set({ uid: admin.uid, codeHash: hash(`${email}:${code}`), tries: 0,
    createdAt: new Date().toISOString(), expiresAt: new Date(Date.now() + EMAIL_CODE_TTL_MS).toISOString() });
  const emailService = require('./emailService');
  await emailService.sendEmail({
    to: email,
    subject: `${code} is your FavCircles admin sign-in code`,
    text: `Your FavCircles admin sign-in code is ${code}\n\nIt works once, for 10 minutes. If you didn't ask for it, ignore this email; your password hasn't changed.`,
    html: `<div style="font-family:-apple-system,Helvetica,Arial,sans-serif;max-width:440px;margin:0 auto;padding:24px;color:#1A2438">
      <div style="font-weight:800;font-size:16px;margin-bottom:16px">FavCircles Admin</div>
      <div style="font-size:15px">Your sign-in code:</div>
      <div style="font-size:34px;font-weight:800;letter-spacing:6px;margin:10px 0 16px">${code}</div>
      <div style="font-size:13px;color:#5B6780">It works once, for 10 minutes. If you didn't ask for it, ignore this email; your password hasn't changed.</div></div>`
  });
  console.log(`🔑 Admin email code sent to ${admin.uid}`);
  return { sent: true };
};

const verifyEmailCode = async (rawEmail, rawCode) => {
  const email = String(rawEmail || '').trim().toLowerCase();
  const code = String(rawCode || '').replace(/\D/g, '');
  const ref = db().collection(EMAIL_CODES).doc(hash(email));
  const guard = await guardFor(email);
  if (guard.locked) throw new ServiceError(429, 'LOCKED', 'Too many wrong codes. Email sign-in is paused for 24 hours; use your password or the app.');
  let failed = false;
  let uid;
  try {
    uid = await db().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const bad = new ServiceError(401, 'BAD_CODE', "That code didn't work. Check the email, or ask for a new code.");
    if (!snap.exists) { failed = true; throw bad; }
    const data = snap.data();
    if (Date.parse(data.expiresAt) < Date.now()) { tx.delete(ref); throw new ServiceError(401, 'CODE_EXPIRED', 'That code expired. Ask for a new one.'); }
    if (!sameHash(data.codeHash, hash(`${email}:${code}`))) {
      if (data.tries + 1 >= MAX_TRIES) tx.delete(ref); else tx.update(ref, { tries: data.tries + 1 });
      failed = true;
      throw bad;
    }
    tx.delete(ref); // single use
    return data.uid;
  });
  } catch (error) {
    if (failed) {
      const failures = (guard.data.failures || 0) + 1;
      const lock = failures >= MAX_FAILURES_PER_DAY ? { lockedUntil: new Date(Date.now() + LOCK_MS).toISOString() } : {};
      await guard.ref.set({ ...guard.data, failures, ...lock }, { merge: true });
      if (lock.lockedUntil) console.warn('🔑 Admin email sign-in locked for 24 h after repeated wrong codes');
    }
    throw error;
  }
  const user = await db().collection('users').doc(uid).get();
  if (!user.exists || user.data().isSuperUser !== true) throw new ServiceError(403, 'NOT_ADMIN', "This account isn't an admin.");
  return { token: signDashboardToken(uid) };
};

module.exports.requestEmailCode = requestEmailCode;
module.exports.verifyEmailCode = verifyEmailCode;
