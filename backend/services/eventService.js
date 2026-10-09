// backend/services/eventService.js
//
// Events widget (first use: a "Party Bus", Wes 2026-10-04). A coordinator
// creates an event; people join from an in-app invite or a share link pasted
// into a group text (anyone with the link joins instantly; the coordinator can
// remove people and close joining). Members share photos only with each
// other, tag the places they go, and save a tagged place into a public circle
// named after the event on their own profile. Each member also gets an Inner
// Circle list named after the event holding the members they're CONNECTED to
// (Inner Circle stays connections-only); it's re-synced whenever a member
// joins/leaves and whenever a member opens the event (a connection made later
// lands then).
//
// Photo files are ordinary uploads (unguessable public URLs); "members only"
// is enforced by only ever returning them to members.

const { FieldValue, FieldPath } = require('firebase-admin/firestore');
const { getFirestore } = require('../config/firebase');
const { COLLECTIONS, createCircle, createPlace } = require('../models/FirestoreModels');
const { normalizeUserId } = require('./idService');
const { isBlockedEitherWay } = require('./moderationService');
const { getConnectedUserIds } = require('../utils/networkAccess');
const { isAllowedImageUrl } = require('./postcardShareService');
const { ServiceError } = require('../utils/serviceError');
const { newId, nowIso } = require('../utils/ids');
const { clean } = require('../utils/text');
const notifyQuiet = require('./notifyQuiet');
const { atLeast } = require('../utils/appVersion');

/**
 * Events invites go to 1.3.8 and newer (Wes, 2026-10-08: 1.3.7 users update
 * to 1.3.8 to use Events, even the 1.3.7 (8) builds that have the widget).
 */
const EVENTS_MIN_CLIENT = { version: '1.3.8' };

/**
 * Whether this person's app is new enough for an event invite: any of their
 * phones, or the app they last opened, is 1.3.8 or newer. Nothing recorded
 * means they haven't opened the app since July (it has reported its version
 * since). Pure.
 */
function canOpenEvents(user) {
  const asClient = (version, build) => ({ version, build: parseInt(build, 10) });
  if (!user) return false;
  if (atLeast(asClient(user.appVersion, user.appBuild), EVENTS_MIN_CLIENT)) return true;
  return (Array.isArray(user.deviceTokens) ? user.deviceTokens : [])
    .some((t) => t && atLeast(asClient(t.appVersion, t.appBuild), EVENTS_MIN_CLIENT));
}

const NAME_MAX = 40;
const DEFAULT_NAME = 'Party Bus';
const DEFAULT_EMOJI = '🚌';
const MAX_MEMBERS = 100;
const MAX_EVENTS_LISTED = 30;
const MAX_INVITES_PER_CALL = 50;
const PHOTO_PAGE = 200;
const CAPTION_MAX = 200;
const LINK_BASE = `${process.env.API_PUBLIC_BASE_URL || 'https://api.favcircles.com'}/app/event/`;
const TOKEN_RE = /^[A-Za-z0-9_-]{16,32}$/;
// One "new photos" push per uploader per event at most this often
const PHOTO_PUSH_COOLDOWN_MS = 15 * 60 * 1000;

const db = () => getFirestore();
// Member maps are keyed by user id, and some legacy ids contain dots — a
// dotted string field path would nest them wrongly. Always build the path.
const memberPath = (uid, ...rest) => new FieldPath('members', String(uid), ...rest);
const eventsCol = () => db().collection(COLLECTIONS.EVENTS);
const photosCol = () => db().collection(COLLECTIONS.EVENT_PHOTOS);
const placesCol = () => db().collection(COLLECTIONS.EVENT_PLACES);

// ---------------------------------------------------------------------------
// Pure helpers (tested)
// ---------------------------------------------------------------------------

const cleanEventName = (raw) => {
  const name = clean(raw, NAME_MAX);
  return name || DEFAULT_NAME;
};

const cleanEmoji = (raw) => {
  if (typeof raw !== 'string') return DEFAULT_EMOJI;
  const trimmed = raw.trim();
  // One grapheme-ish: emoji are short; anything long is not an emoji
  return trimmed && [...trimmed].length <= 4 ? trimmed : DEFAULT_EMOJI;
};

const newToken = () => require('crypto').randomBytes(15).toString('base64url'); // 20 chars

const isMember = (event, uid) => Array.isArray(event.memberIds) && event.memberIds.includes(uid);

const { parsePhotoCapture, distanceMeters, PHOTO_PLACE_RADIUS_M } = require('../utils/photoCapture');

/**
 * The tagged place a photo was taken at: the nearest one within
 * PHOTO_PLACE_RADIUS_M, or null. `places` are rows with id/name/lat/lng.
 * Worked out when read, so places tagged after the photo count too. Pure.
 */
