// backend/controllers/trashController.js
//
// Per-user trash for deleted circles and places.
//
// - Deleting a circle moves its doc to the `deletedCircles` collection and
//   soft-deletes its places (deletedAt + deletedViaCircleDelete) — see
//   firebaseCircleController.deleteCircle. Because the doc leaves the
//   `circles` collection, no read query anywhere needs a filter change.
// - Deleting a place sets deletedAt (existing behavior).
// - Everything here is scoped to the authenticated user and retained until
//   they permanently delete it.

const { getFirestore } = require('../config/firebase');
const { normalizeUserId } = require('../services/idService');

const db = getFirestore();
const CIRCLES = 'circles';
const PLACES = 'places';
const DELETED_CIRCLES = 'deletedCircles';

const serialize = (doc) => ({ _id: doc.id, ...doc.data() });
const isSameUser = (a, b) => normalizeUserId(a) === normalizeUserId(b);

// Firestore batches cap at 500 ops — commit in chunks.
async function batchedUpdate(docs, buildOp) {
  for (let i = 0; i < docs.length; i += 400) {
    const batch = db.batch();
    docs.slice(i, i + 400).forEach((doc) => buildOp(batch, doc));
    await batch.commit();
  }
}

// @desc    List the user's trash (deleted circles + individually deleted places)
// @route   GET /api/trash
// @access  Private
exports.listTrash = async (req, res, next) => {
  try {
    const uid = req.user.uid;

    const circlesSnap = await db.collection(DELETED_CIRCLES).where('owner', '==', uid).get();
    const circles = circlesSnap.docs.map(serialize);

    // Individually deleted places only — places removed by a circle deletion
    // are restored together with their circle, not one by one.
    const placesSnap = await db.collection(PLACES).where('addedBy', '==', uid).get();
    const places = placesSnap.docs
      .map(serialize)
      .filter((p) => p.deletedAt != null && p.deletedViaCircleDelete !== true);

    res.status(200).json({
      success: true,
      circles,
      places,
      counts: { circles: circles.length, places: places.length }
    });
  } catch (error) {
    console.error('Error listing trash:', error);
    next(error);
  }
};

// @desc    Restore a deleted circle (and the places deleted with it)
// @route   POST /api/trash/circles/:id/restore
// @access  Private (owner)
exports.restoreCircle = async (req, res, next) => {
  try {
    const trashRef = db.collection(DELETED_CIRCLES).doc(req.params.id);
    const trashDoc = await trashRef.get();
    if (!trashDoc.exists) {
      return res.status(404).json({ success: false, message: 'Circle not found in trash' });
    }
    const circle = serialize(trashDoc);
    if (!isSameUser(circle.owner, req.user.uid)) {
      return res.status(403).json({ success: false, message: 'Not authorized to restore this circle' });
    }

    const now = new Date().toISOString();
    const { _id, deletedAt, ...circleData } = circle;

    // Restore the places that were deleted BY the circle deletion.
    const placesSnap = await db.collection(PLACES)
      .where('circleId', '==', req.params.id)
      .get();
    const toRestore = placesSnap.docs.filter((d) => d.data().deletedViaCircleDelete === true);

    await batchedUpdate(toRestore, (batch, doc) => {
      batch.update(doc.ref, { deletedAt: null, deletedViaCircleDelete: null, updatedAt: now });
    });

    const finalBatch = db.batch();
    finalBatch.set(db.collection(CIRCLES).doc(req.params.id), { ...circleData, updatedAt: now });
    finalBatch.delete(trashRef);
    await finalBatch.commit();

    res.status(200).json({
      success: true,
      message: `Circle restored with ${toRestore.length} place(s)`,
      circle: { _id: req.params.id, ...circleData },
      restoredPlaces: toRestore.length
    });
  } catch (error) {
    console.error('Error restoring circle:', error);
    next(error);
  }
};

