// services/homePrompt/starter.js — the first-week program's home cards
// (new-user audit, Wes 2026-10-09). For accounts under STARTER_DAYS old, a
// card picked from what the person has actually done yet: start the map,
// explore more maps, add a few more places, make a circle of their own, try
// the widgets. Methods are mixed into HomePromptService; `starterStep` is pure.
const { COLLECTIONS, toMillis } = require('./shared');

const HOUR = 60 * 60 * 1000;
const DAY = 24 * HOUR;
const STARTER_DAYS = 14;
/** Not in the first hours: the signup walkthrough and tour cover that. */
const STARTER_MIN_AGE_MS = 3 * HOUR;
/** Each step comes back a day after it was shown or skipped. */
const STARTER_REPEAT_MS = DAY;

const { DEFAULT_FOLLOW_EMAILS, defaultFollowIds, chosenFollowCount } = require('../defaultAccounts');
const DEFAULT_CIRCLE_NAMES = new Set(['Want to Try', 'Favorite Local Spots', 'Vacation']);

/**
 * Pure (tested): the next step for `progress`, or null when they've done
 * them all. progress = { realPlaces, followingOthers, ownCircles, hasWidgetData }
 */
function starterStep(progress) {
  const p = progress || {};
  if ((p.realPlaces || 0) === 0) {
    return {
      key: 'starter_first_place', target: 'add_place', actionLabel: 'Add a place',
      title: 'Start your map 🗺️',
      body: 'Save a place you love — your go-to coffee spot, a favorite restaurant. It goes on your personal map.'
    };
  }
  if ((p.followingOthers || 0) < 3) {
    return {
      key: 'starter_follow', target: 'network', actionLabel: 'Find people',
      title: 'Explore more maps 👀',
      body: 'Follow a few people — every place they love shows up on your map too.'
    };
  }
  if ((p.realPlaces || 0) < 3) {
    return {
      key: 'starter_more_places', target: 'add_place', actionLabel: 'Add a place',
      title: `Your map has ${p.realPlaces} place${p.realPlaces === 1 ? '' : 's'}`,
      body: 'Add a couple more favorites so the people who follow you have something to explore.'
    };
  }
  if ((p.ownCircles || 0) === 0) {
    return {
      key: 'starter_circle', target: 'create_circle', actionLabel: 'Make one',
      title: 'Make a circle of your own',
      body: 'Group places your way — Date night, Best tacos, Road trip. Share it or keep it private.'
    };
  }
  if (p.hasWidgetData === false) {
    return {
      key: 'starter_widgets', target: 'widgets_tab', actionLabel: 'Show me',
      title: 'Have you tried the widgets?',
      body: 'Weather, workouts, postcards, events and more — scroll through them on the Widgets tab.'
    };
  }
  return null;
}

module.exports = {
  starterStep, STARTER_DAYS, STARTER_MIN_AGE_MS, DEFAULT_FOLLOW_EMAILS,

  mixin: {
    /** Account age in ms, or null when createdAt is unknown. */
    accountAgeMs(ctx) {
      const created = toMillis(ctx.user.createdAt);
      return Number.isFinite(created) ? ctx.now - created : null;
    },

    isStarterAge(ctx) {
      const age = this.accountAgeMs(ctx);
      return age !== null && age >= STARTER_MIN_AGE_MS && age < STARTER_DAYS * DAY;
    },

    /** What they've done so far (bounded reads). */
    async starterProgress(ctx) {
      const uid = ctx.user.id;
      const [placesSnap, circlesSnap, defaults, evidence] = await Promise.all([
        this.db.collection(COLLECTIONS.PLACES).where('addedBy', '==', uid).limit(6).get(),
        this.db.collection(COLLECTIONS.CIRCLES).where('owner', '==', uid).limit(10).get(),
        defaultFollowIds(this.db),
        this.loadEvidence(ctx)
      ]);
      const realPlaces = placesSnap.docs.map(d => d.data()).filter(p => !p.isSamplePlace && !p.deletedAt).length;
      const ownCircles = circlesSnap.docs.map(d => d.data())
        .filter(c => !c.deletedAt && !c.isDefaultCircle && !DEFAULT_CIRCLE_NAMES.has(c.name)).length;
      const followingOthers = chosenFollowCount(ctx.user.following, defaults);
      return { realPlaces, followingOthers, ownCircles, hasWidgetData: evidence.hasWidgetData };
    },

    /** The first-week card, when one is due. */
    async starterCard(ctx) {
      if (!this.isStarterAge(ctx)) return null;
      const step = starterStep(await this.starterProgress(ctx));
      if (!step || !this.nudgeDue(ctx, step.key, STARTER_REPEAT_MS)) return null;
      return {
        key: step.key,
        type: 'starter',
        title: step.title,
        body: step.body,
        actionLabel: step.actionLabel,
        skipLabel: 'Later',
        target: step.target,
        data: {},
        imageUrl: null
      };
    }
  }
};
