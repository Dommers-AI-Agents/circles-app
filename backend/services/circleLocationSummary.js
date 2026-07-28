// backend/services/circleLocationSummary.js
//
// Precomputed per-circle location summaries — the scalable core of the
// network-wide browse tree. One small doc per circle holds density counts of
// its places by city/state, so a Browse-open merges a bounded set of summaries
// (one per allowed circle) instead of scanning every place in the network.
//
//   circleLocationSummaries/{circleId} = {
//     cityCounts: { "charlotte|NC": 12 },
//     cityMeta:   { "charlotte|NC": { city:"Charlotte", stateCode:"NC", state:"North Carolina" } },
//     unplacedCount: 3,
//     updatedAt
//   }
//
// Maintenance is best-effort and fire-and-forget so it never blocks a save; the
// rebuild path (build-circle-location-summaries.js / a nightly job) is the
// source of truth and corrects any drift. cityKey is used as a MAP KEY inside
// the doc (not a Firestore field path) and updates go through a transaction
// read-modify-write, so keys containing '.' (e.g. "st. louis|MO") are safe.

const admin = require('firebase-admin');
const { getFirestore } = require('../config/firebase');
const { COLLECTIONS, serializeDoc } = require('../models/FirestoreModels');
const { summarizeCirclePlaces } = require('./browseAggregation');

const db = getFirestore();
const COLLECTION = 'circleLocationSummaries';

// Apply a +1 / -1 for one place's location to its circle's summary.
// loc: { cityKey, city, stateCode, state } (cityKey null/absent => Unplaced).
async function applyDelta(circleId, loc, delta) {
  if (!circleId) return;
  const ref = db.collection(COLLECTION).doc(circleId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.exists ? snap.data() : {};
    const cityCounts = data.cityCounts || {};
    const cityMeta = data.cityMeta || {};
    let unplacedCount = data.unplacedCount || 0;

    if (!loc || !loc.cityKey) {
      unplacedCount = Math.max(0, unplacedCount + delta);
    } else {
      const next = (cityCounts[loc.cityKey] || 0) + delta;
      if (next <= 0) {
        delete cityCounts[loc.cityKey];
        delete cityMeta[loc.cityKey];
      } else {
        cityCounts[loc.cityKey] = next;
        cityMeta[loc.cityKey] = {
          city: loc.city || 'Unknown',
          stateCode: loc.stateCode || null,
          state: loc.state || loc.stateCode || null
        };
      }
    }
    tx.set(ref, { cityCounts, cityMeta, unplacedCount, updatedAt: new Date().toISOString() });
  });
}

// Pull the location fields off a (serialized) place doc.
const locOf = (p) => ({ cityKey: p.cityKey, city: p.city, stateCode: p.stateCode, state: p.state });

// Fire-and-forget wrappers used from the request path. They never throw into
// the caller; drift is corrected by the rebuild job.
function indexPlaceAdded(circleId, place) {
  applyDelta(circleId, locOf(place), +1).catch(e =>
    console.warn(`⚠️ [locSummary] add ${circleId} failed: ${e.message}`));
}
function indexPlaceRemoved(circleId, place) {
  applyDelta(circleId, locOf(place), -1).catch(e =>
    console.warn(`⚠️ [locSummary] remove ${circleId} failed: ${e.message}`));
}
function indexPlaceMoved(fromCircleId, toCircleId, place) {
  indexPlaceRemoved(fromCircleId, place);
  indexPlaceAdded(toCircleId, place);
}

// Recompute one circle's summary from scratch (rebuild/nightly). Returns the doc.
async function rebuildCircleSummary(circleId, { write = true } = {}) {
  const snap = await db.collection(COLLECTIONS.PLACES).where('circleId', '==', circleId).get();
  const places = snap.docs.map(serializeDoc);
  const summary = summarizeCirclePlaces(places);
  summary.updatedAt = new Date().toISOString();
  if (write) await db.collection(COLLECTION).doc(circleId).set(summary);
  return summary;
}

// Read summaries for a set of circle ids (batched getAll).
async function getSummaries(circleIds) {
  if (!circleIds.length) return [];
  const refs = circleIds.map(id => db.collection(COLLECTION).doc(id));
  const out = [];
  for (let i = 0; i < refs.length; i += 300) {
    const chunk = refs.slice(i, i + 300);
    const docs = await db.getAll(...chunk);
    docs.forEach(d => { if (d.exists) out.push(d.data()); });
  }
  return out;
}

module.exports = {
  COLLECTION,
  applyDelta,
  indexPlaceAdded,
  indexPlaceRemoved,
  indexPlaceMoved,
  rebuildCircleSummary,
  getSummaries
};
