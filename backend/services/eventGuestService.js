// backend/services/eventGuestService.js
//
// Email invites and RSVPs for the Events widget (Wes, 2026-11-02: "allow
// email invites and rsvp similar to the functionality of evite.com").
//
// The coordinator invites anyone by email. Each guest gets their own reply
// link (/rsvp/<token>, outside the app's /app/* links so it always opens the
// page): Going / Maybe / Can't go, how many adults and kids, a note. No
// account needed; the same link changes the reply later. People in the app
// reply from the event itself (members[uid].rsvp; joining = Going).
//
// One guest list for the coordinator: members, in-app invitees and email
// guests with their replies and head counts, kept as `rsvpCounts` on the
// event. Guests see who's coming by name, never anyone's email address.
// Reminders go out the day before (task /event-reminders).
//
// Abuse guards (email to strangers is the spam risk): coordinator only,
// MAX_GUESTS per event, DAILY_EMAIL_CAP per coordinator per day, one resend
// per guest per RESEND_COOLDOWN, a few guest messages per event per day,
// every send through emailService's kill switch and bounce suppression, and
// a one-click "stop emails about this event" on every message.
const { FieldValue, FieldPath } = require('firebase-admin/firestore');
const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');
const { ServiceError } = require('../utils/serviceError');
const { clean, maskEmail } = require('../utils/text');
const { nowIso } = require('../utils/ids');
const { localDateKey } = require('../utils/localClock');
const notifyQuiet = require('./notifyQuiet');
const details = require('./eventDetails');

const GUESTS = 'eventGuests';
const QUOTA = 'eventEmailQuota';
const MAX_GUESTS = 150;
const MAX_PER_CALL = 50;
const DAILY_EMAIL_CAP = 200;
const RESEND_COOLDOWN_MS = 12 * 3600 * 1000;
const MESSAGES_PER_DAY = 5;
const MESSAGE_MAX = 1000;
const NOTE_MAX = 300;
const MAX_HEADS = 20;
const RSVPS = ['yes', 'maybe', 'no'];
const TOKEN_RE = /^[A-Za-z0-9_-]{20,40}$/;
const EMAIL_RE = /^[^\s@<>()",;:]+@[^\s@<>()",;:]+\.[A-Za-z]{2,}$/;
const PUBLIC_BASE = process.env.API_PUBLIC_BASE_URL || 'https://api.favcircles.com';

const db = () => getFirestore();
const guestsCol = () => db().collection(GUESTS);
const memberPath = (uid, ...rest) => new FieldPath('members', String(uid), ...rest);
const newGuestToken = () => require('crypto').randomBytes(18).toString('base64url'); // 24 chars

// ---------------------------------------------------------------------------
// Pure helpers (tested)
// ---------------------------------------------------------------------------

const normalizeEmail = (raw) => String(raw || '').trim().toLowerCase();
const isEmail = (raw) => EMAIL_RE.test(normalizeEmail(raw)) && normalizeEmail(raw).length <= 254;

/**
 * The guests a coordinator typed or picked: valid, de-duplicated addresses
 * with an optional name. Returns { guests, invalid }.
 */
const parseGuestList = (list) => {
  const seen = new Set();
  const guests = [];
  const invalid = [];
  for (const raw of Array.isArray(list) ? list : []) {
    const email = normalizeEmail(raw && typeof raw === 'object' ? raw.email : raw);
    if (!email) continue;
    if (!isEmail(email)) { invalid.push(email.slice(0, 80)); continue; }
    if (seen.has(email)) continue;
    seen.add(email);
    const name = raw && typeof raw === 'object' ? clean(raw.name, 60) : '';
    guests.push({ email, name });
  }
  return { guests, invalid };
};

const heads = (value, min, fallback) => {
  const n = parseInt(value, 10);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(min, Math.min(MAX_HEADS, n));
};

/** A reply from the page or the app: the choice, head counts, a note. */
const parseReply = (body = {}) => {
  const rsvp = String(body.rsvp || '').toLowerCase();
  if (!RSVPS.includes(rsvp)) throw new ServiceError(400, 'invalid_rsvp', 'Pick Going, Maybe or Can\'t go');
  const coming = rsvp !== 'no';
  return {
    rsvp,
    adults: coming ? heads(body.adults, 1, 1) : 0,
    kids: coming ? heads(body.kids, 0, 0) : 0,
    note: clean(body.note, NOTE_MAX),
    ...(body.name !== undefined ? { name: clean(body.name, 60) } : {})
  };
};

