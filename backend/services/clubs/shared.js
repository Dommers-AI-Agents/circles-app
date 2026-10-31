// backend/services/clubs/shared.js
//
// Clubs widget (Wes, 2026-10-21: "a new widget that revolves around clubs.
// Think a run club. People, event, days times, bulletin board or message
// board. Maybe both."). A club has an owner and organizers, members who join
// from a link, weekly meetups and one-off events (each date takes RSVPs), an
// organizers' bulletin that notifies everyone, and a members' board.
//
// Shared constants, collections and the pure helpers (tested): validation,
// the schedule → dated occurrences expansion in the club's own time zone, and
// what a member sees.
const { getFirestore } = require('../../config/firebase');
const { COLLECTIONS } = require('../../models/FirestoreModels');
const { ServiceError } = require('../../utils/serviceError');
const { clean } = require('../../utils/text');
const { localDateKey, zonedTimeToUtc, FALLBACK_ZONE } = require('../../utils/localClock');
const { atLeast } = require('../../utils/appVersion');
const { fetchUsersById, nameOf, photoOf } = require('../userLookup');

const NAME_MAX = 40;
const DESCRIPTION_MAX = 500;
const MAX_MEMBERS = 500;
const MAX_CLUBS_LISTED = 50;
const MAX_MEETUPS = 10;
const MAX_EVENTS = 50;
const MAX_INVITES_PER_CALL = 50;
const POST_MAX = 1000;
const REPLY_MAX = 500;
const POSTS_PAGE = 20;
const REPLIES_MAX = 200;
const UPCOMING_WEEKS = 6;
const UPCOMING_LIMIT = 12;
const MAX_LISTED_EVENTS = 20;
// A meetup that started up to an hour ago is still "on" (people are running)
const STILL_ON_MS = 60 * 60 * 1000;
const LINK_BASE = `${process.env.API_PUBLIC_BASE_URL || 'https://api.favcircles.com'}/app/club/`;
const TOKEN_RE = /^[A-Za-z0-9_-]{16,32}$/;
const TIME_RE = /^([01]\d|2[0-3]):([0-5]\d)$/;

/** Club invites go to 1.4.1 and newer (the first build with the Clubs widget). */
const CLUBS_MIN_CLIENT = { version: '1.4.1' };

const KINDS = {
  run: { emoji: '🏃', label: 'Run' },
  walk: { emoji: '🚶', label: 'Walk' },
  ride: { emoji: '🚴', label: 'Ride' },
  hike: { emoji: '🥾', label: 'Hike' },
  swim: { emoji: '🏊', label: 'Swim' },
  yoga: { emoji: '🧘', label: 'Yoga' },
  book: { emoji: '📚', label: 'Book club' },
  other: { emoji: '🤝', label: 'Club' }
};
const WEEKDAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

const db = () => getFirestore();
const clubsCol = () => db().collection(COLLECTIONS.CLUBS);
const rsvpsCol = () => db().collection(COLLECTIONS.CLUB_RSVPS);
const postsCol = () => db().collection(COLLECTIONS.CLUB_POSTS);
const repliesCol = () => db().collection(COLLECTIONS.CLUB_REPLIES);
const fieldValue = () => require('../../config/firebase').FieldValue;

const newToken = () => require('crypto').randomBytes(15).toString('base64url'); // 20 chars

// ---------------------------------------------------------------------------
// Validation (pure)
// ---------------------------------------------------------------------------

const cleanKind = (raw) => (KINDS[raw] ? raw : 'other');

const cleanEmoji = (raw, kind = 'other') => {
  const fallback = (KINDS[kind] || KINDS.other).emoji;
  if (typeof raw !== 'string') return fallback;
  const trimmed = raw.trim();
  return trimmed && [...trimmed].length <= 4 ? trimmed : fallback;
};

const cleanName = (raw) => {
  const name = clean(raw, NAME_MAX);
  if (!name) throw new ServiceError(400, 'invalid_name', 'Give the club a name');
  return name;
};

