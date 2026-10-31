// backend/services/venueGoogleSignals.js — one writer for "a Google details
// result arrived for this venue": keep every free signal on the canonical
// record (services/googlePlaceFields) and let Google's types set the
// category unless an owner or admin chose it. Used by the paths that already
// call Google (fill-once details, share-save enrichment, refresh); never
// makes a call of its own.
const { getFirestore } = require('../config/firebase');
const { GLOBAL_COLLECTIONS } = require('../models/GlobalPlace');
const { googleSignals, venueSignalUpdates } = require('./googlePlaceFields');
const { googleReclassification } = require('./placeCategoryDerivation');

/**
 * A system category change (Google types, the nightly sweep, the LLM tier)
 * reaches every copy: each save's cache (the map and list queries filter on
 * those) and the venue's store record. The ONE category fan-out for writers
 * that keep their own categorySource/categoryBefore bookkeeping on the
 * canonical record — human edits go through venueDetailsService instead.
 * `venue` (the canonical record) lets the store be found by Google id too.
 * Returns how many saves were updated.
 */
async function syncCategoryToSaves(globalPlaceId, category, now, { db = getFirestore(), venue = null } = {}) {
  const siblings = await db.collection('places').where('globalPlaceId', '==', globalPlaceId).get();
  for (let i = 0; i < siblings.docs.length; i += 400) {
    const batch = db.batch();
    siblings.docs.slice(i, i + 400).forEach((doc) => batch.update(doc.ref, { category, updatedAt: now }));
    await batch.commit();
  }
  // Lazy: venueDetailsService pulls in photo/permission modules
  await require('./venueDetailsService').syncStoreFromVenue(globalPlaceId, venue, { category }, now)
    .catch((e) => console.error('⚠️ [GlobalPlace] store category sync failed:', e.message));
  return siblings.size;
}

/**
 * The updates a details result implies for a venue: its signals, and a new
 * category when Google says something different. Pure.
 */
function updatesForSignals(venue, signals, name) {
  if (!signals) return { updates: {}, reclass: null };
  const reclass = googleReclassification(venue, {
    googleTypes: signals.googleTypes.length ? signals.googleTypes : venue.googleTypes,
    googlePrimaryType: venue.googlePrimaryType,
    serves: signals.serves,
    dineIn: signals.dineIn ?? (venue.googleData || {}).dineIn,
    name: name || venue.name
  });
  return { updates: { ...venueSignalUpdates(signals), ...(reclass || {}) }, reclass };
}

function updatesFor(venue, details) {
  return updatesForSignals(venue, googleSignals(details), details && details.name);
}

/**
 * Writes them (plus `extra`) in one update; returns the reclassification, if
 * any. Pass `details` (a raw Place Details result) or `signals` (already
 * extracted with googlePlaceFields.googleSignals).
 */
async function applyGoogleDetails(globalPlaceId, details, { db = getFirestore(), venue = null, extra = {}, signals = null, name = null } = {}) {
  const ref = db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).doc(String(globalPlaceId));
  const data = venue || (await ref.get()).data();
  if (!data) return null;
  const now = new Date().toISOString();
  const { updates, reclass } = signals ? updatesForSignals(data, signals, name) : updatesFor(data, details);
  await ref.update({ ...updates, ...extra, updatedAt: now });
  if (reclass && reclass.category !== (data.category || 'other')) {
    await syncCategoryToSaves(globalPlaceId, reclass.category, now, { db, venue: data });
    console.log(`🏷️ [GlobalPlace] "${data.name}" ${globalPlaceId}: ${data.category} → ${reclass.category}${reclass.subcategory ? ` · ${reclass.subcategory}` : ''} (google)`);
  }
  return reclass;
}

module.exports = { updatesFor, updatesForSignals, applyGoogleDetails, syncCategoryToSaves };