const nearestTaggedPlace = (photo, places, radius = PHOTO_PLACE_RADIUS_M) => {
  if (!photo || !Number.isFinite(photo.lat) || !Number.isFinite(photo.lng)) return null;
  let best = null;
  for (const pl of Array.isArray(places) ? places : []) {
    if (!pl || !Number.isFinite(pl.lat) || !Number.isFinite(pl.lng)) continue;
    const d = distanceMeters(photo.lat, photo.lng, pl.lat, pl.lng);
    if (d <= radius && (!best || d < best.d)) best = { d, id: pl.id, name: pl.name };
  }
  return best ? { id: best.id, name: best.name } : null;
};

/** Validates a tagged place from the app (a search result or a saved place). */
const parsePlace = (body) => {
  const b = body || {};
  const name = clean(b.name, 120);
  const lat = Number(b.lat);
  const lng = Number(b.lng);
  if (!name) throw new ServiceError(400, 'invalid_place', 'A place needs a name');
  if (!Number.isFinite(lat) || !Number.isFinite(lng) || Math.abs(lat) > 90 || Math.abs(lng) > 180) {
    throw new ServiceError(400, 'invalid_place', 'A place needs a location');
  }
  return {
    name,
    address: clean(b.address, 200) || '',
    lat,
    lng,
    category: clean(b.category, 40) || 'other',
    placeRefId: clean(b.placeId, 80) || null,
    isGlobal: b.isGlobal === true
  };
};

/** What a member sees. Never includes tokens of other people's lists. */
const toClientEvent = (id, data, viewerId) => ({
  id,
  name: data.name,
  emoji: data.emoji || DEFAULT_EMOJI,
  hostId: data.hostId,
  hostName: data.hostName,
  isHost: data.hostId === viewerId,
  joinOpen: data.joinOpen !== false,
  createdAt: data.createdAt,
  photoCount: data.photoCount || 0,
  placeCount: data.placeCount || 0,
  members: (data.memberIds || []).map(uid => ({
    id: uid,
    name: (data.members && data.members[uid] && data.members[uid].name) || 'Member',
    avatarUrl: (data.members && data.members[uid] && data.members[uid].avatarUrl) || null,
    isHost: uid === data.hostId
  })),
  // Invited (in-app) and not joined yet — so the inviter sees it went out
  invited: (data.pendingInviteIds || []).filter(uid => !(data.memberIds || []).includes(uid)).map(uid => ({
    id: uid,
    name: (data.invited && data.invited[uid] && data.invited[uid].name) || 'Invited'
  })),
  inviteUrl: `${LINK_BASE}${data.inviteToken}`,
  // Archived: hidden from the viewer's list, album intact. By the
  // coordinator for everyone (also closes joining), or by a member for themselves.
  archivedForEveryone: !!data.archivedAt,
  archived: !!data.archivedAt || !!(data.members && data.members[viewerId] && data.members[viewerId].archivedAt),
  myCircleId: (data.members && data.members[viewerId] && data.members[viewerId].circleId) || null,
  // Ended events stay for their members with a recap (2026-10-06)
  endedAt: data.endedAt || null,
  challenges: (data.challenges || []).map(c => ({ id: c.id, text: c.text, emoji: c.emoji || '📸' })),
  rollCall: toClientRollCall(data, viewerId)
});

/** The roll call in progress, if any: who's said "here", and where (only
 *  for those who chose to share it, and only inside the event). */
const toClientRollCall = (data, viewerId) => {
  const rc = data.rollCall;
  if (!rc || !rc.id || rc.closedAt) return null;
  const here = rc.here || {};
  return {
    id: rc.id,
    startedAt: rc.startedAt,
    startedByName: rc.startedByName || data.hostName,
    hereIds: Object.keys(here).filter(uid => (data.memberIds || []).includes(uid)),
    imHere: !!here[viewerId],
    locations: Object.entries(rc.locations || {})
      .filter(([uid]) => (data.memberIds || []).includes(uid))
      .map(([uid, l]) => ({ userId: uid, lat: l.lat, lng: l.lng, at: l.at }))
  };
};

const toClientPhoto = (doc, viewerId, hostId, places = []) => {
  const d = doc.data();
  const likes = Array.isArray(d.likes) ? d.likes : [];
  const hasSpot = Number.isFinite(d.lat) && Number.isFinite(d.lng);
  const at = hasSpot ? nearestTaggedPlace(d, places) : null;
  return {
    id: doc.id,
    imageUrl: d.imageUrl,
    thumbUrl: d.thumbUrl || null,
    uploaderId: d.uploaderId,
    uploaderName: d.uploaderName,
    caption: d.caption || '',
    challengeId: d.challengeId || null,
    createdAt: d.createdAt,
    likeCount: likes.length,
    likedByMe: likes.includes(viewerId),
    canDelete: d.uploaderId === viewerId || hostId === viewerId,
    // Where and when it was taken, from the file (null when it had none)
    takenAt: d.takenAt || null,
    lat: hasSpot ? d.lat : null,
    lng: hasSpot ? d.lng : null,
    placeId: at ? at.id : null,
    placeName: at ? at.name : null
  };
};

