// backend/services/emailCadence.js — the week's emails, spread out (Wes,
// 2026-11-06: "someone isn't getting them Sunday Monday Tuesday… we need a
// better cadence").
//
//   Wednesday the weekly letter (dailySummaryService, each user's local hour)
//   Thursday  "People you may know" (new accounts following few people;
//             its job is paused while there are few new users, 2026-11-06)
//   Saturday  the map email, every other week (mapDigestService)
//
// The schedule lives on the Cloud Scheduler jobs; this rule is the backstop:
// a recap email never goes out within MIN_GAP_DAYS of another one, whatever
// day a job (or a manual rerun) fires.
const MIN_GAP_DAYS = 2;
const DAY_MS = 86400000;

const toMs = (value) => {
  if (!value) return null;
  if (typeof value.toDate === 'function') return value.toDate().getTime();
  const ms = new Date(value).getTime();
  return Number.isNaN(ms) ? null : ms;
};

/** When each recap email last reached this user (plain user doc). Pure. */
const lastRecapTimes = (user) => [
  user && user.lastWeeklySummary,
  user && user.followSuggestionEmail && user.followSuggestionEmail.lastSentAt,
  user && user.mapDigest && user.mapDigest.lastSentAt
].map(toMs).filter((ms) => ms !== null);

/** True when another recap email went to this user less than `days` ago. Pure. */
const recentlyEmailed = (user, now = Date.now(), days = MIN_GAP_DAYS) =>
  lastRecapTimes(user).some((ms) => now - ms < days * DAY_MS);

module.exports = { MIN_GAP_DAYS, recentlyEmailed, toMs };
