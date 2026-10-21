// backend/services/clubs/membership.js
//
// Clubs: reading, creating, joining (an invite link joins instantly while
// joining is open), inviting connections, leaving, removing, organizer roles,
// club settings and muting. Member maps are rewritten whole inside a
// transaction (never a dotted field path: some legacy user ids contain dots).
const s = require('./shared');
const { ServiceError } = require('../../utils/serviceError');
const { normalizeUserId } = require('../idService');
const { isBlockedEitherWay } = require('../moderationService');
const { getConnectedUserIds } = require('../../utils/networkAccess');
const { clean } = require('../../utils/text');
const { nowIso } = require('../../utils/ids');
const notifyQuiet = require('../notifyQuiet');
const { COLLECTIONS } = require('../../models/FirestoreModels');

// ---------------------------------------------------------------------------
// Reads
// ---------------------------------------------------------------------------

async function latestPosts(clubId, kind, n, club, uid) {
  const snap = await s.postsCol().where('clubId', '==', clubId).where('kind', '==', kind)
    .orderBy('createdAt', 'desc').limit(n).get();
  return snap.docs.map((d) => s.toClientPost(d.id, d.data(), club, uid));
}

/** Everything the club page shows. */
async function clubDetail(id, data, uid, now = new Date()) {
  const occurrences = s.upcomingOccurrences(data, now);
  const [rsvps, bulletin, boardPreview] = await Promise.all([
    s.rsvpsFor(id, occurrences),
    latestPosts(id, 'bulletin', 3, data, uid),
    latestPosts(id, 'board', 3, data, uid)
  ]);
  const upcoming = occurrences.map((o) => s.toClientOccurrence(o, rsvps.get(o.key), data, uid));
  const from = now.getTime() - 60 * 60 * 1000;
  return {
    ...s.toClientSummary(id, data, uid, upcoming[0] || null),
    description: data.description || '',
    homeSpot: data.homeSpot || null,
    timezone: s.cleanTimezone(data.timezone),
    ownerId: data.ownerId,
    ownerName: data.ownerName,
    joinOpen: data.joinOpen !== false,
    inviteLink: `${s.LINK_BASE}${data.inviteToken}`,
    scheduleLine: s.scheduleLine(data.schedule),
    schedule: (data.schedule || []).map((m) => ({ id: m.id, weekday: m.weekday, time: m.time, title: m.title, spot: m.spot || null, notes: m.notes || '' })),
    events: (data.events || []).filter((e) => Date.parse(e.startsAt) >= from)
      .sort((a, b) => a.startsAt.localeCompare(b.startsAt))
      .map((e) => ({ id: e.id, title: e.title, startsAt: e.startsAt, spot: e.spot || null, notes: e.notes || '' })),
    members: s.toClientMembers(data),
    upcoming,
    bulletin,
    boardPreview
  };
}

/** My clubs, the one meeting soonest first (clubs with nothing scheduled last, by name). */
async function listClubs(uid, now = new Date()) {
  const snap = await s.clubsCol().where('memberIds', 'array-contains', uid)
    .orderBy('createdAt', 'desc').limit(s.MAX_CLUBS_LISTED).get();
  const clubs = snap.docs.filter((d) => !d.data().deletedAt);
  const nexts = clubs.map((d) => s.upcomingOccurrences(d.data(), now, { limit: 1 })[0] || null);
  const wanted = clubs.map((d, i) => (nexts[i] ? s.rsvpsCol().doc(`${d.id}_${nexts[i].key}`) : null)).filter(Boolean);
  const rsvpDocs = wanted.length ? await s.db().getAll(...wanted) : [];
  const rsvpById = new Map(rsvpDocs.map((d) => [d.id, d.exists ? d.data() : null]));
  const summaries = clubs.map((d, i) => {
    const next = nexts[i] ? s.toClientOccurrence(nexts[i], rsvpById.get(`${d.id}_${nexts[i].key}`), d.data(), uid) : null;
    return s.toClientSummary(d.id, d.data(), uid, next);
  });
  return summaries.sort((a, b) => {
    if (a.next && b.next) return a.next.startsAt.localeCompare(b.next.startsAt);
    if (a.next || b.next) return a.next ? -1 : 1;
    return a.name.localeCompare(b.name);
  });
}

