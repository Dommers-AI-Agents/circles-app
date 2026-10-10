// backend/services/eventExtrasService.js
// Events widget, the things people do together during an event (Wes,
// 2026-10-06): the shout-out wall, song requests, photo challenges, roll
// call ("everyone on the bus?") and the after-party recap. Membership,
// photos and places stay in eventService.

const { FieldValue, FieldPath } = require('firebase-admin/firestore');
const { getFirestore } = require('../config/firebase');
const ev = require('./eventService');
const { ServiceError } = require('../utils/serviceError');
const { newId, nowIso } = require('../utils/ids');
const { clean } = require('../utils/text');
const notifyQuiet = require('./notifyQuiet');

const db = () => getFirestore();

const WALL_MAX = 280;
const WALL_PAGE = 100;
const SONG_TITLE_MAX = 80;
const SONG_ARTIST_MAX = 60;
const SONGS_PAGE = 100;
const MAX_CHALLENGES = 20;
const CHALLENGE_MAX = 80;
const REACTIONS = ['❤️', '😂', '🔥', '🎉', '👏', '🙌'];
// "Where are you?" to the same person at most this often
const PING_COOLDOWN_MS = 5 * 60 * 1000;

const wallCol = (eventId) => ev.eventsCol().doc(eventId).collection('wall');
const songsCol = (eventId) => ev.eventsCol().doc(eventId).collection('songs');
const nameOf = (data, uid) => (data.members && data.members[uid] && data.members[uid].name) || 'Member';
const emojiOf = (data) => data.emoji || ev.DEFAULT_EMOJI;
const liveRefresh = (eventId) => require('./eventLiveActivityService').refreshSoon(eventId);

const notEnded = (data) => {
  if (data.endedAt) throw new ServiceError(409, 'event_ended', `${data.name} has ended`);
};

// ---------------------------------------------------------------------------
// Shout-out wall
// ---------------------------------------------------------------------------

const toClientPost = (doc, viewerId, hostId) => {
  const d = doc.data();
  const reactions = d.reactions || {};
  return {
    id: doc.id,
    authorId: d.authorId,
    authorName: d.authorName,
    text: d.text,
    createdAt: d.createdAt,
    reactions: REACTIONS.map(e => ({ emoji: e, count: (reactions[e] || []).length, mine: (reactions[e] || []).includes(viewerId) }))
      .filter(r => r.count > 0),
    canDelete: d.authorId === viewerId || hostId === viewerId
  };
};

async function listWall(eventId, uid) {
  const { ref, data } = await ev.loadAsMember(eventId, uid);
  const snap = await wallCol(ref.id).orderBy('createdAt', 'desc').limit(WALL_PAGE).get();
  return { posts: snap.docs.map(d => toClientPost(d, uid, data.hostId)), reactions: REACTIONS };
}

async function postToWall(eventId, uid, { text } = {}) {
  const { ref, data } = await ev.loadAsMember(eventId, uid);
  const body = clean(text, WALL_MAX);
  if (!body) throw new ServiceError(400, 'empty', 'Write something first');
  const row = { authorId: uid, authorName: nameOf(data, uid), text: body, reactions: {}, createdAt: nowIso() };
  const doc = await wallCol(ref.id).add(row);
  await ref.update({ lastShoutout: { text: body, authorName: row.authorName, at: row.createdAt }, updatedAt: nowIso() });
  liveRefresh(ref.id);
  return { post: toClientPost({ id: doc.id, data: () => row }, uid, data.hostId) };
}

async function deleteWallPost(eventId, uid, postId) {
  const { ref, data } = await ev.loadAsMember(eventId, uid);
  const postRef = wallCol(ref.id).doc(String(postId));
  const doc = await postRef.get();
  if (!doc.exists) throw new ServiceError(404, 'not_found', 'That shout-out is gone');
  if (doc.data().authorId !== uid && data.hostId !== uid) {
    throw new ServiceError(403, 'not_allowed', 'Only the person who posted it or the coordinator can delete it');
  }
  await postRef.delete();
  return { deleted: true };
}

