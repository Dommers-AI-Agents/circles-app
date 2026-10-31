// backend/services/userLookup.js
//
// Who someone is RIGHT NOW, for anything that shows a person: a comment, a
// reaction, a notification row, a chat list, an event's members, a run's
// cheers. Records store only the person's id; the name and photo come from
// their user record when the response is built (Wes, 2026-10-31: "stored in
// the db and pulled from one place"). A stored name/photo on an old record is
// only a fallback for a deleted account.
//
// One batched read per response (db.getAll in chunks), never one per row.
const { getFirestore } = require('../config/firebase');
const { COLLECTIONS, serializeDoc } = require('../models/FirestoreModels');
const { projectPublicUser } = require('./publicUserProjection');
const { normalizeUserId } = require('./idService');

const CHUNK = 100;

/**
 * @param {Iterable<string>} ids  any user ids (duplicates, nulls and odd id shapes are fine)
 * @returns {Promise<Map<string, object>>} id → public card (projectPublicUser: never email),
 *   keyed by BOTH the id given and the normalized id
 */
async function fetchUsersById(ids) {
  const db = getFirestore();
  const asked = [...new Set([...(ids || [])].filter(Boolean).map(String))];
  const out = new Map();
  if (asked.length === 0) return out;
  const byNormal = new Map();
  for (const id of asked) {
    const n = normalizeUserId(id) || id;
    if (!byNormal.has(n)) byNormal.set(n, []);
    byNormal.get(n).push(id);
  }
  const normals = [...byNormal.keys()];
  for (let i = 0; i < normals.length; i += CHUNK) {
    const slice = normals.slice(i, i + CHUNK);
    const docs = await db.getAll(...slice.map((id) => db.collection(COLLECTIONS.USERS).doc(id)));
    docs.forEach((doc, index) => {
      if (!doc || !doc.exists) return;
      const card = projectPublicUser(serializeDoc(doc));
      card.id = doc.id;
      out.set(slice[index], card);
      for (const original of byNormal.get(slice[index]) || []) out.set(original, card);
    });
  }
  return out;
}

/** The photo URL on a public card, whichever field the account uses. */
const photoOf = (card) => (card && (card.profilePicture || card.photoURL || card.photoUrl)) || null;
const nameOf = (card) => (card && card.displayName) || null;

/**
 * Overwrite a stored name/photo with the person's current ones. Returns a NEW
 * object; leaves the stored values when the account is gone.
 * @param {object} row
 * @param {Map} users from fetchUsersById
 * @param {{ id: string, name?: string, photo?: string }} fields  row field names
 */
function withCurrentUser(row, users, { id, name, photo }) {
  if (!row) return row;
  const card = users.get(String(row[id] || ''));
  if (!card) return row;
  const out = { ...row };
  if (name) out[name] = nameOf(card) || row[name] || null;
  if (photo) out[photo] = photoOf(card) || row[photo] || null;
  return out;
}

module.exports = { fetchUsersById, withCurrentUser, photoOf, nameOf };
