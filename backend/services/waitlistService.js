// backend/services/waitlistService.js
//
// A store's waitlist (Wes, 2026-11-09): what a restaurant or barber pays
// Yelp Guest Manager or Waitwhile for, with a free push instead of a paid
// text. Business only. A customer joins from the store's window App Clip,
// its place page, or (Phase 5) its web page; sees their place in line and
// the store's quoted wait; and gets a Time Sensitive push when the host
// taps Notify. The host's screen: the line in order, Notify / Seated / Remove.
//
//   waitlistEntries/{id} = { venueId, venueName, userId, name, partySize,
//     status: waiting → notified → seated | left | removed | expired,
//     joinedAt, notifiedAt?, closedAt?, quoteMinutes, placeId }
//
// Reads are equality filters only (venueId + status in […]), sorted here,
// so no composite index. One open entry per person per store. A notified
// guest who doesn't show in 15 minutes expires (told); a waiting entry
// older than 4 hours expires quietly (the store closed). Both run in the
// orders sweep. Settings live on the store: `waitlist.{enabled, quoteMinutes}`.
const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');
const { STICKER_COLLECTIONS } = require('../models/StickerModels');
const { ServiceError } = require('../utils/serviceError');
const { newId, nowIso } = require('../utils/ids');
const jwt = require('jsonwebtoken');

const GUEST_TOKEN_PURPOSE = 'web_waitlist';
const GUEST_TOKEN_TTL = '2d';
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

const ENTRIES = 'waitlistEntries';
const STATUS = {
  WAITING: 'waiting', NOTIFIED: 'notified', SEATED: 'seated',
  LEFT: 'left', REMOVED: 'removed', EXPIRED: 'expired'
};
const OPEN = [STATUS.WAITING, STATUS.NOTIFIED];
const LIMITS = {
  partyMin: 1, partyMax: 12,
  quoteMin: 5, quoteMax: 120, quoteDefault: 15,
  holdMinutes: 15,        // a notified guest has this long to show
  staleHours: 4,          // a waiting entry this old is a closed store
  nameMax: 60
};

const db = () => getFirestore();

// ---------- Settings ----------

const settingsOf = (venue) => {
  const w = (venue && venue.waitlist) || {};
  const quote = Number(w.quoteMinutes);
  return {
    enabled: w.enabled === true,
    quoteMinutes: Number.isInteger(quote) && quote >= LIMITS.quoteMin && quote <= LIMITS.quoteMax ? quote : LIMITS.quoteDefault
  };
};

const normalizeSettings = (input = {}) => {
  if (input.enabled !== undefined && typeof input.enabled !== 'boolean') {
    throw new ServiceError(400, 'invalid_waitlist', 'Waitlist must be on or off.');
  }
  const quote = input.quoteMinutes === undefined ? LIMITS.quoteDefault : Math.round(Number(input.quoteMinutes));
  if (!Number.isFinite(quote) || quote < LIMITS.quoteMin || quote > LIMITS.quoteMax) {
    throw new ServiceError(400, 'invalid_waitlist', `The quoted wait is ${LIMITS.quoteMin} to ${LIMITS.quoteMax} minutes.`);
  }
  return { enabled: input.enabled === true, quoteMinutes: quote, updatedAt: nowIso() };
};

/** What customers see: the waitlist while it's on and the plan is live; else null. */
const waitlistFor = (venue, { live }) => {
  const s = settingsOf(venue);
  return live && s.enabled ? { enabled: true, quoteMinutes: s.quoteMinutes } : null;
};

// ---------- Pure helpers ----------

const sortLine = (entries) => [...entries].sort((a, b) => String(a.joinedAt).localeCompare(String(b.joinedAt)));

/** Each open entry with its place in line (1-based), oldest first. */
const withPositions = (entries) => sortLine(entries).map((e, i) => ({ ...e, position: i + 1 }));

/** "about 15 min" for the front of the line; later parties add the quote per party ahead, capped. */
const estimateMinutes = (position, quoteMinutes) => Math.min(LIMITS.quoteMax * 2, quoteMinutes * Math.max(1, position));

const normalizeParty = (value) => {
  const n = Math.round(Number(value));
  if (!Number.isFinite(n) || n < LIMITS.partyMin || n > LIMITS.partyMax) {
    throw new ServiceError(400, 'invalid_party', `Party size is ${LIMITS.partyMin} to ${LIMITS.partyMax}.`);
  }
  return n;
};

// ---------- Reads ----------