const toClientPlace = (doc, viewerId) => {
  const d = doc.data();
  const savedBy = Array.isArray(d.savedBy) ? d.savedBy : [];
  return {
    id: doc.id,
    name: d.name,
    address: d.address || '',
    lat: d.lat,
    lng: d.lng,
    category: d.category || 'other',
    taggedById: d.taggedById,
    taggedByName: d.taggedByName,
    createdAt: d.createdAt,
    savedCount: savedBy.length,
    savedByMe: savedBy.includes(viewerId)
  };
};

/** Each member's event list: the other members they're connected to. */
const listMembersFor = (memberIds, uid, connectedIds) =>
  memberIds.filter(id => id !== uid && connectedIds.has(id));

// ---------------------------------------------------------------------------
// Reads
// ---------------------------------------------------------------------------

async function userSummary(uid) {
  const doc = await db().collection(COLLECTIONS.USERS).doc(uid).get();
  if (!doc.exists) throw new ServiceError(404, 'user_not_found', 'Account not found');
  const d = doc.data();
  return {
    data: d,
    name: (d.displayName && d.displayName.trim()) || 'Someone',
    avatarUrl: d.profilePicture || null
  };
}

async function loadEvent(eventId) {
  const doc = await eventsCol().doc(String(eventId)).get();
  if (!doc.exists || doc.data().deletedAt) throw new ServiceError(404, 'not_found', "This event isn't here anymore");
  return { ref: doc.ref, data: doc.data() };
}

async function loadAsMember(eventId, uid) {
  const event = await loadEvent(eventId);
  if (!isMember(event.data, uid)) throw new ServiceError(403, 'not_member', 'Join the event to see it');
  return event;
}

async function loadByToken(token) {
  if (!TOKEN_RE.test(String(token || ''))) throw new ServiceError(404, 'not_found', "That invite link isn't valid");
  const snap = await eventsCol().where('inviteToken', '==', String(token)).limit(1).get();
  const doc = snap.docs.find(d => !d.data().deletedAt);
  if (!doc) throw new ServiceError(404, 'not_found', "That invite link isn't valid");
  return { ref: doc.ref, data: doc.data(), id: doc.id };
}

/**
 * The viewer's events, newest first. `hideArchived`: leave out events
 * archived for everyone or by this viewer — for apps that predate archiving
 * and would otherwise list them as live (Brittany on 1.3.7 still saw the
 * archived Party Bus, 2026-10-08). Newer apps get them all and show
 * archived ones in their own section.
 */
async function listEvents(uid, { hideArchived = false } = {}) {
  const snap = await eventsCol()
    .where('memberIds', 'array-contains', uid)
    .orderBy('createdAt', 'desc')
    .limit(MAX_EVENTS_LISTED)
    .get();
  return snap.docs
    .filter(d => !d.data().deletedAt)
    .map(d => toClientEvent(d.id, d.data(), uid))
    .filter(e => !(hideArchived && e.archived));
}

async function getEvent(eventId, uid) {
  const { ref, data } = await loadAsMember(eventId, uid);
  const [photos, places] = await Promise.all([
    photosCol().where('eventId', '==', ref.id).orderBy('createdAt', 'desc').limit(PHOTO_PAGE).get(),
    placesCol().where('eventId', '==', ref.id).orderBy('createdAt', 'desc').limit(100).get()
  ]);
  // A connection made since the last visit joins the viewer's event list
  syncInnerListFor(ref, data, uid).catch(err => console.error('🚌 inner list sync failed:', err.message));
  const event = toClientEvent(ref.id, data, uid);
  // The coordinator sees who pushes can't reach (notifications off, or no
  // device), so they know to text those people about roll call etc.
  if (data.hostId === uid) event.pushOffMemberIds = await pushOffMembers(data, uid);
  const placeRows = places.docs.map(d => ({ id: d.id, ...d.data() }));
  return {
    event,
    photos: photos.docs.map(d => toClientPhoto(d, uid, data.hostId, placeRows)),
    places: places.docs.map(d => toClientPlace(d, uid))
  };
}

/** Members (not the viewer) a push can't reach — same rule as the email fallback. */
async function pushOffMembers(data, viewerId) {
  const ids = (data.memberIds || []).filter(id => id !== viewerId).slice(0, MAX_MEMBERS);
  if (!ids.length) return [];
  const { pushReachable } = require('./emailFallback');
  const docs = await db().getAll(...ids.map(id => db().collection(COLLECTIONS.USERS).doc(id)));
  return docs.filter(d => d.exists && !pushReachable(d.data())).map(d => d.id);
}

/** The join screen's preview (any signed-in person holding the link). */
async function previewByToken(token, uid) {
  const { id, data } = await loadByToken(token);
  return {
    id,
    name: data.name,
    emoji: data.emoji || DEFAULT_EMOJI,
    hostName: data.hostName,
    memberCount: (data.memberIds || []).length,
    joinOpen: data.joinOpen !== false,
    alreadyMember: isMember(data, uid)
  };
}

