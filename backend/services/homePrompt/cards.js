// services/homePrompt/cards.js — methods of HomePromptService (mixed into its prototype by the facade).
const { COLLECTIONS, METERS_PER_MILE, PIGGY_COLLECTIONS, POSTCARD_PLACE_SCAN_LIMIT, POSTCARD_PLACE_WINDOW_MS, getAssumedLocation, haversineMeters, minTripMiles, tipsService, toMillis, TIP_REPEAT_MS, TIP_REPEAT_SKIPPED_MS, TIP_REPEAT_ACTED_MS } = require('./shared');

module.exports = {
   // 1. "Send a postcard from Lisbon?" — a place this user photographed in the
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
    if (!this.postcardNudgeDue(ctx)) return null;

    // No orderBy, so it rides the existing
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

  // 2. "You have 340 FavCoins in your piggy bank" — once, until the user has
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

  // 3. Evergreen feature tips from the catalog, home surface only, in
  //    ROTATION: a tip the person has never seen goes first (in catalog
  //    order), then whichever they saw longest ago. Each tip waits out a
  //    floor before coming round again — a day after being shown, three days
  //    after a skip, a week after they actually tried it — and the card they
  //    saw last never repeats immediately. Still gated by behavioural
  //    evidence, so "have you seen Moments?" stops once they watch Moments.
  //
  //    This used to be once-ever, which with a two-tip catalog meant the
  //    home card went silent on the third open.
  async catalogCard(ctx) {
    const catalog = await tipsService.loadCatalog('home');
    if (catalog.length === 0) return null;
    const evidence = await this.loadEvidence(ctx);
    const lastKey = (ctx.user.homePrompt || {}).lastCardId || null;

    const floorFor = (ack) => {
      if (!ack) return 0;
      if (ack.action === 'acted') return TIP_REPEAT_ACTED_MS;
      if (ack.action === 'skipped') return TIP_REPEAT_SKIPPED_MS;
      return TIP_REPEAT_MS;
    };
    const lastShownMs = (ack) => (ack ? toMillis(ack.at) : null);

    const due = catalog
      .filter(t => tipsService.userMatchesRequirement(ctx.user, t, evidence))
      .filter(t => t.id !== lastKey)
      .filter(t => {
        const ack = ctx.acks[t.id];
        const at = lastShownMs(ack);
        return !Number.isFinite(at) || ctx.now - at >= floorFor(ack);
      })
      .sort((a, b) => {
        const aAt = lastShownMs(ctx.acks[a.id]);
        const bAt = lastShownMs(ctx.acks[b.id]);
        const aNever = !Number.isFinite(aAt), bNever = !Number.isFinite(bAt);
        if (aNever !== bNever) return aNever ? -1 : 1;        // never-shown first
        if (aNever) return (a.order ?? 9999) - (b.order ?? 9999); // then catalog order
        return aAt - bAt;                                        // then least recent
      });
    const tip = due[0];
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