/** "Sam is going (+2)", "Sam might come", "Sam can't make it". */
const replyLine = (name, { rsvp, adults = 1, kids = 0 }) => {
  const extra = Math.max(0, (adults || 0) + (kids || 0) - 1);
  const plus = extra > 0 ? ` (+${extra})` : '';
  if (rsvp === 'yes') return `${name} is going${plus}`;
  if (rsvp === 'maybe') return `${name} might come${plus}`;
  return `${name} can't make it`;
};

const emptyBucket = () => ({ replies: 0, people: 0 });

/**
 * The guest list's totals: replies and heads for Going / Maybe / Can't go /
 * No reply. Members count as Going unless they said otherwise; email guests
 * who later joined in the app (linkedUserId) count once, as the member.
 * `guestTallies` (stored on the event as guestRsvpCounts) stands in for the
 * guest rows when they weren't read. Pure.
 */
const countRsvps = (event, guests = [], guestTallies = null) => {
  const counts = { yes: emptyBucket(), maybe: emptyBucket(), no: emptyBucket(), pending: emptyBucket() };
  const add = (rsvp, adults, kids) => {
    const bucket = counts[RSVPS.includes(rsvp) ? rsvp : 'pending'];
    bucket.replies += 1;
    bucket.people += rsvp === 'no' ? 0 : Math.max(1, (adults || 0) + (kids || 0));
  };
  const memberIds = event.memberIds || [];
  for (const uid of memberIds) {
    const m = (event.members || {})[uid] || {};
    add(m.rsvp || 'yes', m.adults || 1, m.kids || 0);
  }
  for (const uid of event.pendingInviteIds || []) {
    if (memberIds.includes(uid)) continue;
    const inv = (event.invited || {})[uid] || {};
    add(inv.rsvp === 'no' ? 'no' : 'pending', 1, 0);
  }
  for (const g of guests) {
    if (g.linkedUserId) continue;
    add(g.rsvp || 'pending', g.adults, g.kids);
  }
  if (!guests.length && guestTallies) {
    for (const key of Object.keys(counts)) {
      counts[key].replies += (guestTallies[key] && guestTallies[key].replies) || 0;
      counts[key].people += (guestTallies[key] && guestTallies[key].people) || 0;
    }
  }
  // A "no reply" is one person until they say otherwise
  counts.pending.people = counts.pending.replies;
  return counts;
};

/** Just the email guests' totals (what the event stores). Pure. */
const tallyGuests = (guests) => countRsvps({ memberIds: [], pendingInviteIds: [] }, guests);

/** What the coordinator sees for an email guest (the address is theirs to see). */
const toHostGuest = (id, g) => ({
  id,
  kind: 'email',
  name: g.name || '',
  email: g.email,
  rsvp: g.rsvp || 'pending',
  adults: g.adults || 0,
  kids: g.kids || 0,
  note: g.note || '',
  respondedAt: g.respondedAt || null,
  invitedAt: g.invitedAt || null,
  lastEmailedAt: g.lastEmailedAt || null,
  optedOut: !!g.optedOut,
  bounced: !!g.bounced,
  joinedInApp: !!g.linkedUserId
});

/** A guest as everyone else sees them: a first name and a reply, no address. */
const publicName = (g) => {
  const name = (g.name || '').trim();
  if (name) return name.split(/\s+/)[0];
  return 'A guest';
};

const quotaKey = (uid, now = new Date()) => `${uid}_${localDateKey('America/New_York', now)}`;

const rsvpUrl = (token, choice) => `${PUBLIC_BASE}/rsvp/${token}${choice ? `?r=${choice}` : ''}`;
const stopUrl = (token) => `${PUBLIC_BASE}/rsvp/${token}/stop`;
const calendarUrlForGuest = (token) => `${PUBLIC_BASE}/rsvp/${token}/event.ics`;
const calendarUrlForEvent = (inviteToken) => `${PUBLIC_BASE}/calendar/event/${inviteToken}.ics`;