/** Public page data for /app/event/<token> (no auth, no member names). */
async function publicPreview(token) {
  const { data } = await loadByToken(token);
  return {
    name: data.name,
    emoji: data.emoji || DEFAULT_EMOJI,
    hostName: data.hostName,
    memberCount: (data.memberIds || []).length,
    joinOpen: data.joinOpen !== false
  };
}

// ---------------------------------------------------------------------------
// Membership
// ---------------------------------------------------------------------------

async function createEvent(uid, { name, emoji } = {}) {
  const me = await userSummary(uid);
  const now = nowIso();
  const data = {
    name: cleanEventName(name),
    emoji: cleanEmoji(emoji),
    hostId: uid,
    hostName: me.name,
    memberIds: [uid],
    members: { [uid]: { name: me.name, avatarUrl: me.avatarUrl, joinedAt: now } },
    pendingInviteIds: [],
    joinOpen: true,
    inviteToken: newToken(),
    photoCount: 0,
    placeCount: 0,
    createdAt: now,
    updatedAt: now
  };
  const ref = await eventsCol().add(data);
  return toClientEvent(ref.id, data, uid);
}

/**
 * Join from a link token (or an in-app invite, which carries the same
 * token). Instant; idempotent. Returns { event, joined, coinCredited }.
 */
async function joinByToken(token, uid) {
  const { ref } = await loadByToken(token);
  const me = await userSummary(uid);
  const result = await db().runTransaction(async (tx) => {
    const doc = await tx.get(ref);
    const data = doc.data();
    if (data.deletedAt) throw new ServiceError(404, 'not_found', "This event isn't here anymore");
    if (isMember(data, uid)) return { data, joined: false };
    if (data.joinOpen === false) throw new ServiceError(403, 'join_closed', `${data.hostName} closed joining for ${data.name}`);
    if ((data.removedIds || []).includes(uid)) throw new ServiceError(403, 'removed', `You were removed from ${data.name}`);
    if (isBlockedEitherWay(me.data, data.hostId)) throw new ServiceError(403, 'blocked', "You can't join this event");
    if ((data.memberIds || []).length >= MAX_MEMBERS) throw new ServiceError(403, 'full', `${data.name} is full`);
    const now = nowIso();
    tx.update(ref,
      'memberIds', FieldValue.arrayUnion(uid),
      'pendingInviteIds', FieldValue.arrayRemove(uid),
      memberPath(uid), { name: me.name, avatarUrl: me.avatarUrl, joinedAt: now },
      'updatedAt', now);
    return {
      data: {
        ...data,
        memberIds: [...(data.memberIds || []), uid],
        members: { ...(data.members || {}), [uid]: { name: me.name, avatarUrl: me.avatarUrl, joinedAt: now } }
      },
      joined: true
    };
  });

  let coinCredited = false;
  if (result.joined) {
    notifyQuiet.sendInBackground(result.data.hostId, {
      type: 'event_joined',
      title: `${result.data.emoji || DEFAULT_EMOJI} ${me.name} joined ${result.data.name}`,
      body: `${result.data.memberIds.length} people are in`,
      data: { eventId: ref.id }
    }, 'event_joined');
    if (process.env.WIDGET_PIGGY_ENABLED === '1') {
      const bonus = await require('./piggyBankService').credit({
        userId: uid, eventType: 'event_joined', sourceRef: { eventId: ref.id }
      });
      coinCredited = !!(bonus && bonus.credited);
    }
    syncAllInnerLists(ref.id).catch(err => console.error('🚌 inner list sync failed:', err.message));
  }
  return { event: toClientEvent(ref.id, result.data, uid), joined: result.joined, coinCredited };
}

