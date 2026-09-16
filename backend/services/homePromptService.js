// backend/services/homePromptService.js
//
// Home "daily card": one intriguing thing per visit. The server picks at most
// one card for a user, roughly once a day, from a fixed priority list —
// something a connection just did, the newest network moment, a nudge to add
// a place, the piggy-bank balance, then evergreen "have you seen…" feature
// tips from the `notificationTips` catalog (surfaces: ["home"]).
//
// All memory of what a user has seen or already knows lives on the user doc
// (`homePrompt`), never on the device, so a reinstall doesn't re-ask and two
// devices agree. Three signals stop a card from repeating:
//   1. explicit acks — Skip / acted / shown, keyed by card key;
//   2. behavioural evidence — has widget data → knows the Widgets tab; has any
//      video view → has scrolled Moments; added a place this week → no nudge;
//   3. the catalog's own `tipsSeen` list (push tips already delivered).
//
// Showing nothing is a normal outcome. The card is stamped as shown on pick
// (not on a client ack) — if the phone drops the response the user misses one
// card today, which is the cheap failure. Ships dark behind HOME_PROMPTS_ENABLED.

const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');
const { PIGGY_COLLECTIONS } = require('../models/PiggyBankModels');
const { queryInChunks } = require('../utils/firestoreChunks');
const { excludedUserIds } = require('./moderationService');
const tipsService = require('./tipsService');
const { getAssumedLocation } = require('./userCardEnrichment');
const { haversineMeters } = require('./globalPlaceResolver');

const CATALOG_COLLECTION = 'notificationTips';
const HOUR = 60 * 60 * 1000;
const DAY = 24 * HOUR;

// Rolling window between cards. 20h (not 24h) so "first open of the day"
// still qualifies for someone who opened at 9am yesterday and 8am today.
const SHOW_INTERVAL_MS = parseInt(process.env.HOME_PROMPT_INTERVAL_HOURS || '20', 10) * HOUR;
// New accounts get the onboarding chain, not cards.
const NEW_ACCOUNT_GUARD_MS = 48 * HOUR;
// A connection's activity is only "news" for a day.
const ACTIVITY_WINDOW_MS = DAY;
// Dynamic acks (per activity / moment) are app state, not user content —
// prune them after this so the map stays bounded. Static keys are kept
// forever: that's the "never ask twice" memory.
const DYNAMIC_ACK_TTL_MS = 90 * DAY;
// Personal nudges may repeat, but not more often than this.
const NUDGE_REPEAT_MS = 7 * DAY;
// The postcard nudge is rarer than the rest: it asks for effort (and, if the
// user picks print, money), so a fortnight between asks. Shared with the
// post-save pop-up in the app — both read and write the `postcard_nudge` ack,
// so being asked in one place silences the other.
const POSTCARD_REPEAT_MS = parseInt(process.env.POSTCARD_NUDGE_REPEAT_DAYS || '14', 10) * DAY;
// Only nudge about places saved recently enough to still feel like news.
const POSTCARD_PLACE_WINDOW_MS = 7 * DAY;
// Optional tightener: only nudge when the place is at least this far from
// where the user usually is, i.e. it reads as a trip. Unset = off (and then
// the picker never pays for a location lookup).
// Newest activities scanned per actor chunk.
const ACTIVITY_SCAN_LIMIT = 10;

const ACTIVITY_TYPES = new Set(['place_added', 'video_uploaded', 'photo_uploaded', 'check_in']);
const ACTIONS = new Set(['skipped', 'acted', 'shown']);

const METERS_PER_MILE = 1609.344;
// Recent saves scanned for one with a photo.
const POSTCARD_PLACE_SCAN_LIMIT = 20;

// Keys that may be acked by the client directly (not derived from a card):
// the FavCoins explainer records itself when the user finishes it, and the
// post-save postcard pop-up records itself so the home card honours the same
// cooldown (and vice versa).
const CLIENT_ACK_KEYS = new Set(['favcoins_intro', 'postcard_nudge']);

const isEnabled = () => process.env.HOME_PROMPTS_ENABLED === '1';
// Read per call, like isEnabled: 0/unset keeps the tightener off.
const minTripMiles = () => parseFloat(process.env.POSTCARD_NUDGE_MIN_MILES || '0');