async function getClub(clubId, uid) {
  const { id, data } = await s.loadAsMember(clubId, uid);
  return clubDetail(id, data, uid);
}

/** The join screen (any signed-in person holding the link). */
async function previewByToken(token, uid) {
  const { id, data } = await s.loadByToken(token);
  return {
    id,
    name: data.name,
    emoji: data.emoji,
    kind: data.kind || 'other',
    description: data.description || '',
    ownerName: data.ownerName,
    memberCount: (data.memberIds || []).length,
    joinOpen: data.joinOpen !== false,
    alreadyMember: s.isMember(data, uid),
    scheduleLine: s.scheduleLine(data.schedule)
  };
}

/** The public page behind /app/club/<token>: no member names. */
async function publicPreview(token) {
  const { data } = await s.loadByToken(token);
  return {
    name: data.name,
    emoji: data.emoji,
    kind: data.kind || 'other',
    description: data.description || '',
    ownerName: data.ownerName,
    memberCount: (data.memberIds || []).length,
    joinOpen: data.joinOpen !== false,
    scheduleLine: s.scheduleLine(data.schedule),
    homeSpotName: (data.homeSpot && data.homeSpot.name) || null
  };
}

// ---------------------------------------------------------------------------
// Membership
// ---------------------------------------------------------------------------

async function createClub(uid, body = {}) {
  const me = await s.userSummary(uid);
  const kind = s.cleanKind(body.kind);
  const now = nowIso();
  const data = {
    name: s.cleanName(body.name),
    kind,
    emoji: s.cleanEmoji(body.emoji, kind),
    description: clean(body.description, s.DESCRIPTION_MAX) || '',
    homeSpot: s.parseSpot(body.homeSpot),
    timezone: s.cleanTimezone(body.timezone),
    ownerId: uid,
    ownerName: me.name,
    organizerIds: [uid],
    memberIds: [uid],
    members: { [uid]: { name: me.name, avatarUrl: me.avatarUrl, joinedAt: now } },
    removedIds: [],
    joinOpen: true,
    inviteToken: s.newToken(),
    schedule: [],
    events: [],
    createdAt: now,
    updatedAt: now
  };
  const ref = await s.clubsCol().add(data);
  return clubDetail(ref.id, data, uid);
}

/** Join from a link (instant, idempotent). Returns { club, joined, coinCredited }. */
async function joinByToken(token, uid) {
  const { ref } = await s.loadByToken(token);
  const me = await s.userSummary(uid);
  const result = await s.db().runTransaction(async (tx) => {
    const data = (await tx.get(ref)).data();
    if (data.deletedAt) throw new ServiceError(404, 'not_found', "This club isn't here anymore");
    if (s.isMember(data, uid)) return { data, joined: false };
    if (data.joinOpen === false) throw new ServiceError(403, 'join_closed', `${data.name} isn't taking new members right now`);
    if ((data.removedIds || []).includes(uid)) throw new ServiceError(403, 'removed', `You were removed from ${data.name}`);
    if (isBlockedEitherWay(me.data, data.ownerId)) throw new ServiceError(403, 'blocked', "You can't join this club");
    if ((data.memberIds || []).length >= s.MAX_MEMBERS) throw new ServiceError(403, 'full', `${data.name} is full`);
    const now = nowIso();
    const members = { ...(data.members || {}), [uid]: { name: me.name, avatarUrl: me.avatarUrl, joinedAt: now } };
    const memberIds = [...(data.memberIds || []), uid];
    tx.update(ref, { memberIds, members, updatedAt: now });
    return { data: { ...data, memberIds, members }, joined: true };
  });

  let coinCredited = false;
  if (result.joined) {
    const d = result.data;
    for (const id of s.pushTargets(d, { only: d.organizerIds, exclude: [uid] })) {
      notifyQuiet.sendInBackground(id, {
        type: 'club_joined',
        title: `${d.emoji} ${me.name} joined ${d.name}`,
        body: `${d.memberIds.length} members now`,
        data: { clubId: ref.id }
      }, 'club_joined');
    }
    if (process.env.WIDGET_PIGGY_ENABLED === '1') {
      const bonus = await require('../piggyBankService').credit({
        userId: uid, eventType: 'club_joined', sourceRef: { clubId: ref.id }
      });
      coinCredited = !!(bonus && bonus.credited);
    }
  }
  return { club: await clubDetail(ref.id, result.data, uid), joined: result.joined, coinCredited };
}