/** In-app invites to the coordinator's or a member's connections. */
async function inviteConnections(eventId, uid, userIds) {
  const { ref, data } = await loadAsMember(eventId, uid);
  if (data.joinOpen === false) throw new ServiceError(403, 'join_closed', 'Joining is closed');
  const wanted = [...new Set((Array.isArray(userIds) ? userIds : []).map(normalizeUserId).filter(Boolean))]
    .filter(id => id !== uid && !isMember(data, id))
    .slice(0, MAX_INVITES_PER_CALL);
  if (!wanted.length) return { invited: 0 };
  const connected = await getConnectedUserIds(uid);
  const invitees = wanted.filter(id => connected.has(id));
  if (!invitees.length) throw new ServiceError(400, 'not_connected', 'You can invite people you are connected with');
  // Names for the "Invited" rows (one batched read)
  const userDocs = await db().getAll(...invitees.map(id => db().collection(COLLECTIONS.USERS).doc(id)));
  const fields = ['pendingInviteIds', FieldValue.arrayUnion(...invitees), 'updatedAt', nowIso()];
  userDocs.forEach((doc, i) => {
    const name = doc.exists ? ((doc.data().displayName || '').trim() || 'Friend') : 'Friend';
    fields.push(new FieldPath('invited', invitees[i]), { name, invitedAt: nowIso() });
  });
  await ref.update(...fields);
  const inviter = (data.members && data.members[uid] && data.members[uid].name) || 'A friend';
  invitees.forEach((id, i) => {
    // Below 1.3.8: ask them to update rather than send an invite their app
    // isn't meant to open (Wes, 2026-10-08). The invite stays pending either way.
    const hasEvents = canOpenEvents(userDocs[i].exists ? userDocs[i].data() : null);
    notifyQuiet.sendInBackground(id, {
      type: 'event_invite',
      title: `${data.emoji || DEFAULT_EMOJI} ${inviter} invited you to ${data.name}`,
      body: hasEvents
        ? 'Join to share photos and places with everyone there'
        : 'Update FavCircles in the App Store to join — then tap this invite again',
      data: { eventId: ref.id, eventToken: data.inviteToken, ...(hasEvents ? {} : { needsUpdate: 'true' }) }
    }, 'event_invite');
  });
  const fresh = (await ref.get()).data();
  return { invited: invitees.length, event: toClientEvent(ref.id, fresh, uid) };
}

async function leaveEvent(eventId, uid) {
  const { ref, data } = await loadAsMember(eventId, uid);
  if (data.hostId === uid) throw new ServiceError(400, 'host_cannot_leave', 'Coordinators end the event instead of leaving');
  await removeMemberInternal(ref, data, uid, { removed: false });
  return { left: true };
}

async function removeMember(eventId, hostUid, memberId) {
  const { ref, data } = await loadAsMember(eventId, hostUid);
  if (data.hostId !== hostUid) throw new ServiceError(403, 'not_host', 'Only the coordinator can remove people');
  const target = normalizeUserId(memberId);
  if (!target || target === hostUid) throw new ServiceError(400, 'invalid_member', "You can't remove yourself");
  if (!isMember(data, target)) return { removed: false };
  await removeMemberInternal(ref, data, target, { removed: true });
  return { removed: true };
}

async function removeMemberInternal(ref, data, uid, { removed }) {
  const listId = data.members && data.members[uid] && data.members[uid].innerListId;
  const fields = [
    'memberIds', FieldValue.arrayRemove(uid),
    memberPath(uid), FieldValue.delete(),
    'updatedAt', nowIso()
  ];
  if (removed) fields.push('removedIds', FieldValue.arrayUnion(uid));
  await ref.update(...fields);
  if (listId) {
    require('./innerCircleService').deleteInnerCircleList(uid, listId).catch(() => {});
  }
  syncAllInnerLists(ref.id).catch(err => console.error('🚌 inner list sync failed:', err.message));
}

async function updateEvent(eventId, hostUid, { name, emoji, joinOpen } = {}) {
  const { ref, data } = await loadAsMember(eventId, hostUid);
  if (data.hostId !== hostUid) throw new ServiceError(403, 'not_host', 'Only the coordinator can change the event');
  const update = { updatedAt: nowIso() };
  if (name !== undefined) update.name = cleanEventName(name);
  if (emoji !== undefined) update.emoji = cleanEmoji(emoji);
  if (joinOpen !== undefined) update.joinOpen = joinOpen === true;
  await ref.update(update);
  const next = { ...data, ...update };
  if (update.name && update.name !== data.name) {
    syncAllInnerLists(ref.id).catch(err => console.error('🚌 inner list rename failed:', err.message));
  }
  return toClientEvent(ref.id, next, hostUid);
}

/** A fresh link (the old one stops working) — the coordinator's undo for a leaked link. */
async function resetInviteLink(eventId, hostUid) {
  const { ref, data } = await loadAsMember(eventId, hostUid);
  if (data.hostId !== hostUid) throw new ServiceError(403, 'not_host', 'Only the coordinator can reset the link');
  const inviteToken = newToken();
  await ref.update({ inviteToken, updatedAt: nowIso() });
  return toClientEvent(ref.id, { ...data, inviteToken }, hostUid);
}

/** Archive: out of the list, nothing deleted. forEveryone is coordinator-only. */
async function archiveEvent(eventId, uid, { forEveryone = false } = {}) {
  const { ref, data } = await loadAsMember(eventId, uid);
  const now = nowIso();
  if (forEveryone) {
    if (data.hostId !== uid) throw new ServiceError(403, 'not_host', 'Only the coordinator can archive it for everyone');
    await ref.update({ archivedAt: now, joinOpen: false, updatedAt: now });
    return toClientEvent(ref.id, { ...data, archivedAt: now, joinOpen: false }, uid);
  }
  await ref.update(memberPath(uid, 'archivedAt'), now);
  const members = { ...(data.members || {}), [uid]: { ...((data.members || {})[uid] || {}), archivedAt: now } };
  return toClientEvent(ref.id, { ...data, members }, uid);
}