// Firestore Timestamp, Date, ISO string, or millis → millis (NaN if unknown).
function toMillis(value) {
  if (!value) return NaN;
  if (typeof value.toMillis === 'function') return value.toMillis();
  if (typeof value.toDate === 'function') return value.toDate().getTime();
  if (value instanceof Date) return value.getTime();
  if (typeof value === 'number') return value;
  if (typeof value === 'string') return new Date(value).getTime();
  if (typeof value._seconds === 'number') return value._seconds * 1000;
  return NaN;
}

const isDynamicKey = (key) => key.includes(':');

class HomePromptError extends Error {
  constructor(status, code, message) {
    super(message);
    this.status = status;
    this.code = code;
  }
}

class HomePromptService {
  constructor(db = getFirestore()) {
    this.db = db;
  }

  // ---------------------------------------------------------------- pick

  async pick(userId, { now = Date.now() } = {}) {
    if (!isEnabled()) return null;

    const userDoc = await this.db.collection(COLLECTIONS.USERS).doc(userId).get();
    if (!userDoc.exists) return null;
    const user = { id: userDoc.id, ...userDoc.data() };

    const createdAt = toMillis(user.createdAt);
    if (Number.isFinite(createdAt) && now - createdAt < NEW_ACCOUNT_GUARD_MS) return null;

    const state = user.homePrompt || {};
    const lastShownAt = toMillis(state.lastShownAt);
    if (Number.isFinite(lastShownAt) && now - lastShownAt < SHOW_INTERVAL_MS) return null;

    const acks = state.acks || {};
    const ctx = { user, acks, now, lastShownAt: Number.isFinite(lastShownAt) ? lastShownAt : null };

    const card = await this.firstCandidate(ctx);
    if (!card) return null;

    await this.stamp(userId, state, card.key, now);
    return card;
  }

  // Priority order: first match wins. Each builder returns a card or null and
  // swallows its own errors — one broken source must never blank the home
  // screen's card slot for everyone.
  async firstCandidate(ctx) {
    const builders = [
      () => this.connectionActivityCard(ctx),
      () => this.latestMomentCard(ctx),
      () => this.addPlaceCard(ctx),
      () => this.postcardCard(ctx),
      () => this.favCoinsCard(ctx),
      () => this.catalogCard(ctx)
    ];
    for (const build of builders) {
      try {
        const card = await build();
        if (card) return card;
      } catch (error) {
        console.error('🃏 home prompt candidate failed:', error.message);
      }
    }
    return null;
  }

  isAcked(ctx, key) {
    return Boolean(ctx.acks[key]);
  }

  // A repeating nudge is due when it has never been acked, or the last ack is
  // older than the repeat interval.
  nudgeDue(ctx, key, repeatMs = NUDGE_REPEAT_MS) {
    const ack = ctx.acks[key];
    if (!ack) return true;
    const at = toMillis(ack.at);
    return !Number.isFinite(at) || ctx.now - at >= repeatMs;
  }

  // ---------------------------------------------------------------- sources

  // Connections + followed users, minus anyone blocked either way. Two sets
  // because moment privacy distinguishes "connected" from "follows".
  async loadNetwork(ctx) {
    if (ctx.network) return ctx.network;
    const { user } = ctx;
    const [outgoing, incoming] = await Promise.all([
      this.db.collection(COLLECTIONS.CONNECTIONS).where('userId', '==', user.id).where('status', '==', 'accepted').get(),
      this.db.collection(COLLECTIONS.CONNECTIONS).where('connectedUserId', '==', user.id).where('status', '==', 'accepted').get()
    ]);
    const connections = new Set();
    outgoing.docs.forEach(doc => connections.add(doc.data().connectedUserId));
    incoming.docs.forEach(doc => connections.add(doc.data().userId));
    const following = new Set(user.following || []);
    for (const blocked of excludedUserIds(user)) {
      connections.delete(blocked);
      following.delete(blocked);
    }
    connections.delete(user.id);
    following.delete(user.id);
    ctx.network = { connections, following, all: new Set([...connections, ...following]) };
    return ctx.network;
  }

  async loadActor(ctx, actorId) {
    ctx.actors = ctx.actors || new Map();
    if (!ctx.actors.has(actorId)) {
      const doc = await this.db.collection(COLLECTIONS.USERS).doc(actorId).get();
      ctx.actors.set(actorId, doc.exists ? { id: doc.id, ...doc.data() } : null);
    }
    return ctx.actors.get(actorId);
  }

  actorName(actor) {
    if (!actor) return null;
    return actor.firstName || (actor.displayName || '').split(' ')[0] || actor.displayName || null;
  }

