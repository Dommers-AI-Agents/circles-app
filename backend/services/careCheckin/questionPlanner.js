// backend/services/careCheckin/questionPlanner.js
// Pure: which question goes out at this slot. No Firestore, no clock — the
// scheduler hands in the plan's shape and what was asked recently, and gets
// one question back. Every "why did Dad get the PT question on a Tuesday"
// is answerable from a unit test here.
//
// The pool is the bank filtered by the care profile, minus the questions the
// owner muted, plus the owner's own questions. Then:
//   1. the parent's app must be able to answer the kind (older builds only
//      have the three mood buttons) — never send a question with no buttons;
//   2. nothing is asked twice in one day, and a question waits out its
//      `everyDays` before coming round again;
//   3. a weekday-pinned question (PT on Friday, refills on Monday) only
//      goes out on its day — at the last slot that suits it, so "did you go
//      to PT this week?" lands Friday evening, not before breakfast — and
//      then goes first;
//   4. otherwise the most overdue, best-fitting question wins: weight ×
//      days since it was last asked, scaled down when the time of day is
//      wrong for it (sleep at 7 PM), and up when the profile boosts it.
// Ties break on bank order so the result is stable.
const { BANK_BY_TEXT, applicable, phaseOf } = require('./questionBank');

const CUSTOM_EVERY_DAYS = 1;
const OFF_PHASE_FACTOR = 0.3;
const BOOST_FACTOR = 1.6;
/** A question never asked counts as this overdue: new questions get their turn soon, without swamping the daily ones. */
const NEVER_ASKED_DAYS = 3;

/** Whole days between two "YYYY-MM-DD" keys (b − a). */
function daysBetween(a, b) {
  const toUtc = (k) => {
    const [y, m, d] = String(k).split('-').map((n) => parseInt(n, 10));
    return Date.UTC(y, (m || 1) - 1, d || 1);
  };
  return Math.round((toUtc(b) - toUtc(a)) / 86400000);
}

/**
 * @param {object} args
 * @param {object} [args.profile]        care-profile flags
 * @param {Array}  [args.custom]         the owner's own questions [{id, text, kind, ...}]
 * @param {Array}  [args.muted]          bank ids the owner switched off
 * @param {boolean} [args.capable=false] the parent's app can answer non-mood kinds
 * @param {string} args.slot             "HH:mm"
 * @param {string[]} [args.slots]        all of the plan's times, to place weekday-pinned questions
 * @param {number} args.weekday          0 = Sunday … 6 = Saturday, parent-local
 * @param {string} args.dateKey          "YYYY-MM-DD", parent-local
 * @param {Array}  [args.recent]         [{questionId, dateKey}] newest first
 * @returns {object|null} the question, or null when nothing fits (all asked today)
 */
function pick({ profile = {}, custom = [], muted = [], capable = false, slot, slots, weekday, dateKey, recent = [] }) {
  const mutedSet = new Set(muted);
  const daySlots = [...new Set([...(Array.isArray(slots) && slots.length ? slots : []), slot])].sort();
  const pool = [
    ...applicable(profile).filter((q) => !mutedSet.has(q.id)),
    ...ownQuestions(custom)
  ].filter((q) => capable || q.kind === 'mood');

  const lastAsked = new Map();
  for (const r of recent) {
    if (r && r.questionId && r.dateKey && !lastAsked.has(r.questionId)) lastAsked.set(r.questionId, r.dateKey);
  }
  const phase = phaseOf(slot);

  let best = null;
  pool.forEach((q, order) => {
    const last = lastAsked.get(q.id);
    const since = last ? daysBetween(last, dateKey) : NEVER_ASKED_DAYS;
    if (last && since < (q.everyDays || 1)) return;            // asked today, or not due yet (a week is a week)
    if (Number.isInteger(q.weekday)) {
      if (q.weekday !== weekday) return;
      if (slot !== pinnedSlot(q, daySlots)) return;
    }

    let score = (q.weight || 1) * (since + 1);
    if (q.phases && !q.phases.includes(phase)) score *= OFF_PHASE_FACTOR;
    if (q.boost && profile[q.boost] === true) score *= BOOST_FACTOR;
    if (Number.isInteger(q.weekday)) score += 1000;            // its day: it goes first
    if (!best || score > best.score) best = { q, score, order };
  });
  return best ? best.q : null;
}

/**
 * The owner's own questions, as the planner sees them. One that is word for
 * word a bank question is dropped: the bank asks it with the right answers
 * (plans from before kinds carried the old defaults as mood questions —
 * "Did you get outside today?" with Doing great / Okay / Not so good).
 */
function ownQuestions(custom) {
  return custom
    .filter((q) => q && q.text && !BANK_BY_TEXT.has(q.text))
    .map((q) => ({ everyDays: CUSTOM_EVERY_DAYS, ...q, kind: q.kind || 'mood', custom: true }));
}

/** The slot a weekday-pinned question goes out at: the last one in its preferred time of day, else the day's last. */
function pinnedSlot(q, daySlots) {
  const suited = q.phases ? daySlots.filter((s) => q.phases.includes(phaseOf(s))) : daySlots;
  return (suited.length ? suited : daySlots)[(suited.length ? suited : daySlots).length - 1];
}

/** The questions the owner sees as "in rotation", with the reason each is there. */
function rotation({ profile = {}, custom = [], muted = [] }) {
  const mutedSet = new Set(muted);
  return [
    ...applicable(profile).map((q) => ({ ...q, source: 'bank', muted: mutedSet.has(q.id) })),
    ...ownQuestions(custom).map((q) => ({ ...q, source: 'custom', muted: false }))
  ];
}

module.exports = { daysBetween, pick, pinnedSlot, rotation };
