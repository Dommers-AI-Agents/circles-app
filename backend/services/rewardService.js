// backend/services/rewardService.js
// Points ledger + venue stats for the sticker rewards program.
// Singleton, following the milestoneService pattern.

const { getFirestore, FieldValue } = require('../config/firebase');
const QRCode = require('qrcode');
const { Client } = require('@googlemaps/google-maps-services-js');
const { googleMapsApiKey } = require('../config/config');
const { COLLECTIONS } = require('../models/FirestoreModels');
const {
  STICKER_COLLECTIONS,
  createStickerVenue,
  createRewardEvent,
  sanitizeKeyPart
} = require('../models/StickerModels');
const rewardConfig = require('../config/rewardConfig');

const CODE_CHARS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

class RewardService {
  get db() {
    return getFirestore();
  }

  // ---------- Venue codes ----------

  randomCode() {
    let code = '';
    for (let i = 0; i < rewardConfig.CODE_LENGTH; i++) {
      code += CODE_CHARS.charAt(Math.floor(Math.random() * CODE_CHARS.length));
    }
    return code;
  }

  async codeInUse(code) {
    const venues = this.db.collection(STICKER_COLLECTIONS.STICKER_VENUES);
    const [windowHit, registerHit] = await Promise.all([
      venues.where('windowCode', '==', code).limit(1).get(),
      venues.where('registerCode', '==', code).limit(1).get()
    ]);
    return !(windowHit.empty && registerHit.empty);
  }

  async generateUniqueCode() {
    for (let attempt = 0; attempt < 10; attempt++) {
      const code = this.randomCode();
      if (!(await this.codeInUse(code))) return code;
    }
    throw new Error('Failed to generate a unique sticker code');
  }

  // Resolve a googlePlaceId from name + address/coordinates so venues created
  // from the phone (MapKit search has no Google IDs) still match place saves.
  async resolveGooglePlaceId(name, address, lat, lng) {
    if (!googleMapsApiKey) return null;
    try {
      const client = new Client({});
      const params = {
        input: [name, address].filter(Boolean).join(', '),
        inputtype: 'textquery',
        fields: ['place_id'],
        key: googleMapsApiKey
      };
      if (typeof lat === 'number' && typeof lng === 'number') {
        params.locationbias = `circle:250@${lat},${lng}`;
      }
      const response = await client.findPlaceFromText({ params });
      return response.data.candidates?.[0]?.place_id || null;
    } catch (error) {
      console.error('⚠️ googlePlaceId resolution failed:', error.message);
      return null;
    }
  }

  stickerUrl(code) {
    const baseUrl = process.env.STICKER_LINK_BASE_URL
      || 'https://circles-backend-196924649787.us-central1.run.app';
    return `${baseUrl}/s/${code}`;
  }

  // Print-resolution QR PNG buffers for both codes (1200px, error correction H)
  async generateQRBuffers(venue) {
    const options = {
      errorCorrectionLevel: 'H',
      width: 1200,
      margin: 4,
      color: { dark: '#000000', light: '#FFFFFF' }
    };
    const [windowQR, registerQR] = await Promise.all([
      QRCode.toBuffer(this.stickerUrl(venue.windowCode), options),
      QRCode.toBuffer(this.stickerUrl(venue.registerCode), options)
    ]);
    return { windowQR, registerQR };
  }

  async createVenue(data) {
    const windowCode = await this.generateUniqueCode();
    let registerCode;
    do {
      registerCode = await this.generateUniqueCode();
    } while (registerCode === windowCode);

    const venue = createStickerVenue(data, windowCode, registerCode);
    // Link the venue to its owner's account when the contact email matches an
    // existing user; otherwise getMyVenues lazily claims it by email later.
    if (!venue.ownerUserId && venue.ownerEmail) {
      venue.ownerUserId = await this.resolveOwnerUserId(venue.ownerEmail);
    }
    const ref = await this.db.collection(STICKER_COLLECTIONS.STICKER_VENUES).add(venue);
    return { venueId: ref.id, ...venue };
  }

