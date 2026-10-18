// services/momentExpiry.js — disappearing moments (Wes, 2026-10-18): a moment
// posted with "Disappears after 24 hours" carries `expiresAt` (ISO string)
// and is deleted for good once it passes, files, likes, comments and all.
// Reads hide an expired moment straight away; `sweep` (every 15 minutes,
// /api/tasks/moments-expire) does the deleting.
const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');
const { removeMoment } = require('./momentDeletion');

const DISAPPEAR_MS = 24 * 60 * 60 * 1000;
const SWEEP_LIMIT = 200;
/** Error code a read answers with for a moment that disappeared */
const GONE_CODE = 'moment_gone';
const GONE_MESSAGE = 'This moment has disappeared.';

/** When a disappearing moment posted at `liveAt` runs out (ISO string). */
function expiresAtFor(liveAt = new Date()) {
  const start = liveAt instanceof Date ? liveAt : new Date(liveAt);
  return new Date(start.getTime() + DISAPPEAR_MS).toISOString();
}

/** The body asked for a disappearing moment (true / "true" / 1). */
function wantsDisappearing(body) {
  const v = body && body.disappearing;
  return v === true || v === 'true' || v === 1 || v === '1';
}

/** Has this moment (or activity metadata) run out? Non-disappearing never do. */
function isExpired(doc, now = Date.now()) {
  const at = doc && doc.expiresAt;
  if (!at) return false;
  const ms = typeof at === 'string' ? Date.parse(at) : (at.toMillis ? at.toMillis() : new Date(at).getTime());
  return Number.isFinite(ms) && ms <= now;
}

/** Drops expired moments from a list of docs or plain objects. */
function withoutExpired(items, now = Date.now()) {
  return (items || []).filter(item => {
    const data = item && typeof item.data === 'function' ? item.data() : item;
    return !isExpired(data, now);
  });
}

/**
 * Deletes every moment whose time is up (up to SWEEP_LIMIT a run; the next
 * run takes the rest). Returns { deleted, failed }.
 */
async function sweep({ db = getFirestore(), bucket = null, now = new Date() } = {}) {
  const snap = await db.collection(COLLECTIONS.PLACE_VIDEOS)
    .where('expiresAt', '<=', now.toISOString())
    .limit(SWEEP_LIMIT)
    .get();
  let deleted = 0;
  let failed = 0;
  for (const doc of snap.docs) {
    try {
      await removeMoment(doc.id, doc.data(), { db, bucket, reason: 'disappeared after 24 hours' });
      deleted += 1;
    } catch (e) {
      failed += 1;
      console.error(`moment ${doc.id}: expiry delete failed:`, e.message);
    }
  }
  return { deleted, failed, more: snap.size >= SWEEP_LIMIT };
}

module.exports = {
  DISAPPEAR_MS, GONE_CODE, GONE_MESSAGE, SWEEP_LIMIT,
  expiresAtFor, wantsDisappearing, isExpired, withoutExpired, sweep
};