const cleanTimezone = (raw) => {
  const zone = typeof raw === 'string' ? raw.trim() : '';
  if (!zone) return FALLBACK_ZONE;
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: zone }).format(new Date());
    return zone;
  } catch (e) {
    return FALLBACK_ZONE;
  }
};

/** A meeting spot: a name, plus an address and coordinates when known. Null clears it. */
const parseSpot = (raw) => {
  if (raw === null || raw === undefined || raw === '') return null;
  if (typeof raw !== 'object') throw new ServiceError(400, 'invalid_spot', 'A meeting spot needs a name');
  const name = clean(raw.name, 120);
  if (!name) throw new ServiceError(400, 'invalid_spot', 'A meeting spot needs a name');
  const lat = Number(raw.lat);
  const lng = Number(raw.lng);
  const located = Number.isFinite(lat) && Number.isFinite(lng) && Math.abs(lat) <= 90 && Math.abs(lng) <= 180 && !(lat === 0 && lng === 0);
  return {
    name,
    address: clean(raw.address, 200) || null,
    lat: located ? lat : null,
    lng: located ? lng : null
  };
};

const parseMeetup = (body, kind = 'other') => {
  const b = body || {};
  const weekday = Number(b.weekday);
  if (!Number.isInteger(weekday) || weekday < 0 || weekday > 6) throw new ServiceError(400, 'invalid_weekday', 'Pick a day of the week');
  const time = String(b.time || '').trim();
  if (!TIME_RE.test(time)) throw new ServiceError(400, 'invalid_time', 'Pick a time');
  return {
    weekday,
    time,
    title: clean(b.title, 60) || `${WEEKDAYS[weekday]} ${(KINDS[kind] || KINDS.other).label.toLowerCase()}`,
    spot: parseSpot(b.spot),
    notes: clean(b.notes, 300) || ''
  };
};

const parseEvent = (body, now = new Date()) => {
  const b = body || {};
  const title = clean(b.title, 80);
  if (!title) throw new ServiceError(400, 'invalid_title', 'Give the event a name');
  const at = Date.parse(b.startsAt);
  if (!Number.isFinite(at)) throw new ServiceError(400, 'invalid_date', 'Pick a date and time');
  if (at < now.getTime() - STILL_ON_MS) throw new ServiceError(400, 'in_the_past', 'That time has already passed');
  if (at > now.getTime() + 400 * 86400000) throw new ServiceError(400, 'too_far', 'Pick a date within the next year');
  return { title, startsAt: new Date(at).toISOString(), spot: parseSpot(b.spot), notes: clean(b.notes, 300) || '' };
};

// ---------------------------------------------------------------------------
// Roles (pure)
// ---------------------------------------------------------------------------

const isMember = (club, uid) => Array.isArray(club.memberIds) && club.memberIds.includes(uid);
const isOrganizer = (club, uid) => club.ownerId === uid || (Array.isArray(club.organizerIds) && club.organizerIds.includes(uid));
const roleOf = (club, uid) => (club.ownerId === uid ? 'owner' : isOrganizer(club, uid) ? 'organizer' : 'member');
const isMuted = (club, uid) => !!(club.members && club.members[uid] && club.members[uid].muted);

/** Who a club push goes to: members, minus muted ones and anyone excluded. */
const pushTargets = (club, { only = null, exclude = [] } = {}) =>
  (only || club.memberIds || []).filter((id) => isMember(club, id) && !isMuted(club, id) && !exclude.includes(id));

/** Same rule as canOpenEvents: any phone, or the last-opened app, is new enough. */
function canOpenClubs(user) {
  const asClient = (version, build) => ({ version, build: parseInt(build, 10) });
  if (!user) return false;
  if (atLeast(asClient(user.appVersion, user.appBuild), CLUBS_MIN_CLIENT)) return true;
  return (Array.isArray(user.deviceTokens) ? user.deviceTokens : [])
    .some((t) => t && atLeast(asClient(t.appVersion, t.appBuild), CLUBS_MIN_CLIENT));
}

