// backend/utils/firestoreChunks.js
//
// Firestore's 'in' / 'array-contains-any' operators cap at 30 comparison
// values — and several of our queries fan out over a user's connections, which
// broke the moment anyone passed 30 accepted connections. Chunk by 10 (the old
// limit, and safely under every composite-query restriction) and merge.

const IN_CHUNK = 10;

function chunk(values, size = IN_CHUNK) {
  const arr = Array.from(values);
  const out = [];
  for (let i = 0; i < arr.length; i += size) out.push(arr.slice(i, i + size));
  return out;
}

// Runs buildQuery(chunkOfValues) -> Promise<QuerySnapshot> for each chunk in
// parallel and returns the merged, de-duplicated docs.
async function queryInChunks(values, buildQuery) {
  const chunks = chunk(values);
  if (chunks.length === 0) return [];
  const snaps = await Promise.all(chunks.map(c => buildQuery(c)));
  const seen = new Set();
  const docs = [];
  for (const snap of snaps) {
    for (const doc of snap.docs) {
      if (seen.has(doc.id)) continue;
      seen.add(doc.id);
      docs.push(doc);
    }
  }
  return docs;
}

module.exports = { chunk, queryInChunks, IN_CHUNK };
