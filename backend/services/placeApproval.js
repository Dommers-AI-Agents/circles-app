// backend/services/placeApproval.js — a place nobody can vouch for waits for
// the admin (Wes, 2026-11-05: "they can enter a street address manually and
// it's private and flags me to approve for a public global place").
//
// A venue minted from a save with no Google listing, no Apple Maps place and
// no Apple business category (a spot tapped on the map and named by hand, a
// street address) gets approvalStatus 'pending': the save turns private, the
// venue stays out of search for everyone else, and the admin is alerted.
// Approve → the saves get back the privacy they were saved with; Reject →
// the place stays private to the people who saved it.
const admin = require('firebase-admin');
const { getFirestore } = require('../config/firebase');
const { GLOBAL_COLLECTIONS } = require('../models/GlobalPlace');
const { COLLECTIONS } = require('../models/FirestoreModels');
const { isAddressOnly } = require('./googleAddressGuard');
const { ServiceError } = require('../utils/serviceError');

const HIDDEN = new Set(['pending', 'rejected']);

/** True when a venue must not show to anyone but its savers. Pure. */
const isHiddenVenue = (venue) => !!venue && HIDDEN.has(venue.approvalStatus);

/**
 * True when a save names a place no map source knows: no Google listing
 * (an address entry doesn't count), no Apple place id, no Apple business
 * category. Pure.
 */
function needsApproval(save) {
  if (!save) return false;
  const google = save.googlePlaceId && !isAddressOnly(save.googleTypes);
  return !google && !save.applePlaceId && !save.applePoiCategory;
}

/**
 * Hold a save of a hidden venue private, remembering the privacy it was saved
 * with so approval can give it back.
 */
async function holdSavePrivate(saveRef, save) {
  if (save.privacy === 'private' && !save.privacyBeforeApproval) {
    await saveRef.update({ privacyBeforeApproval: 'private' });
    return;
  }
  await saveRef.update({ privacyBeforeApproval: save.privacy || 'public', privacy: 'private', updatedAt: new Date().toISOString() });
}

/**
 * Called by the link step right after a save is linked. `minted` = the venue
 * was created by this save. Never throws (a save must not fail on this).
 */
async function onSaveLinked({ saveDoc, venueId, venue, minted }, deps = {}) {
  try {
    const db = deps.db || getFirestore();
    const save = saveDoc.data();
    const saveRef = db.collection(COLLECTIONS.PLACES).doc(saveDoc.id);
    if (minted && needsApproval(save)) {
      await db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).doc(venueId).update({
        approvalStatus: 'pending', pendingSince: new Date().toISOString(),
        submittedBy: save.addedBy || null, submittedSaveId: saveDoc.id
      });
      await holdSavePrivate(saveRef, save);
      const alertAdmin = deps.alertAdmin || require('./adminAlerts').alertAdmin;
      alertAdmin({
        // The app opens its Approve places screen for this key (NotificationTapRouter)
        key: `place-approval-${venueId}`,
        title: `Place to approve: ${save.name || 'Unnamed'}`,
        body: `"${save.name || 'Unnamed'}"\n${save.address || ''}\n\nSaved without a Google or Apple Maps match, so it's private until you approve it.\nApprove or reject: admin dashboard → Approve places.`
      });
      return 'pending';
    }
    if (!minted && isHiddenVenue(venue)) {
      await holdSavePrivate(saveRef, save);
      return 'held';
    }
    return null;
  } catch (error) {
    console.error(`[place-approval] ${venueId}: ${error.message}`);
    return null;
  }
}

/** The approval queue, oldest first, with each place's saves. */
async function listPending({ db = getFirestore() } = {}) {
  const snap = await db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).where('approvalStatus', '==', 'pending').get();
  const rows = await Promise.all(snap.docs.map(async (doc) => {
    const v = doc.data();
    if (v.deletedAt || v.mergedInto) return null;
    const saves = await db.collection(COLLECTIONS.PLACES).where('globalPlaceId', '==', doc.id).get();
    const live = saves.docs.filter((s) => !s.data().deletedAt);
    const userIds = [...new Set(live.map((s) => s.data().addedBy).filter(Boolean))];
    const users = await Promise.all(userIds.slice(0, 10).map((id) => db.collection(COLLECTIONS.USERS).doc(String(id)).get()));
    const coords = v.location && v.location.coordinates;
    const photo = (v.photos || []).map((p) => (typeof p === 'string' ? p : p && !p.removedAt && p.url)).find(Boolean) || null;
    return {
      id: doc.id, name: v.name, address: v.address || '', category: v.category || 'other',
      pendingSince: v.pendingSince || v.createdAt || null, photo,
      mapUrl: coords ? `https://maps.apple.com/?ll=${coords[1]},${coords[0]}&q=${encodeURIComponent(v.name || '')}` : null,
      saves: live.length,
      savedBy: users.filter((u) => u.exists).map((u) => u.data().displayName || u.data().username || 'Someone')
    };
  }));
  return rows.filter(Boolean).sort((a, b) => String(a.pendingSince).localeCompare(String(b.pendingSince)));
}

/** Approve or reject a waiting place. */
async function decide(venueId, decision, adminUid, { db = getFirestore() } = {}) {
  if (!['approved', 'rejected'].includes(decision)) throw new ServiceError(400, 'BAD_DECISION', 'Choose approve or reject');
  const ref = db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).doc(String(venueId));
  const snap = await ref.get();
  if (!snap.exists || snap.data().deletedAt) throw new ServiceError(404, 'NOT_FOUND', 'Place not found');
  if (snap.data().approvalStatus !== 'pending') throw new ServiceError(409, 'NOT_PENDING', 'This place is not waiting for approval');
  const now = new Date().toISOString();
  await ref.update({ approvalStatus: decision, decidedAt: now, decidedBy: adminUid || null, updatedAt: now });
  let restored = 0;
  if (decision === 'approved') {
    const saves = await db.collection(COLLECTIONS.PLACES).where('globalPlaceId', '==', ref.id).get();
    for (const s of saves.docs) {
      const before = s.data().privacyBeforeApproval;
      if (!before) continue;
      await s.ref.update({ privacy: before, privacyBeforeApproval: admin.firestore.FieldValue.delete(), updatedAt: now });
      restored += 1;
    }
  }
  return { id: ref.id, approvalStatus: decision, restored };
}

module.exports = { isHiddenVenue, needsApproval, onSaveLinked, listPending, decide };