// ---------------------------------------------------------------------------
// When things happen (pure)
// ---------------------------------------------------------------------------

/** "2026-10-31" plus n calendar days (no clocks involved). */
const addDays = (dateKey, n) => {
  const [y, m, d] = dateKey.split('-').map((x) => parseInt(x, 10));
  const t = new Date(Date.UTC(y, m - 1, d + n));
  return { key: t.toISOString().slice(0, 10), weekday: t.getUTCDay() };
};

/**
 * The club's dated occurrences, soonest first: each weekly meetup on its
 * weekday for the next `weeks` weeks, plus upcoming one-off events. Times are
 * worked out on the club's own calendar (zonedTimeToUtc), so "Saturdays 7 AM"
 * stays 7 AM across a DST change. Keys: m_<meetupId>_<local date> / e_<eventId>.
 */
function upcomingOccurrences(club, now = new Date(), { weeks = UPCOMING_WEEKS, limit = UPCOMING_LIMIT } = {}) {
  const zone = cleanTimezone(club.timezone);
  const today = localDateKey(zone, now);
  const from = now.getTime() - STILL_ON_MS;
  const out = [];
  for (const meetup of club.schedule || []) {
    for (let i = 0; i <= weeks * 7; i++) {
      const day = addDays(today, i);
      if (day.weekday !== meetup.weekday) continue;
      const startsAt = zonedTimeToUtc(day.key, meetup.time, zone);
      if (startsAt.getTime() < from) continue;
      out.push({
        key: `m_${meetup.id}_${day.key}`, kind: 'meetup', sourceId: meetup.id, title: meetup.title,
        startsAt: startsAt.toISOString(), spot: meetup.spot || club.homeSpot || null, notes: meetup.notes || ''
      });
    }
  }
  for (const event of club.events || []) {
    if (Date.parse(event.startsAt) < from) continue;
    out.push({
      key: `e_${event.id}`, kind: 'event', sourceId: event.id, title: event.title,
      startsAt: event.startsAt, spot: event.spot || club.homeSpot || null, notes: event.notes || ''
    });
  }
  // The cap trims weekly meetups only: a one-off event (a race in five
  // weeks) is the thing people most need to see and RSVP to, so a club that
  // meets twice a week must never push it off the list
  const byTime = (a, b) => a.startsAt.localeCompare(b.startsAt);
  const meetups = out.filter((o) => o.kind === 'meetup').sort(byTime).slice(0, limit);
  const events = out.filter((o) => o.kind === 'event').sort(byTime).slice(0, MAX_LISTED_EVENTS);
  return [...meetups, ...events].sort(byTime);
}

/** "Thu, Nov 27 · 8 AM" on the club's calendar. */
function occurrenceLine(startsAt, timezone) {
  const d = new Date(startsAt);
  const zone = cleanTimezone(timezone);
  const day = d.toLocaleDateString('en-US', { timeZone: zone, weekday: 'short', month: 'short', day: 'numeric' });
  const time = d.toLocaleTimeString('en-US', { timeZone: zone, hour: 'numeric', minute: '2-digit' }).replace(':00', '');
  return `${day} · ${time}`;
}

/** "7 AM", "6:30 PM" */
const time12 = (hhmm) => {
  const [h, m] = hhmm.split(':').map((x) => parseInt(x, 10));
  return `${h % 12 === 0 ? 12 : h % 12}${m ? `:${String(m).padStart(2, '0')}` : ''} ${h < 12 ? 'AM' : 'PM'}`;
};

/** "Saturdays 7 AM · Wednesdays 6:30 PM" (in week order, starting Monday). */
function scheduleLine(schedule) {
  const order = (w) => (w + 6) % 7;
  const lines = [...(schedule || [])]
    .sort((a, b) => order(a.weekday) - order(b.weekday) || a.time.localeCompare(b.time))
    .map((m) => `${WEEKDAYS[m.weekday]}s ${time12(m.time)}`);
  return [...new Set(lines)].join(' · ');
}

