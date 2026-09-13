// backend/services/nextBarRoundService.js
//
// NextBar voting rounds: the host picks 2–5 candidate bars, tags accepted
// connections, everyone votes, the winner is announced. Rounds are shared
// documents in `nextbarRounds` (widget data docs are per-user, so the round
// can't live there).
//
// Lifecycle: `open` → `closed`. A round closes when every participant has
// voted (inside the vote transaction, so two last voters can't both close
// it), when the host ends it, or lazily on the next list/read once
// `expiresAt` has passed (no scheduler). Winner = most votes, ties broken at
// random; with no votes at all, a random option.
//
// All timestamps are ISO strings so the list query's orderBy and the expiry
// comparison behave identically in Firestore and in the in-memory test mock.

const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');
const { normalizeUserId, isSameUser } = require('./idService');
const { isBlockedEitherWay } = require('./moderationService');
const { getConnectedUserIds } = require('../utils/networkAccess');
const notificationService = require('./notificationService');

const MIN_PARTICIPANTS = 1;
const MAX_PARTICIPANTS = 10;
const MIN_OPTIONS = 2;
const MAX_OPTIONS = 5;
const MAX_SAVERS = 10;
const MIN_EXPIRES_MINUTES = 15;
const MAX_EXPIRES_MINUTES = 1440;
const DEFAULT_EXPIRES_MINUTES = 180;
const LIST_LIMIT = 20;
const PUSH_TYPE_ROUND = 'nextbar_round';
const PUSH_TYPE_RESULT = 'nextbar_result';

class RoundError extends Error {
  constructor(status, code, message, extra = {}) {
    super(message || code);
    this.name = 'RoundError';
    this.status = status;
    this.code = code;
    Object.assign(this, extra);
  }
}

const db = () => getFirestore();
const roundsCol = () => db().collection(COLLECTIONS.NEXTBAR_ROUNDS);
const nowIso = () => new Date().toISOString();
const displayNameOf = (data, fallback = 'Someone') =>
  (data && typeof data.displayName === 'string' && data.displayName.trim())
    ? data.displayName.trim()
    : ((data && typeof data.name === 'string' && data.name.trim()) || fallback);

// ---------------------------------------------------------------------------
// Validation
// ---------------------------------------------------------------------------

const cleanString = (v, max) => (typeof v === 'string' && v.trim() ? v.trim().slice(0, max) : null);
const finiteOrNull = (v) => (typeof v === 'number' && Number.isFinite(v) ? v : null);

// Options are stored as given (after shape validation): the widget already
// resolved them and the client re-renders them from the round.
function normalizeOption(raw, index) {
  const at = `options[${index}]`;
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
    throw new RoundError(400, 'invalid_options', `${at} must be an object`);
  }
  const placeId = cleanString(raw.placeId, 200);
  const name = cleanString(raw.name, 200);
  if (!placeId) throw new RoundError(400, 'invalid_options', `${at}.placeId is required`);
  if (!name) throw new RoundError(400, 'invalid_options', `${at}.name is required`);

  let savers = [];
  if (raw.savers !== undefined && raw.savers !== null) {
    if (!Array.isArray(raw.savers) || raw.savers.length > MAX_SAVERS
        || !raw.savers.every(s => typeof s === 'string')) {
      throw new RoundError(400, 'invalid_options', `${at}.savers must be an array of at most ${MAX_SAVERS} strings`);
    }
    savers = raw.savers.map(s => s.trim().slice(0, 100)).filter(Boolean);
  }
  for (const key of ['distanceMeters', 'lat', 'lng']) {
    const v = raw[key];
    if (v !== undefined && v !== null && !(typeof v === 'number' && Number.isFinite(v))) {
      throw new RoundError(400, 'invalid_options', `${at}.${key} must be a finite number`);
    }
  }
  return {
    placeId,
    name,
    address: cleanString(raw.address, 300),
    source: cleanString(raw.source, 40),
    savers,
    distanceMeters: finiteOrNull(raw.distanceMeters),
    lat: finiteOrNull(raw.lat),
    lng: finiteOrNull(raw.lng),
    isGlobal: raw.isGlobal === true
  };
}

