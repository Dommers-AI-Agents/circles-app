// backend/services/circleLookup.js
//
// A circle's CURRENT name, cover and category for anything that shows one (a
// feed post "added X to <circle>", a profile timeline). Records keep the
// circle's id; the rest comes from the circle when the response is built
// (Wes, 2026-10-31). A stored name is only a fallback for a deleted circle.
const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');

const CHUNK = 100;

/** @returns {Promise<Map<string, {name, coverImage, category, privacy, owner}>>} */
async function fetchCirclesById(ids) {
  const db = getFirestore();
  const asked = [...new Set([...(ids || [])].filter(Boolean).map(String))];
  const out = new Map();
  for (let i = 0; i < asked.length; i += CHUNK) {
    const slice = asked.slice(i, i + CHUNK);
    const docs = await db.getAll(...slice.map((id) => db.collection(COLLECTIONS.CIRCLES).doc(id)));
    docs.forEach((doc, index) => {
      if (!doc || !doc.exists) return;
      const c = doc.data();
      if (c.deletedAt) return;
      out.set(slice[index], {
        name: c.name || null, coverImage: c.coverImage || null, category: c.category || null,
        privacy: c.privacy || null, owner: c.owner || null
      });
    });
  }
  return out;
}

module.exports = { fetchCirclesById };
