// backend/services/dogPark/daily.js
//
// Daily Dog: an opt-in push at the times the person picks (1–3 a day,
// default 9 AM), quiet hours respected by notificationService. Each one is
// either Dog of the Day (yesterday's most-petted Dog Park post, picked once
// per day for everyone, on Charlotte's calendar) or a funny line from the
// seeded bank (config/dogLines.js), least recently sent first.
//
// Delivery follows quotesService: a Cloud Scheduler tick every 15 minutes,
// each person gated on their OWN local clock, and the slot's document id as
// the lock so a retried run can't send twice.
//
//   dogOfTheDay/{YYYY-MM-DD}                { postId|null, petCount, pickedAt }
//   dogDailySends/{uid_YYYY-MM-DD_HHMM}     { userId, dailyId, kind, text, postId, date, slot, sentAt }
//
// A DailyDog's id says what it is, so a shared link works for anyone:
// `dotd_<date>` or `line_<lineId>`.
const s = require('./shared');
const { ServiceError } = require('../../utils/serviceError');
const { localClock, localDateKey, zonedTimeToUtc, FALLBACK_ZONE } = require('../../utils/localClock');
const { nowIso } = require('../../utils/ids');
const LINES = require('../../config/dogLines');

const DEFAULT_PREFS = { enabled: false, times: ['09:00'] };
const MAX_TIMES = 3;
const RUN_WINDOW_MINUTES = 60;
const RECENT_MEMORY = 100;
const LIST_PAGE = 20;
const BATCH_SIZE = 25;
const TIME_RE = /^([01]\d|2[0-3]):[0-5]\d$/;
/** Dog of the Day runs on one calendar for everyone: Charlotte's */
const DOTD_ZONE = FALLBACK_ZONE;
const DOTD_SCAN = 1000;

const LINE_BY_ID = new Map(LINES.map((l) => [l.id, l]));

// ---------------------------------------------------------------------------
// Preferences (pure)
// ---------------------------------------------------------------------------

function normalizeTimes(list) {
  const times = [...new Set((Array.isArray(list) ? list : []).map((t) => String(t).trim()))].filter((t) => TIME_RE.test(t)).sort();
  return times.length ? times.slice(0, MAX_TIMES) : [...DEFAULT_PREFS.times];
}

const prefsOf = (user) => {
  const stored = (user && user.dogPrefs) || {};
  return { enabled: stored.enabled === true, times: normalizeTimes(stored.times) };
};

function normalizePrefs(input = {}, existing = {}) {
  const out = { ...DEFAULT_PREFS, ...existing };
  if (input.enabled !== undefined) out.enabled = input.enabled === true;
  if (input.times !== undefined) {
    if (!Array.isArray(input.times)) throw new ServiceError(400, 'bad_time', 'Times must be a list.');
    const times = [...new Set(input.times.map((t) => String(t).trim()))];
    if (!times.length) throw new ServiceError(400, 'bad_time', 'Pick at least one time.');
    if (times.length > MAX_TIMES) throw new ServiceError(400, 'bad_time', `Up to ${MAX_TIMES} times a day.`);
    if (times.some((t) => !TIME_RE.test(t))) throw new ServiceError(400, 'bad_time', 'Pick a time like 09:00.');
    out.times = times.sort();
  }
  out.times = normalizeTimes(out.times);
  return { enabled: out.enabled === true, times: out.times };
}

/** The person's slot ("HH:mm") whose hour contains `now`, in their zone. Pure. */
function dueSlot(user, now = new Date()) {
  const prefs = prefsOf(user);
  if (!prefs.enabled || (user && user.banned === true)) return null;
  const zone = ((user && user.notificationPreferences) || {}).timezone;
  const clock = localClock(zone, now);
  return prefs.times.find((slot) => {
    const [h, m] = slot.split(':').map((n) => parseInt(n, 10));
    const delta = clock.minutes - (h * 60 + m);
    return delta >= 0 && delta < RUN_WINDOW_MINUTES;
  }) || null;
}

const sendId = (uid, dateKey, slot) => `${uid}_${dateKey}_${String(slot).replace(':', '')}`;