const entryView = (id, e, quoteMinutes) => ({
  entryId: id,
  venueId: e.venueId,
  venueName: e.venueName || null,
  placeId: e.placeId || null,
  userId: e.userId,
  name: e.name || null,
  partySize: e.partySize,
  status: e.status,
  joinedAt: e.joinedAt,
  notifiedAt: e.notifiedAt || null,
  position: e.position || null,
  estimateMinutes: e.position ? estimateMinutes(e.position, quoteMinutes || e.quoteMinutes || LIMITS.quoteDefault) : null,
  holdMinutes: LIMITS.holdMinutes
});

async function openEntries(venueId) {
  const snap = await db().collection(ENTRIES).where('venueId', '==', venueId).where('status', 'in', OPEN).get();
  return withPositions(snap.docs.map((d) => ({ id: d.id, ...d.data() })));
}

/** The host's line, oldest first, with positions. */
async function line(venue) {
  const quote = settingsOf(venue).quoteMinutes;
  return (await openEntries(venue.venueId)).map((e) => entryView(e.id, e, quote));
}

/** How many are waiting or called right now. */
async function count(venueId) {
  return (await openEntries(venueId)).length;
}

/** This person's open entry at the store, with their place in line; null when none. */
async function mine(venueId, userId) {
  const entries = await openEntries(venueId);
  const own = entries.find((e) => e.userId && String(e.userId) === String(userId));
  return own ? entryView(own.id, own, own.quoteMinutes) : null;
}

// ---------- Web guests (the store's web page, Phase 5) ----------

/** A token that can read or leave one guest entry; `protect` rejects tokens with a purpose. */
const signGuestToken = (entryId) => jwt.sign({ entryId, purpose: GUEST_TOKEN_PURPOSE }, require('../config/secrets').jwtSecret(), { expiresIn: GUEST_TOKEN_TTL });
const verifyGuestToken = (token, entryId) => {
  try {
    const decoded = jwt.verify(String(token || ''), require('../config/secrets').jwtSecret(), { algorithms: ['HS256'] });
    return decoded.purpose === GUEST_TOKEN_PURPOSE && decoded.entryId === String(entryId);
  } catch (error) { return false; }
};

/**
 * Join from the store's web page without an account: a name, a party size
 * and an email, which is where "your table is ready" goes. Returns the entry
 * and a token for its status.
 */
async function joinGuest({ venueId, name, email, partySize, now = new Date() }) {
  const venue = await loadVenue(venueId);
  const settings = settingsOf(venue);
  const { isVenueBusinessLive } = require('./ownerSubscriptionService');
  if (!settings.enabled || !(await isVenueBusinessLive(venue))) {
    throw new ServiceError(409, 'waitlist_off', `${venue.venueName} isn't taking a waitlist right now.`);
  }
  const party = normalizeParty(partySize);
  const displayName = String(name || '').trim().replace(/\s+/g, ' ').slice(0, LIMITS.nameMax);
  if (displayName.length < 2) throw new ServiceError(400, 'bad_name', 'Tell the host who the table is for.');
  const address = String(email || '').trim().toLowerCase().slice(0, 120);
  if (!EMAIL_RE.test(address)) throw new ServiceError(400, 'bad_email', 'Enter the email we should notify when your table is ready.');

  const open = await openEntries(venue.venueId);
  const same = open.find((e) => e.guest && e.guest.email === address);
  if (same) return { entry: entryView(same.id, same, same.quoteMinutes), token: signGuestToken(same.id), alreadyInLine: true };

  const { venueGlobalPlaceId } = require('./venueHelpers');
  const placeId = await venueGlobalPlaceId(venue).catch(() => null);
  const id = newId();
  const entry = {
    venueId: venue.venueId, venueName: venue.venueName || null, placeId: placeId || null,
    userId: null, guest: { name: displayName, email: address }, name: displayName, partySize: party,
    status: STATUS.WAITING, joinedAt: now.toISOString(), quoteMinutes: settings.quoteMinutes
  };
  await db().collection(ENTRIES).doc(id).set(entry);
  notifyTeam(venue, entry).catch((e) => console.error('waitlist: team push failed', e.message));
  const placed = (await openEntries(venue.venueId)).find((e) => e.id === id);
  return { entry: entryView(id, placed || { ...entry, position: open.length + 1 }, settings.quoteMinutes), token: signGuestToken(id) };
}

/** A guest's entry by token: its status and place in line (null position once closed). */
async function guestStatus(entryId, token) {
  if (!verifyGuestToken(token, entryId)) throw new ServiceError(403, 'bad_token', 'That link is not valid.');
  const doc = await db().collection(ENTRIES).doc(String(entryId)).get();
  if (!doc.exists) throw new ServiceError(404, 'not_found', 'That spot in line was not found.');
  const e = doc.data();
  if (!OPEN.includes(e.status)) return entryView(doc.id, e, e.quoteMinutes);
  const placed = (await openEntries(e.venueId)).find((x) => x.id === doc.id);
  return entryView(doc.id, placed || e, e.quoteMinutes);
}

