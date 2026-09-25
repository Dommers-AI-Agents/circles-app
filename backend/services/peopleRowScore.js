// backend/services/peopleRowScore.js
// The order of the people row on the home screen, for connections and
// followed users alike: one scale, driven by what the other person DID
// lately. Someone with no activity — a brand account with twenty imported
// places and nothing since — does not belong in the top row, however many
// places they have. Pure: no Firestore, no clock of its own.
//
// Points:
//   their latest activity (a place, check-in, moment, comment, like):
//     40 for right now, sliding down by 1.2 a day to 4 at 30 days, then 0 —
//     so more recent always ranks higher, and a month of silence is worth
//     next to nothing
//   a message between you: this week +10 · this month +4
//   something of theirs you haven't seen yet: +5
//   places: no points — only a hair of a tie-break, so among equally quiet
//   people the one with more to look at comes first.
//
// `components` keeps the shape older clients decode (messages / engagement /
// content / recency / total); `engagement` is always 0.
const DAY_MS = 24 * 60 * 60 * 1000;
const RECENT_DAYS = 7;

const RECENCY_MAX = 40;
const RECENCY_PER_DAY = 1.2;
const RECENCY_WINDOW_DAYS = 30;
const MESSAGES = [[7, 10], [30, 4]];
const UNVIEWED = 5;
const PLACES_TIEBREAK_CAP = 500;

const ageInDays = (value, now) => {
  if (!value) return Infinity;
  const t = value instanceof Date ? value.getTime() : Date.parse(value);
  if (Number.isNaN(t)) return Infinity;
  return Math.max(0, (now - t) / DAY_MS);
};

const tiered = (days, tiers) => {
  for (const [limit, points] of tiers) if (days <= limit) return points;
  return 0;
};

/** 40 today, sliding to 4 at 30 days, 0 after; rounded to a tenth so the score reads. */
const recencyPoints = (days) => {
  if (days > RECENCY_WINDOW_DAYS) return 0;
  return Math.round(Math.max(0, RECENCY_MAX - RECENCY_PER_DAY * days) * 10) / 10;
};

/**
 * @param {object} person
 * @param {Date|string|null} [person.lastActivityAt]  when they last did something
 * @param {Date|string|null} [person.lastMessageAt]   last message between the two
 * @param {number} [person.totalPlaces]
 * @param {boolean} [person.hasUnviewedActivity]
 * @param {number} [now] epoch ms
 */
function scorePerson(person = {}, now = Date.now()) {
  const activityDays = ageInDays(person.lastActivityAt, now);
  const components = {
    messages: tiered(ageInDays(person.lastMessageAt, now), MESSAGES),
    engagement: 0,
    content: person.hasUnviewedActivity ? UNVIEWED : 0,
    recency: recencyPoints(activityDays),
    total: 0
  };
  components.total = Math.round((components.messages + components.content + components.recency) * 10) / 10;
  const tieBreak = Math.min(Math.max(0, person.totalPlaces || 0), PLACES_TIEBREAK_CAP) / 1000;
  return {
    score: Math.round((components.total + tieBreak) * 1000) / 1000,
    components,
    hasRecentActivity: activityDays <= RECENT_DAYS,
    calculatedAt: new Date(now)
  };
}

module.exports = { RECENT_DAYS, scorePerson };
