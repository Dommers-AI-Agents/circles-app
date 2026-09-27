// backend/services/ownActivity/shape.js
// Pure rules for the profile's Activity tab: which feed rows belong to which
// filter, how one row is presented, and the month's summary (counts, the
// check-in streak, the most visited place, "on this day"). No Firestore.
//
// The Activity tab is the owner's own history — everything they did,
// including what never reached the feed (private check-ins, postcards,
// Fridge Mail). Those rows are written with `metadata.ownerOnly` and the
// feed gate never shows them to anyone else.

const CATEGORY_TYPES = {
  checkins: ['check_in'],
  places: ['place_added', 'place', 'photo_uploaded', 'place_discovered', 'circle_created'],
  moments: ['video_uploaded', 'moment_uploaded'],
  sent: ['postcard_sent', 'postcard_mailed', 'fridgemail_sent', 'suggestion_sent'],
  social: ['place_liked', 'global_place_liked', 'video_liked', 'comment_added', 'place_commented',
    'circle_liked', 'circle_commented', 'comment_liked', 'user_followed', 'reaction_added', 'suggestion_accepted']
};
const FILTERS = ['all', ...Object.keys(CATEGORY_TYPES)];
const TYPE_TO_CATEGORY = new Map();
for (const [category, types] of Object.entries(CATEGORY_TYPES)) for (const t of types) TYPE_TO_CATEGORY.set(t, category);

/** The filter's category, or null for "all" / unknown. */
function normalizeFilter(filter) {
  return FILTERS.includes(filter) ? filter : 'all';
}

function categoryOf(type) {
  return TYPE_TO_CATEGORY.get(type) || null;
}

/** Whether a stored row belongs on the owner's timeline (some types are noise). */
function belongs(doc, filter = 'all') {
  const category = categoryOf(doc && doc.type);
  if (!category) return false;
  return filter === 'all' || filter === category;
}

const toIso = (value) => {
  if (!value) return null;
  if (typeof value.toDate === 'function') return value.toDate().toISOString();
  const d = value instanceof Date ? value : new Date(value);
  return Number.isNaN(d.getTime()) ? null : d.toISOString();
};

/**
 * One timeline row as the app renders it. `extras` carries what the row
 * itself doesn't hold (a moment's like and comment counts).
 */
function presentItem(doc, extras = {}) {
  const m = doc.metadata || {};
  const category = categoryOf(doc.type);
  return {
    id: doc.id,
    type: doc.type,
    category,
    timestamp: toIso(doc.timestamp || doc.createdAt),
    targetType: doc.targetType || null,
    targetId: doc.targetId || null,
    targetName: doc.targetName || null,
    circleName: doc.circleName || null,
    placeId: m.placeId || (doc.targetType === 'place' ? doc.targetId : null) || null,
    globalPlaceId: m.globalPlaceId || null,
    placeAddress: m.placeAddress || null,
    thumbnailUrl: m.videoThumbnail || m.placePhoto || m.imageUrl || null,
    message: m.message || m.comment || null,
    rating: Number.isFinite(m.rating) ? m.rating : null,
    companions: Array.isArray(m.companions) ? m.companions.slice(0, 6) : [],
    isPrivate: m.isPrivate === true || m.ownerOnly === true && doc.type === 'check_in',
    contentType: m.contentType || null,
    recipientName: m.recipientName || null,
    mailStatus: m.mailStatus || null,
    likeCount: Number.isFinite(extras.likeCount) ? extras.likeCount : null,
    commentCount: Number.isFinite(extras.commentCount) ? extras.commentCount : null
  };
}

// MARK: - Summary

/** "2026-09" bounds in the given zone, as [start, end) Dates. Defaults to the month of `now`. */
function monthBounds(month, { now = new Date(), timezone = 'UTC' } = {}) {
  const key = /^\d{4}-\d{2}$/.test(month || '') ? month : localMonthKey(now, timezone);
  const [y, m] = key.split('-').map((n) => parseInt(n, 10));
  // Midnight local at the first of the month, found by probing the offset.
  const start = zonedMidnight(y, m, 1, timezone);
  const end = m === 12 ? zonedMidnight(y + 1, 1, 1, timezone) : zonedMidnight(y, m + 1, 1, timezone);
  return { key, start, end };
}

function localMonthKey(date, timezone) {
  const parts = new Intl.DateTimeFormat('en-US', { timeZone: timezone, year: 'numeric', month: '2-digit' }).formatToParts(date);
  const get = (t) => parts.find((p) => p.type === t).value;
  return `${get('year')}-${get('month')}`;
}

