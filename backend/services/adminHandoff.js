// backend/services/adminHandoff.js
//
// Opening the admin dashboard from the app without typing a password. The
// app (already signed in, and an admin) asks for a one-time code; it opens
// /admin#handoff=<code>; the page trades the code for a short-lived token.
// The code lives 60 s, works once, and only its hash is stored, so a code
// seen in a log or a screenshot is useless a minute later. The page gets
// its own 12-hour token, never the app's long-lived one.
const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const { getFirestore } = require('../config/firebase');
const { ServiceError } = require('../utils/serviceError');

const COLLECTION = 'adminHandoffs';
const CODE_TTL_MS = 60 * 1000;
const PAGE_TOKEN_TTL = '12h';

const hash = (code) => crypto.createHash('sha256').update(String(code)).digest('hex');
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
  const token = jwt.sign({ uid }, process.env.JWT_SECRET, { expiresIn: PAGE_TOKEN_TTL });
  return { token };
};

module.exports = { issue, redeem, hash, CODE_TTL_MS };