  async resolveOwnerUserId(email) {
    const normalized = String(email || '').trim().toLowerCase();
    if (!normalized) return null;
    try {
      const snapshot = await this.db.collection(COLLECTIONS.USERS)
        .where('email', '==', normalized)
        .limit(1)
        .get();
      return snapshot.empty ? null : snapshot.docs[0].id;
    } catch (error) {
      console.error('⚠️ Owner lookup by email failed:', error.message);
      return null;
    }
  }

  // Replace the register card's code (e.g. after a leak, or to bind a new
  // points value to a freshly printed card). The old code stops resolving
  // immediately because scans look venues up by field value.
  async rotateRegisterCode(venue, earnRate) {
    let registerCode;
    do {
      registerCode = await this.generateUniqueCode();
    } while (registerCode === venue.windowCode);

    const update = { registerCode, updatedAt: new Date().toISOString() };
    if (Number.isInteger(earnRate) && earnRate > 0) {
      update.earnRate = earnRate;
    }
    await this.db.collection(STICKER_COLLECTIONS.STICKER_VENUES)
      .doc(venue.venueId).update(update);
    return registerCode;
  }

  // Returns { venueId, kind: 'window' | 'register', ...venueData } or null
  async findVenueByCode(code) {
    const normalized = String(code || '').trim().toUpperCase();
    if (!normalized) return null;

    const venues = this.db.collection(STICKER_COLLECTIONS.STICKER_VENUES);
    const windowHit = await venues.where('windowCode', '==', normalized).limit(1).get();
    if (!windowHit.empty) {
      const doc = windowHit.docs[0];
      return { venueId: doc.id, kind: 'window', ...doc.data() };
    }
    const registerHit = await venues.where('registerCode', '==', normalized).limit(1).get();
    if (!registerHit.empty) {
      const doc = registerHit.docs[0];
      return { venueId: doc.id, kind: 'register', ...doc.data() };
    }
    return null;
  }

  // ---------- Ledger ----------

  currentMonthKey() {
    return new Date().toISOString().slice(0, 7); // "2026-07"
  }

  async incrementVenueStats(venueId, field, amount = 1) {
    if (!venueId) return;
    try {
      const monthKey = this.currentMonthKey();
      await this.db.collection(STICKER_COLLECTIONS.STICKER_VENUES).doc(venueId).update({
        [`stats.${field}`]: FieldValue.increment(amount),
        [`statsMonthly.${monthKey}.${field}`]: FieldValue.increment(amount),
        updatedAt: new Date().toISOString()
      });
    } catch (error) {
      console.error(`⚠️ Failed to increment venue stat ${field} for ${venueId}:`, error.message);
    }
  }

  // Awards points exactly once per idempotencyKey.
  // Returns { awarded: true, points } or { awarded: false, duplicate: true }.
  async awardPoints({ userId, type, points, idempotencyKey, venueId, venueName, code, googlePlaceId, sourceUserId }) {
    const eventRef = this.db
      .collection(STICKER_COLLECTIONS.REWARD_EVENTS)
      .doc(sanitizeKeyPart(idempotencyKey));

    const event = createRewardEvent({
      userId, type, points, venueId, venueName, code, googlePlaceId, sourceUserId
    });

    try {
      if (typeof eventRef.create === 'function') {
        await eventRef.create(event); // fails with ALREADY_EXISTS on duplicates
      } else {
        // Mock Firestore in dev has no .create()
        await eventRef.set(event);
      }
    } catch (error) {
      if (error.code === 6 || /already exists/i.test(error.message || '')) {
        return { awarded: false, duplicate: true };
      }
      throw error;
    }

    await this.db.collection(COLLECTIONS.USERS).doc(userId).update({
      rewardPoints: FieldValue.increment(points)
    });

    return { awarded: true, type, points };
  }

