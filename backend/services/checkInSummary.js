// services/checkInSummary.js
//
// The top of the Check In screen: why check in, in your own numbers — how
// many check-ins, how many places, this month, your weekly streak — and which
// of your people are out somewhere right now. Only the viewer's own history;
// friends come through the same visibility gate as GET /check-ins/active.

const DAY = 24 * 60 * 60 * 1000;

/** Monday 00:00 UTC of the week holding `ms`, as a day number. Pure. */
const weekOf = (ms) => {
  const day = Math.floor(ms / DAY);
  return day - ((day + 3) % 7); // 1970-01-01 was a Thursday
};

/**
 * Fold the viewer's check-ins into the header numbers. Pure.
 * weekStreak counts consecutive weeks with a check-in, ending this week —
 * or last week, when this week has none yet (the streak is still alive;
 * checkedInThisWeek says whether today's keeps it going).
 */
function summarize(checkIns, now = Date.now()) {
  const times = [];
  const places = new Set();
  let last = null;
  for (const c of checkIns) {
    const ms = Date.parse(c.startTime || c.createdAt);
    if (!Number.isFinite(ms)) continue;
    times.push(ms);
    const key = c.globalPlaceId || c.placeId || String(c.placeName || '').trim().toLowerCase();
    if (key) places.add(key);
    if (!last || ms > last.ms) last = { ms, placeName: c.placeName || null };
  }
  const d = new Date(now);
  const monthStart = Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), 1);
  const weeks = new Set(times.map(weekOf));
  const thisWeek = weekOf(now);
  let streak = 0;
  let w = weeks.has(thisWeek) ? thisWeek : thisWeek - 7;
  while (weeks.has(w)) { streak += 1; w -= 7; }
  return {
    total: times.length,
    thisMonth: times.filter((t) => t >= monthStart).length,
    places: places.size,
    weekStreak: streak,
    checkedInThisWeek: weeks.has(thisWeek),
    lastPlaceName: last ? last.placeName : null,
    lastAt: last ? new Date(last.ms).toISOString() : null
  };
}

/** People out right now, newest first, one row each, never the viewer. Pure. */
function friendsOut(visible, viewerId, limit = 8) {
  const seen = new Set([String(viewerId)]);
  const out = [];
  for (const c of visible) {
    const id = String(c.userId || '');
    if (!id || seen.has(id)) continue;
    seen.add(id);
    out.push({ userId: id, displayName: c.userName || 'Someone', profilePicture: c.userPhoto || null, placeName: c.placeName || null });
    if (out.length >= limit) break;
  }
  return out;
}

module.exports = { summarize, friendsOut, weekOf };