async function reactToWallPost(eventId, uid, postId, { emoji } = {}) {
  if (!REACTIONS.includes(emoji)) throw new ServiceError(400, 'bad_reaction', 'Pick one of the reactions');
  const { ref, data } = await ev.loadAsMember(eventId, uid);
  const postRef = wallCol(ref.id).doc(String(postId));
  return db().runTransaction(async (tx) => {
    const doc = await tx.get(postRef);
    if (!doc.exists) throw new ServiceError(404, 'not_found', 'That shout-out is gone');
    const current = (doc.data().reactions || {})[emoji] || [];
    const next = current.includes(uid) ? current.filter(id => id !== uid) : [...current, uid];
    tx.update(postRef, new FieldPath('reactions', emoji), next);
    const reactions = { ...(doc.data().reactions || {}), [emoji]: next };
    return { post: toClientPost({ id: doc.id, data: () => ({ ...doc.data(), reactions }) }, uid, data.hostId) };
  });
}

// ---------------------------------------------------------------------------
// Song requests
// ---------------------------------------------------------------------------

const toClientSong = (doc, viewerId, hostId) => {
  const d = doc.data();
  const votes = Array.isArray(d.votes) ? d.votes : [];
  return {
    id: doc.id,
    title: d.title,
    artist: d.artist || null,
    addedById: d.addedById,
    addedByName: d.addedByName,
    votes: votes.length,
    votedByMe: votes.includes(viewerId),
    played: !!d.playedAt,
    createdAt: d.createdAt,
    canManage: d.addedById === viewerId || hostId === viewerId
  };
};

/** Unplayed first, most votes first, then oldest; played songs last. */
const sortSongs = (songs) => [...songs].sort((a, b) =>
  (a.played - b.played) || (b.votes - a.votes) || String(a.createdAt).localeCompare(String(b.createdAt)));

async function listSongs(eventId, uid) {
  const { ref, data } = await ev.loadAsMember(eventId, uid);
  const snap = await songsCol(ref.id).orderBy('createdAt', 'desc').limit(SONGS_PAGE).get();
  return { songs: sortSongs(snap.docs.map(d => toClientSong(d, uid, data.hostId))) };
}

async function requestSong(eventId, uid, { title, artist } = {}) {
  const { ref, data } = await ev.loadAsMember(eventId, uid);
  notEnded(data);
  const t = clean(title, SONG_TITLE_MAX);
  if (!t) throw new ServiceError(400, 'empty', 'Which song?');
  const row = {
    title: t, artist: clean(artist, SONG_ARTIST_MAX) || null,
    addedById: uid, addedByName: nameOf(data, uid), votes: [uid], createdAt: nowIso()
  };
  const doc = await songsCol(ref.id).add(row);
  liveRefresh(ref.id);
  return { song: toClientSong({ id: doc.id, data: () => row }, uid, data.hostId) };
}

async function voteSong(eventId, uid, songId) {
  const { ref, data } = await ev.loadAsMember(eventId, uid);
  const songRef = songsCol(ref.id).doc(String(songId));
  const out = await db().runTransaction(async (tx) => {
    const doc = await tx.get(songRef);
    if (!doc.exists) throw new ServiceError(404, 'not_found', 'That song is gone');
    const votes = doc.data().votes || [];
    const next = votes.includes(uid) ? votes.filter(id => id !== uid) : [...votes, uid];
    tx.update(songRef, { votes: next });
    return toClientSong({ id: doc.id, data: () => ({ ...doc.data(), votes: next }) }, uid, data.hostId);
  });
  liveRefresh(ref.id);
  return { song: out };
}