/** Back in the list. The coordinator's unarchive restores it for everyone (joining stays closed until reopened). */
async function unarchiveEvent(eventId, uid) {
  const { ref, data } = await loadAsMember(eventId, uid);
  const fields = [memberPath(uid, 'archivedAt'), FieldValue.delete()];
  if (data.archivedAt && data.hostId === uid) fields.push('archivedAt', FieldValue.delete(), 'updatedAt', nowIso());
  await ref.update(...fields);
  const members = { ...(data.members || {}) };
  if (members[uid]) { members[uid] = { ...members[uid] }; delete members[uid].archivedAt; }
  const next = { ...data, members };
  if (data.hostId === uid) delete next.archivedAt;
  return toClientEvent(ref.id, next, uid);
}

async function endEvent(eventId, hostUid) {
  const { ref, data } = await loadAsMember(eventId, hostUid);
  if (data.hostId !== hostUid) throw new ServiceError(403, 'not_host', 'Only the coordinator can end the event');
  if (data.endedAt) return { ended: true };
  // Ended, not deleted: members keep the photos and get the recap. Roll
  // call and shared locations close with it.
  await ref.update({ endedAt: nowIso(), joinOpen: false, 'rollCall.closedAt': nowIso(), 'rollCall.locations': FieldValue.delete(), updatedAt: nowIso() });
  require('./eventLiveActivityService').endForEvent(ref.id).catch(() => {});
  // Event lists are removed; circles of saved places stay with their owners
  const innerCircleService = require('./innerCircleService');
  for (const uid of data.memberIds || []) {
    const listId = data.members && data.members[uid] && data.members[uid].innerListId;
    if (listId) await innerCircleService.deleteInnerCircleList(uid, listId).catch(() => {});
  }
  return { ended: true };
}

// ---------------------------------------------------------------------------
// Inner Circle lists ("Party Bus" = the members you're connected to)
// ---------------------------------------------------------------------------

async function syncInnerListFor(ref, data, uid) {
  const innerCircleService = require('./innerCircleService');
  const connected = await getConnectedUserIds(uid);
  const userIds = listMembersFor(data.memberIds || [], uid, connected);
  const listId = data.members && data.members[uid] && data.members[uid].innerListId;
  if (listId) {
    const lists = await innerCircleService.getInnerCircleLists(uid);
    const current = lists.find(l => l.id === listId);
    if (current) {
      const same = current.name === data.name
        && current.userIds.length === userIds.length
        && userIds.every(id => current.userIds.includes(id));
      if (!same) await innerCircleService.updateInnerCircleList(uid, listId, { name: data.name, userIds });
      return;
    }
    // They deleted it themselves: respect that, don't recreate
    return;
  }
  if (!userIds.length) return; // created once there's someone to put in it
  // A list with the event's name already there (a sync that raced this one,
  // or a re-join): adopt it rather than create a twin
  const existing = (await innerCircleService.getInnerCircleLists(uid)).find(l => l.name === data.name);
  if (existing) {
    await innerCircleService.updateInnerCircleList(uid, existing.id, { userIds });
    await ref.update(memberPath(uid, 'innerListId'), existing.id);
    return;
  }
  try {
    const lists = await innerCircleService.createInnerCircleList(uid, { name: data.name, userIds });
    const created = lists[lists.length - 1];
    await ref.update(memberPath(uid, 'innerListId'), created.id);
  } catch (error) {
    if (error.code !== 'INNER_CIRCLE_TOO_MANY_LISTS') throw error; // at the 20-list cap: skip quietly
  }
}

// One sync per event at a time: two joins seconds apart would otherwise both
// see a member without a list and both create one, and the lists' own
// read-modify-write would clobber each other.
const syncChains = new Map();
function syncAllInnerLists(eventId) {
  const previous = syncChains.get(eventId) || Promise.resolve();
  const next = previous.catch(() => {}).then(() => runInnerListSync(eventId));
  syncChains.set(eventId, next);
  next.finally(() => { if (syncChains.get(eventId) === next) syncChains.delete(eventId); }).catch(() => {});
  return next;
}

async function runInnerListSync(eventId) {
  const { ref, data } = await loadEvent(eventId);
  for (const uid of data.memberIds || []) {
    // Re-read per member: each create stamps its listId on the event
    const fresh = (await ref.get()).data();
    await syncInnerListFor(ref, fresh, uid).catch(err => console.error(`🚌 list sync ${uid}:`, err.message));
  }
}

// ---------------------------------------------------------------------------
// Photos
// ---------------------------------------------------------------------------