function normalizeOptions(options) {
  if (!Array.isArray(options) || options.length < MIN_OPTIONS || options.length > MAX_OPTIONS) {
    throw new RoundError(400, 'invalid_options', `options must contain ${MIN_OPTIONS} to ${MAX_OPTIONS} places`);
  }
  const normalized = options.map(normalizeOption);
  // Votes are keyed by placeId, so a duplicate would make the winner ambiguous.
  const ids = new Set(normalized.map(o => o.placeId));
  if (ids.size !== normalized.length) {
    throw new RoundError(400, 'invalid_options', 'options must not repeat a placeId');
  }
  return normalized;
}

function normalizeParticipantIds(participantIds, hostId) {
  if (!Array.isArray(participantIds)) {
    throw new RoundError(400, 'invalid_participants', 'participantIds must be an array');
  }
  const seen = new Set();
  for (const raw of participantIds) {
    const id = normalizeUserId(raw);
    if (!id) throw new RoundError(400, 'invalid_participants', 'participantIds contains an invalid id');
    if (isSameUser(id, hostId)) {
      throw new RoundError(400, 'invalid_participants', 'You\'re already in your own round');
    }
    seen.add(id);
  }
  if (seen.size < MIN_PARTICIPANTS || seen.size > MAX_PARTICIPANTS) {
    throw new RoundError(400, 'invalid_participants',
      `Tag ${MIN_PARTICIPANTS} to ${MAX_PARTICIPANTS} connections`);
  }
  return [...seen];
}

function normalizeExpiresInMinutes(v) {
  if (v === undefined || v === null) return DEFAULT_EXPIRES_MINUTES;
  if (!Number.isInteger(v) || v < MIN_EXPIRES_MINUTES || v > MAX_EXPIRES_MINUTES) {
    throw new RoundError(400, 'invalid_expiry',
      `expiresInMinutes must be an integer between ${MIN_EXPIRES_MINUTES} and ${MAX_EXPIRES_MINUTES}`);
  }
  return v;
}

// ---------------------------------------------------------------------------
// Winner + close
// ---------------------------------------------------------------------------

const pickRandom = (arr) => arr[Math.floor(Math.random() * arr.length)];

// Most-voted option; ties broken at random; no votes at all → random option.
function pickWinner(options, votes) {
  const counts = new Map(options.map(o => [o.placeId, 0]));
  for (const placeId of Object.values(votes || {})) {
    if (counts.has(placeId)) counts.set(placeId, counts.get(placeId) + 1);
  }
  const top = Math.max(...counts.values());
  const leaders = options.filter(o => counts.get(o.placeId) === top);
  return pickRandom(leaders).placeId;
}

// Pure: the fields that flip a round to closed.
function closingFields(data, at = nowIso()) {
  return {
    status: 'closed',
    winnerPlaceId: pickWinner(data.options, data.votes),
    closedAt: at
  };
}

const isExpired = (data, at = nowIso()) =>
  data.status === 'open' && typeof data.expiresAt === 'string' && data.expiresAt <= at;

const isParticipant = (data, uid) =>
  Array.isArray(data.participantIds) && data.participantIds.includes(uid);

// ---------------------------------------------------------------------------
// Client shape
// ---------------------------------------------------------------------------

// Never exposes the raw `votes` map (keyed by uid): the viewer sees their own
// vote, per-option tallies, and voter *names*.
function toClientRound(doc, viewerId) {
  if (!doc) return null;
  const data = typeof doc.data === 'function' ? doc.data() : doc;
  const id = doc.id || data.id;
  const votes = data.votes || {};
  const participants = Array.isArray(data.participants) ? data.participants : [];
  // Walk participants (host first) rather than the votes map so voter order
  // is deterministic: Firestore returns map keys sorted, not in insertion order.
  const votersByPlace = new Map();
  for (const p of participants) {
    if (!Object.prototype.hasOwnProperty.call(votes, p.id)) continue;
    const placeId = votes[p.id];
    if (!votersByPlace.has(placeId)) votersByPlace.set(placeId, []);
    votersByPlace.get(placeId).push(p.name || 'Someone');
  }
  return {
    id,
    hostId: data.hostId,
    hostName: data.hostName,
    status: data.status,
    winnerPlaceId: data.winnerPlaceId || null,
    createdAt: data.createdAt || null,
    expiresAt: data.expiresAt || null,
    closedAt: data.closedAt || null,
    participants: participants.map(p => ({
      id: p.id,
      name: p.name,
      voted: Object.prototype.hasOwnProperty.call(votes, p.id)
    })),
    options: (data.options || []).map(o => {
      const voters = votersByPlace.get(o.placeId) || [];
      return { ...o, votes: voters.length, voters };
    }),
    myVote: Object.prototype.hasOwnProperty.call(votes, viewerId) ? votes[viewerId] : null,
    isHost: data.hostId === viewerId
  };
}