/** Played (or not) — the adder or the coordinator (the DJ). */
async function markSongPlayed(eventId, uid, songId, { played = true } = {}) {
  const { ref, data } = await ev.loadAsMember(eventId, uid);
  const songRef = songsCol(ref.id).doc(String(songId));
  const doc = await songRef.get();
  if (!doc.exists) throw new ServiceError(404, 'not_found', 'That song is gone');
  if (doc.data().addedById !== uid && data.hostId !== uid) throw new ServiceError(403, 'not_allowed', 'Only the coordinator or whoever added it');
  await songRef.update({ playedAt: played ? nowIso() : FieldValue.delete() });
  liveRefresh(ref.id);
  return { song: toClientSong({ id: doc.id, data: () => ({ ...doc.data(), playedAt: played ? nowIso() : null }) }, uid, data.hostId) };
}

async function deleteSong(eventId, uid, songId) {
  const { ref, data } = await ev.loadAsMember(eventId, uid);
  const songRef = songsCol(ref.id).doc(String(songId));
  const doc = await songRef.get();
  if (!doc.exists) throw new ServiceError(404, 'not_found', 'That song is gone');
  if (doc.data().addedById !== uid && data.hostId !== uid) throw new ServiceError(403, 'not_allowed', 'Only the coordinator or whoever added it');
  await songRef.delete();
  return { deleted: true };
}

// ---------------------------------------------------------------------------
// Photo challenges (the coordinator's list; a photo carries challengeId and
// pays a FavCoin once per challenge per person — see eventService.addPhotos)
// ---------------------------------------------------------------------------

async function addChallenges(eventId, uid, { challenges } = {}) {
  const { ref, data } = await ev.loadAsMember(eventId, uid);
  if (data.hostId !== uid) throw new ServiceError(403, 'not_host', 'Only the coordinator sets the challenges');
  notEnded(data);
  const existing = data.challenges || [];
  const known = new Set(existing.map(c => c.text.toLowerCase()));
  const incoming = (Array.isArray(challenges) ? challenges : [])
    .map(c => ({ text: clean(c && c.text, CHALLENGE_MAX), emoji: ev.cleanEmoji(c && c.emoji) }))
    .filter(c => c.text && !known.has(c.text.toLowerCase()));
  if (!incoming.length) throw new ServiceError(400, 'empty', 'Add a challenge');
  if (existing.length + incoming.length > MAX_CHALLENGES) throw new ServiceError(400, 'too_many', `Up to ${MAX_CHALLENGES} challenges`);
  const next = [...existing, ...incoming.map(c => ({ id: newId(), text: c.text, emoji: c.emoji, createdAt: nowIso() }))];
  await ref.update({ challenges: next, updatedAt: nowIso() });
  // Everyone hears about a new batch (one push, not one per challenge)
  for (const id of (data.memberIds || []).filter(m => m !== uid)) {
    notifyQuiet.sendInBackground(id, {
      type: 'event_challenge',
      title: `${emojiOf(data)} New photo challenge${incoming.length === 1 ? '' : 's'} in ${data.name}`,
      body: incoming.length === 1 ? incoming[0].text : `${incoming[0].text} and ${incoming.length - 1} more`,
      data: { eventId: ref.id }
    }, 'event_challenge');
  }
  liveRefresh(ref.id);
  return { challenges: next.map(c => ({ id: c.id, text: c.text, emoji: c.emoji })) };
}

async function removeChallenge(eventId, uid, challengeId) {
  const { ref, data } = await ev.loadAsMember(eventId, uid);
  if (data.hostId !== uid) throw new ServiceError(403, 'not_host', 'Only the coordinator sets the challenges');
  const next = (data.challenges || []).filter(c => c.id !== challengeId);
  await ref.update({ challenges: next, updatedAt: nowIso() });
  return { challenges: next.map(c => ({ id: c.id, text: c.text, emoji: c.emoji })) };
}

// ---------------------------------------------------------------------------
// Roll call
// ---------------------------------------------------------------------------

