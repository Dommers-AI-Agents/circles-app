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
      || 'https://api.favcircles.com';
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

  // Single write path for ownership — used by the super-user assign-by-email
  // endpoint and by claim approval, so both stamp the same fields.
  async assignVenueOwner(venueId, { ownerUserId, ownerEmail }) {
    await this.db.collection(STICKER_COLLECTIONS.STICKER_VENUES)
      .doc(venueId)
      .update({
        ownerUserId,
        ownerEmail: (ownerEmail || '').trim().toLowerCase() || null,
        updatedAt: new Date().toISOString()
      });
  }

  // Announcements shown to place-page visitors: unexpired only, newest first.
  activeAnnouncements(venue) {
    const now = new Date();
    return (venue.announcements || [])
      .filter((a) => !a.expiresAt || new Date(a.expiresAt) > now)
      .sort((a, b) => (b.createdAt || '').localeCompare(a.createdAt || ''));
  }

  // Find the (active) venue for a place the app is showing. Tries the ids the
  // place view has on hand; the last tier covers legacy save-doc ids whose
  // googlePlaceId isn't known client-side.
  async findVenueByPlace(placeId, googlePlaceId) {
    const venues = this.db.collection(STICKER_COLLECTIONS.STICKER_VENUES);
    const lookup = async (field, value) => {
      if (!value) return null;
      const hit = await venues.where(field, '==', value).limit(1).get();
      if (hit.empty) return null;
      const venue = { venueId: hit.docs[0].id, ...hit.docs[0].data() };
      return venue.active === false ? null : venue;
    };

    let venue = await lookup('globalPlaceId', placeId)
      || await lookup('googlePlaceId', placeId)
      || await lookup('googlePlaceId', googlePlaceId);
    if (venue) return venue;

    try {
      const legacyDoc = await this.db.collection(COLLECTIONS.PLACES).doc(placeId).get();
      if (legacyDoc.exists) {
        const legacy = legacyDoc.data();
        venue = await lookup('globalPlaceId', legacy.globalPlaceId)
          || await lookup('googlePlaceId', legacy.googlePlaceId);
      }
    } catch (error) {
      console.error('⚠️ Venue-by-place legacy lookup failed:', error.message);
    }
    return venue || null;
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

    // Per-store loyalty: the venue bucket is the spendable balance — points
    // earned at a shop are only good at that shop. The flat rewardPoints
    // counter stays as the display total (kept equal to the sum of buckets).
    // venueName rides along denormalized so balance reads need no venue fetch.
    const userUpdate = { rewardPoints: FieldValue.increment(points) };
    if (venueId) {
      userUpdate[`rewardPointsByVenue.${venueId}.points`] = FieldValue.increment(points);
      if (venueName) {
        userUpdate[`rewardPointsByVenue.${venueId}.venueName`] = venueName;
      }
    } else {
      // Every live award type is venue-stamped; a venue-less award would mint
      // points spendable nowhere. Loud so a future caller gets caught in dev.
      console.warn(`⚠️ awardPoints without venueId (type=${type}) — points have no shop to be spent at`);
    }
    await this.db.collection(COLLECTIONS.USERS).doc(userId).update(userUpdate);

    return { awarded: true, type, points };
  }

  // { venueId, venueName, points } for every shop where the user holds
  // points, richest first.
  venueBalancesFrom(userData) {
    const byVenue = (userData && userData.rewardPointsByVenue) || {};
    return Object.entries(byVenue)
      .map(([venueId, bucket]) => ({
        venueId,
        venueName: (bucket && bucket.venueName) || '',
        points: (bucket && bucket.points) || 0
      }))
      .filter((v) => v.points > 0)
      .sort((a, b) => b.points - a.points);
  }

  venuePointsFrom(userData, venueId) {
    const bucket = userData && userData.rewardPointsByVenue
      && userData.rewardPointsByVenue[venueId];
    return (bucket && bucket.points) || 0;
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
    const userData = userDoc.exists ? userDoc.data() : {};
    const rewardPoints = userData.rewardPoints || 0;
    const venueBalances = this.venueBalancesFrom(userData);

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

    return { rewardPoints, venueBalances, events };
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

  // ---------- App Clip funnel ----------

  // Stamps acquisition fields on a freshly created user and counts the clip
  // signup for the venue. Attribution must never fail a signup — log and move on.
  // Points are NOT awarded here; the clip's authenticated POST /api/rewards/scan
  // goes through awardStickerSignup like any other scan.
  async attributeClipSignup(userId, stickerCode) {
    try {
      const venue = await this.findVenueByCode(stickerCode);
      const update = {
        acquisitionSource: 'app_clip',
        acquisitionStickerCode: String(stickerCode || '').trim().toUpperCase(),
        acquisitionAt: new Date().toISOString()
      };
      if (venue && venue.active !== false) {
        update.acquisitionVenueId = venue.venueId;
        update.acquisitionVenueName = venue.venueName;
      }
      await this.db.collection(COLLECTIONS.USERS).doc(userId).update(update);
      if (update.acquisitionVenueId) {
        await this.incrementVenueStats(update.acquisitionVenueId, 'clipSignups');
      }
      return { attributed: true, venueId: update.acquisitionVenueId || null };
    } catch (error) {
      console.error(`⚠️ Clip signup attribution failed for ${userId}:`, error.message);
      return { attributed: false };
    }
  }

  // Called by the full app once on first launch after a clip handoff. The
  // transaction makes the conversion count exactly once per user; organic
  // users (no acquisitionSource) resolve to a successful no-op.
  async markClipInstallConverted(userId) {
    const userRef = this.db.collection(COLLECTIONS.USERS).doc(userId);
    const outcome = await this.db.runTransaction(async (tx) => {
      const doc = await tx.get(userRef);
      if (!doc.exists) return { converted: false, reason: 'user_not_found' };
      const data = doc.data();
      if (data.acquisitionSource !== 'app_clip') {
        return { converted: false, reason: 'not_clip_user' };
      }
      if (data.clipInstallConvertedAt) {
        return { converted: false, alreadyConverted: true, venueId: data.acquisitionVenueId || null };
      }
      tx.update(userRef, { clipInstallConvertedAt: new Date().toISOString() });
      return { converted: true, venueId: data.acquisitionVenueId || null };
    });
    if (outcome.converted && outcome.venueId) {
      await this.incrementVenueStats(outcome.venueId, 'clipInstalls');
    }
    return outcome;
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

  // (Share conversions no longer pay store points — they aren't tied to any
  // shop, so under per-store loyalty they had nowhere to be spent. The same
  // trigger already pays the sharer FavCoins via the piggy bank's
  // place_adopted earn; historical share_conversion points were converted to
  // FavCoins by scripts/backfill-per-venue-points.js. Retired 2026-08-10.)

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

    // True per-store loyalty: an offer is paid for with points earned at THAT
    // shop — the venue bucket, not the account-wide total, is what's checked
    // and spent.
    let shortBy = 0;
    try {
      await this.db.runTransaction(async (transaction) => {
        const userDoc = await transaction.get(userRef);
        const balanceHere = this.venuePointsFrom(userDoc.exists ? userDoc.data() : {}, venueId);
        if (balanceHere < offer.pointsCost) {
          shortBy = offer.pointsCost - balanceHere;
          throw new Error('INSUFFICIENT_POINTS');
        }
        transaction.update(userRef, {
          rewardPoints: FieldValue.increment(-offer.pointsCost),
          [`rewardPointsByVenue.${venueId}.points`]: FieldValue.increment(-offer.pointsCost),
          [`rewardPointsByVenue.${venueId}.venueName`]: venue.venueName
        });
        transaction.set(eventRef, event);
      });
    } catch (error) {
      if (error.message === 'INSUFFICIENT_POINTS') {
        return {
          success: false,
          error: `Not enough points at ${venue.venueName} — you need ${shortBy} more. Points are earned and spent per shop.`
        };
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