// ---------------------------------------------------------------------------
// Push
// ---------------------------------------------------------------------------

// Pushes are best-effort: a failure is logged and never fails the request.
async function pushSafely(userIds, notification, label) {
  if (!userIds.length) return;
  try {
    await notificationService.sendToUsers(userIds, notification);
  } catch (error) {
    console.error(`🍸 ${label} push failed:`, error.message);
  }
}

function notifyRoundStarted(round) {
  const recipients = round.participantIds.filter(id => id !== round.hostId);
  return pushSafely(recipients, {
    type: PUSH_TYPE_ROUND,
    title: `🍸 ${round.hostName} started a bar vote`,
    body: 'Tap to vote on where you\'re going next',
    data: { type: PUSH_TYPE_ROUND, roundId: round.id }
  }, 'nextbar_round');
}

function notifyResult(round) {
  const winner = round.options.find(o => o.placeId === round.winnerPlaceId);
  const voted = Object.keys(round.votes || {}).length;
  const total = round.participantIds.length;
  return pushSafely(round.participantIds, {
    type: PUSH_TYPE_RESULT,
    title: `🍸 It's ${winner ? winner.name : 'decided'}!`,
    body: `${voted} of ${total} voted`,
    data: { type: PUSH_TYPE_ROUND, roundId: round.id }
  }, 'nextbar_result');
}

// ---------------------------------------------------------------------------
// Operations
// ---------------------------------------------------------------------------

// Closes an open round inside a transaction; no-op (returns the stored data)
// if it is already closed. `justClosed` tells the caller whether to announce.
async function closeInTransaction(id, precheck) {
  const ref = roundsCol().doc(id);
  return db().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new RoundError(404, 'round_not_found', 'Round not found');
    const data = snap.data();
    if (precheck) precheck(data);
    if (data.status !== 'open') return { round: { id, ...data }, justClosed: false };
    const fields = closingFields(data);
    tx.update(ref, fields);
    return { round: { id, ...data, ...fields }, justClosed: true };
  });
}

// Lazy expiry: close and announce any open round whose expiresAt has passed.
async function settleExpired(rounds) {
  const at = nowIso();
  return Promise.all(rounds.map(async (round) => {
    if (!isExpired(round, at)) return round;
    try {
      const { round: closed, justClosed } = await closeInTransaction(round.id);
      if (justClosed) await notifyResult(closed);
      return closed;
    } catch (error) {
      console.error(`🍸 expiry close failed for round ${round.id}:`, error.message);
      return round;
    }
  }));
}

/**
 * Create a round. `host` is req.user (uid + cached user doc); the host's own
 * doc is re-read alongside the participants so hostName and the block lists
 * are fresh rather than TTL-cached.
 */
async function createRound(host, { participantIds, options, expiresInMinutes } = {}) {
  const hostId = host.uid;
  const ids = normalizeParticipantIds(participantIds, hostId);
  const normalizedOptions = normalizeOptions(options);
  const minutes = normalizeExpiresInMinutes(expiresInMinutes);

  const users = db().collection(COLLECTIONS.USERS);
  const snaps = await db().getAll(users.doc(hostId), ...ids.map(id => users.doc(id)));
  const [hostSnap, ...participantSnaps] = snaps;
  const hostData = hostSnap.exists ? hostSnap.data() : host;

  const missing = participantSnaps.find(s => !s.exists);
  if (missing) {
    throw new RoundError(404, 'user_not_found', 'One of the tagged people could not be found', { userId: missing.id });
  }

  const connected = await getConnectedUserIds(hostId);
  const strangers = ids.filter(id => !connected.has(id));
  if (strangers.length) {
    const offender = participantSnaps.find(s => s.id === strangers[0]);
    const name = displayNameOf(offender && offender.data(), strangers[0]);
    throw new RoundError(403, 'not_connected',
      `You must be connected with ${name} to tag them`, { userId: strangers[0] });
  }
  const blocked = ids.find(id => isBlockedEitherWay(hostData, id));
  if (blocked) {
    throw new RoundError(403, 'blocked', 'You can\'t tag this user', { userId: blocked });
  }

  const hostName = displayNameOf(hostData);
  const participants = [
    { id: hostId, name: hostName },
    ...participantSnaps.map(s => ({ id: s.id, name: displayNameOf(s.data()) }))
  ];
  const createdAt = nowIso();
  const expiresAt = new Date(Date.parse(createdAt) + minutes * 60 * 1000).toISOString();
  const ref = roundsCol().doc();
  const round = {
    hostId,
    hostName,
    participantIds: participants.map(p => p.id),
    participants,
    options: normalizedOptions,
    votes: {},
    status: 'open',
    winnerPlaceId: null,
    createdAt,
    expiresAt,
    closedAt: null
  };
  await ref.set(round);
  const stored = { id: ref.id, ...round };
  await notifyRoundStarted(stored);
  return toClientRound(stored, hostId);
}