  // Same gates the activity feed applies, so a card never points at content
  // the tap can't open: moment visibility by relationship to the owner, circle
  // privacy for circle-scoped rows, and place-level privacy.
  async activityVisible(ctx, activity, network) {
    const meta = activity.metadata || {};
    if (activity.type === 'video_uploaded') {
      const vis = meta.momentVisibility;
      const owner = meta.momentOwnerId;
      if (vis && owner && owner !== ctx.user.id) {
        if (vis === 'public') return true;
        if (vis === 'followers') return network.following.has(owner);
        if (vis === 'network') return network.connections.has(owner);
        return false;
      }
      return true;
    }
    if (activity.circleId) {
      const circleDoc = await this.db.collection(COLLECTIONS.CIRCLES).doc(activity.circleId).get();
      if (!circleDoc.exists) return false;
      const circle = circleDoc.data();
      if (circle.owner !== ctx.user.id) {
        if (circle.privacy === 'myNetwork' && !network.connections.has(circle.owner)) return false;
        if (circle.privacy === 'private' && !(circle.sharedWith || []).includes(ctx.user.id)) return false;
        if (!['public', 'myNetwork', 'private'].includes(circle.privacy)) return false;
      }
    }
    // Place-level privacy. A missing doc is allowed through: photo uploads
    // target the canonical globalPlaces id, which has no `places` row.
    const placeId = this.activityPlaceId(activity);
    if (placeId) {
      const placeDoc = await this.db.collection(COLLECTIONS.PLACES).doc(placeId).get();
      if (placeDoc.exists) {
        const place = placeDoc.data();
        if (place.deletedAt) return false;
        if (place.privacy === 'private' && place.addedBy !== ctx.user.id) return false;
      }
    }
    return true;
  }

  // place_added / photo_uploaded target the place; check_in targets the
  // check-in row and carries the place in metadata.
  activityPlaceId(activity) {
    const meta = activity.metadata || {};
    if (activity.type === 'check_in') return meta.placeId || null;
    return activity.targetType === 'place' ? (activity.targetId || null) : null;
  }

  // 1. "Ana added Mabel's Kitchen" — newest unseen activity from the network
  //    since the last card (capped at a day).
  async connectionActivityCard(ctx) {
    const network = await this.loadNetwork(ctx);
    if (network.all.size === 0) return null;

    const since = new Date(Math.max(ctx.lastShownAt || 0, ctx.now - ACTIVITY_WINDOW_MS));
    const docs = await queryInChunks(network.all, chunk =>
      this.db.collection(COLLECTIONS.ACTIVITIES)
        .where('actorId', 'in', chunk)
        .where('timestamp', '>=', since)
        .orderBy('timestamp', 'desc')
        .limit(ACTIVITY_SCAN_LIMIT)
        .get()
    );
    const rows = docs.map(doc => ({ id: doc.id, ...doc.data() }))
      .filter(a => ACTIVITY_TYPES.has(a.type) && a.actorId !== ctx.user.id)
      .sort((a, b) => toMillis(b.timestamp) - toMillis(a.timestamp));

    for (const activity of rows) {
      // A moment's activity row and its placeVideos row share one key, so a
      // Skip on "Ana shared a moment" also silences "Latest moment from Ana".
      const key = activity.type === 'video_uploaded'
        ? `moment:${activity.targetId}`
        : `activity:${activity.id}`;
      if (this.isAcked(ctx, key)) continue;
      if (!(await this.activityVisible(ctx, activity, network))) continue;
      const actor = await this.loadActor(ctx, activity.actorId);
      const name = this.actorName(actor);
      if (!name) continue;
      return this.buildActivityCard(key, activity, actor, name);
    }
    return null;
  }

