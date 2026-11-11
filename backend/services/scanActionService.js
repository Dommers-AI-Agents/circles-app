// backend/services/scanActionService.js
//
// Scan Actions (Wes, 2026-11-11, at brunch): "scan this QR and it adds this
// place to your profile". A QR holds one short link,
// https://api.favcircles.com/q/<code>; the server keeps what the code does (a
// recipe) and the app or App Clip runs it:
//
//   place       one place → the scanner picks a circle → saved
//   placeSet    a frozen list of places (a filtered circle or Home view) →
//               the scanner ticks which to keep, picks a circle → saved
//   storeSetup  a super-user's QR for one store: whoever redeems it first
//               becomes its owner (pre-approved), then the rewards setup
//   guides      fixed codes from config/scanGuides (no doc, never expire)
//
// What a QR hands over is the VENUE (name, address, spot, category, a public
// photo), never anyone's notes. A creator may only put a place in a QR when
// they can see it, and a spot no map source knows (a home, a hand-named
// address) only when it isn't private. Venues waiting for approval never go.
// Saves go through the core save (placeSaveService), so the one-venue rule,
// the duplicate check across circles, approval and FavCoins all apply.

const crypto = require('crypto');
const { getFirestore, FieldValue } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');
const { GLOBAL_COLLECTIONS } = require('../models/GlobalPlace');
const { STICKER_COLLECTIONS, createVenueClaimRequest, sanitizeKeyPart } = require('../models/StickerModels');
const { ServiceError } = require('../utils/serviceError');
const { getDocsById } = require('../utils/batchGet');
const { scanGuide } = require('../config/scanGuides');
const visibility = require('./visibility');
const { isHiddenVenue, needsApproval } = require('./placeApproval');

const COLLECTION = 'scanActions';
const PUBLIC_BASE_URL = process.env.API_PUBLIC_BASE_URL || 'https://api.favcircles.com';

// No 0/O, 1/I/L: a code someone reads aloud or types from a printout
const ALPHABET = '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
const CODE_LENGTH = 8;
const CODE_RE = /^[23456789ABCDEFGHJKMNPQRSTUVWXYZ]{8}$/;

const DAY_MS = 24 * 60 * 60 * 1000;
const LIFETIME_DAYS = { place: 30, placeSet: 30, storeSetup: 14 };
const MAX_SET_PLACES = 50;
const MAX_NOTE = 200;
const MAX_TITLE = 80;

const urlFor = (code) => `${PUBLIC_BASE_URL}/q/${code}`;

function newCode() {
  let code = '';
  for (let i = 0; i < CODE_LENGTH; i += 1) code += ALPHABET[crypto.randomInt(ALPHABET.length)];
  return code;
}

/** A code as typed or scanned → its canonical form, or null. Pure. */
function normalizeCode(raw) {
  const text = String(raw || '').trim();
  if (scanGuide(text)) return text.toLowerCase();
  const upper = text.toUpperCase();
  return CODE_RE.test(upper) ? upper : null;
}

const isLive = (data) => !!data && (data.deletedAt === null || data.deletedAt === undefined);
const clip = (text, max) => (typeof text === 'string' ? text.trim().slice(0, max) : '');

const coordsOf = (location) => {
  if (!location) return null;
  if (Array.isArray(location.coordinates) && location.coordinates.length === 2) {
    return { lat: Number(location.coordinates[1]), lng: Number(location.coordinates[0]) };
  }
  if (Number.isFinite(location.latitude) && Number.isFinite(location.longitude)) {
    return { lat: location.latitude, lng: location.longitude };
  }
  if (Number.isFinite(location.lat) && Number.isFinite(location.lng)) return { lat: location.lat, lng: location.lng };
  return null;
};

/** A place a map source knows (Google listing, Apple Maps place): a business, not someone's home. Pure. */
const isKnownVenue = (venue, save) =>
  !!((venue && (venue.googlePlaceId || venue.applePlaceId))
    || (save && (save.applePlaceId || save.appleMatched === true || !needsApproval(save))));

/**
 * May `creatorId` put this save's venue in a QR? Pure.
 * @returns {'ok'|'hidden'|'private'} hidden = can't see it / venue held for approval
 */