/** Least recently sent wins; random among the unseen. Pure (random injectable). */
function pickLine(recentIds = [], { random = Math.random, lines = LINES } = {}) {
  if (!lines.length) return null;
  const recent = new Set(recentIds);
  const unseen = lines.filter((l) => !recent.has(l.id));
  const pool = unseen.length ? unseen : lines;
  return pool[Math.floor(random() * pool.length)];
}

/** The line everyone sees on a day nobody was sent anything. Pure. */
function lineOfTheDay(dateKey, lines = LINES) {
  const day = Math.floor(Date.parse(`${dateKey}T00:00:00Z`) / 86400000);
  return lines[((day % lines.length) + lines.length) % lines.length];
}

/** "2026-10-22" → "2026-10-21". Pure. */
const previousDay = (dateKey) => new Date(Date.parse(`${dateKey}T00:00:00Z`) - 86400000).toISOString().slice(0, 10);

/** The most-petted post among `rows` ({id, data}), at least one pet; ties: earliest. Pure. */
function pickTopPost(rows) {
  let best = null;
  for (const r of rows) {
    const pets = r.data.petCount || 0;
    if (pets < 1) continue;
    if (!best || pets > best.pets || (pets === best.pets && String(r.data.createdAt) < String(best.createdAt))) {
      best = { id: r.id, pets, createdAt: r.data.createdAt };
    }
  }
  return best;
}

// ---------------------------------------------------------------------------
// Dog of the Day
// ---------------------------------------------------------------------------

/**
 * The Dog of the Day for `dateKey` (Charlotte's calendar): yesterday's
 * most-petted visible post. Picked once and stored; a race keeps the first.
 */
async function ensureDogOfTheDay(dateKey) {
  const ref = s.dotdCol().doc(dateKey);
  const existing = await ref.get();
  if (existing.exists) return existing.data();
  const start = zonedTimeToUtc(previousDay(dateKey), '00:00', DOTD_ZONE).toISOString();
  const end = zonedTimeToUtc(dateKey, '00:00', DOTD_ZONE).toISOString();
  const snap = await s.postsCol().where('createdAt', '>=', start).where('createdAt', '<', end)
    .orderBy('createdAt', 'asc').limit(DOTD_SCAN).get();
  const rows = snap.docs.map((d) => ({ id: d.id, data: d.data() }));
  const authors = await s.authorsOf(rows.map((r) => r.data));
  // Seen by nobody in particular: no blocks, but never hidden/removed/test accounts
  const visible = rows.filter((r) => s.canSeePost(r.data, null, { authors }) && !r.data.moderationStatus);
  const top = pickTopPost(visible);
  const pick = { date: dateKey, postId: top ? top.id : null, petCount: top ? top.pets : 0, pickedAt: nowIso() };
  try {
    await ref.create(pick);
    return pick;
  } catch (e) {
    const again = await ref.get();
    return again.exists ? again.data() : pick;
  }
}

const dotdText = (post, pets) => `🏆 ${s.dogNames(post.dogs, 'This good dog')} got petted ${pets.toLocaleString('en-US')} ${pets === 1 ? 'time' : 'times'} yesterday. Give one more?`;

// ---------------------------------------------------------------------------
// Reading
// ---------------------------------------------------------------------------

function lineItem(line, dateKey) {
  return { id: `line_${line.id}`, date: dateKey, kind: line.kind, text: line.text, post: null, shareUrl: s.dailyShareUrl(`line_${line.id}`) };
}

/** A Dog of the Day as the viewer sees it, or null when it has no post they may see. */
async function dotdItem(dateKey, uid, viewer) {
  const pick = await ensureDogOfTheDay(dateKey);
  if (!pick || !pick.postId) return null;
  const doc = await s.postsCol().doc(pick.postId).get();
  if (!doc.exists) return null;
  const [post] = await s.present([doc], uid, viewer);
  if (!post) return null;
  const id = `dotd_${dateKey}`;
  return { id, date: dateKey, kind: 'dogOfTheDay', text: dotdText(doc.data(), pick.petCount || post.petCount), post, shareUrl: s.dailyShareUrl(id) };
}