  buildActivityCard(key, activity, actor, name) {
    const meta = activity.metadata || {};
    const placeName = activity.targetName || 'a place';
    const imageUrl = meta.videoThumbnail || meta.placePhoto || null;
    const base = {
      key,
      type: 'connection_activity',
      skipLabel: 'Skip',
      imageUrl,
      actorId: actor.id,
      actorPhoto: actor.profilePicture || null
    };
    switch (activity.type) {
      case 'video_uploaded':
        return {
          ...base,
          title: `${name} shared a moment`,
          body: `At ${placeName}. Take a look.`,
          actionLabel: 'Watch',
          target: 'video',
          data: { videoId: activity.targetId, placeId: meta.placeId || null }
        };
      case 'photo_uploaded':
        return {
          ...base,
          title: `${name} added a photo`,
          body: `New photo at ${placeName}.`,
          actionLabel: 'View',
          target: 'place',
          data: { placeId: activity.targetId, globalPlaceId: meta.globalPlaceId || null }
        };
      case 'check_in':
        return {
          ...base,
          title: `${name} checked in at ${placeName}`,
          body: meta.message || 'See where they went.',
          actionLabel: 'View',
          target: 'place',
          data: { placeId: this.activityPlaceId(activity), globalPlaceId: meta.globalPlaceId || null }
        };
      default: // place_added
        return {
          ...base,
          title: `${name} added ${placeName}`,
          body: activity.circleName ? `To ${activity.circleName}.` : 'A new favorite in your network.',
          actionLabel: 'View',
          target: 'place',
          data: { placeId: activity.targetId, globalPlaceId: meta.globalPlaceId || null }
        };
    }
  }

  // 2. "Latest moment from Ana" — newest network moment in the last day that
  //    this user hasn't watched.
  async latestMomentCard(ctx) {
    const network = await this.loadNetwork(ctx);
    if (network.all.size === 0) return null;
    const sinceIso = new Date(ctx.now - ACTIVITY_WINDOW_MS).toISOString();

    const docs = await queryInChunks(network.all, chunk =>
      this.db.collection(COLLECTIONS.PLACE_VIDEOS)
        .where('userId', 'in', chunk)
        .where('uploadStatus', '==', 'ready')
        .where('deletedAt', '==', null)
        .where('visibility', 'in', ['public', 'network'])
        .orderBy('createdAt', 'desc')
        .limit(3)
        .get()
    );
    const videos = docs.map(doc => ({ id: doc.id, ...doc.data() }))
      .filter(v => String(v.createdAt) >= sinceIso)
      .filter(v => v.visibility === 'public' || network.connections.has(v.userId))
      .sort((a, b) => String(b.createdAt).localeCompare(String(a.createdAt)));

    for (const video of videos) {
      const key = `moment:${video.id}`;
      if (this.isAcked(ctx, key)) continue;
      if (await this.hasViewed(ctx.user.id, video.id)) continue;
      const actor = await this.loadActor(ctx, video.userId);
      const name = this.actorName(actor);
      if (!name) continue;
      return {
        key,
        type: 'latest_moment',
        title: `Latest moment from ${name}`,
        body: video.placeName ? `At ${video.placeName}.` : 'Fresh from your network.',
        actionLabel: 'Watch',
        skipLabel: 'Skip',
        target: 'video',
        data: { videoId: video.id, placeId: video.placeId || null },
        imageUrl: video.thumbnailUrl || null,
        actorId: actor.id,
        actorPhoto: actor.profilePicture || null
      };
    }
    return null;
  }

  async hasViewed(userId, videoId) {
    const snap = await this.db.collection(COLLECTIONS.VIDEO_VIEWS)
      .where('userId', '==', userId).where('videoId', '==', videoId).limit(1).get();
    return !snap.empty;
  }

  // 3. "Add a new place?" — nothing saved in the last week, at most weekly.
  async addPlaceCard(ctx) {
    const key = 'add_place';
    if (!this.nudgeDue(ctx, key)) return null;
    const weekAgo = new Date(ctx.now - NUDGE_REPEAT_MS).toISOString();
    const recent = await this.db.collection(COLLECTIONS.PLACES)
      .where('addedBy', '==', ctx.user.id)
      .where('createdAt', '>=', weekAgo)
      .limit(1)
      .get();
    if (!recent.empty) return null;
    const hasAny = (ctx.user.placesCount ?? ctx.user.totalPlaces ?? 1) > 0;
    return {
      key,
      type: 'add_place',
      title: hasAny ? 'Add a new place?' : 'Save your first place',
      body: hasAny
        ? 'Been somewhere good lately? Save it before you forget.'
        : 'Your circles are empty — add a favorite spot to get started.',
      actionLabel: 'Add a place',
      skipLabel: 'Skip',
      target: 'add_place',
      data: {},
      imageUrl: null
    };
  }