async function addPhotos(eventId, uid, photos) {
  const { ref, data } = await loadAsMember(eventId, uid);
  const list = (Array.isArray(photos) ? photos : []).slice(0, 20);
  if (!list.length) throw new ServiceError(400, 'no_photos', 'Add at least one photo');
  for (const p of list) {
    if (!isAllowedImageUrl(p && p.imageUrl)) throw new ServiceError(400, 'invalid_image', 'Upload the photo first');
  }
  const me = (data.members && data.members[uid]) || {};
  const now = Date.now();
  const batch = db().batch();
  const created = [];
  list.forEach((p, i) => {
    const docRef = photosCol().doc();
    const row = {
      eventId: ref.id,
      uploaderId: uid,
      uploaderName: me.name || 'Member',
      imageUrl: p.imageUrl,
      // ~25 KB preview the album grid loads instead of the full photo
      // (2026-10-06: a grid of full images was ~300 MB per album open)
      thumbUrl: isAllowedImageUrl(p.thumbUrl) ? p.thumbUrl : null,
      caption: clean(p.caption, CAPTION_MAX) || '',
      challengeId: (data.challenges || []).some(c => c.id === p.challengeId) ? p.challengeId : null,
      // Where and when the file said it was taken (nulls when it didn't)
      ...parsePhotoCapture(p, now),
      likes: [],
      // Spread by a millisecond so a batch keeps the order it was picked in
      createdAt: new Date(now + i).toISOString()
    };
    batch.set(docRef, row);
    created.push({ id: docRef.id, row });
  });
  batch.update(ref, { photoCount: FieldValue.increment(list.length), lastPhotoAt: nowIso(), updatedAt: nowIso(),
    // The lock screen's "📸 Sal added 3 photos"
    lastPhoto: { by: me.name || 'Member', count: list.length, at: nowIso() } });
  await batch.commit();

  // A challenge photo: one FavCoin per challenge per person (dedup key + daily cap)
  if (process.env.WIDGET_PIGGY_ENABLED === '1') {
    const done = [...new Set(created.map(c => c.row.challengeId).filter(Boolean))];
    for (const challengeId of done) {
      const photo = created.find(c => c.row.challengeId === challengeId);
      await require('./piggyBankService').credit({
        userId: uid, eventType: 'event_challenge', sourceRef: { eventId: ref.id, challengeId, photoId: photo.id }
      });
    }
  }
  require('./eventLiveActivityService').refreshSoon(ref.id);

  // "Sal added 6 photos" — once per uploader per 15 minutes per event
  const lastPush = (data.photoPushAt && data.photoPushAt[uid]) || 0;
  if (now - lastPush > PHOTO_PUSH_COOLDOWN_MS) {
    await ref.update(new FieldPath('photoPushAt', String(uid)), now).catch(() => {});
    const others = (data.memberIds || []).filter(id => id !== uid);
    for (const id of others) {
      notifyQuiet.sendInBackground(id, {
        type: 'event_photos',
        title: `${data.emoji || DEFAULT_EMOJI} ${me.name || 'Someone'} added ${list.length === 1 ? 'a photo' : `${list.length} photos`}`,
        body: `See them in ${data.name}`,
        data: { eventId: ref.id }
      }, 'event_photos');
    }
  }
  // The reply names the tagged place each located photo was taken at
  let placeRows = [];
  if (created.some(c => Number.isFinite(c.row.lat))) {
    const snap = await placesCol().where('eventId', '==', ref.id).limit(100).get().catch(() => null);
    placeRows = snap ? snap.docs.map(d => ({ id: d.id, ...d.data() })) : [];
  }
  return created.map(c => toClientPhoto({ id: c.id, data: () => c.row }, uid, data.hostId, placeRows));
}

async function deletePhoto(eventId, uid, photoId) {
  const { ref, data } = await loadAsMember(eventId, uid);
  const photoRef = photosCol().doc(String(photoId));
  const doc = await photoRef.get();
  if (!doc.exists || doc.data().eventId !== ref.id) throw new ServiceError(404, 'not_found', 'That photo is gone');
  if (doc.data().uploaderId !== uid && data.hostId !== uid) {
    throw new ServiceError(403, 'not_allowed', 'Only the person who added it or the coordinator can delete it');
  }
  await photoRef.delete();
  await ref.update({ photoCount: FieldValue.increment(-1), updatedAt: nowIso() });
  // The stored file is left alone on purpose: any bucket URL passes the
  // allow-list, so deleting by URL could delete someone else's file. Same
  // as drinks, postcards and workout cards (orphans are harmless).
  return { deleted: true };
}

async function togglePhotoLike(eventId, uid, photoId) {
  const { ref, data } = await loadAsMember(eventId, uid);
  const photoRef = photosCol().doc(String(photoId));
  return db().runTransaction(async (tx) => {
    const doc = await tx.get(photoRef);
    if (!doc.exists || doc.data().eventId !== ref.id) throw new ServiceError(404, 'not_found', 'That photo is gone');
    const likes = Array.isArray(doc.data().likes) ? doc.data().likes : [];
    const liked = likes.includes(uid);
    const next = liked ? likes.filter(id => id !== uid) : [...likes, uid];
    tx.update(photoRef, { likes: next });
    return toClientPhoto({ id: doc.id, data: () => ({ ...doc.data(), likes: next }) }, uid, data.hostId);
  });
}

