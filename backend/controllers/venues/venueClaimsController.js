// controllers/venues/venueClaimsController.js
// Ownership claims: submit (venue/place/details), list, approve, deny
// Split out of rewardController.js (handlers unchanged).
const { getFirestore } = require('../../config/firebase');
const { COLLECTIONS } = require('../../models/FirestoreModels');
const { createVenueClaimRequest, sanitizeKeyPart, STICKER_COLLECTIONS } = require('../../models/StickerModels');
const rewardService = require('../../services/rewardService');
const emailService = require('../../services/emailService');
const db = getFirestore();

// ---------- Ownership claims (filed from a place page) ----------

// Email the admin about a new ownership claim — the approval decision is
// made by a human, so this is the actual verification channel.
const sendClaimAdminEmail = async (claim, claimId) => {
  try {
    const emailService = require('../../services/emailService');
    const adminEmail = process.env.ADMIN_EMAIL || 'wesley@favcircles.com';
    const enrolled = !!claim.venueId;
    const businessName = claim.venueName || claim.placeName || 'Unknown business';
    await emailService.sendEmail({
      to: adminEmail,
      subject: `🏪 Ownership claim: ${businessName}`,
      text: [
        `Someone claimed a business on FavCircles.`,
        ``,
        `Business: ${businessName}`,
        `Address: ${claim.placeAddress || 'unknown'}`,
        enrolled
          ? `Sticker venue: ${claim.venueId} (enrolled — approve from the app's claims tray)`
          : `Sticker venue: not enrolled (verify, then enroll the venue and assign this owner)`,
        `Place ID: ${claim.placeId || 'n/a'} · Global: ${claim.globalPlaceId || 'n/a'} · Google: ${claim.googlePlaceId || 'n/a'}`,
        ``,
        `Claimer account: ${claim.userDisplayName || 'unknown'} (${claim.userEmail || claim.userId})`,
        `Contact name: ${claim.contactName || '-'}`,
        `Contact email: ${claim.contactEmail || '-'}`,
        `Contact phone: ${claim.contactPhone || '-'}`,
        `Message: ${claim.message || '-'}`,
        ``,
        `Claim ID: ${claimId}`
      ].join('\n'),
      html: `
        <h2>🏪 Ownership claim: ${businessName}</h2>
        <p><strong>Address:</strong> ${claim.placeAddress || 'unknown'}<br>
        <strong>Sticker venue:</strong> ${enrolled ? `${claim.venueId} (enrolled — approve from the app's claims tray)` : 'not enrolled — verify, then enroll the venue and assign this owner'}<br>
        <strong>Place ID:</strong> ${claim.placeId || 'n/a'} · <strong>Global:</strong> ${claim.globalPlaceId || 'n/a'} · <strong>Google:</strong> ${claim.googlePlaceId || 'n/a'}</p>
        <p><strong>Claimer account:</strong> ${claim.userDisplayName || 'unknown'} (${claim.userEmail || claim.userId})</p>
        <p><strong>Contact:</strong> ${claim.contactName || '-'} · ${claim.contactEmail || '-'} · ${claim.contactPhone || '-'}</p>
        <p><strong>Message:</strong> ${claim.message || '-'}</p>
        <p><em>Claim ID: ${claimId}</em></p>
      `
    });
  } catch (emailError) {
    console.error('⚠️ Claim admin email failed:', emailError.message);
  }
};

// Shared submit: idempotent on the doc id — a repeat request returns the
// existing pending claim; a denied claim is re-filed in place.
const submitClaim = async (res, claimRef, claimFields) => {
  const existing = await claimRef.get();
  if (existing.exists && existing.data().status === 'pending') {
    return res.json({
      success: true,
      data: { claim: { claimId: existing.id, ...existing.data() } }
    });
  }

  const claim = createVenueClaimRequest(claimFields);
  await claimRef.set(claim);
  await sendClaimAdminEmail(claim, claimRef.id);

  // Alert the admin in-app + push too — email alone is easy to miss.
  try {
    const notificationService = require('../../services/notificationService');
    await notificationService.notifyStoreClaimSubmitted(claim, claimRef.id);
  } catch (notifyError) {
    console.error('⚠️ Claim admin notification failed:', notifyError.message);
  }

  res.status(existing.exists ? 200 : 201).json({
    success: true,
    data: { claim: { claimId: claimRef.id, ...claim } }
  });
};

// @desc    Ask to become the owner of an unclaimed sticker venue.
// @route   POST /api/rewards/venues/:venueId/claim
//          body: { contactName?, contactEmail?, contactPhone?, message? }
// @access  Private
exports.claimVenue = async (req, res) => {
  try {
    const userId = req.user.uid;
    const venueDoc = await db.collection(STICKER_COLLECTIONS.STICKER_VENUES)
      .doc(req.params.venueId).get();
    if (!venueDoc.exists || venueDoc.data().active === false) {
      return res.status(404).json({ success: false, error: 'Venue not found' });
    }
    const venue = { venueId: venueDoc.id, ...venueDoc.data() };
    if (venue.ownerUserId) {
      return res.status(409).json({ success: false, error: 'This business already has an owner' });
    }

    const claimRef = db.collection(STICKER_COLLECTIONS.VENUE_CLAIM_REQUESTS)
      .doc(sanitizeKeyPart(`${venue.venueId}_${userId}`));

    await submitClaim(res, claimRef, {
      venueId: venue.venueId,
      venueName: venue.venueName,
      userId,
      userEmail: req.user.email,
      userDisplayName: req.user.displayName || req.user.name,
      message: req.body?.message,
      contactName: req.body?.contactName,
      contactEmail: req.body?.contactEmail,
      contactPhone: req.body?.contactPhone,
      globalPlaceId: venue.globalPlaceId,
      googlePlaceId: venue.googlePlaceId,
      placeName: venue.placeName,
      placeAddress: venue.placeAddress
    });
  } catch (error) {
    console.error('❌ claimVenue failed:', error);
    res.status(500).json({ success: false, error: 'Failed to submit ownership claim' });
  }
};

// @desc    Claim a business straight from its place page, whether or not it
//          is enrolled in the sticker program. With an enrolled venue this
//          behaves like claimVenue; otherwise the claim records the place
//          and the admin enrolls + assigns after verifying.
// @route   POST /api/rewards/places/:placeId/claim
//          body: { googlePlaceId?, contactName?, contactEmail?, contactPhone?, message? }
// @access  Private
exports.claimPlace = async (req, res) => {
  try {
    const userId = req.user.uid;
    const placeId = req.params.placeId;

    // Enrolled venue? Same path as claimVenue.
    const venue = await rewardService.findVenueByPlace(placeId, req.body?.googlePlaceId);
    if (venue) {
      if (venue.ownerUserId) {
        return res.status(409).json({ success: false, error: 'This business already has an owner' });
      }
      const claimRef = db.collection(STICKER_COLLECTIONS.VENUE_CLAIM_REQUESTS)
        .doc(sanitizeKeyPart(`${venue.venueId}_${userId}`));
      return await submitClaim(res, claimRef, {
        venueId: venue.venueId,
        venueName: venue.venueName,
        userId,
        userEmail: req.user.email,
        userDisplayName: req.user.displayName || req.user.name,
        message: req.body?.message,
        contactName: req.body?.contactName,
        contactEmail: req.body?.contactEmail,
        contactPhone: req.body?.contactPhone,
        globalPlaceId: venue.globalPlaceId,
        googlePlaceId: venue.googlePlaceId,
        placeName: venue.placeName,
        placeAddress: venue.placeAddress
      });
    }

    // No venue: resolve the place itself (save doc id or global id)
    let placeName = null;
    let placeAddress = null;
    let globalPlaceId = null;
    let googlePlaceId = req.body?.googlePlaceId || null;
    const placeDoc = await db.collection(COLLECTIONS.PLACES).doc(placeId).get();
    if (placeDoc.exists) {
      const place = placeDoc.data();
      placeName = place.name;
      placeAddress = place.address;
      globalPlaceId = place.globalPlaceId || null;
      googlePlaceId = place.googlePlaceId || googlePlaceId;
    } else {
      const globalDoc = await db.collection('globalPlaces').doc(placeId).get();
      if (!globalDoc.exists) {
        return res.status(404).json({ success: false, error: 'Place not found' });
      }
      const place = globalDoc.data();
      placeName = place.name;
      placeAddress = place.address;
      globalPlaceId = globalDoc.id;
      googlePlaceId = place.googlePlaceId || googlePlaceId;
    }

    // Any resolved place is claimable — ownership is verified by a human, so
    // Apple-sourced saves without a googlePlaceId are fine. (The place-exists
    // check above already 404'd unresolvable ids.)
    const placeKey = globalPlaceId || googlePlaceId || placeId;
    const claimRef = db.collection(STICKER_COLLECTIONS.VENUE_CLAIM_REQUESTS)
      .doc(sanitizeKeyPart(`place_${placeKey}_${userId}`));

    await submitClaim(res, claimRef, {
      userId,
      userEmail: req.user.email,
      userDisplayName: req.user.displayName || req.user.name,
      message: req.body?.message,
      contactName: req.body?.contactName,
      contactEmail: req.body?.contactEmail,
      contactPhone: req.body?.contactPhone,
      placeId,
      globalPlaceId,
      googlePlaceId,
      placeName,
      placeAddress
    });
  } catch (error) {
    console.error('❌ claimPlace failed:', error);
    res.status(500).json({ success: false, error: 'Failed to submit ownership claim' });
  }
};

// @desc    Add-and-claim: a store owner whose business was never saved by any
//          user submits it by details. Reuses an existing canonical venue
//          record when one matches (name + proximity), otherwise creates one —
//          no personal circle save required — then files the ownership claim.
// @route   POST /api/rewards/businesses/claim
//          body: { name, address, lat, lng, category?, phone?, website?,
//                  applePoiCategory?, contactName, contactEmail,
//                  contactPhone?, message? }
// @access  Private
exports.claimBusinessByDetails = async (req, res) => {
  try {
    const userId = req.user.uid;
    const { name, address, lat, lng } = req.body || {};

    if (!name || !String(name).trim()) {
      return res.status(400).json({ success: false, error: 'Business name is required' });
    }
    if (!address || !String(address).trim()) {
      return res.status(400).json({ success: false, error: 'Business address is required' });
    }
    if (typeof lat !== 'number' || typeof lng !== 'number' ||
        Math.abs(lat) > 90 || Math.abs(lng) > 180) {
      return res.status(400).json({ success: false, error: 'A map location is required' });
    }
    if (!req.body?.contactName || !req.body?.contactEmail) {
      return res.status(400).json({ success: false, error: 'Contact name and business email are required' });
    }

    const location = { type: 'Point', coordinates: [lng, lat] };
    const {
      findCanonicalByNameAndLocation,
      createGlobalPlaceFromDetails
    } = require('../../services/globalPlaceResolver');

    // Reuse the canonical venue if it exists under any name/address variant
    let globalPlaceId;
    let placeName = String(name).trim();
    let placeAddress = String(address).trim();
    const matched = await findCanonicalByNameAndLocation(placeName, location);
    if (matched) {
      globalPlaceId = matched.id;
      placeName = matched.data().name || placeName;
      placeAddress = matched.data().address || placeAddress;
    } else {
      const created = await createGlobalPlaceFromDetails({
        name: placeName,
        address: placeAddress,
        location,
        category: req.body.category || 'other',
        phone: req.body.phone || null,
        website: req.body.website || null,
        applePoiCategory: req.body.applePoiCategory || null
      });
      globalPlaceId = created.resolvedId;
    }

    // Already an enrolled venue? Same guard as claimPlace.
    const venue = await rewardService.findVenueByPlace(globalPlaceId, req.body?.googlePlaceId);
    if (venue && venue.ownerUserId) {
      return res.status(409).json({ success: false, error: 'This business already has an owner' });
    }

    const claimRef = venue
      ? db.collection(STICKER_COLLECTIONS.VENUE_CLAIM_REQUESTS)
          .doc(sanitizeKeyPart(`${venue.venueId}_${userId}`))
      : db.collection(STICKER_COLLECTIONS.VENUE_CLAIM_REQUESTS)
          .doc(sanitizeKeyPart(`place_${globalPlaceId}_${userId}`));

    await submitClaim(res, claimRef, {
      ...(venue ? { venueId: venue.venueId, venueName: venue.venueName } : {}),
      userId,
      userEmail: req.user.email,
      userDisplayName: req.user.displayName || req.user.name,
      message: req.body?.message,
      contactName: req.body.contactName,
      contactEmail: req.body.contactEmail,
      contactPhone: req.body?.contactPhone,
      globalPlaceId,
      googlePlaceId: req.body?.googlePlaceId || null,
      placeName,
      placeAddress
    });
  } catch (error) {
    console.error('❌ claimBusinessByDetails failed:', error);
    res.status(500).json({ success: false, error: 'Failed to submit ownership claim' });
  }
};

// @desc    List ownership claims for review
// @route   GET /api/rewards/claims?status=pending
// @access  Super user
exports.listClaims = async (req, res) => {
  try {
    const status = req.query.status || 'pending';
    // Single equality filter (automatic index); newest first in memory
    const snapshot = await db.collection(STICKER_COLLECTIONS.VENUE_CLAIM_REQUESTS)
      .where('status', '==', status)
      .limit(100)
      .get();
    const claims = snapshot.docs
      .map((doc) => ({ claimId: doc.id, ...doc.data() }))
      .sort((a, b) => (b.createdAt || '').localeCompare(a.createdAt || ''));

    res.json({ success: true, data: { claims, count: claims.length } });
  } catch (error) {
    console.error('❌ listClaims failed:', error);
    res.status(500).json({ success: false, error: 'Failed to load claims' });
  }
};

// @desc    Approve a claim: the claimant becomes the venue's owner and any
//          competing pending claims are denied.
// @route   POST /api/rewards/claims/:claimId/approve
// @access  Super user
exports.approveClaim = async (req, res) => {
  try {
    const claimRef = db.collection(STICKER_COLLECTIONS.VENUE_CLAIM_REQUESTS)
      .doc(req.params.claimId);
    const claimDoc = await claimRef.get();
    if (!claimDoc.exists) {
      return res.status(404).json({ success: false, error: 'Claim not found' });
    }
    const claim = claimDoc.data();
    if (claim.status !== 'pending') {
      return res.status(409).json({ success: false, error: `Claim is already ${claim.status}` });
    }

    // Claims on businesses not yet in the sticker program: approving
    // auto-enrolls the venue from the claim's place data, assigns the
    // claimant as owner, and emails the QR codes to the approving admin.
    if (!claim.venueId) {
      // Resolve location/category from the canonical place (or legacy save)
      let location = null;
      let category = null;
      let placeFound = false;
      if (claim.globalPlaceId) {
        const globalDoc = await db.collection('globalPlaces').doc(claim.globalPlaceId).get();
        if (globalDoc.exists) {
          placeFound = true;
          const coords = globalDoc.data().location?.coordinates; // GeoJSON [lng, lat]
          if (Array.isArray(coords) && coords.length === 2) {
            location = { lat: coords[1], lng: coords[0] };
          }
          category = globalDoc.data().category || null;
        }
      }
      if (!placeFound && claim.placeId) {
        const placeDoc = await db.collection(COLLECTIONS.PLACES).doc(claim.placeId).get();
        if (placeDoc.exists) {
          placeFound = true;
          const coords = placeDoc.data().location?.coordinates;
          if (Array.isArray(coords) && coords.length === 2) {
            location = { lat: coords[1], lng: coords[0] };
          }
          category = placeDoc.data().category || null;
        }
      }
      if (!placeFound) {
        return res.status(404).json({ success: false, error: 'The claimed place no longer exists' });
      }

      const ownerEmail = claim.contactEmail || claim.userEmail || null;
      const venue = await rewardService.createVenue({
        venueName: claim.placeName || claim.venueName,
        placeName: claim.placeName || claim.venueName,
        placeAddress: claim.placeAddress || null,
        googlePlaceId: claim.googlePlaceId || null,
        globalPlaceId: claim.globalPlaceId || null,
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

      // QR codes go to the approving admin for printing — best-effort
      let emailSent = false;
      if (req.user.email) {
        try {
          const { windowQR, registerQR } = await rewardService.generateQRBuffers(venue);
          await emailService.sendStickerQREmail(req.user.email, venue, windowQR, registerQR);
          emailSent = true;
        } catch (emailError) {
          console.error('⚠️ QR email failed (venue still enrolled):', emailError.message);
        }
      }

      const now = new Date().toISOString();
      await claimRef.update({
        status: 'approved',
        venueId: venue.venueId,
        resolvedBy: req.user.uid,
        resolvedAt: now,
        updatedAt: now
      });

      // Tell the new owner (in-app + push) — approval otherwise happens silently.
      try {
        const notificationService = require('../../services/notificationService');
        await notificationService.notifyStoreClaimApproved(claim, claimRef.id, venue.venueId);
      } catch (notifyError) {
        console.error('⚠️ Claim-approved notification failed:', notifyError.message);
      }

      // And by email — the durable record, plus the Business-tier walkthrough
      if (ownerEmail) {
        emailService.sendClaimApprovedEmail(
          ownerEmail,
          claim.contactName || claim.userDisplayName || null,
          claim.placeName || claim.venueName || null
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
              resolvedBy: req.user.uid,
              resolvedAt: now,
              updatedAt: now,
              denialReason: 'Another claim was approved'
            })));
        }
      } catch (cleanupError) {
        console.error('⚠️ Failed to close competing claims:', cleanupError.message);
      }

      return res.json({
        success: true,
        data: {
          claim: { claimId: claimRef.id, ...claim, status: 'approved', venueId: venue.venueId, resolvedBy: req.user.uid, resolvedAt: now },
          venueId: venue.venueId,
          ownerEmail,
          enrolled: true,
          emailSent
        }
      });
    }

    const venueDoc = await db.collection(STICKER_COLLECTIONS.STICKER_VENUES)
      .doc(claim.venueId).get();
    if (!venueDoc.exists) {
      return res.status(404).json({ success: false, error: 'Venue no longer exists' });
    }
    const now = new Date().toISOString();

    // The venue may have been assigned an owner (or another claim approved)
    // since this claim was filed — deny rather than silently reassign.
    if (venueDoc.data().ownerUserId) {
      await claimRef.update({
        status: 'denied',
        resolvedBy: req.user.uid,
        resolvedAt: now,
        updatedAt: now,
        denialReason: 'Venue already has an owner'
      });
      return res.status(409).json({ success: false, error: 'Venue already has an owner — claim denied' });
    }

    await rewardService.assignVenueOwner(claim.venueId, {
      ownerUserId: claim.userId,
      ownerEmail: claim.userEmail || venueDoc.data().ownerEmail
    });
    await claimRef.update({ status: 'approved', resolvedBy: req.user.uid, resolvedAt: now, updatedAt: now });

    // Tell the new owner (in-app + push) — approval otherwise happens silently.
    try {
      const notificationService = require('../../services/notificationService');
      await notificationService.notifyStoreClaimApproved(claim, claimRef.id, claim.venueId);
    } catch (notifyError) {
      console.error('⚠️ Claim-approved notification failed:', notifyError.message);
    }

    // And by email — the durable record, plus the Business-tier walkthrough
    const approvedEmail = claim.contactEmail || claim.userEmail;
    if (approvedEmail) {
      emailService.sendClaimApprovedEmail(
        approvedEmail,
        claim.contactName || claim.userDisplayName || null,
        claim.venueName || claim.placeName || null
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
          resolvedBy: req.user.uid,
          resolvedAt: now,
          updatedAt: now,
          denialReason: 'Another claim was approved'
        })));
    } catch (cleanupError) {
      console.error('⚠️ Failed to close competing claims:', cleanupError.message);
    }

    res.json({
      success: true,
      data: {
        claim: { claimId: claimRef.id, ...claim, status: 'approved', resolvedBy: req.user.uid, resolvedAt: now },
        venueId: claim.venueId,
        ownerEmail: claim.userEmail || null
      }
    });
  } catch (error) {
    console.error('❌ approveClaim failed:', error);
    res.status(500).json({ success: false, error: 'Failed to approve claim' });
  }
};

// @desc    Deny a claim, optionally with a reason shown to the claimant
// @route   POST /api/rewards/claims/:claimId/deny
// @access  Super user
exports.denyClaim = async (req, res) => {
  try {
    const claimRef = db.collection(STICKER_COLLECTIONS.VENUE_CLAIM_REQUESTS)
      .doc(req.params.claimId);
    const claimDoc = await claimRef.get();
    if (!claimDoc.exists) {
      return res.status(404).json({ success: false, error: 'Claim not found' });
    }
    if (claimDoc.data().status !== 'pending') {
      return res.status(409).json({ success: false, error: `Claim is already ${claimDoc.data().status}` });
    }

    const now = new Date().toISOString();
    const update = {
      status: 'denied',
      resolvedBy: req.user.uid,
      resolvedAt: now,
      updatedAt: now,
      denialReason: (req.body?.reason || '').trim() || null
    };
    await claimRef.update(update);

    res.json({ success: true, data: { claim: { claimId: claimRef.id, ...claimDoc.data(), ...update } } });
  } catch (error) {
    console.error('❌ denyClaim failed:', error);
    res.status(500).json({ success: false, error: 'Failed to deny claim' });
  }
};