// ---------------------------------------------------------------------------
// Reads
// ---------------------------------------------------------------------------

async function guestsOf(eventId) {
  const snap = await guestsCol().where('eventId', '==', String(eventId)).limit(MAX_GUESTS + 10).get();
  return snap.docs.map((d) => ({ id: d.id, ...d.data() }));
}

async function loadGuestByToken(token) {
  if (!TOKEN_RE.test(String(token || ''))) throw new ServiceError(404, 'not_found', "That invite link isn't valid");
  const snap = await guestsCol().where('token', '==', String(token)).limit(1).get();
  if (snap.empty) throw new ServiceError(404, 'not_found', "That invite link isn't valid");
  const doc = snap.docs[0];
  const eventDoc = await db().collection(COLLECTIONS.EVENTS).doc(doc.data().eventId).get();
  if (!eventDoc.exists || eventDoc.data().deletedAt) throw new ServiceError(404, 'not_found', "This event isn't here anymore");
  return { guestRef: doc.ref, guest: doc.data(), eventId: eventDoc.id, eventRef: eventDoc.ref, event: eventDoc.data() };
}

/**
 * Stores the email guests' totals on the event (members' replies live on the
 * event already and are counted when it's read). Returns the full totals.
 */
async function refreshCounts(eventId) {
  const eventRef = db().collection(COLLECTIONS.EVENTS).doc(String(eventId));
  const [doc, guests] = await Promise.all([eventRef.get(), guestsOf(eventId)]);
  if (!doc.exists) return null;
  await eventRef.update({ guestRsvpCounts: tallyGuests(guests), guestCount: guests.filter((g) => !g.linkedUserId).length });
  return countRsvps(doc.data(), guests);
}

/**
 * The guest list. The coordinator gets everyone with replies, notes and
 * email guests' addresses; members get names and replies only.
 */
async function listGuests(eventId, uid) {
  const { loadAsMember } = require('./eventService');
  const { data } = await loadAsMember(eventId, uid);
  const isHost = data.hostId === uid;
  const guests = await guestsOf(eventId);
  const { fetchUsersById, nameOf, photoOf } = require('./userLookup');
  const users = await fetchUsersById([...(data.memberIds || []), ...(data.pendingInviteIds || [])]);
  const people = [];
  for (const id of data.memberIds || []) {
    const m = (data.members || {})[id] || {};
    const card = users.get(String(id));
    people.push({
      id, kind: 'member', name: nameOf(card) || m.name || 'Member', avatarUrl: photoOf(card) || m.avatarUrl || null,
      rsvp: m.rsvp || 'yes', adults: m.adults || 1, kids: m.kids || 0,
      note: isHost ? (m.rsvpNote || '') : '', isHost: id === data.hostId, respondedAt: m.rsvpAt || m.joinedAt || null
    });
  }
  for (const id of data.pendingInviteIds || []) {
    if ((data.memberIds || []).includes(id)) continue;
    const inv = (data.invited || {})[id] || {};
    const card = users.get(String(id));
    people.push({
      id, kind: 'invited', name: nameOf(card) || inv.name || 'Invited', avatarUrl: photoOf(card) || null,
      rsvp: inv.rsvp === 'no' ? 'no' : 'pending', adults: 0, kids: 0, note: '', isHost: false, respondedAt: inv.rsvpAt || null
    });
  }
  for (const g of guests) {
    if (g.linkedUserId && (data.memberIds || []).includes(g.linkedUserId)) continue;
    people.push(isHost ? toHostGuest(g.id, g) : {
      id: g.id, kind: 'email', name: publicName(g), rsvp: g.rsvp || 'pending', adults: g.adults || 0, kids: g.kids || 0
    });
  }
  return {
    guests: people,
    counts: countRsvps(data, guests),
    // What the coordinator can still send today
    ...(isHost ? { emailsLeftToday: Math.max(0, DAILY_EMAIL_CAP - await usedToday(uid)), maxGuests: MAX_GUESTS } : {})
  };
}

// ---------------------------------------------------------------------------
// Quota
// ---------------------------------------------------------------------------

async function usedToday(uid) {
  const doc = await db().collection(QUOTA).doc(quotaKey(uid)).get();
  return doc.exists ? (doc.data().count || 0) : 0;
}

