// services/venueClaimApproval.js
//
// Approving an ownership claim: enroll the store when it isn't in the
// program yet, make the claimant its owner, publish its App Clip cards, email
// the approver its QR codes, tell the owner, and close competing claims.
// Moved out of controllers/venues/venueClaimsController (unchanged) so a
// super-user's pre-approved store-setup QR (services/scanActionService) takes
// the same path as the Approve button.
const { getFirestore } = require('../config/firebase');
const { STICKER_COLLECTIONS } = require('../models/StickerModels');
const rewardService = require('./rewardService');
const emailService = require('./emailService');
const { placeVenueFields } = require('./venueEnrollmentService');
const { ServiceError } = require('../utils/serviceError');
const db = getFirestore();

async function readyStoreCodes(venue, adminEmail) {
  require('./appClipExperienceService').publishNewVenueQuiet(venue.venueId);
  if (!adminEmail) return false;
  try {
    const { windowQR, registerQR } = await rewardService.generateQRBuffers(venue);
    await emailService.sendStickerQREmail(adminEmail, venue, windowQR, registerQR);
    return true;
  } catch (emailError) {
    console.error('⚠️ QR email failed (claim still approved):', emailError.message);
    return false;
  }
}

/**
 * Approves the pending claim `claimId` as `approverId`. Throws ServiceError
 * 404 (claim/place/venue gone) or 409 (already resolved / store owned).
 * @returns {Promise<{data: object}>} the approve endpoint's `data`
 */