async function startRollCall(eventId, uid) {
  const { ref, data } = await ev.loadAsMember(eventId, uid);
  if (data.hostId !== uid) throw new ServiceError(403, 'not_host', 'Only the coordinator calls roll');
  notEnded(data);
  const now = nowIso();
  const rollCall = { id: newId(), startedAt: now, startedBy: uid, startedByName: nameOf(data, uid), here: { [uid]: now }, locations: {} };
  await ref.update({ rollCall, updatedAt: now });
  for (const id of (data.memberIds || []).filter(m => m !== uid)) {
    notifyQuiet.sendInBackground(id, {
      type: 'event_rollcall',
      title: `${emojiOf(data)} Roll call! Everyone here?`,
      body: `${rollCall.startedByName} wants to know who's with ${data.name}. Tap I'm here.`,
      data: { eventId: ref.id, rollCallId: rollCall.id }
    }, 'event_rollcall');
  }
  liveRefresh(ref.id);
  return { event: ev.toClientEvent(ref.id, { ...data, rollCall }, uid) };
}

/** "I'm here", optionally with where (shown only to the event, cleared at the end). */
async function answerRollCall(eventId, uid, { lat, lng } = {}) {
  const { ref, data } = await ev.loadAsMember(eventId, uid);
  const rc = data.rollCall;
  if (!rc || !rc.id || rc.closedAt) throw new ServiceError(409, 'no_roll_call', 'There is no roll call right now');
  const now = nowIso();
  const updates = [new FieldPath('rollCall', 'here', uid), now, 'updatedAt', now];
  const hasSpot = Number.isFinite(Number(lat)) && Number.isFinite(Number(lng))
    && Math.abs(Number(lat)) <= 90 && Math.abs(Number(lng)) <= 180;
  if (hasSpot) updates.push(new FieldPath('rollCall', 'locations', uid), { lat: Number(lat), lng: Number(lng), at: now });
  await ref.update(...updates);
  liveRefresh(ref.id);
  const next = { ...rc, here: { ...(rc.here || {}), [uid]: now },
    locations: hasSpot ? { ...(rc.locations || {}), [uid]: { lat: Number(lat), lng: Number(lng), at: now } } : (rc.locations || {}) };
  return { event: ev.toClientEvent(ref.id, { ...data, rollCall: next }, uid) };
}

/** The coordinator nudges whoever hasn't answered (or one person). */
async function pingMissing(eventId, uid, { userId } = {}) {
  const { ref, data } = await ev.loadAsMember(eventId, uid);
  if (data.hostId !== uid) throw new ServiceError(403, 'not_host', 'Only the coordinator can ping');
  const rc = data.rollCall;
  if (!rc || !rc.id || rc.closedAt) throw new ServiceError(409, 'no_roll_call', 'Start a roll call first');
  const here = rc.here || {};
  const pings = rc.pingedAt || {};
  const now = Date.now();
  const targets = (data.memberIds || [])
    .filter(id => !here[id] && id !== uid && (!userId || id === userId))
    .filter(id => !pings[id] || now - pings[id] > PING_COOLDOWN_MS);
  for (const id of targets) {
    notifyQuiet.sendInBackground(id, {
      type: 'event_rollcall_ping',
      title: `${emojiOf(data)} Where are you?`,
      body: `${nameOf(data, uid)} is looking for you. Tap I'm here in ${data.name}.`,
      data: { eventId: ref.id, rollCallId: rc.id }
    }, 'event_rollcall_ping');
  }
  if (targets.length) {
    const updates = targets.flatMap(id => [new FieldPath('rollCall', 'pingedAt', id), now]);
    await ref.update(...updates);
  }
  return { pinged: targets.length };
}

async function closeRollCall(eventId, uid) {
  const { ref, data } = await ev.loadAsMember(eventId, uid);
  if (data.hostId !== uid) throw new ServiceError(403, 'not_host', 'Only the coordinator closes roll call');
  await ref.update({ 'rollCall.closedAt': nowIso(), 'rollCall.locations': FieldValue.delete(), updatedAt: nowIso() });
  liveRefresh(ref.id);
  return { closed: true };
}

// ---------------------------------------------------------------------------
// After-party recap
// ---------------------------------------------------------------------------