/** One DailyDog by id (`dotd_<date>` | `line_<lineId>`). Anyone signed in may open it. */
async function getDaily(uid, id) {
  const viewer = await s.loadUser(uid);
  const today = localDateKey(DOTD_ZONE);
  const raw = String(id || '');
  if (raw.startsWith('line_')) {
    const line = LINE_BY_ID.get(raw.slice(5));
    if (line) return { item: lineItem(line, today) };
  } else if (raw.startsWith('dotd_')) {
    const date = raw.slice(5);
    if (/^\d{4}-\d{2}-\d{2}$/.test(date) && date <= today) {
      const item = await dotdItem(date, uid, viewer);
      if (item) return { item };
    }
  }
  throw new ServiceError(404, 'not_found', "That daily dog isn't here anymore");
}

/** What the widget shows today: the latest thing sent today, else today's pick or line. */
async function todayFor(uid, viewer, now = new Date()) {
  const zone = ((viewer && viewer.notificationPreferences) || {}).timezone;
  const dateKey = localDateKey(zone, now);
  const prefs = prefsOf(viewer);
  const docs = await s.db().getAll(...prefs.times.map((slot) => s.sendsCol().doc(sendId(uid, dateKey, slot))));
  const sent = docs.filter((d) => d.exists).map((d) => d.data()).sort((a, b) => (a.sentAt < b.sentAt ? 1 : -1));
  if (sent.length) {
    const item = await itemForSend(sent[0], uid, viewer);
    if (item) return item;
  }
  const dotd = await dotdItem(localDateKey(DOTD_ZONE, now), uid, viewer).catch(() => null);
  return dotd || lineItem(lineOfTheDay(dateKey), dateKey);
}

async function itemForSend(send, uid, viewer) {
  if (send.kind === 'dogOfTheDay') {
    const item = await dotdItem(String(send.dailyId || '').slice(5), uid, viewer).catch(() => null);
    return item ? { ...item, date: send.date } : null;
  }
  const line = LINE_BY_ID.get(String(send.dailyId || '').slice(5));
  return line ? lineItem(line, send.date) : { id: send.dailyId, date: send.date, kind: send.kind, text: send.text, post: null, shareUrl: s.dailyShareUrl(send.dailyId) };
}

/** Everything this person was sent, newest first. */
async function listDaily(uid, { before = null } = {}) {
  const viewer = await s.loadUser(uid);
  let q = s.sendsCol().where('userId', '==', uid);
  if (before && Number.isFinite(Date.parse(before))) q = q.where('sentAt', '<', new Date(Date.parse(before)).toISOString());
  const snap = await q.orderBy('sentAt', 'desc').limit(LIST_PAGE + 1).get();
  const sends = snap.docs.slice(0, LIST_PAGE).map((d) => d.data());
  // sentAt rides along as the paging cursor (?before=)
  const items = (await Promise.all(sends.map(async (send) => {
    const item = await itemForSend(send, uid, viewer);
    return item ? { ...item, sentAt: send.sentAt } : null;
  }))).filter(Boolean);
  return { items, hasMore: snap.docs.length > LIST_PAGE };
}

async function getSettings(uid) {
  const user = await s.loadUser(uid);
  return { prefs: prefsOf(user) };
}

async function updateSettings(uid, input = {}) {
  const user = await s.loadUser(uid);
  const prefs = normalizePrefs({ enabled: input.enabled, times: input.times }, user.dogPrefs || {});
  await s.usersCol().doc(uid).update({ dogPrefs: prefs, updatedAt: nowIso() });
  return { prefs };
}

// ---------------------------------------------------------------------------
// Delivery
// ---------------------------------------------------------------------------

async function loadCandidates(userId) {
  if (userId) {
    const doc = await s.usersCol().doc(String(userId)).get();
    return doc.exists ? [{ id: doc.id, ...doc.data() }] : [];
  }
  // Equality on a nested field: no composite index
  const snap = await s.usersCol().where('dogPrefs.enabled', '==', true).get();
  return snap.docs.map((d) => ({ id: d.id, ...d.data() }));
}