/** In-app invites to a member's connections. */
async function inviteConnections(clubId, uid, userIds) {
  const { id, data } = await s.loadAsMember(clubId, uid);
  if (data.joinOpen === false) throw new ServiceError(403, 'join_closed', 'Joining is closed');
  const wanted = [...new Set((Array.isArray(userIds) ? userIds : []).map(normalizeUserId).filter(Boolean))]
    .filter((x) => x !== uid && !s.isMember(data, x) && !(data.removedIds || []).includes(x))
    .slice(0, s.MAX_INVITES_PER_CALL);
  if (!wanted.length) return { invited: 0 };
  const connected = await getConnectedUserIds(uid);
  const invitees = wanted.filter((x) => connected.has(x));
  if (!invitees.length) throw new ServiceError(400, 'not_connected', 'You can invite people you are connected with');
  const docs = await s.db().getAll(...invitees.map((x) => s.db().collection(COLLECTIONS.USERS).doc(x)));
  const inviter = (data.members && data.members[uid] && data.members[uid].name) || 'A friend';
  let invited = 0;
  docs.forEach((doc, i) => {
    const user = doc.exists ? doc.data() : null;
    if (!user || isBlockedEitherWay(user, uid)) return;
    // Below 1.4.1 the app has no Clubs: ask them to update instead
    const hasClubs = s.canOpenClubs(user);
    notifyQuiet.sendInBackground(invitees[i], {
      type: 'club_invite',
      title: `${data.emoji} ${inviter} invited you to ${data.name}`,
      body: hasClubs
        ? (s.scheduleLine(data.schedule) || 'Join to see the meetups and the board')
        : 'Update FavCircles in the App Store to join, then tap this invite again',
      data: { clubId: id, clubToken: data.inviteToken, ...(hasClubs ? {} : { needsUpdate: 'true' }) }
    }, 'club_invite');
    invited++;
  });
  return { invited };
}

/** Rewrites membership inside a transaction. */
async function dropMember(ref, uid, { removed }) {
  return s.db().runTransaction(async (tx) => {
    const data = (await tx.get(ref)).data();
    const members = { ...(data.members || {}) };
    delete members[uid];
    const patch = {
      memberIds: (data.memberIds || []).filter((x) => x !== uid),
      organizerIds: (data.organizerIds || []).filter((x) => x !== uid),
      members,
      updatedAt: nowIso()
    };
    if (removed) patch.removedIds = [...new Set([...(data.removedIds || []), uid])];
    tx.update(ref, patch);
    return { ...data, ...patch };
  });
}

async function leaveClub(clubId, uid) {
  const { ref, data } = await s.loadAsMember(clubId, uid);
  if (data.ownerId === uid) throw new ServiceError(400, 'owner_cannot_leave', 'The owner ends the club instead of leaving');
  await dropMember(ref, uid, { removed: false });
  return { left: true };
}