async function approveClaimById(claimId, { approverId, approverEmail = null }) {
  const claimRef = db.collection(STICKER_COLLECTIONS.VENUE_CLAIM_REQUESTS)
    .doc(claimId);
  const claimDoc = await claimRef.get();
  if (!claimDoc.exists) {
    throw new ServiceError(404, 'not_found', 'Claim not found');
  }
  const claim = claimDoc.data();
  if (claim.status !== 'pending') {
    throw new ServiceError(409, 'already_resolved', `Claim is already ${claim.status}`);
  }

  // Claims on businesses not yet in the sticker program: approving
  // auto-enrolls the venue from the claim's place data, assigns the
  // claimant as owner, and emails the QR codes to the approving admin.
  if (!claim.venueId) {
    // Location/category come from the canonical place (or legacy save)
    const placeFields = (claim.globalPlaceId && await placeVenueFields(claim.globalPlaceId))
      || (claim.placeId && await placeVenueFields(claim.placeId))
      || null;
    if (!placeFields) {
      throw new ServiceError(404, 'not_found', 'The claimed place no longer exists');
    }
    const { location, category } = placeFields;
    // Name and address from the place as it is NOW (the claim holds a copy
    // from the day it was filed); the copy only fills what the place lacks
    const storeName = placeFields.venueName || claim.placeName || claim.venueName;

    const ownerEmail = claim.contactEmail || claim.userEmail || null;
    const venue = await rewardService.createVenue({
      venueName: storeName,
      placeName: storeName,
      placeAddress: placeFields.placeAddress || claim.placeAddress || null,
      googlePlaceId: claim.googlePlaceId || placeFields.googlePlaceId || null,
      globalPlaceId: claim.globalPlaceId || placeFields.globalPlaceId || null,
      location,
      category: category || 'restaurant',
      contactName: claim.contactName || claim.userDisplayName || null,
      contactEmail: ownerEmail
    });

    // The claimant becomes the owner regardless of which email they gave
    // as business contact (it may differ from their account email)
    await rewardService.assignVenueOwner(venue.venueId, {
      ownerUserId: claim.userId,
      ownerEmail
    });
    const emailSent = await readyStoreCodes(venue, approverEmail);

    const now = new Date().toISOString();
    await claimRef.update({
      status: 'approved',
      venueId: venue.venueId,
      resolvedBy: approverId,
      resolvedAt: now,
      updatedAt: now
    });

    // Tell the new owner (in-app + push) — approval otherwise happens silently.
    try {
      const notificationService = require('./notificationService');
      await notificationService.notifyStoreClaimApproved({ ...claim, venueName: storeName, placeName: storeName }, claimRef.id, venue.venueId);
    } catch (notifyError) {
      console.error('⚠️ Claim-approved notification failed:', notifyError.message);
    }

    // And by email — the durable record, plus the Business-tier walkthrough
    if (ownerEmail) {
      emailService.sendClaimApprovedEmail(
        ownerEmail,
        claim.contactName || claim.userDisplayName || null,
        storeName || null
      ).catch((e) => console.error('⚠️ Claim-approved email failed:', e.message));
    }

    // Best-effort: close out competing pending claims for the same place
    try {
      const placeKey = claim.globalPlaceId || claim.googlePlaceId;
      if (placeKey) {
        const field = claim.globalPlaceId ? 'globalPlaceId' : 'googlePlaceId';
        const others = await db.collection(STICKER_COLLECTIONS.VENUE_CLAIM_REQUESTS)
          .where(field, '==', placeKey)
          .get();
        await Promise.all(others.docs
          .filter((doc) => doc.id !== claimRef.id && doc.data().status === 'pending')
          .map((doc) => doc.ref.update({
            status: 'denied',
            resolvedBy: approverId,
            resolvedAt: now,
            updatedAt: now,
            denialReason: 'Another claim was approved'
          })));
      }
    } catch (cleanupError) {
      console.error('⚠️ Failed to close competing claims:', cleanupError.message);
    }

    return {
      data: {
        claim: { claimId: claimRef.id, ...claim, status: 'approved', venueId: venue.venueId, resolvedBy: approverId, resolvedAt: now },
        venueId: venue.venueId,
        ownerEmail,
        enrolled: true,
        emailSent
      }
    };
  }

  const venueDoc = await db.collection(STICKER_COLLECTIONS.STICKER_VENUES)
    .doc(claim.venueId).get();
  if (!venueDoc.exists) {
    throw new ServiceError(404, 'not_found', 'Venue no longer exists');
  }
  const now = new Date().toISOString();

  // The venue may have been assigned an owner (or another claim approved)
  // since this claim was filed — deny rather than silently reassign.
  if (venueDoc.data().ownerUserId) {
    await claimRef.update({
      status: 'denied',
      resolvedBy: approverId,
      resolvedAt: now,
      updatedAt: now,
      denialReason: 'Venue already has an owner'
    });
    throw new ServiceError(409, 'has_owner', 'Venue already has an owner — claim denied');
  }

  await rewardService.assignVenueOwner(claim.venueId, {
    ownerUserId: claim.userId,
    ownerEmail: claim.userEmail || venueDoc.data().ownerEmail
  });
  await claimRef.update({ status: 'approved', resolvedBy: approverId, resolvedAt: now, updatedAt: now });
  const emailSent = await readyStoreCodes({ venueId: claim.venueId, ...venueDoc.data() }, approverEmail);
  // The store as it is called now, not as it was when the claim was filed
  const currentName = venueDoc.data().venueName || venueDoc.data().placeName || claim.venueName || claim.placeName || null;

  // Tell the new owner (in-app + push) — approval otherwise happens silently.
  try {
    const notificationService = require('./notificationService');
    await notificationService.notifyStoreClaimApproved({ ...claim, venueName: currentName, placeName: currentName }, claimRef.id, claim.venueId);
  } catch (notifyError) {
    console.error('⚠️ Claim-approved notification failed:', notifyError.message);
  }

  // And by email — the durable record, plus the Business-tier walkthrough
  const approvedEmail = claim.contactEmail || claim.userEmail;
  if (approvedEmail) {
    emailService.sendClaimApprovedEmail(
      approvedEmail,
      claim.contactName || claim.userDisplayName || null,
      currentName
    ).catch((e) => console.error('⚠️ Claim-approved email failed:', e.message));
  }

  // Best-effort: close out competing pending claims for the same venue
  try {
    const others = await db.collection(STICKER_COLLECTIONS.VENUE_CLAIM_REQUESTS)
      .where('venueId', '==', claim.venueId)
      .get();
    await Promise.all(others.docs
      .filter((doc) => doc.id !== claimRef.id && doc.data().status === 'pending')
      .map((doc) => doc.ref.update({
        status: 'denied',
        resolvedBy: approverId,
        resolvedAt: now,
        updatedAt: now,
        denialReason: 'Another claim was approved'
      })));
  } catch (cleanupError) {
    console.error('⚠️ Failed to close competing claims:', cleanupError.message);
  }

  return {
    data: {
      claim: { claimId: claimRef.id, ...claim, status: 'approved', resolvedBy: approverId, resolvedAt: now },
      venueId: claim.venueId,
      ownerEmail: claim.userEmail || null,
      emailSent
    }
  };
}

module.exports = { approveClaimById, readyStoreCodes };