/** What one slot sends: today's Dog of the Day the first time they'd see it, else a line. */
async function chooseFor(user, { dotdDate }) {
  const dotdId = `dotd_${dotdDate}`;
  if (user.dogLastDotd !== dotdId) {
    const item = await dotdItem(dotdDate, user.id, user).catch(() => null);
    if (item) return { kind: 'dogOfTheDay', dailyId: dotdId, text: item.text, postId: item.post.id };
  }
  const line = pickLine(user.dogLineRecentIds || []);
  if (!line) return null;
  return { kind: line.kind, dailyId: `line_${line.id}`, text: line.text, postId: null, lineId: line.id };
}

const PUSH_TITLES = { dogOfTheDay: '🏆 Dog of the Day', joke: '🐶 Daily Dog', line: '🐶 Daily Dog', fact: '🐾 Dog fact' };

async function sendToUser(user, { now = new Date(), dryRun = false, dotdDate = localDateKey(DOTD_ZONE, now) } = {}) {
  const zone = (user.notificationPreferences || {}).timezone;
  const dateKey = localDateKey(zone, now);
  const slot = dueSlot(user, now) || prefsOf(user).times[0];
  const pick = await chooseFor(user, { dotdDate });
  if (!pick) return { sent: false, reason: 'nothing_to_send' };
  if (dryRun) return { sent: false, reason: 'dry_run', preview: { userId: user.id, ...pick } };
  // The slot's document id is the lock: a retried run stops here
  try {
    await s.sendsCol().doc(sendId(user.id, dateKey, slot)).create({
      userId: user.id, dailyId: pick.dailyId, kind: pick.kind, text: pick.text, postId: pick.postId || null,
      date: dateKey, slot, sentAt: now.toISOString()
    });
  } catch (e) {
    return { sent: false, reason: 'already_sent' };
  }
  await require('../notificationService').sendToUser(user.id, {
    type: 'daily_dog',
    title: PUSH_TITLES[pick.kind] || PUSH_TITLES.line,
    body: pick.text,
    data: { type: 'daily_dog', dailyId: pick.dailyId, ...(pick.postId ? { postId: pick.postId } : {}) }
  });
  const patch = { updatedAt: nowIso() };
  if (pick.kind === 'dogOfTheDay') patch.dogLastDotd = pick.dailyId;
  if (pick.lineId) patch.dogLineRecentIds = [...(user.dogLineRecentIds || []), pick.lineId].slice(-RECENT_MEMORY);
  await s.usersCol().doc(user.id).update(patch);
  return { sent: true, dailyId: pick.dailyId };
}

async function runDue({ now = new Date(), userId = null, force = false, dryRun = false } = {}) {
  const users = await loadCandidates(userId);
  const due = force ? users : users.filter((u) => dueSlot(u, now) !== null);
  const results = { candidates: users.length, due: due.length, sent: 0, skipped: 0, dryRun };
  const dotdDate = localDateKey(DOTD_ZONE, now);
  if (due.length) await ensureDogOfTheDay(dotdDate).catch((e) => console.error('🐶 dog of the day failed:', e.message));
  for (let i = 0; i < due.length; i += BATCH_SIZE) {
    await Promise.all(due.slice(i, i + BATCH_SIZE).map(async (user) => {
      try {
        const outcome = await sendToUser(user, { now, dryRun, dotdDate });
        if (outcome.sent) results.sent += 1; else results.skipped += 1;
      } catch (error) {
        console.error(`🐶 daily dog failed for ${user.id}:`, error.message);
        results.skipped += 1;
      }
    }));
  }
  return results;
}

module.exports = {
  getSettings, updateSettings, getDaily, listDaily, todayFor, runDue, sendToUser, ensureDogOfTheDay,
  // pure (tested)
  DEFAULT_PREFS, MAX_TIMES, prefsOf, normalizePrefs, dueSlot, sendId, pickLine, lineOfTheDay, previousDay, pickTopPost, dotdText
};