/** The instant of local midnight on y-m-d in `timezone`. */
function zonedMidnight(y, m, d, timezone) {
  const guess = Date.UTC(y, m - 1, d);
  const offsetAt = (t) => {
    const parts = new Intl.DateTimeFormat('en-US', { timeZone: timezone, hour12: false, year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit' }).formatToParts(new Date(t));
    const get = (k) => parseInt(parts.find((p) => p.type === k).value, 10);
    const asUtc = Date.UTC(get('year'), get('month') - 1, get('day'), get('hour') % 24, get('minute'));
    return asUtc - t;
  };
  return new Date(guess - offsetAt(guess));
}

/** Local "YYYY-MM-DD" of an instant. */
function localDateKey(date, timezone) {
  const parts = new Intl.DateTimeFormat('en-US', { timeZone: timezone, year: 'numeric', month: '2-digit', day: '2-digit' }).formatToParts(date);
  const get = (t) => parts.find((p) => p.type === t).value;
  return `${get('year')}-${get('month')}-${get('day')}`;
}

/** ISO week key "YYYY-Www" of a local date key. */
function weekKey(dateKey) {
  const [y, m, d] = dateKey.split('-').map((n) => parseInt(n, 10));
  const date = new Date(Date.UTC(y, m - 1, d));
  const day = date.getUTCDay() || 7;
  date.setUTCDate(date.getUTCDate() + 4 - day);
  const yearStart = Date.UTC(date.getUTCFullYear(), 0, 1);
  const week = Math.ceil(((date - yearStart) / 86400000 + 1) / 7);
  return `${date.getUTCFullYear()}-W${String(week).padStart(2, '0')}`;
}

/** Previous ISO week key. */
function previousWeek(key) {
  const [y, w] = key.split('-W').map((n) => parseInt(n, 10));
  // Thursday of that week, minus 7 days, re-keyed.
  const jan4 = new Date(Date.UTC(y, 0, 4));
  const jan4Day = jan4.getUTCDay() || 7;
  const monday = new Date(jan4.getTime() + ((w - 1) * 7 - (jan4Day - 1)) * 86400000);
  const prev = new Date(monday.getTime() - 7 * 86400000);
  return weekKey(prev.toISOString().slice(0, 10));
}

/**
 * How many consecutive weeks, ending with the current one (or the one
 * before it, if this week hasn't had one yet), had at least one check-in.
 * `checkInDates` are local date keys, any order, any range.
 */
function checkInStreakWeeks(checkInDates, { now = new Date(), timezone = 'UTC' } = {}) {
  const weeks = new Set(checkInDates.map(weekKey));
  let key = weekKey(localDateKey(now, timezone));
  if (!weeks.has(key)) key = previousWeek(key);
  let streak = 0;
  while (weeks.has(key)) { streak += 1; key = previousWeek(key); }
  return streak;
}

/** The place checked into most: { name, count } or null. */
function mostVisited(checkIns) {
  const counts = new Map();
  for (const c of checkIns) {
    const name = c.targetName || (c.metadata && c.metadata.placeName) || null;
    if (!name) continue;
    counts.set(name, (counts.get(name) || 0) + 1);
  }
  let best = null;
  for (const [name, count] of counts) if (!best || count > best.count) best = { name, count };
  return best;
}

/**
 * The month's summary from its rows (the owner's own, any category).
 * `all` = every row of the month; `pastYearCheckIns` = check-ins from this
 * day a year ago (for "on this day").
 */
function summarize(rows, { now = new Date(), timezone = 'UTC', pastYearCheckIns = [] } = {}) {
  const counts = { checkins: 0, places: 0, moments: 0, sent: 0, social: 0 };
  const checkIns = [];
  for (const r of rows) {
    const category = categoryOf(r.type);
    if (!category) continue;
    counts[category] += 1;
    if (category === 'checkins') checkIns.push(r);
  }
  const dates = checkIns.map((c) => toIso(c.timestamp || c.createdAt)).filter(Boolean).map((iso) => localDateKey(new Date(iso), timezone));
  return {
    counts: { ...counts, postcards: rows.filter((r) => r.type === 'postcard_sent' || r.type === 'postcard_mailed').length },
    streakWeeks: checkInStreakWeeks(dates, { now, timezone }),
    mostVisited: mostVisited(checkIns),
    privateCheckIns: checkIns.filter((c) => c.metadata && (c.metadata.isPrivate === true || c.metadata.ownerOnly === true)).length,
    onThisDay: pastYearCheckIns.map((c) => ({ placeName: c.targetName || null, placeId: (c.metadata && c.metadata.placeId) || null, at: toIso(c.timestamp || c.createdAt) }))
  };
}

module.exports = {
  CATEGORY_TYPES, FILTERS, belongs, categoryOf, checkInStreakWeeks, localDateKey, monthBounds, mostVisited,
  normalizeFilter, presentItem, summarize, weekKey, zonedMidnight
};
