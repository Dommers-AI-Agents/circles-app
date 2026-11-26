// backend/services/emailPreferences.js
// The email switches a person can change while signed in (Settings in the
// web app, 2026-11-26). The same opt-outs the one-click unsubscribe link in
// each email flips (routes/emailPreferenceRoutes): users/{uid}.emailPreferences
// [kind] === false means "don't send"; missing means on.
const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');
const { ServiceError } = require('../utils/serviceError');

// One row per email a person can turn off, in the order Settings lists them
const EMAIL_KINDS = [
  { kind: 'messageEmails', title: 'Unread messages', detail: 'When a message waits an hour, and again after a day' },
  { kind: 'activityEmails', title: 'Followers, comments and suggestions', detail: 'Only when notifications on your phone are off' },
  { kind: 'storeNudges', title: 'Emails from stores', detail: 'Specials, events and rewards from stores you follow or earn points at' },
  { kind: 'weeklyMapDigest', title: 'Your map', detail: 'Every other week: new places on your map and your friends\' maps' },
  { kind: 'followSuggestions', title: 'People you may know', detail: 'Now and then, people near you on FavCircles' },
  { kind: 'productUpdates', title: 'FavCircles news', detail: 'New features, a few times a year' }
];
const KINDS = new Set(EMAIL_KINDS.map((row) => row.kind));

/** Pure: each switch with its state (missing = on). */
const switchesFor = (user) => EMAIL_KINDS.map((row) => ({
  ...row,
  on: !(user && user.emailPreferences && user.emailPreferences[row.kind] === false)
}));

/** Pure: a request body → the fields to write. Throws ServiceError 400. */
const changesFrom = (body) => {
  const wanted = body && typeof body === 'object' && !Array.isArray(body) ? body : null;
  if (!wanted) throw new ServiceError(400, 'BAD_EMAIL_PREFERENCES', 'Send the switches to change.');
  const changes = {};
  for (const [kind, on] of Object.entries(wanted)) {
    if (!KINDS.has(kind) || typeof on !== 'boolean') {
      throw new ServiceError(400, 'BAD_EMAIL_PREFERENCES', `“${kind}” isn't an email switch.`);
    }
    changes[`emailPreferences.${kind}`] = on;
  }
  if (!Object.keys(changes).length) throw new ServiceError(400, 'BAD_EMAIL_PREFERENCES', 'Send the switches to change.');
  return changes;
};

async function read(userId) {
  const doc = await getFirestore().collection(COLLECTIONS.USERS).doc(userId).get();
  return switchesFor(doc.exists ? doc.data() : null);
}

/** Changes only the switches sent (dotted paths: the others are untouched). */
async function update(userId, body) {
  const changes = changesFrom(body);
  const ref = getFirestore().collection(COLLECTIONS.USERS).doc(userId);
  await ref.update({ ...changes, updatedAt: new Date().toISOString() });
  return read(userId);
}

module.exports = { EMAIL_KINDS, switchesFor, changesFrom, read, update };