async function leaveGuest(entryId, token) {
  if (!verifyGuestToken(token, entryId)) throw new ServiceError(403, 'bad_token', 'That link is not valid.');
  const ref = db().collection(ENTRIES).doc(String(entryId));
  const doc = await ref.get();
  if (!doc.exists) throw new ServiceError(404, 'not_found', 'That spot in line was not found.');
  if (!OPEN.includes(doc.data().status)) return { left: true, status: doc.data().status };
  await ref.update({ status: STATUS.LEFT, closedAt: nowIso() });
  return { left: true, status: STATUS.LEFT };
}

async function loadVenue(venueId) {
  const doc = await db().collection(STICKER_COLLECTIONS.STICKER_VENUES).doc(String(venueId)).get();
  if (!doc.exists) throw new ServiceError(404, 'not_found', 'Store not found');
  return { venueId: doc.id, ...doc.data() };
}

// ---------- Customer ----------

/** Join the line: one open entry per person per store. Returns the entry with its position. */
async function join({ venueId, userId, partySize, name = null, now = new Date() }) {
  const venue = await loadVenue(venueId);
  const settings = settingsOf(venue);
  const { isVenueBusinessLive } = require('./ownerSubscriptionService');
  if (!settings.enabled || !(await isVenueBusinessLive(venue))) {
    throw new ServiceError(409, 'waitlist_off', `${venue.venueName} isn't taking a waitlist right now.`);
  }
  const party = normalizeParty(partySize);
  const existing = await mine(venue.venueId, userId);
  if (existing) return { ...existing, alreadyInLine: true };

  let displayName = String(name || '').trim().slice(0, LIMITS.nameMax);
  if (!displayName) {
    const userDoc = await db().collection(COLLECTIONS.USERS).doc(String(userId)).get();
    displayName = (userDoc.exists && (userDoc.data().firstName || userDoc.data().displayName)) || 'Guest';
  }
  const { venueGlobalPlaceId } = require('./venueHelpers');
  const placeId = await venueGlobalPlaceId(venue).catch(() => null);
  const id = newId();
  const entry = {
    venueId: venue.venueId, venueName: venue.venueName || null, placeId: placeId || null,
    userId: String(userId), name: displayName, partySize: party,
    status: STATUS.WAITING, joinedAt: now.toISOString(), quoteMinutes: settings.quoteMinutes
  };
  await db().collection(ENTRIES).doc(id).set(entry);
  notifyTeam(venue, entry).catch((e) => console.error('waitlist: team push failed', e.message));
  const result = await mine(venue.venueId, userId);
  return result || entryView(id, { ...entry, position: 1 }, settings.quoteMinutes);
}

async function leave(entryId, userId) {
  const ref = db().collection(ENTRIES).doc(String(entryId));
  const doc = await ref.get();
  if (!doc.exists || String(doc.data().userId) !== String(userId)) throw new ServiceError(404, 'not_found', 'That spot in line was not found.');
  if (!OPEN.includes(doc.data().status)) return { left: true, status: doc.data().status };
  await ref.update({ status: STATUS.LEFT, closedAt: nowIso() });
  return { left: true, status: STATUS.LEFT };
}

// ---------- Host ----------

const ACTIONS = {
  notify: { from: [STATUS.WAITING], to: STATUS.NOTIFIED },
  seat: { from: [STATUS.WAITING, STATUS.NOTIFIED], to: STATUS.SEATED },
  remove: { from: [STATUS.WAITING, STATUS.NOTIFIED], to: STATUS.REMOVED }
};

/** The host moves a party: notify (push: your table is ready), seat, remove. */
async function act(venue, entryId, action, { now = new Date() } = {}) {
  const rule = ACTIONS[action];
  if (!rule) throw new ServiceError(400, 'invalid_action', 'Notify, seat or remove.');
  const ref = db().collection(ENTRIES).doc(String(entryId));
  const doc = await ref.get();
  if (!doc.exists || doc.data().venueId !== venue.venueId) throw new ServiceError(404, 'not_found', 'That party is not in your line.');
  const e = doc.data();
  if (!rule.from.includes(e.status)) throw new ServiceError(409, 'wrong_status', `That party is already ${e.status}.`);
  const patch = { status: rule.to };
  if (action === 'notify') patch.notifiedAt = now.toISOString(); else patch.closedAt = now.toISOString();
  await ref.update(patch);
  const updated = { ...e, ...patch };
  if (action === 'notify') pushGuest(updated, 'ready');
  if (action === 'remove') pushGuest(updated, 'removed');
  return entryView(doc.id, updated, settingsOf(venue).quoteMinutes);
}