/** Reserves `n` sends against today's cap; throws when it would go over. */
async function reserveEmails(uid, n) {
  if (n <= 0) return;
  const ref = db().collection(QUOTA).doc(quotaKey(uid));
  await db().runTransaction(async (tx) => {
    const doc = await tx.get(ref);
    const used = doc.exists ? (doc.data().count || 0) : 0;
    if (used + n > DAILY_EMAIL_CAP) {
      throw new ServiceError(429, 'email_cap', `You can send ${Math.max(0, DAILY_EMAIL_CAP - used)} more event emails today`);
    }
    tx.set(ref, { uid, count: used + n, updatedAt: nowIso() }, { merge: true });
  });
}

// ---------------------------------------------------------------------------
// Email
// ---------------------------------------------------------------------------

async function hostName(event) {
  const { fetchUsersById, nameOf } = require('./userLookup');
  const users = await fetchUsersById([event.hostId]);
  return nameOf(users.get(String(event.hostId))) || event.hostName || 'A friend';
}

/** Sends one event email to one guest; records the outcome on the guest row. */
async function sendGuestEmail(guestRef, guest, event, eventId, kind, extra = {}) {
  const emailService = require('./emailService');
  const { renderEventEmail } = require('../views/eventEmails');
  const host = extra.hostName || await hostName(event);
  const email = renderEventEmail(kind, {
    eventId, event, guest, hostName: host,
    message: extra.message || '',
    links: {
      yes: rsvpUrl(guest.token, 'yes'), maybe: rsvpUrl(guest.token, 'maybe'), no: rsvpUrl(guest.token, 'no'),
      page: rsvpUrl(guest.token), stop: stopUrl(guest.token), calendar: calendarUrlForGuest(guest.token),
      app: event.joinOpen !== false && !event.endedAt ? `${PUBLIC_BASE}/app/event/${event.inviteToken}` : null,
      maps: details.mapsUrl(event)
    }
  });
  try {
    const result = await emailService.sendEmail({
      to: guest.email,
      subject: email.subject,
      html: email.html,
      text: email.text,
      fromName: `${host} via FavCircles`,
      headers: {
        'List-Unsubscribe': `<${stopUrl(guest.token)}>`,
        'List-Unsubscribe-Post': 'List-Unsubscribe=One-Click'
      },
      userTriggered: true
    });
    const sent = !!(result && result.success);
    await guestRef.update({
      lastEmailedAt: nowIso(),
      lastEmailKind: kind,
      emailStatus: sent ? 'sent' : (result && result.skipped) || 'skipped'
    });
    return sent;
  } catch (error) {
    console.warn(`🎟️ event ${kind} email to ${maskEmail(guest.email)} failed: ${error.message}`);
    await guestRef.update({ emailStatus: 'failed', lastEmailError: String(error.message).slice(0, 200) }).catch(() => {});
    return false;
  }
}

// ---------------------------------------------------------------------------
// Coordinator actions
// ---------------------------------------------------------------------------

async function loadAsHost(eventId, uid) {
  const { loadAsMember } = require('./eventService');
  const event = await loadAsMember(eventId, uid);
  if (event.data.hostId !== uid) throw new ServiceError(403, 'not_host', 'Only the coordinator can do that');
  if (event.data.endedAt) throw new ServiceError(400, 'ended', 'This event has ended');
  return event;
}

/**
 * Invite people by email. Skips addresses already on the list (and the
 * coordinator's own). Returns { invited, alreadyInvited, invalid, sent }.
 */