function shareVerdict({ save, circle, venue, creatorId, ctx }) {
  if (!save || !isLive(save) || !venue) return 'hidden';
  if (isHiddenVenue(venue)) return 'hidden';
  if (!visibility.canSeePlace(save, circle, creatorId, ctx)) return 'hidden';
  if (isKnownVenue(venue, save)) return 'ok';
  // A spot no map knows: shareable only when it isn't private to its saver
  if (visibility.canSeePlace(save, circle, null, null)) return 'ok';
  const own = String(save.addedBy || '') === String(creatorId || '');
  const tier = visibility.followsCircle(save) ? (circle && circle.privacy) : save.privacy;
  return own && visibility.normalizePrivacy(tier) !== 'private' ? 'ok' : 'private';
}

/** The card a scanner sees for a venue: venue fields only. Pure. */
function placeCard(venueId, venue) {
  const placePhotos = require('./placePhotoService');
  const photo = placePhotos.visiblePhotos(venue.photos || [], null)[0];
  const spot = coordsOf(venue.location);
  return {
    globalPlaceId: venueId,
    name: venue.name || 'A place',
    address: venue.address || null,
    category: venue.category || null,
    photoUrl: photo ? placePhotos.urlOf(photo) : null,
    location: spot,
    googlePlaceId: venue.googlePlaceId || null,
    applePlaceId: venue.applePlaceId || null
  };
}

class ScanActionService {
  constructor({ db, savePlace, approveClaim, buildViewerContext, defaultCircle, now } = {}) {
    this._db = db;
    this._savePlace = savePlace;
    this._approveClaim = approveClaim;
    this._buildViewerContext = buildViewerContext;
    this._defaultCircle = defaultCircle;
    this._now = now || (() => Date.now());
  }

  get db() { return this._db || getFirestore(); }
  get col() { return this.db.collection(COLLECTION); }
  savePlace(...args) { return (this._savePlace || require('./placeSaveService').savePlace)(...args); }
  approveClaim(...args) { return (this._approveClaim || require('./venueClaimApproval').approveClaimById)(...args); }
  viewerContext(uid) { return (this._buildViewerContext || require('./viewerContext').buildViewerContext)(uid); }
  defaultCircle(uid) { return (this._defaultCircle || defaultCircleFor)(uid); }

  async uniqueCode() {
    for (let i = 0; i < 6; i += 1) {
      const code = newCode();
      const doc = await this.col.doc(code).get();
      if (!doc.exists) return code;
    }
    throw new ServiceError(503, 'code_unavailable', 'Could not make a code. Try again.');
  }

  /**
   * The venues behind the creator's picks, each judged shareable or not.
   * `saveIds` are `places` docs; `globalPlaceIds` venues straight from the
   * catalog (search results), which must be known, approved businesses.
   */
  async judgePicks({ saveIds = [], globalPlaceIds = [] }, creatorId) {
    const saves = await getDocsById(COLLECTIONS.PLACES, saveIds, { db: this.db });
    const circleIds = [...saves.values()].map((d) => d.data().circleId).filter(Boolean);
    const venueIds = [
      ...[...saves.values()].map((d) => d.data().globalPlaceId).filter(Boolean),
      ...globalPlaceIds
    ];
    const [circles, venues, ctx] = await Promise.all([
      getDocsById(COLLECTIONS.CIRCLES, circleIds, { db: this.db }),
      getDocsById(GLOBAL_COLLECTIONS.GLOBAL_PLACES, venueIds, { db: this.db }),
      this.viewerContext(creatorId)
    ]);

    const picked = new Map(); // venueId → card, in the creator's order
    let leftOutPrivate = 0;
    let leftOutHidden = 0;
    for (const saveId of saveIds) {
      const doc = saves.get(String(saveId));
      const save = doc ? doc.data() : null;
      const venueDoc = save && save.globalPlaceId ? venues.get(String(save.globalPlaceId)) : null;
      const circleDoc = save && save.circleId ? circles.get(String(save.circleId)) : null;
      const verdict = shareVerdict({
        save, circle: circleDoc ? circleDoc.data() : null, venue: venueDoc ? venueDoc.data() : null, creatorId, ctx
      });
      if (verdict === 'ok') {
        if (!picked.has(venueDoc.id)) picked.set(venueDoc.id, placeCard(venueDoc.id, venueDoc.data()));
      } else if (verdict === 'private') leftOutPrivate += 1;
      else leftOutHidden += 1;
    }
    for (const venueId of globalPlaceIds) {
      const venueDoc = venues.get(String(venueId));
      const venue = venueDoc ? venueDoc.data() : null;
      const ok = venue && !isHiddenVenue(venue) && (isKnownVenue(venue, null) || venue.approvalStatus === 'approved');
      if (ok) {
        if (!picked.has(venueDoc.id)) picked.set(venueDoc.id, placeCard(venueDoc.id, venue));
      } else leftOutHidden += 1;
    }
    return { cards: [...picked.values()], leftOutPrivate, leftOutHidden };
  }