/** Rounds the viewer is part of, newest first; expired ones are closed first. */
async function listRounds(viewerId) {
  const snap = await roundsCol()
    .where('participantIds', 'array-contains', viewerId)
    .orderBy('createdAt', 'desc')
    .limit(LIST_LIMIT)
    .get();
  const rounds = snap.docs.map(d => ({ id: d.id, ...d.data() }));
  const settled = await settleExpired(rounds);
  return settled.map(r => toClientRound(r, viewerId));
}

/** One round; participants only. Also settles expiry so a stale "open" never shows. */
async function getRound(viewerId, id) {
  const snap = await roundsCol().doc(id).get();
  if (!snap.exists) throw new RoundError(404, 'round_not_found', 'Round not found');
  const data = snap.data();
  if (!isParticipant(data, viewerId)) {
    throw new RoundError(403, 'not_participant', 'You\'re not part of this round');
  }
  const [round] = await settleExpired([{ id: snap.id, ...data }]);
  return toClientRound(round, viewerId);
}

/**
 * Record a vote. Vote + auto-close happen in one transaction so two last
 * voters can't both close the round; the result push goes out after commit
 * and only from the caller whose write actually closed it.
 */
async function vote(viewerId, id, placeId) {
  const choice = cleanString(placeId, 200);
  if (!choice) throw new RoundError(400, 'invalid_option', 'placeId is required');

  const ref = roundsCol().doc(id);
  const outcome = await db().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new RoundError(404, 'round_not_found', 'Round not found');
    const data = snap.data();
    if (!isParticipant(data, viewerId)) {
      throw new RoundError(403, 'not_participant', 'You\'re not part of this round');
    }
    if (isExpired(data)) {
      // Persist the lazy close (a throw here would abort the write), then
      // reject the late vote after commit.
      const fields = closingFields(data);
      tx.update(ref, fields);
      return { round: { id, ...data, ...fields }, justClosed: true, expired: true };
    }
    if (data.status !== 'open') throw new RoundError(409, 'round_closed', 'This round has ended');
    if (!data.options.some(o => o.placeId === choice)) {
      throw new RoundError(400, 'invalid_option', 'That place isn\'t one of the options');
    }
    const votes = { ...(data.votes || {}), [viewerId]: choice };
    const everyoneVoted = data.participantIds.every(pid => Object.prototype.hasOwnProperty.call(votes, pid));
    const fields = everyoneVoted ? { votes, ...closingFields({ ...data, votes }) } : { votes };
    tx.update(ref, fields);
    return { round: { id, ...data, ...fields }, justClosed: everyoneVoted };
  });
  if (outcome.justClosed) await notifyResult(outcome.round);
  if (outcome.expired) throw new RoundError(409, 'round_closed', 'This round has ended');
  return toClientRound(outcome.round, viewerId);
}

/** Host ends the round early. Idempotent: an already-closed round is returned as is. */
async function closeRound(viewerId, id) {
  const { round, justClosed } = await closeInTransaction(id, (data) => {
    if (data.hostId !== viewerId) {
      throw new RoundError(403, 'not_host', 'Only the host can end this round');
    }
  });
  if (justClosed) await notifyResult(round);
  return toClientRound(round, viewerId);
}

module.exports = {
  createRound,
  listRounds,
  getRound,
  vote,
  closeRound,
  toClientRound,
  pickWinner,
  RoundError,
  PUSH_TYPE_ROUND,
  PUSH_TYPE_RESULT,
  MIN_OPTIONS,
  MAX_OPTIONS,
  MAX_PARTICIPANTS,
  DEFAULT_EXPIRES_MINUTES,
  LIST_LIMIT
};