async function saveSettings(venue, input) {
  const settings = normalizeSettings(input);
  await db().collection(STICKER_COLLECTIONS.STICKER_VENUES).doc(venue.venueId).update({ waitlist: settings });
  return { enabled: settings.enabled, quoteMinutes: settings.quoteMinutes };
}

// ---------- Pushes ----------

const guestNotice = (e, kind) => ({
  ready: {
    type: 'waitlist_ready',
    title: `Your table is ready at ${e.venueName || 'the store'}`,
    body: `Head to the host stand — they'll hold it for ${LIMITS.holdMinutes} minutes.`
  },
  removed: {
    type: 'waitlist_update',
    title: `${e.venueName || 'The store'} took you off the waitlist`,
    body: 'Ask at the host stand if that was a mistake.'
  },
  expired: {
    type: 'waitlist_update',
    title: `Your spot at ${e.venueName || 'the store'} went to the next party`,
    body: `You were called ${LIMITS.holdMinutes} minutes ago. Join the line again when you're nearby.`
  }
}[kind]);

function pushGuest(e, kind) {
  const notice = guestNotice(e, kind);
  if (!notice) return;
  if (!e.userId) {
    // A web guest has no app: the same word, by email
    if (e.guest && e.guest.email) emailGuest(e, notice).catch((err) => console.error('waitlist: guest email failed', err.message));
    return;
  }
  require('./notifyQuiet').sendInBackground(e.userId, {
    type: notice.type, title: notice.title, body: notice.body,
    data: { venueId: e.venueId, placeId: e.placeId || null, entryId: e.entryId || null, status: e.status }
  }, notice.type);
}

async function emailGuest(e, notice) {
  const { escapeHtml } = require('../utils/text');
  const html = `<div style="font-family:-apple-system,Helvetica,Arial,sans-serif;max-width:520px">
<h2 style="margin:0 0 8px">${escapeHtml(notice.title)}</h2>
<p style="margin:0 0 14px;font-size:16px;line-height:1.5">${escapeHtml(notice.body)}</p>
<p style="color:#6B7280;font-size:13px">You joined the waitlist at ${escapeHtml(e.venueName || 'the store')} on its FavCircles page.</p>
</div>`;
  await require('./emailService').sendEmail({ to: e.guest.email, subject: notice.title, html, text: `${notice.title}\n\n${notice.body}` });
}

async function notifyTeam(venue, entry) {
  const { venueManagerIds } = require('./venueHelpers');
  const team = [venue.ownerUserId, ...venueManagerIds(venue)].filter(Boolean);
  const party = entry.partySize === 1 ? 'party of 1' : `party of ${entry.partySize}`;
  [...new Set(team.map(String))].forEach((uid) => require('./notifyQuiet').sendInBackground(uid, {
    type: 'waitlist_joined',
    title: `${entry.name} joined the waitlist`,
    body: `${party} at ${venue.venueName}. Tap Notify when their table is ready.`,
    data: { venueId: venue.venueId }
  }, 'waitlist_joined'));
}

// ---------- Sweep ----------

/** Called parties who didn't show expire (told); waiting entries older than 4 h close quietly. */
async function sweep({ now = new Date() } = {}) {
  const holdBy = new Date(now.getTime() - LIMITS.holdMinutes * 60000).toISOString();
  const staleBy = new Date(now.getTime() - LIMITS.staleHours * 3600000).toISOString();
  let expired = 0; let closed = 0;
  const notified = await db().collection(ENTRIES).where('status', '==', STATUS.NOTIFIED).where('notifiedAt', '<=', holdBy).limit(200).get();
  for (const doc of notified.docs) {
    const e = { entryId: doc.id, ...doc.data(), status: STATUS.EXPIRED };
    await doc.ref.update({ status: STATUS.EXPIRED, closedAt: now.toISOString() });
    pushGuest(e, 'expired');
    expired += 1;
  }
  const stale = await db().collection(ENTRIES).where('status', '==', STATUS.WAITING).where('joinedAt', '<=', staleBy).limit(200).get();
  for (const doc of stale.docs) {
    await doc.ref.update({ status: STATUS.EXPIRED, closedAt: now.toISOString() });
    closed += 1;
  }
  return { waitlistExpired: expired, waitlistClosed: closed };
}

module.exports = {
  ENTRIES, STATUS, OPEN, LIMITS,
  settingsOf, normalizeSettings, waitlistFor, withPositions, estimateMinutes, normalizeParty,
  line, count, mine, join, leave, act, saveSettings, sweep,
  joinGuest, guestStatus, leaveGuest, signGuestToken, verifyGuestToken
};