  async creatorProfile(uid) {
    const doc = await this.db.collection(COLLECTIONS.USERS).doc(String(uid)).get();
    const data = doc.exists ? doc.data() : {};
    return {
      id: String(uid),
      displayName: data.displayName || 'A FavCircles member',
      profilePicture: data.profilePicture || null,
      email: data.email || null
    };
  }

  /**
   * Makes a QR. `user` is req.user.
   *   place:      { saveId and/or globalPlaceId (the venue, when the save isn't one), note? }
   *   placeSet:   { title, saveIds?: [], globalPlaceIds?: [], source?: {circleId?, category?, tag?, connectionId?} }
   *   storeSetup: { venueId | globalPlaceId }   (super-users only)
   * @returns {{code, url, kind, expiresAt, places, leftOutPrivate, leftOutHidden}}
   */
  async create(user, { kind, ...input } = {}) {
    if (!user || !user.uid) throw new ServiceError(401, 'unauthorized', 'Sign in first');
    const nowMs = this._now();
    const base = {
      kind,
      createdBy: user.uid,
      createdAt: new Date(nowMs).toISOString(),
      scans: 0,
      saves: 0
    };

    let doc;
    let result = { leftOutPrivate: 0, leftOutHidden: 0, places: [] };
    if (kind === 'place' || kind === 'placeSet') {
      const saveIds = (kind === 'place' ? [input.saveId] : (input.saveIds || [])).filter(Boolean).map(String);
      const globalPlaceIds = (kind === 'place' ? (input.saveId ? [] : [input.globalPlaceId]) : (input.globalPlaceIds || [])).filter(Boolean).map(String);
      if (kind === 'place' && saveIds.length + globalPlaceIds.length !== 1) {
        throw new ServiceError(400, 'invalid_place', 'Pick one place');
      }
      if (saveIds.length + globalPlaceIds.length > MAX_SET_PLACES) {
        throw new ServiceError(400, 'too_many_places', `A QR holds up to ${MAX_SET_PLACES} places`, { max: MAX_SET_PLACES });
      }
      let judged = await this.judgePicks({ saveIds, globalPlaceIds }, user.uid);
      // A place page can show the venue itself rather than a save: its id
      // then names no save, and the venue (a known business) goes instead
      if (kind === 'place' && judged.cards.length === 0 && judged.leftOutPrivate === 0 && input.saveId && input.globalPlaceId) {
        judged = await this.judgePicks({ globalPlaceIds: [String(input.globalPlaceId)] }, user.uid);
      }
      if (judged.cards.length === 0) {
        const allPrivate = judged.leftOutPrivate > 0 && judged.leftOutHidden === 0;
        throw new ServiceError(400, allPrivate ? 'all_private' : 'nothing_to_share',
          allPrivate ? 'That place is private, so it can’t go in a QR' : 'There’s nothing here to share',
          { leftOutPrivate: judged.leftOutPrivate, leftOutHidden: judged.leftOutHidden });
      }
      const source = input.source && typeof input.source === 'object' ? input.source : {};
      doc = {
        ...base,
        expiresAt: new Date(nowMs + LIFETIME_DAYS[kind] * DAY_MS).toISOString(),
        title: kind === 'placeSet' ? (clip(input.title, MAX_TITLE) || 'Places') : judged.cards[0].name,
        note: kind === 'place' ? (clip(input.note, MAX_NOTE) || null) : null,
        // Frozen at creation: the scanner gets what the creator saw, never
        // their filters re-run against the creator's live data
        places: judged.cards,
        source: {
          circleId: source.circleId ? String(source.circleId) : null,
          category: source.category ? String(source.category).slice(0, 40) : null,
          tag: source.tag ? String(source.tag).slice(0, 40) : null,
          connectionId: source.connectionId ? String(source.connectionId).slice(0, 64) : null
        }
      };
      result = { leftOutPrivate: judged.leftOutPrivate, leftOutHidden: judged.leftOutHidden, places: judged.cards };
    } else if (kind === 'storeSetup') {
      if (user.isSuperUser !== true) throw new ServiceError(403, 'forbidden', 'Only FavCircles staff can make store setup codes');
      const store = await this.storeTarget(input);
      const minter = await this.creatorProfile(user.uid);
      doc = {
        ...base,
        expiresAt: new Date(nowMs + LIFETIME_DAYS.storeSetup * DAY_MS).toISOString(),
        title: store.name,
        store,
        createdByEmail: user.email || minter.email || null,
        redeemedBy: null,
        redeemedAt: null
      };
      result.places = store.globalPlaceId ? [{ globalPlaceId: store.globalPlaceId, name: store.name, address: store.address }] : [];
    } else {
      throw new ServiceError(400, 'invalid_kind', 'Unknown QR type');
    }

    const code = await this.uniqueCode();
    await this.col.doc(code).set(doc);
    return { code, url: urlFor(code), kind, title: doc.title, expiresAt: doc.expiresAt, ...result };
  }

