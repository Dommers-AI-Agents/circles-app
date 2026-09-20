// backend/services/homePromptService.js
// Home daily card: one server-picked prompt per ~20h.
// Picking, suppression and acks here; the per-kind card builders are mixed in from ./homePrompt/cards.
// Constants and pure helpers live in ./homePrompt/shared.js.
const { ACTIONS, CARDS_COLLECTION, CATALOG_COLLECTION, CLIENT_ACK_KEYS, COLLECTIONS, DYNAMIC_ACK_TTL_MS, HomePromptError, NEW_ACCOUNT_GUARD_MS, NUDGE_REPEAT_MS, POSTCARD_REPEAT_MS, SHOW_INTERVAL_MS, getFirestore, homeCards, isDynamicKey, isEnabled, toMillis } = require('./homePrompt/shared');

class HomePromptService {
  constructor(db = getFirestore()) {
    this.db = db;
  }

  // ---------------------------------------------------------------- pick

  async pick(userId, { now = Date.now() } = {}, options = {}) {
    if (!isEnabled()) return null;

    const userDoc = await this.db.collection(COLLECTIONS.USERS).doc(userId).get();
    if (!userDoc.exists) return null;
    const user = { id: userDoc.id, ...userDoc.data() };

    const createdAt = toMillis(user.createdAt);
    if (Number.isFinite(createdAt) && now - createdAt < NEW_ACCOUNT_GUARD_MS) return null;

    const state = user.homePrompt || {};
    const lastShownAt = toMillis(state.lastShownAt);
    const acks = state.acks || {};
    const ctx = {
      user,
      acks,
      now,
      lastShownAt: Number.isFinite(lastShownAt) ? lastShownAt : null,
      appVersion: options.appVersion || null
    };
    const withinWindow = Number.isFinite(lastShownAt) && now - lastShownAt < SHOW_INTERVAL_MS;

    // A scheduled card marked `override` is picked before any organic source,
    // and one marked `bypassInterval` is picked even when the user already had
    // a card today. That is the whole point of the tier: what Wes schedules
    // wins, and the rest of the ladder is untouched underneath it.
    let card = null;
    try {
      card = await this.overrideCard(ctx);
    } catch (error) {
      console.error('🃏 scheduled card lookup failed:', error.message);
    }
    if (card && withinWindow && !card.bypassInterval) card = null;

    if (!card) {
      if (withinWindow) return null;
      card = await this.firstCandidate(ctx);
    }
    if (!card) return null;

    // Every card covers the home screen and asks for an answer. Inline was
    // the organic cards' default and it made them easy to scroll past
    // unread — fine for a feed row, wrong for the one thing we chose to
    // say. A scheduled card may still opt into inline explicitly.
    if (!card.presentation) card.presentation = 'overlay';

    await this.stamp(userId, state, card.key, now);
    return card;
  }

  // ------------------------------------------------- scheduled (custom) cards

  // Every live, due, in-audience card for this user, highest priority first.
  // Cached on ctx because both the override tier and the tail of the ladder
  // ask for it.
  async liveCards(ctx) {
    if (ctx._liveCards) return ctx._liveCards;
    let docs = [];
    try {
      const snap = await this.db.collection(CARDS_COLLECTION).where('enabled', '==', true).get();
      snap.forEach(doc => docs.push({ id: doc.id, ...doc.data() }));
    } catch (error) {
      console.error('🃏 homeCards read failed:', error.message);
    }
    const zone = (ctx.user.notificationPreferences || {}).timezone;
    ctx._liveCards = docs
      .filter(c => c.title)
      .filter(c => homeCards.windowOpen(c, ctx.now, zone))
      .filter(c => homeCards.cadenceDue(c, ctx.acks[homeCards.ackKey(c)], ctx.now))
      .filter(c => homeCards.audienceMatches(c, ctx.user, { now: ctx.now, appVersion: ctx.appVersion }))
      .sort(homeCards.byPriority)
      .map(homeCards.toCard);
    return ctx._liveCards;
  }

  async overrideCard(ctx) {
    const live = await this.liveCards(ctx);
    return live.find(c => c.override) || null;
  }

  // Scheduled cards that did NOT ask to override sit just above the evergreen
  // tips: more specific than "did you know", less urgent than a friend's news.
  async scheduledCard(ctx) {
    const live = await this.liveCards(ctx);
    return live.find(c => !c.override) || null;
  }

  // Priority order: first match wins. Each builder returns a card or null and
  // swallows its own errors — one broken source must never blank the home
  // screen's card slot for everyone.
  async firstCandidate(ctx) {
    // Only things that point at a FEATURE. "Ana added a place" and "latest
    // moment from Ana" used to sit at the top of this ladder, and they were
    // exactly what the activity feed already shows — a card repeating the
    // feed, over the feed, is noise. The card's job is to tell someone
    // arriving about something they may not have tried.
    const builders = [
      () => this.postcardCard(ctx),
      () => this.favCoinsCard(ctx),
      () => this.scheduledCard(ctx),
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
 
  // 1. "Ana added Mabel's Kitchen" — newest unseen activity from the network
  //    since the last card (capped at a day).

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

  // `now` is injectable for the same reason pick's is: every other clock in
  // this service is, and a test that acks at the real time but picks at an
  // injected one drifts as the calendar moves.
  async ack(userId, key, action, { now = Date.now() } = {}) {
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
    const next = { action, at: new Date(now).toISOString() };
    await ref.update({ homePrompt: { ...state, acks: { ...acks, [key]: next } } });
    return next;
  }
}

Object.assign(HomePromptService.prototype, require('./homePrompt/cards'));
module.exports = new HomePromptService();
module.exports.HomePromptService = HomePromptService;
module.exports.HomePromptError = HomePromptError;
module.exports.isEnabled = isEnabled;
module.exports.CATALOG_COLLECTION = CATALOG_COLLECTION;