async function inviteByEmail(eventId, hostUid, { guests: list, message } = {}) {
  const { ref, data } = await loadAsHost(eventId, hostUid);
  const { guests: parsed, invalid } = parseGuestList(list);
  if (!parsed.length) {
    throw new ServiceError(400, 'no_emails', invalid.length ? 'Those don\'t look like email addresses' : 'Add an email address');
  }
  if (parsed.length > MAX_PER_CALL) throw new ServiceError(400, 'too_many', `Invite up to ${MAX_PER_CALL} at a time`);
  const existing = await guestsOf(ref.id);
  const known = new Set(existing.map((g) => g.email));
  const hostDoc = await db().collection(COLLECTIONS.USERS).doc(hostUid).get();
  const hostEmail = normalizeEmail(hostDoc.exists ? hostDoc.data().email : '');
  const fresh = parsed.filter((g) => !known.has(g.email) && g.email !== hostEmail);
  if (existing.length + fresh.length > MAX_GUESTS) {
    throw new ServiceError(400, 'guest_cap', `An event can have up to ${MAX_GUESTS} email guests`);
  }
  await reserveEmails(hostUid, fresh.length);

  const now = nowIso();
  const note = clean(message, MESSAGE_MAX);
  const host = await hostName(data);
  const rows = fresh.map((g) => ({
    ref: guestsCol().doc(),
    guest: {
      eventId: ref.id, email: g.email, name: g.name, token: newGuestToken(),
      rsvp: 'pending', adults: 0, kids: 0, note: '',
      invitedBy: hostUid, invitedAt: now, createdAt: now, optedOut: false
    }
  }));
  const batch = db().batch();
  rows.forEach(({ ref: r, guest }) => batch.set(r, guest));
  await batch.commit();

  let sent = 0;
  for (const { ref: r, guest } of rows) {
    // eslint-disable-next-line no-await-in-loop -- SMTP wants sends one at a time
    if (await sendGuestEmail(r, guest, data, ref.id, 'invite', { hostName: host, message: note })) sent += 1;
  }
  await refreshCounts(ref.id);
  return {
    invited: rows.length,
    sent,
    alreadyInvited: parsed.length - fresh.length,
    invalid,
    ...(await listGuests(ref.id, hostUid))
  };
}

/** Send the invite again (not more often than RESEND_COOLDOWN). */
async function resendInvite(eventId, hostUid, guestId) {
  const { ref, data } = await loadAsHost(eventId, hostUid);
  const doc = await guestsCol().doc(String(guestId)).get();
  if (!doc.exists || doc.data().eventId !== ref.id) throw new ServiceError(404, 'not_found', 'That guest isn\'t on this event');
  const guest = doc.data();
  if (guest.optedOut) throw new ServiceError(400, 'opted_out', `${guest.name || guest.email} asked not to get emails about this event`);
  if (guest.lastEmailedAt && Date.now() - Date.parse(guest.lastEmailedAt) < RESEND_COOLDOWN_MS) {
    throw new ServiceError(429, 'too_soon', 'You can send it again tomorrow');
  }
  await reserveEmails(hostUid, 1);
  const sent = await sendGuestEmail(doc.ref, guest, data, ref.id, guest.rsvp === 'pending' ? 'invite' : 'update');
  return { sent };
}

async function removeGuest(eventId, hostUid, guestId) {
  const { loadAsMember } = require('./eventService');
  const { ref, data } = await loadAsMember(eventId, hostUid);
  if (data.hostId !== hostUid) throw new ServiceError(403, 'not_host', 'Only the coordinator can do that');
  const doc = await guestsCol().doc(String(guestId)).get();
  if (!doc.exists || doc.data().eventId !== ref.id) return { removed: false };
  await doc.ref.delete();
  await refreshCounts(ref.id);
  return { removed: true };
}

/**
 * A message from the coordinator to email guests (by reply) and members in
 * the app (push). `audience`: 'all' | 'yes' | 'maybe' | 'pending' | 'going'
 * (Going + Maybe). Returns how many got it.
 */
