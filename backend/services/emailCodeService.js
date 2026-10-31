// backend/services/emailCodeService.js
// Sign in (or sign up) with a 6-digit code emailed to you: no password. The
// App Clip uses it so joining at a store counter is "type your email, type
// the code" (Wes, 2026-10-31). Proving you can read the inbox is the proof
// of ownership, so it signs in an existing account too.
//
// One doc per email in `emailLoginCodes` (keyed by a hash of the email, so
// the collection holds no addresses): the code's HMAC, its expiry, the wrong
// tries so far and the recent starts. A new start replaces the code.
const crypto = require('crypto');
const { ServiceError } = require('../utils/serviceError');
const { maskEmail } = require('../utils/text');

const CODE_TTL_MS = 10 * 60 * 1000;
const MAX_TRIES = 5;
const MAX_STARTS_PER_HOUR = 5;
const HOUR_MS = 60 * 60 * 1000;
const COLLECTION = 'emailLoginCodes';
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

const normalizeEmail = (email) => String(email || '').trim().toLowerCase();
const emailKey = (email) => crypto.createHash('sha256').update(email).digest('hex');
const codeHash = (secret, email, code) =>
  crypto.createHmac('sha256', secret).update(`${email}:${code}`).digest('hex');
const sameHash = (a, b) => a.length === b.length && crypto.timingSafeEqual(Buffer.from(a), Buffer.from(b));
const newCode = () => String(crypto.randomInt(0, 1000000)).padStart(6, '0');

function checkedEmail(raw) {
  const email = normalizeEmail(raw);
  if (!EMAIL_RE.test(email) || email.length > 254) {
    throw new ServiceError(400, 'EMAIL_INVALID', 'Please enter a valid email address.');
  }
  // Same rule as register: a private relay can't receive our mail reliably
  if (email.includes('@privaterelay.appleid.com')) {
    throw new ServiceError(400, 'PRIVATE_RELAY_NOT_ALLOWED', 'Private relay emails are not allowed. Please use your real email address.');
  }
  return email;
}

/**
 * deps: db, auth (firebase-admin auth), sendCode(email, code), secret,
 * now() → ms, createCode() → '123456', and createAccount / signIn hooks
 * (the controller's token minting lives outside this service).
 */
function createEmailCodeService(deps) {
  const now = deps.now || Date.now;
  const createCode = deps.createCode || newCode;
  const users = () => deps.db.collection('users');

  async function findUser(email) {
    const snap = await users().where('email', '==', email).limit(1).get();
    return snap.empty ? null : snap.docs[0];
  }

  /** Sends a fresh code. Returns { newAccount }. */
  async function start(rawEmail) {
    const email = checkedEmail(rawEmail);
    const ref = deps.db.collection(COLLECTION).doc(emailKey(email));
    const code = createCode();
    await deps.db.runTransaction(async (tx) => {
      const doc = await tx.get(ref);
      const starts = ((doc.exists && doc.data().starts) || []).filter((t) => t > now() - HOUR_MS);
      if (starts.length >= MAX_STARTS_PER_HOUR) {
        throw new ServiceError(429, 'TOO_MANY_CODES', 'Too many codes asked for. Please try again in an hour.');
      }
      tx.set(ref, {
        codeHash: codeHash(deps.secret, email, code),
        expiresAt: now() + CODE_TTL_MS,
        tries: 0,
        starts: [...starts, now()]
      });
    });
    const existing = await findUser(email);
    await deps.sendCode(email, code);
    console.log(`📧 Email sign-in code sent to ${maskEmail(email)}`);
    return { newAccount: !existing };
  }

  /**
   * Checks the code and returns { user: {id, ...doc}, isNew }. A new account
   * needs a display name (2–50 characters); asking for it doesn't use up a
   * try or the code.
   */
  async function verify({ email: rawEmail, code, displayName }) {
    const email = checkedEmail(rawEmail);
    const existing = await findUser(email);
    const name = String(displayName || '').trim();
    if (!existing && (name.length < 2 || name.length > 50)) {
      throw new ServiceError(400, 'NAME_REQUIRED', 'Please tell us your name (2–50 characters).');
    }

    const ref = deps.db.collection(COLLECTION).doc(emailKey(email));
    const typed = String(code || '').replace(/\D/g, '');
    // Firestore drops a transaction's writes when its callback throws, so
    // the outcome comes back as a value and the refusal is thrown after,
    // once the wrong try is counted
    const outcome = await deps.db.runTransaction(async (tx) => {
      const doc = await tx.get(ref);
      if (!doc.exists) return 'expired';
      const data = doc.data();
      if (data.tries >= MAX_TRIES) return 'locked';
      if (data.expiresAt <= now()) return 'expired';
      if (typed.length !== 6 || !sameHash(codeHash(deps.secret, email, typed), data.codeHash)) {
        const tries = data.tries + 1;
        tx.update(ref, { tries });
        return tries >= MAX_TRIES ? 'locked' : 'wrong';
      }
      // Used once (the starts history stays for the hourly limit)
      tx.update(ref, { codeHash: '', expiresAt: 0, tries: 0 });
      return 'ok';
    });
    if (outcome === 'expired') throw new ServiceError(400, 'CODE_EXPIRED', 'That code has expired. Ask for a new one.');
    if (outcome === 'locked') throw new ServiceError(429, 'TOO_MANY_TRIES', 'Too many wrong codes. Ask for a new one.');
    if (outcome === 'wrong') throw new ServiceError(400, 'CODE_INVALID', "That code isn't right. Check the email and try again.");

    if (existing) {
      await refuseDisabled(existing.id);
      return { user: { id: existing.id, ...existing.data() }, isNew: false };
    }
    return { user: await createAccount(email, name), isNew: true };
  }

  async function refuseDisabled(uid) {
    const record = await deps.auth.getUser(uid).catch(() => null);
    if (record && record.disabled) {
      throw new ServiceError(403, 'ACCOUNT_DISABLED', 'This account has been disabled.');
    }
  }

  // The inbox is proven, so a half-created Auth record (no user doc) for
  // this email is theirs to finish rather than a reason to refuse.
  async function createAccount(email, displayName) {
    let record = await deps.auth.getUserByEmail(email).catch(() => null);
    if (record && record.disabled) {
      throw new ServiceError(403, 'ACCOUNT_DISABLED', 'This account has been disabled.');
    }
    if (!record) {
      record = await deps.auth.createUser({ email, emailVerified: true, displayName });
    }
    const userData = deps.buildUser({
      uid: record.uid,
      email,
      displayName,
      profilePicture: null,
      linkedProviders: { emailCode: record.uid }
    });
    // create(): two racing verifies can't both write the doc
    await users().doc(record.uid).create(userData).catch((error) => {
      if (error.code !== 6 && !/already.exists/i.test(error.message)) throw error;
    });
    return { id: record.uid, ...userData };
  }

  return { start, verify };
}

let shared = null;
/** The production instance (Firestore, Firebase Auth, SES via emailService). */
function emailCodeService() {
  if (shared) return shared;
  const { getFirestore, getAuth } = require('../config/firebase');
  const { createUser } = require('../models/FirestoreModels');
  const emailService = require('./emailService');
  shared = createEmailCodeService({
    db: getFirestore(),
    auth: getAuth(),
    secret: process.env.JWT_SECRET,
    buildUser: createUser,
    sendCode: (email, code) => emailService.sendLoginCodeEmail(email, code)
  });
  return shared;
}

module.exports = { createEmailCodeService, emailCodeService, CODE_TTL_MS, MAX_TRIES, MAX_STARTS_PER_HOUR, emailKey };
