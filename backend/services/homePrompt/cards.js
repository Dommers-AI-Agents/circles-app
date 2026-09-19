// services/homePrompt/cards.js — methods of HomePromptService (mixed into its prototype by the facade).
const { ACTIVITY_SCAN_LIMIT, ACTIVITY_TYPES, ACTIVITY_WINDOW_MS, COLLECTIONS, METERS_PER_MILE, NUDGE_REPEAT_MS, PIGGY_COLLECTIONS, POSTCARD_PLACE_SCAN_LIMIT, POSTCARD_PLACE_WINDOW_MS, POSTCARD_REPEAT_MS, canViewMoment, getAssumedLocation, haversineMeters, minTripMiles, queryInChunks, tipsService, toMillis } = require('./shared');

module.exports = {
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
  },

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
  },

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
        .where('visibility', 'in', ['public', 'network', 'innerCircle'])
        .orderBy('createdAt', 'desc')
        .limit(3)
        .get()
    );
    const videos = docs.map(doc => ({ id: doc.id, ...doc.data() }))
      .filter(v => String(v.createdAt) >= sinceIso)
      .filter(v => canViewMoment(v, ctx.user.id, network.viewer))
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
  },

  async hasViewed(userId, videoId) {
    const snap = await this.db.collection(COLLECTIONS.VIDEO_VIEWS)
      .where('userId', '==', userId).where('videoId', '==', videoId).limit(1).get();
    return !snap.empty;
  },

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
  },

  // 4. "Send a postcard from Lisbon?" — a place this user photographed in the
  //    last week. Their OWN photo, never the venue's stock one: nobody mails a
  //    postcard of a Google photo, so `hasOwnPhotos` (stamped when the app
  //    names its uploads on a save, or when a photo is added to an existing
  //    save) is the whole gate. Shares the `postcard_nudge` ack with the
  //    pop-up the app shows after a save, so the two surfaces never both ask
  //    in the same fortnight. The card lands on the composer, which offers
  //    both the free in-app send and the printed one — so the copy promises
  //    neither.
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
      if (!place.hasOwnPhotos) continue; // their picture, or no card
      const photo = place.ownPhotoUrl
        || (place.photos || []).find(url => typeof url === 'string' && url.length > 0);
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
  },

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
  },

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
  },

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
  },
};