  // 4. "Send a postcard from Lisbon?" — a place this user saved in the last
  //    week that has a photo worth putting on a card. Rarer than the other
  //    nudges, and it shares the `postcard_nudge` ack with the pop-up the app
  //    shows after a save, so the two surfaces never both ask in the same
  //    fortnight. The card lands on the composer, which offers both the free
  //    in-app send and the printed one — so the copy promises neither.
  async postcardCard(ctx) {
    const key = 'postcard_nudge';
    if (!this.nudgeDue(ctx, key, POSTCARD_REPEAT_MS)) return null;

    // Same query shape as addPlaceCard (no orderBy) so it rides the existing
    // (addedBy, createdAt) index; newest-first is settled in memory.
    const since = new Date(ctx.now - POSTCARD_PLACE_WINDOW_MS).toISOString();
    const snap = await this.db.collection(COLLECTIONS.PLACES)
      .where('addedBy', '==', ctx.user.id)
      .where('createdAt', '>=', since)
      .limit(POSTCARD_PLACE_SCAN_LIMIT)
      .get();

    const places = snap.docs
      .map(doc => ({ id: doc.id, ...doc.data() }))
      .filter(place => !place.deletedAt)
      .sort((a, b) => String(b.createdAt).localeCompare(String(a.createdAt)));

    for (const place of places) {
      const photo = (place.photos || []).find(url => typeof url === 'string' && url.length > 0);
      if (!photo) continue; // the composer opens on a picture or not at all
      if (!place.name) continue;
      if (!(await this.readsAsTrip(ctx, place))) continue;
      return {
        key,
        type: 'postcard',
        title: `Send a postcard from ${place.name}?`,
        body: 'Put your photo on a card and send it to someone.',
        actionLabel: 'Make one',
        skipLabel: 'Not now',
        target: 'postcard',
        data: {
          placeId: place.id,
          globalPlaceId: place.globalPlaceId || null,
          placeName: place.name,
          photoUrl: photo
        },
        imageUrl: photo
      };
    }
    return null;
  }

  // Optional tightener (POSTCARD_NUDGE_MIN_MILES). Off by default, and while
  // it is off nothing here costs a read. Unknown coordinates pass: a nudge we
  // can't place is better than one we never send.
  async readsAsTrip(ctx, place) {
    const minMiles = minTripMiles();
    if (!(minMiles > 0)) return true;
    const coords = place.location && place.location.coordinates;
    if (!Array.isArray(coords) || coords.length !== 2) return true;
    const home = await getAssumedLocation(ctx.user.id, ctx.user);
    if (!home || !Number.isFinite(home.latitude) || !Number.isFinite(home.longitude)) return true;
    const meters = haversineMeters(home.latitude, home.longitude, coords[1], coords[0]);
    return meters / METERS_PER_MILE >= minMiles;
  }

  // 5. "You have 340 FavCoins in your piggy bank" — once, until the user has
  //    been through the explainer (favcoins_intro ack) or skipped it.
  async favCoinsCard(ctx) {
    const key = 'favcoins_balance';
    if (this.isAcked(ctx, key) || this.isAcked(ctx, 'favcoins_intro')) return null;
    const bankDoc = await this.db.collection(PIGGY_COLLECTIONS.BANKS).doc(ctx.user.id).get();
    if (!bankDoc.exists) return null;
    const bank = bankDoc.data();
    const total = Math.round(((bank.pendingCoins || 0) + (bank.confirmedCoins || 0)) * 100) / 100;
    if (!(total > 0)) return null;
    const shown = Number.isInteger(total) ? String(total) : total.toFixed(2);
    return {
      key,
      type: 'favcoins_balance',
      title: `You have ${shown} FavCoins in your piggy bank 🐷`,
      body: 'Did you know they\'re real crypto? See what they are and how to spend them.',
      actionLabel: 'Show me',
      skipLabel: 'Skip',
      target: 'favcoins_intro',
      data: { coins: total },
      imageUrl: null
    };
  }

  // 6. Evergreen feature tips from the catalog, home surface only, each at
  //    most once ever (ack or tipsSeen), gated by behavioural evidence.
  async catalogCard(ctx) {
    const catalog = await tipsService.loadCatalog('home');
    if (catalog.length === 0) return null;
    const seen = new Set(ctx.user.tipsSeen || []);
    const evidence = await this.loadEvidence(ctx);
    const tip = catalog.find(t =>
      !seen.has(t.id) && !this.isAcked(ctx, t.id) && tipsService.userMatchesRequirement(ctx.user, t, evidence)
    );
    if (!tip) return null;
    return {
      key: tip.id,
      type: 'feature_tip',
      title: tip.title,
      body: tip.body,
      actionLabel: tip.actionLabel || 'Show me',
      skipLabel: 'Skip',
      target: tip.target,
      data: tip.data || {},
      imageUrl: tip.imageUrl || null
    };
  }