// ---------------------------------------------------------------------------
// Places
// ---------------------------------------------------------------------------

async function tagPlace(eventId, uid, body) {
  const { ref, data } = await loadAsMember(eventId, uid);
  const place = parsePlace(body);
  // Same spot tagged twice (two people at the same bar): keep one row
  const existing = await placesCol().where('eventId', '==', ref.id).where('name', '==', place.name).limit(5).get();
  const dupe = existing.docs.find(d => Math.abs(d.data().lat - place.lat) < 0.0005 && Math.abs(d.data().lng - place.lng) < 0.0005);
  if (dupe) return toClientPlace(dupe, uid);
  const me = (data.members && data.members[uid]) || {};
  const row = { eventId: ref.id, ...place, taggedById: uid, taggedByName: me.name || 'Member', savedBy: [], createdAt: nowIso() };
  const docRef = await placesCol().add(row);
  await ref.update({ placeCount: FieldValue.increment(1), updatedAt: nowIso() });
  return toClientPlace({ id: docRef.id, data: () => row }, uid);
}

/** The member's public circle named after the event — created on first save. */
async function findOrCreateEventCircle(ref, data, uid) {
  const known = data.members && data.members[uid] && data.members[uid].circleId;
  if (known) {
    const doc = await db().collection(COLLECTIONS.CIRCLES).doc(known).get();
    if (doc.exists && !doc.data().deletedAt) return doc.id;
  }
  // Adopt one already linked to this event (a re-join), else create
  const linked = await db().collection(COLLECTIONS.CIRCLES)
    .where('owner', '==', uid).where('eventId', '==', ref.id).limit(3).get();
  const alive = linked.docs.find(d => !d.data().deletedAt);
  let circleId = alive ? alive.id : null;
  if (!circleId) {
    // Outside the subscription circle cap on purpose, like the check-in circle
    const circle = createCircle({
      name: data.name,
      description: `Places from ${data.name}`,
      privacy: 'public',
      icon: data.emoji || DEFAULT_EMOJI
    }, uid);
    const created = await db().collection(COLLECTIONS.CIRCLES).add({ ...circle, eventId: ref.id });
    circleId = created.id;
  }
  await ref.update(memberPath(uid, 'circleId'), circleId);
  return circleId;
}

async function savePlaceToMyCircle(eventId, uid, eventPlaceId) {
  const { ref, data } = await loadAsMember(eventId, uid);
  const placeRef = placesCol().doc(String(eventPlaceId));
  const doc = await placeRef.get();
  if (!doc.exists || doc.data().eventId !== ref.id) throw new ServiceError(404, 'not_found', 'That place is gone');
  const p = doc.data();
  const circleId = await findOrCreateEventCircle(ref, data, uid);

  // Already in the circle (same name at the same spot): nothing to add
  const inCircle = await db().collection(COLLECTIONS.PLACES).where('circleId', '==', circleId).where('name', '==', p.name).limit(5).get();
  const already = inCircle.docs.find(d => !d.data().deletedAt);
  if (!already) {
    const placeData = createPlace({
      name: p.name,
      address: p.address || '',
      location: { type: 'Point', coordinates: [p.lng, p.lat] },
      category: p.category || 'other'
    }, circleId, uid);
    const savedRef = await db().collection(COLLECTIONS.PLACES).add(placeData);
    // Every save path links the canonical venue record (CLAUDE.md)
    await require('./globalPlaceResolver').ensureGlobalPlaceLink(await savedRef.get()).catch(err =>
      console.error('🚌 global link failed:', err.message));
    await db().collection(COLLECTIONS.CIRCLES).doc(circleId).update({
      placesCount: FieldValue.increment(1),
      updatedAt: nowIso()
    }).catch(() => {});
  }
  await placeRef.update({ savedBy: FieldValue.arrayUnion(uid) });
  return {
    place: toClientPlace({ id: doc.id, data: () => ({ ...p, savedBy: [...new Set([...(p.savedBy || []), uid])] }) }, uid),
    circleId,
    alreadySaved: !!already
  };
}

module.exports = {
  canOpenEvents,
  // operations
  listEvents, getEvent, previewByToken, publicPreview, createEvent, joinByToken, inviteConnections,
  leaveEvent, removeMember, updateEvent, resetInviteLink, endEvent, archiveEvent, unarchiveEvent,
  // shared with eventExtrasService / eventLiveActivityService
  loadEvent, loadAsMember, eventsCol, photosCol, placesCol, DEFAULT_EMOJI,
  addPhotos, deletePhoto, togglePhotoLike, tagPlace, savePlaceToMyCircle,
  // pure (tested)
  cleanEventName, cleanEmoji, parsePlace, toClientEvent, listMembersFor, isMember,
  parsePhotoCapture, distanceMeters, nearestTaggedPlace, toClientPhoto, PHOTO_PLACE_RADIUS_M,
  DEFAULT_NAME, LINK_BASE, TOKEN_RE
};
