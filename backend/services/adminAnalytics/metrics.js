// backend/services/adminAnalytics/metrics.js
//
// Pure aggregations for the admin dashboard. Every function takes plain
// arrays (already fetched) and `now`, so the numbers are unit-testable and
// the loader can change without touching the math.
const DAY = 24 * 60 * 60 * 1000;

/** Any date shape Firestore hands back → Date, or null. */
const toDate = (v) => {
  if (!v) return null;
  if (v instanceof Date) return Number.isNaN(v.getTime()) ? null : v;
  if (typeof v.toDate === 'function') return v.toDate();
  if (typeof v._seconds === 'number') return new Date(v._seconds * 1000);
  if (typeof v === 'number') return new Date(v);
  const d = new Date(v);
  return Number.isNaN(d.getTime()) ? null : d;
};

const dayKey = (d) => d.toISOString().slice(0, 10);

/** Every day key from `from` to `to` inclusive (UTC days). */
const daysBetween = (from, to) => {
  const out = [];
  const start = new Date(Date.UTC(from.getUTCFullYear(), from.getUTCMonth(), from.getUTCDate()));
  for (let t = start.getTime(); t <= to.getTime(); t += DAY) out.push(dayKey(new Date(t)));
  return out;
};

/** Count of items per day over [from, to]: [{ day, count }]. */
const perDay = (items, dateOf, from, to) => {
  const counts = new Map(daysBetween(from, to).map((d) => [d, 0]));
  for (const item of items) {
    const d = toDate(dateOf(item));
    if (!d || d < from || d > to) continue;
    const key = dayKey(d);
    if (counts.has(key)) counts.set(key, counts.get(key) + 1);
  }
  return [...counts].map(([day, count]) => ({ day, count }));
};

/** The latest sign of life we have for a user. */
const lastSeen = (user) => {
  const dates = [user.lastActive, user.lastAppOpenAt, user.lastLogin].map(toDate).filter(Boolean);
  return dates.length ? new Date(Math.max(...dates.map((d) => d.getTime()))) : null;
};

/** Daily / weekly / monthly active users as of `now`. */
const activeCounts = (users, now = new Date()) => {
  const within = (days) => users.filter((u) => {
    const seen = lastSeen(u);
    return seen && now - seen <= days * DAY;
  }).length;
  return { dau: within(1), wau: within(7), mau: within(30) };
};

/**
 * Funnel for users who signed up in [from, to]. `counts` maps userId →
 * { places, connections }.
 */
const funnel = (users, counts, from, to) => {
  const cohort = users.filter((u) => {
    const c = toDate(u.createdAt);
    return c && c >= from && c <= to;
  });
  const c = (u) => counts.get(u.id) || { places: 0, connections: 0 };
  return [
    { step: 'Signed up', count: cohort.length },
    { step: 'Finished onboarding', count: cohort.filter((u) => u.onboardingCompleted === true).length },
    { step: 'Saved a place', count: cohort.filter((u) => c(u).places >= 1).length },
    { step: 'Saved 5+ places', count: cohort.filter((u) => c(u).places >= 5).length },
    { step: 'Made a connection', count: cohort.filter((u) => c(u).connections >= 1).length }
  ];
};

/** Monday-start week key for a date (UTC). */
const weekKey = (d) => {
  const day = (d.getUTCDay() + 6) % 7; // Monday = 0
  return dayKey(new Date(d.getTime() - day * DAY));
};

/**
 * Weekly retention: for each signup week, the share of that week's signups
 * active in each later week. `activityByUser` maps userId → [Date...].
 * Returns [{ week, size, weeks: [pct week0, pct week1, ...] }] newest last.
 */
const retention = (users, activityByUser, now = new Date(), maxWeeks = 8) => {
  const cohorts = new Map();
  for (const u of users) {
    const created = toDate(u.createdAt);
    if (!created || now - created > maxWeeks * 7 * DAY) continue;
    const key = weekKey(created);
    if (!cohorts.has(key)) cohorts.set(key, []);
    cohorts.get(key).push(u);
  }
  const out = [];
  for (const [week, members] of [...cohorts].sort()) {
    const start = new Date(`${week}T00:00:00Z`);
    const elapsed = Math.floor((now - start) / (7 * DAY));
    const weeks = [];
    for (let w = 0; w <= Math.min(elapsed, maxWeeks - 1); w++) {
      const lo = start.getTime() + w * 7 * DAY;
      const hi = lo + 7 * DAY;
      const active = members.filter((m) => (activityByUser.get(m.id) || []).some((d) => d.getTime() >= lo && d.getTime() < hi)).length;
      weeks.push(Math.round((active / members.length) * 100));
    }
    out.push({ week, size: members.length, weeks });
  }
  return out;
};

/** Postcards: sales by month, refunds subtracted, failed/canceled ignored. */
const postcardMoney = (orders) => {
  const byMonth = new Map();
  let count = 0; let grossCents = 0; let refundedCents = 0;
  for (const o of orders) {
    const status = String(o.status || '');
    if (['canceled', 'cancelled', 'failed', 'pending_payment', 'requires_payment'].includes(status)) continue;
    if (o.complimentary || o.prepaid) continue; // free resends and Fridge Mail cards aren't sales
    const cents = Number(o.amountCents) || 0;
    const created = toDate(o.createdAt);
    const month = created ? created.toISOString().slice(0, 7) : 'unknown';
    const refunded = Boolean(o.refundedAt) || status === 'refunded';
    const row = byMonth.get(month) || { month, orders: 0, grossCents: 0, refundedCents: 0 };
    row.orders++; row.grossCents += cents; if (refunded) row.refundedCents += cents;
    byMonth.set(month, row);
    count++; grossCents += cents; if (refunded) refundedCents += cents;
  }
  return { count, grossCents, refundedCents, netCents: grossCents - refundedCents, byMonth: [...byMonth.values()].sort((a, b) => a.month.localeCompare(b.month)) };
};

/** FavCoins ledger by status. */
const coinSummary = (rows) => {
  const out = { pending: 0, confirmed: 0, reversed: 0, claimed: 0, settled: 0, other: 0 };
  for (const r of rows) {
    const coins = Number(r.coins) || 0;
    const s = String(r.status || 'other');
    if (s === 'pending') out.pending += coins;
    else if (s === 'confirmed') out.confirmed += coins;
    else if (s === 'reversed') out.reversed += coins;
    else if (s.startsWith('claim')) out.claimed += coins;
    else if (s === 'settled') out.settled += coins;
    else out.other += coins;
  }
  for (const k of Object.keys(out)) out[k] = Math.round(out[k] * 100) / 100;
  return out;
};

/** Can a push reach them? Mirrors services/emailFallback.pushReachable, as a label. */
const pushState = (user) => {
  const tokens = Array.isArray(user.deviceTokens) ? user.deviceTokens.length : 0;
  const status = user.pushStatus && user.pushStatus.status;
  if (!tokens) return 'no_token';
  if (!status) return 'unknown';
  return ['authorized', 'provisional', 'ephemeral'].includes(status) ? 'on' : 'off';
};

module.exports = {
  DAY, toDate, dayKey, daysBetween, perDay, lastSeen, activeCounts, funnel, weekKey, retention,
  postcardMoney, coinSummary, pushState
};