async function messageGuests(eventId, hostUid, { text, audience = 'all' } = {}) {
  const { ref, data } = await loadAsHost(eventId, hostUid);
  const message = clean(text, MESSAGE_MAX);
  if (!message) throw new ServiceError(400, 'empty', 'Write a message');
  const today = localDateKey(data.timezone);
  const sentToday = data.guestMessages && data.guestMessages.day === today ? data.guestMessages.count || 0 : 0;
  if (sentToday >= MESSAGES_PER_DAY) throw new ServiceError(429, 'too_many_messages', 'That\'s enough messages for today');

  const wants = (rsvp) => {
    if (audience === 'all') return rsvp !== 'no';
    if (audience === 'going') return rsvp === 'yes' || rsvp === 'maybe';
    return rsvp === audience;
  };
  const guests = (await guestsOf(ref.id))
    .filter((g) => !g.optedOut && !(g.linkedUserId && (data.memberIds || []).includes(g.linkedUserId)) && wants(g.rsvp || 'pending'));
  await reserveEmails(hostUid, guests.length);
  await ref.update({ guestMessages: { day: today, count: sentToday + 1 }, updatedAt: nowIso() });

  const host = await hostName(data);
  let emailed = 0;
  for (const g of guests) {
    // eslint-disable-next-line no-await-in-loop -- sequential sends
    if (await sendGuestEmail(guestsCol().doc(g.id), g, data, ref.id, 'message', { hostName: host, message })) emailed += 1;
  }
  const members = (data.memberIds || []).filter((id) => id !== hostUid && wants(((data.members || {})[id] || {}).rsvp || 'yes'));
  members.forEach((id) => notifyQuiet.sendInBackground(id, {
    type: 'event_message',
    title: `${data.emoji || '🎉'} ${host} · ${data.name}`,
    body: message.slice(0, 180),
    data: { eventId: ref.id }
  }, 'event_message'));
  return { emailed, pushed: members.length };
}

/**
 * After the coordinator changes when or where: tell everyone still coming
 * (email guests who haven't said no, and members by push).
 */
async function notifyDetailsChanged(eventId, hostUid) {
  const { loadEvent } = require('./eventService');
  const { ref, data } = await loadEvent(eventId);
  const guests = (await guestsOf(ref.id)).filter((g) => !g.optedOut && g.rsvp !== 'no'
    && !(g.linkedUserId && (data.memberIds || []).includes(g.linkedUserId)));
  try {
    await reserveEmails(hostUid, guests.length);
  } catch (e) {
    return { emailed: 0, skipped: e.code || 'cap' };
  }
  const host = await hostName(data);
  let emailed = 0;
  for (const g of guests) {
    // eslint-disable-next-line no-await-in-loop -- sequential sends
    if (await sendGuestEmail(guestsCol().doc(g.id), g, data, ref.id, 'update', { hostName: host })) emailed += 1;
  }
  const when = details.whenLine(data);
  (data.memberIds || []).filter((id) => id !== hostUid && ((data.members || {})[id] || {}).rsvp !== 'no')
    .forEach((id) => notifyQuiet.sendInBackground(id, {
      type: 'event_message',
      title: `${data.emoji || '🎉'} ${data.name} changed`,
      body: [when, details.whereLine(data)].filter(Boolean).join(' · ') || 'Open it to see what\'s new',
      data: { eventId: ref.id }
    }, 'event_message'));
  return { emailed };
}

// ---------------------------------------------------------------------------
// Replies
// ---------------------------------------------------------------------------

function tellHost(event, eventId, name, reply) {
  notifyQuiet.sendInBackground(event.hostId, {
    type: 'event_rsvp',
    title: `${event.emoji || '🎉'} ${replyLine(name, reply)}`,
    body: reply.note ? `“${reply.note.slice(0, 140)}”` : event.name,
    data: { eventId }
  }, 'event_rsvp');
}

/** A member's own reply in the app (joining already counted as Going). */
async function replyAsMember(eventId, uid, body) {
  const { loadAsMember } = require('./eventService');
  const { ref, data } = await loadAsMember(eventId, uid);
  const reply = parseReply(body);
  const now = nowIso();
  await ref.update(
    memberPath(uid, 'rsvp'), reply.rsvp,
    memberPath(uid, 'adults'), reply.adults,
    memberPath(uid, 'kids'), reply.kids,
    memberPath(uid, 'rsvpNote'), reply.note,
    memberPath(uid, 'rsvpAt'), now,
    'updatedAt', now
  );
  const before = ((data.members || {})[uid] || {}).rsvp || 'yes';
  if (uid !== data.hostId && (before !== reply.rsvp || reply.note)) {
    const name = ((data.members || {})[uid] || {}).name || 'Someone';
    tellHost(data, ref.id, name, reply);
  }
  const counts = await refreshCounts(ref.id);
  return { rsvp: reply.rsvp, adults: reply.adults, kids: reply.kids, counts };
}