async function removeMember(clubId, uid, memberId) {
  const { ref, id, data } = await s.loadAsOrganizer(clubId, uid);
  const target = normalizeUserId(memberId);
  if (!s.isMember(data, target)) throw new ServiceError(404, 'not_member', "They're not in the club");
  if (target === data.ownerId) throw new ServiceError(403, 'owner', "The owner can't be removed");
  if (target === uid) throw new ServiceError(400, 'self', 'Leave the club instead');
  // Organizers remove members; only the owner removes an organizer
  if (s.isOrganizer(data, target) && data.ownerId !== uid) throw new ServiceError(403, 'organizer', 'Only the owner can remove an organizer');
  const fresh = await dropMember(ref, target, { removed: true });
  return { club: await clubDetail(id, fresh, uid) };
}

async function setRole(clubId, uid, memberId, role) {
  const { ref, id, data } = await s.loadAsMember(clubId, uid);
  if (data.ownerId !== uid) throw new ServiceError(403, 'not_owner', 'Only the owner can change roles');
  const target = normalizeUserId(memberId);
  if (!s.isMember(data, target)) throw new ServiceError(404, 'not_member', "They're not in the club");
  if (target === data.ownerId) throw new ServiceError(400, 'owner', 'The owner is always an organizer');
  if (!['organizer', 'member'].includes(role)) throw new ServiceError(400, 'invalid_role', 'Pick organizer or member');
  const organizerIds = role === 'organizer'
    ? [...new Set([...(data.organizerIds || []), target])]
    : (data.organizerIds || []).filter((x) => x !== target);
  await ref.update({ organizerIds, updatedAt: nowIso() });
  return { club: await clubDetail(id, { ...data, organizerIds }, uid) };
}

async function updateClub(clubId, uid, body = {}) {
  const { ref, id, data } = await s.loadAsOrganizer(clubId, uid);
  const patch = {};
  if (body.name !== undefined) patch.name = s.cleanName(body.name);
  if (body.kind !== undefined) patch.kind = s.cleanKind(body.kind);
  if (body.emoji !== undefined) patch.emoji = s.cleanEmoji(body.emoji, patch.kind || data.kind);
  if (body.description !== undefined) patch.description = clean(body.description, s.DESCRIPTION_MAX) || '';
  if (body.homeSpot !== undefined) patch.homeSpot = s.parseSpot(body.homeSpot);
  if (body.timezone !== undefined) patch.timezone = s.cleanTimezone(body.timezone);
  if (body.joinOpen !== undefined) patch.joinOpen = body.joinOpen === true;
  if (!Object.keys(patch).length) return { club: await clubDetail(id, data, uid) };
  patch.updatedAt = nowIso();
  await ref.update(patch);
  return { club: await clubDetail(id, { ...data, ...patch }, uid) };
}

async function resetInviteLink(clubId, uid) {
  const { ref, id, data } = await s.loadAsOrganizer(clubId, uid);
  const inviteToken = s.newToken();
  await ref.update({ inviteToken, updatedAt: nowIso() });
  return { club: await clubDetail(id, { ...data, inviteToken }, uid) };
}

async function endClub(clubId, uid) {
  const { ref, data } = await s.loadAsMember(clubId, uid);
  if (data.ownerId !== uid) throw new ServiceError(403, 'not_owner', 'Only the owner can end the club');
  const now = nowIso();
  await ref.update({ deletedAt: now, joinOpen: false, updatedAt: now });
  return { ended: true };
}

async function setMuted(clubId, uid, muted) {
  const { ref, id } = await s.loadAsMember(clubId, uid);
  const fresh = await s.db().runTransaction(async (tx) => {
    const data = (await tx.get(ref)).data();
    const members = { ...(data.members || {}) };
    members[uid] = { ...(members[uid] || {}), muted: muted === true };
    tx.update(ref, { members, updatedAt: nowIso() });
    return { ...data, members };
  });
  return { club: await clubDetail(id, fresh, uid) };
}

module.exports = {
  clubDetail, listClubs, getClub, previewByToken, publicPreview,
  createClub, joinByToken, inviteConnections, leaveClub, removeMember, setRole,
  updateClub, resetInviteLink, endClub, setMuted
};
