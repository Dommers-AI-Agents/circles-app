// backend/utils/batchGet.js
//
// Read many documents by id in as few round trips as Firestore allows:
// db.getAll(...refs) in chunks, optionally projected to a few fields. Replaces
// the `Promise.all(ids.map(id => doc(id).get()))` pattern — one RPC per id —
// that the network, browse and sharing read paths each wrote by hand.
const { getFirestore } = require('../config/firebase');

const CHUNK = 300;

/**
 * @param {string} collection
 * @param {Iterable<string>} ids         duplicates and empties are ignored
 * @param {object} [opts]
 * @param {string[]} [opts.fields]       fieldMask (read only these fields)
 * @returns {Promise<Map<string, FirebaseFirestore.DocumentSnapshot>>} existing docs by id
 */
async function getDocsById(collection, ids, { fields, db = getFirestore() } = {}) {
  const unique = [...new Set(Array.from(ids || []).filter(Boolean).map(String))];
  const out = new Map();
  if (unique.length === 0) return out;
  const chunks = [];
  for (let i = 0; i < unique.length; i += CHUNK) chunks.push(unique.slice(i, i + CHUNK));
  const options = fields && fields.length ? [{ fieldMask: fields }] : [];
  const results = await Promise.all(chunks.map(chunk =>
    db.getAll(...chunk.map(id => db.collection(collection).doc(id)), ...options)));
  for (const docs of results) {
    for (const doc of docs) if (doc.exists) out.set(doc.id, doc);
  }
  return out;
}

module.exports = { getDocsById };