/** An in-app invitee saying they can't go (without joining). */
async function declineInvite(token, uid) {
  const { previewByToken, eventsCol } = require('./eventService');
  await previewByToken(token, uid); // validates the link
  const snap = await eventsCol().where('inviteToken', '==', String(token)).limit(1).get();
  const doc = snap.docs[0];
  if (!doc) throw new ServiceError(404, 'not_found', "That invite link isn't valid");
  const data = doc.data();
  if ((data.memberIds || []).includes(uid)) throw new ServiceError(400, 'member', 'You already joined. Change your reply in the event.');
  const fields = ['pendingInviteIds', FieldValue.arrayUnion(uid), new FieldPath('invited', uid, 'rsvp'), 'no',
    new FieldPath('invited', uid, 'rsvpAt'), nowIso(), 'updatedAt', nowIso()];
  if (!((data.invited || {})[uid] || {}).name) {
    const me = await db().collection(COLLECTIONS.USERS).doc(uid).get();
    fields.push(new FieldPath('invited', uid, 'name'), (me.exists && (me.data().displayName || '').trim()) || 'Friend');
  }
  await doc.ref.update(...fields);
  const name = ((data.invited || {})[uid] || {}).name || 'Someone';
  tellHost(data, doc.id, name, { rsvp: 'no' });
  await refreshCounts(doc.id);
  return { declined: true };
}

/** What the reply page shows for a guest link. */
async function guestPage(token) {
  const { guest, eventId, event } = await loadGuestByToken(token);
  const guests = await guestsOf(eventId);
  const { fetchUsersById, nameOf } = require('./userLookup');
  const users = await fetchUsersById([event.hostId, ...(event.memberIds || [])]);
  // Who's coming, by first name (never addresses): members, then guests
  const coming = [];
  for (const id of event.memberIds || []) {
    const m = (event.members || {})[id] || {};
    const rsvp = m.rsvp || 'yes';
    if (rsvp === 'no') continue;
    coming.push({ name: (nameOf(users.get(String(id))) || m.name || 'Member').split(/\s+/)[0], rsvp });
  }
  for (const g of guests) {
    if (g.token === guest.token) continue;
    if (g.linkedUserId && (event.memberIds || []).includes(g.linkedUserId)) continue;
    if (g.rsvp === 'yes' || g.rsvp === 'maybe') coming.push({ name: publicName(g), rsvp: g.rsvp });
  }
  return {
    eventId,
    event,
    hostName: nameOf(users.get(String(event.hostId))) || event.hostName || 'A friend',
    guest: { name: guest.name || '', rsvp: guest.rsvp || 'pending', adults: guest.adults || 1, kids: guest.kids || 0, note: guest.note || '', optedOut: !!guest.optedOut },
    coming,
    counts: countRsvps(event, guests),
    appUrl: event.joinOpen !== false && !event.endedAt ? `${PUBLIC_BASE}/app/event/${event.inviteToken}` : null,
    calendarUrl: event.startsAt ? calendarUrlForGuest(token) : null,
    googleCalendarUrl: details.googleCalendarUrl(event),
    mapsUrl: details.mapsUrl(event)
  };
}

/** A guest's reply from the page (a POST; GETs never change anything). */
async function replyAsGuest(token, body) {
  const { guestRef, guest, eventId, event } = await loadGuestByToken(token);
  if (event.endedAt) throw new ServiceError(400, 'ended', 'This event has ended');
  const reply = parseReply(body);
  const now = nowIso();
  const update = { rsvp: reply.rsvp, adults: reply.adults, kids: reply.kids, note: reply.note, respondedAt: now, updatedAt: now };
  if (reply.name) update.name = reply.name;
  await guestRef.update(update);
  const changed = guest.rsvp !== reply.rsvp || guest.adults !== reply.adults || guest.kids !== reply.kids || (reply.note && reply.note !== guest.note);
  if (changed) tellHost(event, eventId, reply.name || guest.name || guest.email.split('@')[0], reply);
  await refreshCounts(eventId);
  return { ...reply, eventId };
}

/** "Stop emails about this event" (also the one-click List-Unsubscribe). */
async function optOut(token) {
  const { guestRef, event } = await loadGuestByToken(token);
  await guestRef.update({ optedOut: true, optedOutAt: nowIso() });
  return { name: event.name };
}

/**
 * A person who joined in the app with the same address as an email guest:
 * the guest row now points at the member, so they're counted once.
 */