  /** The store a storeSetup code is for: an unowned program venue, or a place to enroll. */
  async storeTarget({ venueId, globalPlaceId }) {
    if (venueId) {
      const doc = await this.db.collection(STICKER_COLLECTIONS.STICKER_VENUES).doc(String(venueId)).get();
      if (!doc.exists || doc.data().active === false) throw new ServiceError(404, 'store_not_found', 'Store not found');
      const venue = doc.data();
      if (venue.ownerUserId) throw new ServiceError(409, 'store_owned', 'This store already has an owner');
      return {
        venueId: doc.id,
        globalPlaceId: venue.globalPlaceId || null,
        googlePlaceId: venue.googlePlaceId || null,
        name: venue.venueName || venue.placeName || 'Your store',
        address: venue.placeAddress || null
      };
    }
    if (globalPlaceId) {
      const doc = await this.db.collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).doc(String(globalPlaceId)).get();
      if (!doc.exists) throw new ServiceError(404, 'store_not_found', 'Place not found');
      const owned = await this.db.collection(STICKER_COLLECTIONS.STICKER_VENUES)
        .where('globalPlaceId', '==', doc.id).limit(5).get();
      const enrolled = owned.docs.find((d) => d.data().active !== false);
      if (enrolled) return this.storeTarget({ venueId: enrolled.id });
      return {
        venueId: null,
        globalPlaceId: doc.id,
        googlePlaceId: doc.data().googlePlaceId || null,
        name: doc.data().name || 'Your store',
        address: doc.data().address || null
      };
    }
    throw new ServiceError(400, 'invalid_store', 'Pick a store');
  }

  async readDoc(code) {
    const doc = await this.col.doc(code).get();
    return doc.exists ? doc.data() : null;
  }

  isExpired(data) {
    return !!(data.expiresAt && Date.parse(data.expiresAt) < this._now());
  }

  /** Of `venueIds`, the viewer's live saves: venueId → {placeId, circleId}. */
  async ownSaves(viewerId, venueIds) {
    const out = new Map();
    if (!viewerId || venueIds.length === 0) return out;
    for (let i = 0; i < venueIds.length; i += 30) {
      const chunk = venueIds.slice(i, i + 30);
      const snap = await this.db.collection(COLLECTIONS.PLACES)
        .where('addedBy', '==', viewerId)
        .where('globalPlaceId', 'in', chunk)
        .get();
      snap.docs.forEach((d) => {
        const data = d.data();
        if (isLive(data) && !out.has(data.globalPlaceId)) out.set(data.globalPlaceId, { placeId: d.id, circleId: data.circleId || null });
      });
    }
    return out;
  }

  /**
   * What a code does, for the app, the App Clip and the landing page.
   * `viewerId` null = anonymous (the page, a Clip before sign-in).
   */
  async resolve(rawCode, viewerId = null, { countScan = true } = {}) {
    const code = normalizeCode(rawCode);
    if (!code) throw new ServiceError(404, 'not_found', 'This code isn’t one of ours');

    const guide = scanGuide(code);
    if (guide) {
      return {
        code, kind: guide.storeOwner ? 'storeSetup' : 'guide', url: urlFor(code), title: guide.title, expired: false,
        guide: { id: guide.id, appGuide: guide.appGuide, title: guide.title, blurb: guide.blurb },
        store: null, places: [], creator: null, note: null
      };
    }

    const data = await this.readDoc(code);
    if (!data) throw new ServiceError(404, 'not_found', 'This code isn’t one of ours');
    const creator = await this.creatorProfile(data.createdBy);
    const out = {
      code,
      kind: data.kind,
      url: urlFor(code),
      title: data.title || null,
      note: data.note || null,
      expired: this.isExpired(data),
      expiresAt: data.expiresAt || null,
      creator: { id: creator.id, displayName: creator.displayName, profilePicture: creator.profilePicture },
      guide: null,
      store: null,
      places: []
    };

    if (data.kind === 'storeSetup') {
      out.store = {
        ...data.store,
        redeemed: !!data.redeemedBy,
        redeemedByViewer: !!viewerId && data.redeemedBy === viewerId,
        venueId: data.redeemedVenueId || data.store.venueId || null
      };
      out.guide = { id: 'store-setup', appGuide: 'storeSetup', title: 'Set up your store', blurb: null };
      return out;
    }

    // Re-read the venues: a QR shows the place as it is now, and drops one
    // that has since been held for approval or removed
    const ids = (data.places || []).map((p) => p.globalPlaceId);
    const venues = await getDocsById(GLOBAL_COLLECTIONS.GLOBAL_PLACES, ids, { db: this.db });
    const saved = await this.ownSaves(viewerId, ids);
    out.places = (data.places || [])
      .filter((p) => venues.has(p.globalPlaceId) && !isHiddenVenue(venues.get(p.globalPlaceId).data()))
      .map((p) => {
        const card = placeCard(p.globalPlaceId, venues.get(p.globalPlaceId).data());
        const own = saved.get(p.globalPlaceId);
        return { ...card, alreadySaved: !!own, savedPlaceId: own ? own.placeId : null, savedCircleId: own ? own.circleId : null };
      });

    if (countScan && viewerId !== data.createdBy) {
      this.col.doc(code).update({ scans: FieldValue.increment(1), lastScannedAt: new Date(this._now()).toISOString() })
        .catch((error) => console.warn(`[scan-action] scan count ${code}: ${error.message}`));
    }
    return out;
  }

  /**
   * Does what the code says for `user` (req.user).
   *   place / placeSet: { globalPlaceIds?: subset to keep (default all), circleId? (default Want to Try) }
   *   storeSetup:       { contactName?, contactEmail?, contactPhone? }
   *   requestId: the app's id for this tap of Save, so a resend never saves twice
   */
  async complete(rawCode, user, input = {}) {
    if (!user || !user.uid) throw new ServiceError(401, 'unauthorized', 'Sign in first');
    const code = normalizeCode(rawCode);
    if (!code || scanGuide(code)) throw new ServiceError(400, 'nothing_to_complete', 'This code has nothing to save');
    const data = await this.readDoc(code);
    if (!data) throw new ServiceError(404, 'not_found', 'This code isn’t one of ours');

    if (data.kind === 'storeSetup') return this.redeemStoreSetup(code, data, user, input);
    if (this.isExpired(data)) throw new ServiceError(410, 'expired', 'This QR has expired. Ask for a new one.');

    const wanted = Array.isArray(input.globalPlaceIds) && input.globalPlaceIds.length
      ? new Set(input.globalPlaceIds.map(String))
      : null;
    const picks = (data.places || []).filter((p) => !wanted || wanted.has(p.globalPlaceId));
    if (picks.length === 0) throw new ServiceError(400, 'nothing_picked', 'Pick at least one place');

    const requestId = typeof input.requestId === 'string' && /^[A-Za-z0-9-]{8,40}$/.test(input.requestId) ? input.requestId : null;
    let circleId = input.circleId ? String(input.circleId) : null;
    if (!circleId) {
      // The App Clip has no circle picker: a place a friend shows you is one
      // to try. (A brand-new account's starter circles are made in the
      // background, so this waits for them briefly.)
      const circle = await this.defaultCircle(user.uid);
      if (!circle) throw new ServiceError(409, 'no_circle', 'Pick a circle to save to');
      circleId = circle.id;
    }

    const venues = await getDocsById(GLOBAL_COLLECTIONS.GLOBAL_PLACES, picks.map((p) => p.globalPlaceId), { db: this.db });
    const saved = [];
    const alreadySaved = [];
    const failed = [];
    const after = [];
    // One at a time: each save's duplicate check must see the one before it
    for (const pick of picks) {
      const venueDoc = venues.get(pick.globalPlaceId);
      const venue = venueDoc ? venueDoc.data() : null;
      if (!venue || isHiddenVenue(venue)) {
        failed.push({ globalPlaceId: pick.globalPlaceId, name: pick.name, message: 'This place isn’t available anymore' });
        continue;
      }
      const result = await this.savePlace(user, saveBodyFor(pick.globalPlaceId, venue, { circleId, requestId, refUserId: data.createdBy }));
      const payload = (result && result.payload) || {};
      if (result && result.status === 201 && payload.place) {
        saved.push({ globalPlaceId: pick.globalPlaceId, name: venue.name, placeId: payload.place.id });
        if (result.afterResponse) after.push(result.afterResponse);
      } else if (payload.code === 'DUPLICATE_PLACE') {
        alreadySaved.push({
          globalPlaceId: pick.globalPlaceId, name: venue.name,
          placeId: payload.existingPlaceId || null, circleId: payload.existingCircleId || null,
          circleName: payload.existingCircleName || null
        });
      } else {
        failed.push({
          globalPlaceId: pick.globalPlaceId, name: venue.name,
          message: payload.message || 'Couldn’t save this place',
          upgradeRequired: payload.upgradeRequired === true
        });
        // A full plan refuses every save after it too: stop asking
        if (payload.upgradeRequired === true) break;
      }
    }

    if (saved.length) {
      this.col.doc(code).update({ saves: FieldValue.increment(saved.length), lastSavedAt: new Date(this._now()).toISOString() })
        .catch((error) => console.warn(`[scan-action] save count ${code}: ${error.message}`));
    }
    // Activity, FavCoins and pushes, after the answer (one at a time: each
    // writes to the same activity and coin records)
    if (after.length) {
      setImmediate(async () => {
        for (const run of after) {
          await run().catch((error) => console.error('[scan-action] after-save work failed:', error.message));
        }
      });
    }
    return { kind: data.kind, circleId, saved, alreadySaved, failed };
  }

  /**
   * A super-user's store QR: the first person to redeem it becomes the owner.
   * The claim is filed in their name and approved as the super-user who made
   * the code, through the same approval as the admin's Approve button.
   */
  async redeemStoreSetup(code, data, user, input) {
    if (data.redeemedBy) {
      if (data.redeemedBy === user.uid) return { kind: 'storeSetup', venueId: data.redeemedVenueId || null, alreadyRedeemed: true };
      throw new ServiceError(409, 'already_redeemed', 'Someone has already used this code');
    }
    if (this.isExpired(data)) throw new ServiceError(410, 'expired', 'This code has expired. Ask FavCircles for a new one.');

    // Hold the code for this person first, so two scans can't both win
    const ref = this.col.doc(code);
    await this.db.runTransaction(async (tx) => {
      const fresh = await tx.get(ref);
      const now = fresh.exists ? fresh.data() : null;
      if (!now) throw new ServiceError(404, 'not_found', 'This code isn’t one of ours');
      if (now.redeemedBy && now.redeemedBy !== user.uid) throw new ServiceError(409, 'already_redeemed', 'Someone has already used this code');
      tx.update(ref, { redeemedBy: user.uid, redeemedAt: new Date(this._now()).toISOString() });
    });

    try {
      const store = data.store || {};
      const claimId = sanitizeKeyPart(store.venueId
        ? `${store.venueId}_${user.uid}`
        : `place_${store.globalPlaceId || store.googlePlaceId}_${user.uid}`);
      const claimRef = this.db.collection(STICKER_COLLECTIONS.VENUE_CLAIM_REQUESTS).doc(claimId);
      const existing = await claimRef.get();
      if (!existing.exists || existing.data().status !== 'pending') {
        await claimRef.set({
          ...createVenueClaimRequest({
            venueId: store.venueId,
            venueName: store.name,
            userId: user.uid,
            userEmail: user.email,
            userDisplayName: user.displayName || user.name,
            contactName: input.contactName,
            contactEmail: input.contactEmail || user.email,
            contactPhone: input.contactPhone,
            message: 'Store setup QR from FavCircles',
            globalPlaceId: store.globalPlaceId,
            googlePlaceId: store.googlePlaceId,
            placeName: store.name,
            placeAddress: store.address
          }),
          preApprovedBy: data.createdBy,
          scanCode: code
        });
      }
      const approved = await this.approveClaim(claimId, { approverId: data.createdBy, approverEmail: data.createdByEmail || null });
      const venueId = (approved && approved.data && approved.data.venueId) || store.venueId || null;
      await ref.update({ redeemedVenueId: venueId, claimId });
      return { kind: 'storeSetup', venueId, alreadyRedeemed: false };
    } catch (error) {
      // Give the code back: it did nothing
      await ref.update({ redeemedBy: null, redeemedAt: null }).catch(() => {});
      throw error;
    }
  }
}