// ---------------------------------------------------------------------------
// What a member sees (pure)
// ---------------------------------------------------------------------------

const memberInfo = (club, uid) => (club.members && club.members[uid]) || {};

// People are named as they are NOW: the mappers take a `users` map from
// fetchUsersById (see clubPeople) and fall back to the name/photo stored on
// the club, post or RSVP when the account is gone (Wes, 2026-10-31).
const NO_USERS = new Map();
const cardOf = (users, uid) => (users && uid ? users.get(String(uid)) : null);
const currentName = (users, uid, stored) => nameOf(cardOf(users, uid)) || stored;
const currentPhoto = (users, uid, stored) => photoOf(cardOf(users, uid)) || stored;
/** One batched users read for every person a response names. */
const clubPeople = (ids) => fetchUsersById(ids);
const ownerNameOf = (club, users = NO_USERS) => currentName(users, club.ownerId, club.ownerName);

const toClientMember = (club, uid, users = NO_USERS) => ({
  userId: uid,
  name: currentName(users, uid, memberInfo(club, uid).name) || 'Member',
  avatarUrl: currentPhoto(users, uid, memberInfo(club, uid).avatarUrl) || null,
  role: roleOf(club, uid),
  joinedAt: memberInfo(club, uid).joinedAt || null
});

const ROLE_ORDER = { owner: 0, organizer: 1, member: 2 };
const toClientMembers = (club, users = NO_USERS) => (club.memberIds || [])
  .map((uid) => toClientMember(club, uid, users))
  .sort((a, b) => ROLE_ORDER[a.role] - ROLE_ORDER[b.role] || a.name.localeCompare(b.name));

/** One occurrence with its RSVPs (rsvp = the clubRsvps doc data, or null). */
function toClientOccurrence(occ, rsvp, club, viewerId, users = NO_USERS) {
  const going = Object.entries((rsvp && rsvp.going) || {})
    .filter(([uid]) => isMember(club, uid))
    .sort((a, b) => String(a[1].at || '').localeCompare(String(b[1].at || '')))
    .map(([uid, g]) => ({
      userId: uid,
      name: currentName(users, uid, g.name || memberInfo(club, uid).name) || 'Member',
      avatarUrl: currentPhoto(users, uid, g.avatarUrl || memberInfo(club, uid).avatarUrl) || null
    }));
  const not = Object.keys((rsvp && rsvp.not) || {}).filter((uid) => isMember(club, uid));
  return {
    key: occ.key,
    kind: occ.kind,
    title: occ.title,
    startsAt: occ.startsAt,
    spot: occ.spot,
    notes: occ.notes,
    going,
    notGoingCount: not.length,
    myRsvp: going.some((g) => g.userId === viewerId) ? 'going' : not.includes(viewerId) ? 'not' : null
  };
}

const toClientSummary = (id, club, viewerId, next = null) => ({
  id,
  name: club.name,
  emoji: club.emoji || (KINDS[club.kind] || KINDS.other).emoji,
  kind: club.kind || 'other',
  memberCount: (club.memberIds || []).length,
  myRole: roleOf(club, viewerId),
  muted: isMuted(club, viewerId),
  next
});

/** Post shape: reactions summed by emoji, mine flagged. */
function toClientPost(id, post, club, viewerId, users = NO_USERS) {
  const counts = new Map();
  for (const [uid, emoji] of Object.entries(post.reactions || {})) {
    const row = counts.get(emoji) || { emoji, count: 0, mine: false };
    row.count += 1;
    if (uid === viewerId) row.mine = true;
    counts.set(emoji, row);
  }
  return {
    id,
    kind: post.kind,
    authorId: post.authorId,
    authorName: currentName(users, post.authorId, post.authorName) || 'Member',
    authorAvatar: currentPhoto(users, post.authorId, post.authorAvatar) || null,
    text: post.text || '',
    photoUrl: post.photoUrl || null,
    createdAt: post.createdAt,
    replyCount: post.replyCount || 0,
    reactions: [...counts.values()].sort((a, b) => b.count - a.count || a.emoji.localeCompare(b.emoji)),
    canDelete: post.authorId === viewerId || isOrganizer(club, viewerId)
  };
}