  // Behavioural "already knows" signals. Unknown (query failed) is reported as
  // `null`, which the suppression predicates treat as "don't show".
  async loadEvidence(ctx) {
    if (ctx.evidence) return ctx.evidence;
    const userId = ctx.user.id;
    const probe = async (query) => {
      try {
        const snap = await query.limit(1).get();
        return !snap.empty;
      } catch (error) {
        console.error('🃏 home prompt evidence probe failed:', error.message);
        return null;
      }
    };
    const [hasWidgetData, hasVideoViews] = await Promise.all([
      probe(this.db.collection(COLLECTIONS.WIDGET_DATA).where('userId', '==', userId)),
      probe(this.db.collection(COLLECTIONS.VIDEO_VIEWS).where('userId', '==', userId))
    ]);
    ctx.evidence = { hasWidgetData, hasVideoViews };
    return ctx.evidence;
  }

  // ---------------------------------------------------------------- state

  pruneAcks(acks, now) {
    const kept = {};
    for (const [key, ack] of Object.entries(acks || {})) {
      if (isDynamicKey(key)) {
        const at = toMillis(ack && ack.at);
        if (Number.isFinite(at) && now - at > DYNAMIC_ACK_TTL_MS) continue;
      }
      kept[key] = ack;
    }
    return kept;
  }

  async stamp(userId, state, key, now) {
    const at = new Date(now).toISOString();
    const acks = this.pruneAcks(state.acks, now);
    acks[key] = { action: 'shown', at };
    await this.db.collection(COLLECTIONS.USERS).doc(userId).update({
      homePrompt: { ...state, lastShownAt: at, lastCardId: key, acks }
    });
  }

  // Does the app's post-save pop-up get to ask? Same fortnightly
  // `postcard_nudge` memory the home card uses, so whichever surface asks
  // first silences the other for a fortnight. Deliberately independent of
  // HOME_PROMPTS_ENABLED — the pop-up is its own feature, with its own kill
  // switch (POSTCARD_NUDGE_ENABLED=0) — but it honours the new-account guard,
  // because a first-week user is being walked through onboarding already.
  async postcardNudgeEligible(userId, { now = Date.now() } = {}) {
    if (process.env.POSTCARD_NUDGE_ENABLED === '0') return false;
    const doc = await this.db.collection(COLLECTIONS.USERS).doc(userId).get();
    if (!doc.exists) return false;
    const user = doc.data() || {};
    const createdAt = toMillis(user.createdAt);
    if (Number.isFinite(createdAt) && now - createdAt < NEW_ACCOUNT_GUARD_MS) return false;
    const acks = (user.homePrompt || {}).acks || {};
    return this.nudgeDue({ acks, now }, 'postcard_nudge', POSTCARD_REPEAT_MS);
  }

  // ---------------------------------------------------------------- ack

  async ack(userId, key, action) {
    if (typeof key !== 'string' || key.length === 0 || key.length > 200) {
      throw new HomePromptError(400, 'bad_key', 'Card key is required.');
    }
    if (!ACTIONS.has(action)) {
      throw new HomePromptError(400, 'bad_action', 'Action must be skipped, acted, or shown.');
    }
    const ref = this.db.collection(COLLECTIONS.USERS).doc(userId);
    const doc = await ref.get();
    if (!doc.exists) throw new HomePromptError(404, 'user_not_found', 'User not found.');
    const state = (doc.data() || {}).homePrompt || {};
    const acks = state.acks || {};
    // Only cards this user was actually shown can be acked, plus the handful
    // of client-originated keys — otherwise a client could mute anything.
    if (!acks[key] && !CLIENT_ACK_KEYS.has(key)) {
      throw new HomePromptError(404, 'unknown_card', 'That card was never shown.');
    }
    // "shown" never downgrades a skip/act the user already made.
    if (action === 'shown' && acks[key] && acks[key].action !== 'shown') return acks[key];
    const next = { action, at: new Date().toISOString() };
    await ref.update({ homePrompt: { ...state, acks: { ...acks, [key]: next } } });
    return next;
  }
}

module.exports = new HomePromptService();
module.exports.HomePromptService = HomePromptService;
module.exports.HomePromptError = HomePromptError;
module.exports.isEnabled = isEnabled;
module.exports.CATALOG_COLLECTION = CATALOG_COLLECTION;