/** Pure (tested): what the recap shows, from the event, its photos, places and wall. */
function buildRecap({ id, data, photos, places, posts, songs }) {
  const byLikes = [...photos].sort((a, b) => (b.likes || []).length - (a.likes || []).length
    || String(a.createdAt).localeCompare(String(b.createdAt)));
  const uploads = {};
  for (const p of photos) uploads[p.uploaderId] = (uploads[p.uploaderId] || 0) + 1;
  const topUploader = Object.entries(uploads).sort((a, b) => b[1] - a[1])[0];
  const challengeDone = new Set(photos.filter(p => p.challengeId).map(p => p.challengeId));
  const firstAt = photos.map(p => p.createdAt).filter(Boolean).sort()[0] || data.createdAt;
  const topPost = [...posts].sort((a, b) => reactionCount(b) - reactionCount(a))[0];
  const topSong = [...songs].sort((a, b) => (b.votes || []).length - (a.votes || []).length)[0];
  return {
    eventId: id,
    name: data.name,
    emoji: data.emoji || ev.DEFAULT_EMOJI,
    startedAt: firstAt,
    endedAt: data.endedAt || null,
    memberCount: (data.memberIds || []).length,
    memberNames: (data.memberIds || []).map(uid => (data.members && data.members[uid] && data.members[uid].name) || 'Member'),
    photoCount: photos.length,
    placeCount: places.length,
    topPhotos: byLikes.slice(0, 6).map(p => ({ imageUrl: p.imageUrl, thumbUrl: p.thumbUrl || null, uploaderName: p.uploaderName, likes: (p.likes || []).length })),
    photoOfTheNight: byLikes[0] && (byLikes[0].likes || []).length > 0
      ? { imageUrl: byLikes[0].imageUrl, uploaderName: byLikes[0].uploaderName, likes: byLikes[0].likes.length } : null,
    topPhotographer: topUploader ? { name: (photos.find(p => p.uploaderId === topUploader[0]) || {}).uploaderName || 'Member', photos: topUploader[1] } : null,
    places: places.map(p => ({ name: p.name, lat: p.lat, lng: p.lng })),
    challenges: { total: (data.challenges || []).length, done: [...challengeDone].filter(cid => (data.challenges || []).some(c => c.id === cid)).length },
    topShoutout: topPost && reactionCount(topPost) > 0 ? { text: topPost.text, authorName: topPost.authorName } : null,
    topSong: topSong ? { title: topSong.title, artist: topSong.artist || null, votes: (topSong.votes || []).length } : null
  };
}
const reactionCount = (post) => Object.values(post.reactions || {}).reduce((n, v) => n + (Array.isArray(v) ? v.length : 0), 0);

async function getRecap(eventId, uid) {
  const { ref, data } = await ev.loadAsMember(eventId, uid);
  const [photos, places, posts, songs] = await Promise.all([
    ev.photosCol().where('eventId', '==', ref.id).orderBy('createdAt', 'desc').limit(500).get(),
    ev.placesCol().where('eventId', '==', ref.id).orderBy('createdAt', 'desc').limit(100).get(),
    wallCol(ref.id).orderBy('createdAt', 'desc').limit(200).get(),
    songsCol(ref.id).orderBy('createdAt', 'desc').limit(200).get()
  ]);
  return { recap: buildRecap({
    id: ref.id, data,
    photos: photos.docs.map(d => d.data()).filter(row => row.status !== 'uploading'),
    places: places.docs.map(d => d.data()),
    posts: posts.docs.map(d => d.data()),
    songs: songs.docs.map(d => d.data())
  }) };
}

module.exports = {
  listWall, postToWall, deleteWallPost, reactToWallPost,
  listSongs, requestSong, voteSong, markSongPlayed, deleteSong,
  addChallenges, removeChallenge,
  startRollCall, answerRollCall, pingMissing, closeRollCall,
  getRecap,
  // pure (tested)
  buildRecap, sortSongs, REACTIONS
};