  // Which of these googlePlaceIds has the user saved? Same semantics as the
  // controller's userHasSavedVenuePlace (legacy `places` collection), batched
  // with `in` queries (Firestore limit: 30 values per query).
  async getSavedVenuePlaceIds(userId, googlePlaceIds) {
    const saved = new Set();
    const distinct = [...new Set((googlePlaceIds || []).filter(Boolean))];
    const chunks = [];
    for (let i = 0; i < distinct.length; i += 30) {
      chunks.push(distinct.slice(i, i + 30));
    }
    await Promise.all(chunks.map(async (chunk) => {
      try {
        const snapshot = await this.db.collection(COLLECTIONS.PLACES)
          .where('addedBy', '==', userId)
          .where('deletedAt', '==', null)
          .where('googlePlaceId', 'in', chunk)
          .get();
        snapshot.docs.forEach((doc) => saved.add(doc.data().googlePlaceId));
      } catch (error) {
        console.error('⚠️ Saved-place batch lookup failed:', error.message);
      }
    }));
    return saved;
  }

  async getBalance(userId) {
    const userDoc = await this.db.collection(COLLECTIONS.USERS).doc(userId).get();
    const rewardPoints = (userDoc.exists && userDoc.data().rewardPoints) || 0;

    let events = [];
    try {
      const snapshot = await this.db
        .collection(STICKER_COLLECTIONS.REWARD_EVENTS)
        .where('userId', '==', userId)
        .orderBy('createdAt', 'desc')
        .limit(25)
        .get();
      events = snapshot.docs.map((doc) => ({ id: doc.id, ...doc.data() }));
    } catch (error) {
      // Composite index may still be building; balance is more important than history
      console.error('⚠️ Failed to load reward history:', error.message);
    }

    return { rewardPoints, events };
  }

  // ---------- Earning rules ----------

  isWithinSignupWindow(userData) {
    if (!userData || !userData.createdAt) return false;
    const createdAt = new Date(userData.createdAt).getTime();
    if (Number.isNaN(createdAt)) return false;
    const windowMs = rewardConfig.SIGNUP_WINDOW_DAYS * 24 * 60 * 60 * 1000;
    return Date.now() - createdAt <= windowMs;
  }

  async awardStickerSignup(userId, venue) {
    const userDoc = await this.db.collection(COLLECTIONS.USERS).doc(userId).get();
    if (!userDoc.exists || !this.isWithinSignupWindow(userDoc.data())) {
      return { awarded: false, reason: 'not_new_user' };
    }
    const result = await this.awardPoints({
      userId,
      type: 'sticker_signup',
      points: rewardConfig.POINTS.STICKER_SIGNUP,
      idempotencyKey: `signup:${userId}`, // once per user, ever
      venueId: venue.venueId,
      venueName: venue.venueName,
      code: venue.windowCode,
      googlePlaceId: venue.googlePlaceId
    });
    if (result.awarded) {
      await this.incrementVenueStats(venue.venueId, 'signups');
    }
    return result;
  }

  async awardStickerSave(userId, venue) {
    const result = await this.awardPoints({
      userId,
      type: 'sticker_save',
      points: rewardConfig.POINTS.STICKER_SAVE,
      idempotencyKey: `save:${userId}:${venue.venueId}`,
      venueId: venue.venueId,
      venueName: venue.venueName,
      code: venue.windowCode,
      googlePlaceId: venue.googlePlaceId
    });
    if (result.awarded) {
      await this.incrementVenueStats(venue.venueId, 'saves');
    }
    return result;
  }

  // Points per register-code (purchase) scan; legacy venues have no earnRate
  effectiveEarnRate(venue) {
    return Number.isInteger(venue.earnRate) && venue.earnRate > 0
      ? venue.earnRate
      : rewardConfig.POINTS.VENUE_VISIT;
  }