async function linkJoinedMember(eventId, uid, email) {
  const address = normalizeEmail(email);
  if (!address) return;
  const snap = await guestsCol().where('eventId', '==', String(eventId)).where('email', '==', address).limit(1).get();
  if (snap.empty) return;
  const g = snap.docs[0];
  await g.ref.update({ linkedUserId: uid, updatedAt: nowIso() });
  // Their emailed reply carries over to the member
  const gd = g.data();
  if (gd.rsvp && gd.rsvp !== 'pending') {
    await db().collection(COLLECTIONS.EVENTS).doc(String(eventId)).update(
      memberPath(uid, 'rsvp'), gd.rsvp, memberPath(uid, 'adults'), gd.adults || 1, memberPath(uid, 'kids'), gd.kids || 0
    );
  }
}

// ---------------------------------------------------------------------------
// The day-before reminder (task /event-reminders, hourly)
// ---------------------------------------------------------------------------

/**
 * Events whose reminderAt has passed: email Going/Maybe guests and push
 * Going/Maybe members, once (reminderAt is cleared first, so a retry or a
 * second run never repeats it).
 */
async function sendDueReminders(now = new Date()) {
  const events = db().collection(COLLECTIONS.EVENTS);
  const snap = await events.where('reminderAt', '<=', now.toISOString()).limit(50).get();
  let reminded = 0;
  let emailed = 0;
  for (const doc of snap.docs) {
    // eslint-disable-next-line no-await-in-loop -- one event at a time
    const claimed = await db().runTransaction(async (tx) => {
      const fresh = await tx.get(doc.ref);
      const d = fresh.data();
      if (!d || !d.reminderAt || d.reminderAt > now.toISOString()) return null;
      tx.update(doc.ref, { reminderAt: null, reminderSentAt: now.toISOString() });
      return d;
    });
    if (!claimed || claimed.deletedAt || claimed.endedAt || !claimed.startsAt) continue;
    // Too late to be useful (the job was down): skip rather than remind after the start
    if (Date.parse(claimed.startsAt) <= now.getTime()) continue;
    reminded += 1;
    const host = await hostName(claimed); // eslint-disable-line no-await-in-loop
    const guests = (await guestsOf(doc.id)) // eslint-disable-line no-await-in-loop
      .filter((g) => !g.optedOut && (g.rsvp === 'yes' || g.rsvp === 'maybe')
        && !(g.linkedUserId && (claimed.memberIds || []).includes(g.linkedUserId)));
    for (const g of guests) {
      // eslint-disable-next-line no-await-in-loop -- sequential sends
      if (await sendGuestEmail(guestsCol().doc(g.id), g, claimed, doc.id, 'reminder', { hostName: host })) emailed += 1;
    }
    const when = details.whenLine(claimed);
    (claimed.memberIds || []).filter((id) => ((claimed.members || {})[id] || {}).rsvp !== 'no')
      .forEach((id) => notifyQuiet.sendInBackground(id, {
        type: 'event_reminder',
        title: `${claimed.emoji || '🎉'} Tomorrow: ${claimed.name}`,
        body: [when, details.whereLine(claimed)].filter(Boolean).join(' · '),
        data: { eventId: doc.id }
      }, 'event_reminder'));
  }
  return { reminded, emailed };
}

/** Account deletion / event end housekeeping: an ended event sends nothing more. */
async function stopRemindersFor(eventId) {
  await db().collection(COLLECTIONS.EVENTS).doc(String(eventId)).update({ reminderAt: null }).catch(() => {});
}

module.exports = {
  // operations
  listGuests, inviteByEmail, resendInvite, removeGuest, messageGuests, notifyDetailsChanged,
  replyAsMember, declineInvite, guestPage, replyAsGuest, optOut, linkJoinedMember, sendDueReminders,
  refreshCounts, stopRemindersFor, loadGuestByToken,
  // pure (tested)
  parseGuestList, parseReply, replyLine, countRsvps, tallyGuests, toHostGuest, publicName, isEmail, normalizeEmail,
  rsvpUrl, stopUrl, calendarUrlForEvent, quotaKey,
  GUESTS, MAX_GUESTS, DAILY_EMAIL_CAP, RESEND_COOLDOWN_MS, MESSAGES_PER_DAY, TOKEN_RE
};