const toClientReply = (id, reply, club, viewerId, users = NO_USERS) => ({
  id,
  authorId: reply.authorId,
  authorName: currentName(users, reply.authorId, reply.authorName) || 'Member',
  authorAvatar: currentPhoto(users, reply.authorId, reply.authorAvatar) || null,
  text: reply.text || '',
  createdAt: reply.createdAt,
  canDelete: reply.authorId === viewerId || isOrganizer(club, viewerId)
});

// ---------------------------------------------------------------------------
// Loads
// ---------------------------------------------------------------------------

async function userSummary(uid) {
  const doc = await db().collection(COLLECTIONS.USERS).doc(uid).get();
  if (!doc.exists) throw new ServiceError(404, 'user_not_found', 'Account not found');
  const d = doc.data();
  return { data: d, name: (d.displayName && d.displayName.trim()) || 'Someone', avatarUrl: d.profilePicture || null };
}

async function loadClub(clubId) {
  const doc = await clubsCol().doc(String(clubId || '')).get();
  if (!doc.exists || doc.data().deletedAt) throw new ServiceError(404, 'not_found', "This club isn't here anymore");
  return { ref: doc.ref, id: doc.id, data: doc.data() };
}

async function loadAsMember(clubId, uid) {
  const club = await loadClub(clubId);
  if (!isMember(club.data, uid)) throw new ServiceError(403, 'not_member', 'Join the club to see it');
  return club;
}

async function loadAsOrganizer(clubId, uid) {
  const club = await loadAsMember(clubId, uid);
  if (!isOrganizer(club.data, uid)) throw new ServiceError(403, 'not_organizer', 'Only organizers can do that');
  return club;
}

async function loadByToken(token) {
  if (!TOKEN_RE.test(String(token || ''))) throw new ServiceError(404, 'not_found', "That invite link isn't valid");
  const snap = await clubsCol().where('inviteToken', '==', String(token)).limit(1).get();
  const doc = snap.docs.find((d) => !d.data().deletedAt);
  if (!doc) throw new ServiceError(404, 'not_found', "That invite link isn't valid");
  return { ref: doc.ref, id: doc.id, data: doc.data() };
}

/** The RSVP docs for a set of occurrences, by key. */
async function rsvpsFor(clubId, occurrences) {
  if (!occurrences.length) return new Map();
  const docs = await db().getAll(...occurrences.map((o) => rsvpsCol().doc(`${clubId}_${o.key}`)));
  return new Map(docs.map((d, i) => [occurrences[i].key, d.exists ? d.data() : null]));
}

module.exports = {
  NAME_MAX, DESCRIPTION_MAX, MAX_MEMBERS, MAX_CLUBS_LISTED, MAX_MEETUPS, MAX_EVENTS, MAX_INVITES_PER_CALL,
  POST_MAX, REPLY_MAX, POSTS_PAGE, REPLIES_MAX, LINK_BASE, KINDS, WEEKDAYS, CLUBS_MIN_CLIENT,
  db, clubsCol, rsvpsCol, postsCol, repliesCol, fieldValue, newToken,
  cleanKind, cleanEmoji, cleanName, cleanTimezone, parseSpot, parseMeetup, parseEvent,
  isMember, isOrganizer, roleOf, isMuted, pushTargets, canOpenClubs,
  upcomingOccurrences, occurrenceLine, scheduleLine, time12,
  toClientMember, toClientMembers, toClientOccurrence, toClientSummary, toClientPost, toClientReply,
  clubPeople, ownerNameOf,
  userSummary, loadClub, loadAsMember, loadAsOrganizer, loadByToken, rsvpsFor
};