  // Register-code (purchase) scan. Possession of the physical card is the
  // security model — no GPS check. The once-per-venue-per-day idempotency key
  // plus owner-initiated code rotation are the abuse backstops.
  // Returns { awarded, reason? }.
  async awardVenueVisit(userId, venue) {
    const day = new Date().toISOString().slice(0, 10);
    const result = await this.awardPoints({
      userId,
      type: 'venue_visit',
      points: this.effectiveEarnRate(venue),
      idempotencyKey: `visit:${userId}:${venue.venueId}:${day}`, // 1/venue/day
      venueId: venue.venueId,
      venueName: venue.venueName,
      code: venue.registerCode,
      googlePlaceId: venue.googlePlaceId
    });
    if (result.awarded) {
      await this.incrementVenueStats(venue.venueId, 'visits');
    } else if (result.duplicate) {
      result.reason = 'already_today';
    }
    return result;
  }

  // Fire-and-forget hook called from place creation when a refUserId is present.
  async awardShareConversion(sharerUserId, adderUserId, googlePlaceId) {
    try {
      if (!sharerUserId || !adderUserId || sharerUserId === adderUserId) return;
      const placeKey = sanitizeKeyPart(googlePlaceId || 'manual');
      const sharerDoc = await this.db.collection(COLLECTIONS.USERS).doc(sharerUserId).get();
      if (!sharerDoc.exists) return;

      await this.awardPoints({
        userId: sharerUserId,
        type: 'share_conversion',
        points: rewardConfig.POINTS.SHARE_CONVERSION,
        idempotencyKey: `share:${sharerUserId}:${adderUserId}:${placeKey}`,
        googlePlaceId: googlePlaceId || null,
        sourceUserId: adderUserId
      });
    } catch (error) {
      console.error('⚠️ Share conversion award failed:', error.message);
    }
  }

  // ---------- Redemption ----------

  generateVoucherCode() {
    let code = '';
    for (let i = 0; i < 4; i++) {
      code += CODE_CHARS.charAt(Math.floor(Math.random() * CODE_CHARS.length));
    }
    return code;
  }

  // Atomically checks balance, deducts points, and issues a timed voucher.
  async redeemOffer(userId, venueId, offerId) {
    const venueDoc = await this.db.collection(STICKER_COLLECTIONS.STICKER_VENUES).doc(venueId).get();
    if (!venueDoc.exists) {
      return { success: false, error: 'Venue not found' };
    }
    const venue = venueDoc.data();
    const offer = (venue.offers || []).find((o) => o.offerId === offerId && o.active !== false);
    if (!offer) {
      return { success: false, error: 'Offer not found or inactive' };
    }

    const userRef = this.db.collection(COLLECTIONS.USERS).doc(userId);
    const expiresAt = new Date(Date.now() + rewardConfig.VOUCHER_TTL_MINUTES * 60 * 1000).toISOString();
    const voucherCode = this.generateVoucherCode();
    const eventRef = this.db
      .collection(STICKER_COLLECTIONS.REWARD_EVENTS)
      .doc(sanitizeKeyPart(`redeem:${userId}:${venueId}:${offerId}:${Date.now()}`));

    const event = createRewardEvent({
      userId,
      type: 'redemption',
      points: -offer.pointsCost,
      venueId,
      venueName: venue.venueName,
      offerId: offer.offerId,
      offerTitle: offer.title,
      voucherCode,
      expiresAt,
      status: 'issued'
    });

    try {
      await this.db.runTransaction(async (transaction) => {
        const userDoc = await transaction.get(userRef);
        const balance = (userDoc.exists && userDoc.data().rewardPoints) || 0;
        if (balance < offer.pointsCost) {
          throw new Error('INSUFFICIENT_POINTS');
        }
        transaction.update(userRef, { rewardPoints: FieldValue.increment(-offer.pointsCost) });
        transaction.set(eventRef, event);
      });
    } catch (error) {
      if (error.message === 'INSUFFICIENT_POINTS') {
        return { success: false, error: 'Not enough points for this offer' };
      }
      throw error;
    }

    await this.incrementVenueStats(venueId, 'redemptions');

    return {
      success: true,
      voucher: {
        voucherCode,
        offerTitle: offer.title,
        pointsCost: offer.pointsCost,
        venueName: venue.venueName,
        expiresAt
      }
    };
  }
}

module.exports = new RewardService();