/** Want to Try, else Favorite Local Spots, waiting a few seconds for a new account's starter circles. */
async function defaultCircleFor(uid, { tries = 12, gapMs = 500 } = {}) {
  const systemCircles = require('./systemCircles');
  for (let i = 0; i < tries; i += 1) {
    const circle = (await systemCircles.findOwned(uid, 'wantToTry')) || (await systemCircles.findOwned(uid, 'favoriteLocal'));
    if (circle) return circle;
    if (i < tries - 1) await new Promise((resolve) => setTimeout(resolve, gapMs));
  }
  return null;
}

/** The core save's body for a venue from a QR. Pure. */
function saveBodyFor(venueId, venue, { circleId, requestId, refUserId }) {
  const spot = coordsOf(venue.location);
  return {
    circleId,
    globalPlaceId: venueId,
    name: venue.name,
    address: venue.address || (spot ? `${spot.lat.toFixed(5)}, ${spot.lng.toFixed(5)}` : venue.name),
    ...(spot ? { location: { type: 'Point', coordinates: [spot.lng, spot.lat] } } : {}),
    category: venue.category || 'other',
    ...(venue.googlePlaceId ? { googlePlaceId: venue.googlePlaceId } : {}),
    ...(venue.applePlaceId ? { applePlaceId: venue.applePlaceId } : {}),
    refUserId: refUserId || null,
    // The app's id for this one tap of Save: a resend on a weak signal
    // never saves twice, while a later scan (after an unsave) saves again
    ...(requestId ? { clientSaveId: `scan-${crypto.createHash('sha256').update(`${requestId}|${venueId}`).digest('hex').slice(0, 40)}` } : {})
  };
}

const service = new ScanActionService();
module.exports = service;
module.exports.ScanActionService = ScanActionService;
module.exports.normalizeCode = normalizeCode;
module.exports.shareVerdict = shareVerdict;
module.exports.saveBodyFor = saveBodyFor;
module.exports.isKnownVenue = isKnownVenue;
module.exports.urlFor = urlFor;
module.exports.COLLECTION = COLLECTION;
module.exports.MAX_SET_PLACES = MAX_SET_PLACES;
