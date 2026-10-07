// Rules for the scheduled home cards Wes authors in Firestore (`homeCards`).
//
// The home card slot already has organic sources — a connection's activity,
// the newest moment, the add-place nudge, the piggy bank, evergreen tips.
// These are different: they are campaigns with a start, an end, a cadence and
// an audience, written from the backend and live the moment they are saved.
// No app release changes what one says or when it appears.
//
// Everything here is pure so the scheduling can be tested without Firestore
// and without waiting for a Tuesday.
const { localClock } = require('../utils/localClock');
const { compareVersions } = require('../utils/appVersion');

// A card may point only at a destination the app routes. A destination that
// arrived after a release carries the first version that routes it: on an
// older build the card shows as "update to get it" (the build gate below)
// instead of a button that does nothing.
const TARGET_MIN_VERSION = {
  postcard: '1.3.5', widget: '1.3.5', inner_circle: '1.3.5', app_store: '1.3.8'
};
const KNOWN_TARGETS = new Set([
  'place', 'video', 'moment', 'add_place', 'add-place', 'widgets_tab',
  'moments_tab', 'all_places_map', 'create_wallet', 'network', 'favcoins_intro',
  ...Object.keys(TARGET_MIN_VERSION)
]);

const DAY_MS = 24 * 60 * 60 * 1000;
const DATE_ONLY = /^\d{4}-\d{2}-\d{2}$/;

// A bare date means that day where the USER is, not where the server is.
// "Show it tomorrow" has to mean their tomorrow or a card scheduled for
// Tuesday turns up on Monday evening for everyone west of us.
const boundaryMs = (value, timeZone, endOfDay = false) => {
  if (!value) return null;
  if (DATE_ONLY.test(value)) {
    const probe = Date.parse(`${value}T${endOfDay ? '23:59:59.999' : '00:00:00.000'}Z`);
    if (!Number.isFinite(probe)) return null;
    // Offset of the user's zone at that moment, applied to the wall time.
    const local = localClock(timeZone, new Date(probe));
    const wallMinutes = local.hour * 60 + local.minute;
    const utcMinutes = new Date(probe).getUTCHours() * 60 + new Date(probe).getUTCMinutes();
    let drift = wallMinutes - utcMinutes;
    if (drift > 720) drift -= 1440;
    if (drift < -720) drift += 1440;
    return probe - drift * 60000;
  }
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? parsed : null;
};

const windowOpen = (card, now, timeZone) => {
  const from = boundaryMs(card.startsAt, timeZone, false);
  const until = boundaryMs(card.endsAt, timeZone, true);
  if (from !== null && now < from) return false;
  if (until !== null && now > until) return false;
  return true;
};

// `repeatDays: 0` (or absent) means once ever. Anything else is a cadence, and
// the ack the user already writes by tapping Skip or the button is the clock.
const cadenceDue = (card, ack, now) => {
  if (!ack) return true;
  const at = Date.parse(ack.at);
  const repeatDays = Number(card.repeatDays) || 0;
  if (repeatDays <= 0) return false;
  return !Number.isFinite(at) || now - at >= repeatDays * DAY_MS;
};

// Stable 0-99 bucket per (user, card): the same user always lands in the same
// bucket for a given card, so a 10% rollout is 10% of people and not 10% of
// app opens.
const bucket = (userId, cardId) => {
  let h = 5381;
  const s = `${userId}:${cardId}`;
  for (let i = 0; i < s.length; i++) h = ((h * 33) ^ s.charCodeAt(i)) >>> 0;
  return h % 100;
};

const isPremium = (user) =>
  user.isPremium === true ||
  user.manuallyVerified === true ||
  ['active', 'trialing'].includes(user.subscriptionStatus) ||
  user.subscriptionTier === 'premium';