// @desc    Permanently delete a circle from trash (removes its places forever)
// @route   DELETE /api/trash/circles/:id
// @access  Private (owner)
exports.permanentDeleteCircle = async (req, res, next) => {
  try {
    const trashRef = db.collection(DELETED_CIRCLES).doc(req.params.id);
    const trashDoc = await trashRef.get();
    if (!trashDoc.exists) {
      return res.status(404).json({ success: false, message: 'Circle not found in trash' });
    }
    if (!isSameUser(trashDoc.data().owner, req.user.uid)) {
      return res.status(403).json({ success: false, message: 'Not authorized to delete this circle' });
    }

    const placesSnap = await db.collection(PLACES).where('circleId', '==', req.params.id).get();
    await batchedUpdate(placesSnap.docs, (batch, doc) => batch.delete(doc.ref));
    await trashRef.delete();

    res.status(200).json({
      success: true,
      message: `Circle and ${placesSnap.size} place(s) permanently deleted`
    });
  } catch (error) {
    console.error('Error permanently deleting circle:', error);
    next(error);
  }
};

// Shared authorization for place trash ops: place adder or the circle's owner.
async function loadDeletedPlace(placeId, uid) {
  const placeRef = db.collection(PLACES).doc(placeId);
  const placeDoc = await placeRef.get();
  if (!placeDoc.exists) return { error: { status: 404, message: 'Place not found' } };
  const place = serialize(placeDoc);
  if (place.deletedAt == null) return { error: { status: 400, message: 'Place is not in trash' } };

  let isCircleOwner = false;
  if (place.circleId) {
    const circleDoc = await db.collection(CIRCLES).doc(place.circleId).get();
    if (circleDoc.exists) isCircleOwner = isSameUser(circleDoc.data().owner, uid);
  }
  if (!isSameUser(place.addedBy, uid) && !isCircleOwner) {
    return { error: { status: 403, message: 'Not authorized' } };
  }
  return { placeRef, place };
}

// @desc    Restore an individually deleted place into its circle
// @route   POST /api/trash/places/:id/restore
// @access  Private (place adder or circle owner)
exports.restorePlace = async (req, res, next) => {
  try {
    const { error, placeRef, place } = await loadDeletedPlace(req.params.id, req.user.uid);
    if (error) return res.status(error.status).json({ success: false, message: error.message });

    // The circle must still exist to restore into.
    const circleRef = db.collection(CIRCLES).doc(place.circleId);
    const circleDoc = await circleRef.get();
    if (!circleDoc.exists) {
      const inTrash = await db.collection(DELETED_CIRCLES).doc(place.circleId).get();
      return res.status(409).json({
        success: false,
        message: inTrash.exists
          ? 'The circle this place belonged to is in the trash — restore the circle first (that also restores its places).'
          : 'The circle this place belonged to no longer exists.'
      });
    }

    const now = new Date().toISOString();
    const circle = circleDoc.data();
    const places = (circle.places || []).includes(req.params.id)
      ? circle.places
      : [...(circle.places || []), req.params.id];

    const batch = db.batch();
    batch.update(placeRef, { deletedAt: null, deletedViaCircleDelete: null, updatedAt: now });
    batch.update(circleRef, {
      places,
      placesCount: (circle.placesCount || 0) + 1,
      updatedAt: now
    });
    await batch.commit();

    res.status(200).json({
      success: true,
      message: 'Place restored',
      place: { ...place, deletedAt: null }
    });
  } catch (error) {
    console.error('Error restoring place:', error);
    next(error);
  }
};

// @desc    Permanently delete a place from trash
// @route   DELETE /api/trash/places/:id
// @access  Private (place adder or circle owner)
exports.permanentDeletePlace = async (req, res, next) => {
  try {
    const { error, placeRef } = await loadDeletedPlace(req.params.id, req.user.uid);
    if (error) return res.status(error.status).json({ success: false, message: error.message });

    await placeRef.delete();
    res.status(200).json({ success: true, message: 'Place permanently deleted' });
  } catch (error) {
    console.error('Error permanently deleting place:', error);
    next(error);
  }
};