// Unknown evidence passes. A filter that cannot be evaluated must not silently
// mute a campaign — the failure people notice is a card nobody saw. The app
// build is not an audience question: `audience.minAppVersion` goes through
// the build gate below, where a too-old build still gets the card.
const audienceMatches = (card, user, { now } = {}) => {
  const a = card.audience || {};
  if (a.premium === true && !isPremium(user)) return false;
  if (a.premium === false && isPremium(user)) return false;
  if (Number.isFinite(Number(a.newerThanDays))) {
    const created = Date.parse(user.createdAt);
    if (Number.isFinite(created) && now - created > Number(a.newerThanDays) * DAY_MS) return false;
  }
  if (Number.isFinite(Number(a.olderThanDays))) {
    const created = Date.parse(user.createdAt);
    if (Number.isFinite(created) && now - created < Number(a.olderThanDays) * DAY_MS) return false;
  }
  const percent = Number(a.percent);
  if (Number.isFinite(percent) && percent < 100 && bucket(user.id, card.id) >= Math.max(0, percent)) return false;
  return true;
};

// Highest priority first, then the card that started most recently, so a
// campaign scheduled later supersedes an older one left running.
const byPriority = (x, y) =>
  (Number(y.priority) || 0) - (Number(x.priority) || 0) ||
  String(y.startsAt || '').localeCompare(String(x.startsAt || ''));

const ackKey = (card) => `card:${card.id}`;

// ---- Build gate: the one rule for "this needs a newer app" -----------------
// Shared by scheduled cards (homePromptService.liveCards) and catalog tips
// (homePrompt/cards.js). A card or tip that needs a build the person doesn't
// have still shows, as "update to get it" (Wes, 2026-10-07: don't ignore
// them) — under ONE key, so a build several features behind gets one nag per
// cadence, not one per feature. No version header = unknown build: shown
// as-is, never excluded on a guess.
const UPDATE_KEY = 'app_update';
const UPDATE_LINE = 'Update FavCircles in the App Store to get it.';

// The build a card or tip needs: its own minAppVersion, or its target's.
const requiredVersion = ({ minAppVersion, target } = {}) => {
  const forTarget = TARGET_MIN_VERSION[target] || null;
  if (!minAppVersion) return forTarget;
  if (!forTarget) return minAppVersion;
  return compareVersions(minAppVersion, forTarget) >= 0 ? minAppVersion : forTarget;
};

const needsNewerBuild = (minVersion, appVersion) =>
  !!(minVersion && appVersion && compareVersions(appVersion, minVersion) < 0);

// The "update to get it" version of a card. Builds that send X-FC-App-Store
// can open the App Store from it; older ones just close it ("Got it" — an
// unknown target only dismisses).
const updateCard = (card, { canOpenAppStore } = {}) => ({
  ...card,
  key: UPDATE_KEY,
  body: [card.body, UPDATE_LINE].filter(Boolean).join(' '),
  actionLabel: canOpenAppStore ? 'Update' : 'Got it',
  skipLabel: 'Later',
  target: canOpenAppStore ? 'app_store' : 'none',
  data: {}
});

// Shape the picker returns. `key` drives the per-user memory, so it stays
// stable for a card's life — reusing an id reuses its memory.
const toCard = (card) => ({
  key: ackKey(card),
  type: 'custom',
  title: card.title,
  body: card.body || '',
  actionLabel: card.actionLabel || 'Show me',
  skipLabel: card.skipLabel || 'Skip',
  target: card.target || '',
  data: card.data || {},
  imageUrl: card.imageUrl || null,
  presentation: card.presentation === 'inline' ? 'inline' : 'overlay',
  bypassInterval: card.bypassInterval === true,
  override: card.override === true
});

module.exports = {
  KNOWN_TARGETS,
  TARGET_MIN_VERSION,
  UPDATE_KEY,
  requiredVersion,
  needsNewerBuild,
  updateCard,
  windowOpen,
  cadenceDue,
  audienceMatches,
  byPriority,
  ackKey,
  toCard,
  compareVersions,
  bucket,
  isPremium
};
