// backend/services/runShareService.js
// Map My Run, shared (Wes, 2026-10-06): invite people to watch a run live —
// they follow the route on a map, get a fun push at every mile (or km), can
// send cheers that pop up on the runner's phone, and keep the full run when
// it's done. A finished run can also be posted to the activity feed.
//
// One doc per shared run: sharedRuns/{id}. Who may see it: the runner, the
// people watching or invited, and (once posted) the post's feed audience.

const { FieldValue } = require('firebase-admin/firestore');
const { getFirestore } = require('../config/firebase');
const { ServiceError } = require('../utils/serviceError');
const { nowIso } = require('../utils/ids');
const { clean } = require('../utils/text');
const { normalizeUserId } = require('./idService');
const { getConnectedUserIds } = require('../utils/networkAccess');
const notifyQuiet = require('./notifyQuiet');

const db = () => getFirestore();
const runsCol = () => db().collection('sharedRuns');
const LINK_BASE = `${process.env.API_PUBLIC_BASE_URL || 'https://api.favcircles.com'}/app/run/`;
const TOKEN_RE = /^[A-Za-z0-9_-]{16,32}$/;
const MAX_WATCHERS = 50;
const ROUTE_MAX = 40000;          // encoded polyline chars (~600 points is ~6 KB)
const CHEERS = ['🔥', '👏', '💪', '🎉', '🏃', '❤️'];
const CHEER_COOLDOWN_MS = 20 * 1000;
const UNIT_METERS = { mi: 1609.344, km: 1000 };

const newToken = () => require('crypto').randomBytes(15).toString('base64url');
const num = (v, max = 1e7) => (Number.isFinite(Number(v)) && Number(v) >= 0 && Number(v) <= max ? Number(v) : 0);

async function userName(uid) {
  const doc = await db().collection('users').doc(uid).get();
  const d = doc.exists ? doc.data() : {};
  return { name: (d.displayName && d.displayName.trim()) || 'Someone', avatarUrl: d.profilePicture || null };
}

// ---------------------------------------------------------------------------
// Pure (tested)
// ---------------------------------------------------------------------------

const clock = (s) => {
  const t = Math.max(0, Math.round(s));
  return t >= 3600
    ? `${Math.floor(t / 3600)}:${String(Math.floor((t % 3600) / 60)).padStart(2, '0')}:${String(t % 60).padStart(2, '0')}`
    : `${Math.floor(t / 60)}:${String(t % 60).padStart(2, '0')}`;
};

const MILESTONES = [[5000, "That's a 5K! 🎉"], [10000, "That's a 10K! 🏅"], [21097.5, 'HALF MARATHON 🤯'], [42195, 'A FULL MARATHON. Legend. 🏆']];

/** The push for split `n` (1-based) of `splits` (seconds each). */
function splitMessage({ name, unit, splits, n }) {
  const label = unit === 'km' ? 'km' : 'mile';
  const split = splits[n - 1];
  const prev = splits[n - 2];
  const totalSec = splits.slice(0, n).reduce((a, b) => a + b, 0);
  const meters = n * UNIT_METERS[unit === 'km' ? 'km' : 'mi'];
  const prevMeters = (n - 1) * UNIT_METERS[unit === 'km' ? 'km' : 'mi'];
  const milestone = MILESTONES.find(([m]) => prevMeters < m && meters >= m);
  let flavor;
  if (milestone) flavor = milestone[1];
  else if (prev && split < prev - 5) flavor = 'Picking up speed ⚡️';
  else if (prev && split > prev + 30) flavor = 'Hanging in there 💪';
  else flavor = ['Keep it rolling 🔥', 'Smooth and steady 😎', 'Legs feeling it? 🦵', 'Crushing it 🙌'][(n - 1) % 4];
  return {
    title: `🏃 ${name} hit ${label} ${n}`,
    body: `${clock(split)} that ${label} · ${clock(totalSec)} total. ${flavor}`
  };
}

const finishMessage = ({ name, unit, distanceM, movingSec }) => {
  const per = UNIT_METERS[unit === 'km' ? 'km' : 'mi'];
  const d = (distanceM / per).toFixed(2);
  const pace = distanceM >= 20 ? clock(movingSec / (distanceM / per)) : null;
  return {
    title: `🏁 ${name} finished!`,
    body: `${d} ${unit === 'km' ? 'km' : 'mi'} in ${clock(movingSec)}${pace ? ` · ${pace}/${unit === 'km' ? 'km' : 'mi'}` : ''}. Tap for the map and splits.`
  };
};

const canView = (data, uid) =>
  data.ownerId === uid || (data.watcherIds || []).includes(uid) || (data.invitedIds || []).includes(uid);

const toClientRun = (id, data, viewerId) => ({
  id,
  ownerId: data.ownerId,
  ownerName: data.ownerName,
  ownerAvatarUrl: data.ownerAvatarUrl || null,
  isMine: data.ownerId === viewerId,
  status: data.status,                       // live | finished
  unit: data.unit || 'mi',
  startedAt: data.startedAt,
  finishedAt: data.finishedAt || null,
  updatedAt: data.updatedAt,
  isPaused: !!data.isPaused,
  distanceM: data.distanceM || 0,
  movingSec: data.movingSec || 0,
  // The runner's clock at the last update, so watchers tick it forward
  movingAsOf: data.movingAsOf || data.updatedAt,
  splits: data.splits || [],
  route: data.route || '',
  position: data.position || null,
  calories: data.calories || null,
  watchers: (data.watcherIds || []).map(w => ({ id: w, name: (data.watcherNames || {})[w] || 'Watcher' })),
  invitedCount: (data.invitedIds || []).filter(w => !(data.watcherIds || []).includes(w)).length,
  cheers: (data.cheers || []).slice(-30),
  shareUrl: `${LINK_BASE}${data.token}`,
  postedAt: data.postedAt || null,
  watching: (data.watcherIds || []).includes(viewerId)
});

// ---------------------------------------------------------------------------
// Live
// ---------------------------------------------------------------------------

async function load(id) {
  const doc = await runsCol().doc(String(id)).get();
  if (!doc.exists) throw new ServiceError(404, 'not_found', 'That run is gone');
  return { ref: doc.ref, data: doc.data() };
}

async function loadViewable(id, uid) {
  const run = await load(id);
  if (!canView(run.data, uid)) throw new ServiceError(403, 'not_invited', 'Ask the runner for an invite to watch');
  return run;
}

async function startLive(uid, { unit, startedAt } = {}) {
  const me = await userName(uid);
  const now = nowIso();
  const data = {
    ownerId: uid, ownerName: me.name, ownerAvatarUrl: me.avatarUrl,
    status: 'live', unit: unit === 'km' ? 'km' : 'mi',
    startedAt: typeof startedAt === 'string' && startedAt.length < 40 ? startedAt : now,
    token: newToken(), watcherIds: [], watcherNames: {}, invitedIds: [],
    distanceM: 0, movingSec: 0, movingAsOf: now, splits: [], route: '', cheers: [],
    createdAt: now, updatedAt: now
  };
  const ref = await runsCol().add(data);
  return { run: toClientRun(ref.id, data, uid) };
}

async function invite(id, uid, { userIds } = {}) {
  const { ref, data } = await load(id);
  if (data.ownerId !== uid) throw new ServiceError(403, 'not_owner', 'Only the runner can invite');
  const connected = await getConnectedUserIds(uid);
  const wanted = [...new Set((Array.isArray(userIds) ? userIds : []).map(normalizeUserId).filter(Boolean))]
    .filter(w => w !== uid && connected.has(w) && !(data.invitedIds || []).includes(w))
    .slice(0, MAX_WATCHERS);
  if (!wanted.length) return { invited: 0 };
  await ref.update({ invitedIds: FieldValue.arrayUnion(...wanted), updatedAt: nowIso() });
  const live = data.status === 'live';
  for (const w of wanted) {
    notifyQuiet.sendInBackground(w, {
      type: 'run_live_invite',
      title: live ? `🏃 ${data.ownerName} is out for a run!` : `🏃 ${data.ownerName} shared a run with you`,
      body: live ? 'Watch it live: the route, the pace, a ping every mile. Tap to follow along.' : 'See the route and the splits.',
      data: { runId: ref.id }
    }, 'run_live_invite');
  }
  return { invited: wanted.length };
}

/** Follow along (invited, or anyone holding the link). */
async function watch(id, uid, { token } = {}) {
  const { ref, data } = token ? await loadByToken(token) : await load(id);
  if (data.ownerId === uid) return { run: toClientRun(ref.id, data, uid) };
  if (!token && !(data.invitedIds || []).includes(uid) && !(data.watcherIds || []).includes(uid)) {
    throw new ServiceError(403, 'not_invited', 'Ask the runner for an invite to watch');
  }
  if ((data.watcherIds || []).length >= MAX_WATCHERS && !(data.watcherIds || []).includes(uid)) {
    throw new ServiceError(403, 'full', 'This run has a full crowd');
  }
  const me = await userName(uid);
  if (!(data.watcherIds || []).includes(uid)) {
    await ref.update({
      watcherIds: FieldValue.arrayUnion(uid),
      [`watcherNames.${uid}`]: me.name,
      updatedAt: nowIso()
    });
    if (data.status === 'live') {
      notifyQuiet.sendInBackground(data.ownerId, {
        type: 'run_watcher_joined',
        title: `👀 ${me.name} is watching your run`,
        body: 'They get a ping every mile. Go get it!',
        data: { runId: ref.id }
      }, 'run_watcher_joined');
    }
  }
  const fresh = { ...data, watcherIds: [...new Set([...(data.watcherIds || []), uid])], watcherNames: { ...(data.watcherNames || {}), [uid]: me.name } };
  return { run: toClientRun(ref.id, fresh, uid) };
}

async function loadByToken(token) {
  if (!TOKEN_RE.test(String(token || ''))) throw new ServiceError(404, 'not_found', "That run link isn't valid");
  const snap = await runsCol().where('token', '==', String(token)).limit(1).get();
  if (snap.empty) throw new ServiceError(404, 'not_found', "That run link isn't valid");
  return { ref: snap.docs[0].ref, data: snap.docs[0].data() };
}

async function getRun(id, uid) {
  const { ref, data } = await loadViewable(id, uid);
  return { run: toClientRun(ref.id, data, uid) };
}

/** The runner's phone, every ~30 s and at each split: new splits push to watchers. */
async function progress(id, uid, body = {}) {
  const { ref, data } = await load(id);
  if (data.ownerId !== uid) throw new ServiceError(403, 'not_owner', 'Not your run');
  if (data.status !== 'live') return { ok: true };
  const splits = (Array.isArray(body.splits) ? body.splits : []).slice(0, 200).map(s => num(s, 36000));
  const route = typeof body.route === 'string' ? body.route.slice(0, ROUTE_MAX) : data.route;
  const lat = Number(body.lat), lng = Number(body.lng);
  const position = Number.isFinite(lat) && Number.isFinite(lng) && Math.abs(lat) <= 90 && Math.abs(lng) <= 180 ? { lat, lng } : data.position || null;
  const now = nowIso();
  await ref.update({
    distanceM: num(body.distanceM), movingSec: num(body.movingSec), movingAsOf: now,
    splits, route, position, isPaused: !!body.isPaused, updatedAt: now
  });
  const before = (data.splits || []).length;
  if (splits.length > before) {
    for (let n = before + 1; n <= splits.length; n++) {
      const msg = splitMessage({ name: data.ownerName, unit: data.unit, splits, n });
      for (const w of data.watcherIds || []) {
        notifyQuiet.sendInBackground(w, { type: 'run_live_split', ...msg, data: { runId: ref.id } }, 'run_live_split');
      }
    }
  }
  return { ok: true, cheers: (data.cheers || []).slice(-10) };
}

async function finish(id, uid, body = {}) {
  const { ref, data } = await load(id);
  if (data.ownerId !== uid) throw new ServiceError(403, 'not_owner', 'Not your run');
  if (data.status === 'finished') return { run: toClientRun(ref.id, data, uid) };
  const now = nowIso();
  const update = {
    status: 'finished', finishedAt: now, updatedAt: now, isPaused: false,
    distanceM: num(body.distanceM) || data.distanceM || 0,
    movingSec: num(body.movingSec) || data.movingSec || 0, movingAsOf: now,
    splits: Array.isArray(body.splits) ? body.splits.slice(0, 200).map(s => num(s, 36000)) : (data.splits || []),
    route: typeof body.route === 'string' ? body.route.slice(0, ROUTE_MAX) : (data.route || ''),
    calories: Number.isFinite(Number(body.calories)) ? Math.round(Number(body.calories)) : null
  };
  await ref.update(update);
  const msg = finishMessage({ name: data.ownerName, unit: data.unit, distanceM: update.distanceM, movingSec: update.movingSec });
  for (const w of data.watcherIds || []) {
    notifyQuiet.sendInBackground(w, { type: 'run_live_finished', ...msg, data: { runId: ref.id } }, 'run_live_finished');
  }
  return { run: toClientRun(ref.id, { ...data, ...update }, uid) };
}

/** The runner discarded it: watchers are told, the doc goes. */
async function cancel(id, uid) {
  const { ref, data } = await load(id);
  if (data.ownerId !== uid) throw new ServiceError(403, 'not_owner', 'Not your run');
  if (data.postedAt) throw new ServiceError(409, 'posted', 'This run is posted to your activity');
  await ref.delete();
  return { cancelled: true };
}

async function cheer(id, uid, { emoji } = {}) {
  if (!CHEERS.includes(emoji)) throw new ServiceError(400, 'bad_cheer', 'Pick one of the cheers');
  const { ref, data } = await loadViewable(id, uid);
  if (data.ownerId === uid) throw new ServiceError(400, 'own_run', "You can't cheer your own run");
  const last = (data.cheers || []).filter(c => c.fromId === uid).slice(-1)[0];
  if (last && Date.now() - Date.parse(last.at) < CHEER_COOLDOWN_MS) return { ok: true, throttled: true };
  const me = await userName(uid);
  const entry = { fromId: uid, fromName: me.name, emoji, at: nowIso() };
  await ref.update({ cheers: FieldValue.arrayUnion(entry), updatedAt: nowIso() });
  if (data.status === 'live') {
    notifyQuiet.sendInBackground(data.ownerId, {
      type: 'run_cheer',
      title: `${emoji} ${me.name} is cheering you on!`,
      body: 'Keep going!',
      data: { runId: ref.id }
    }, 'run_cheer');
  }
  return { ok: true };
}

/** Runs you're watching or were invited to (live first), and your own shared runs. */
async function listWatching(uid) {
  const [watching, invited, mine] = await Promise.all([
    runsCol().where('watcherIds', 'array-contains', uid).limit(30).get(),
    runsCol().where('invitedIds', 'array-contains', uid).limit(30).get(),
    runsCol().where('ownerId', '==', uid).limit(30).get()
  ]);
  const seen = new Map();
  for (const d of [...watching.docs, ...invited.docs, ...mine.docs]) seen.set(d.id, d);
  return {
    runs: [...seen.values()].map(d => toClientRun(d.id, d.data(), uid))
      .sort((a, b) => (a.status === 'live' ? 0 : 1) - (b.status === 'live' ? 0 : 1)
        || String(b.startedAt).localeCompare(String(a.startedAt)))
  };
}

// ---------------------------------------------------------------------------
// Posting a finished run to the activity feed
// ---------------------------------------------------------------------------

/**
 * Post a run (shared live or not). `runId` reuses a live run's doc; else a
 * new one is made from `summary`. The feed row is gated to `audience`
 * (connections, or the Inner Circle / one named list), like a workout.
 */
async function postToActivity(uid, { runId, summary = {}, audience, audienceListId, mapImageUrl } = {}) {
  const aud = audience === 'innerCircle' ? 'innerCircle' : 'connections';
  let ref, data;
  if (runId) {
    ({ ref, data } = await load(runId));
    if (data.ownerId !== uid) throw new ServiceError(403, 'not_owner', 'Not your run');
  } else {
    const me = await userName(uid);
    const now = nowIso();
    data = {
      ownerId: uid, ownerName: me.name, ownerAvatarUrl: me.avatarUrl, status: 'finished',
      unit: summary.unit === 'km' ? 'km' : 'mi', startedAt: typeof summary.startedAt === 'string' ? summary.startedAt : now,
      finishedAt: now, token: newToken(), watcherIds: [], watcherNames: {}, invitedIds: [], cheers: [],
      distanceM: num(summary.distanceM), movingSec: num(summary.movingSec), movingAsOf: now,
      splits: Array.isArray(summary.splits) ? summary.splits.slice(0, 200).map(s => num(s, 36000)) : [],
      route: typeof summary.route === 'string' ? summary.route.slice(0, ROUTE_MAX) : '',
      calories: Number.isFinite(Number(summary.calories)) ? Math.round(Number(summary.calories)) : null,
      createdAt: now, updatedAt: now
    };
    ref = await runsCol().add(data);
  }
  const { isAllowedImageUrl } = require('./postcardShareService');
  const image = mapImageUrl && isAllowedImageUrl(mapImageUrl) ? mapImageUrl : null;
  await ref.update({ postedAt: nowIso(), postAudience: aud, postAudienceListId: aud === 'innerCircle' ? (clean(audienceListId, 64) || null) : null, mapImageUrl: image });
  const per = UNIT_METERS[data.unit === 'km' ? 'km' : 'mi'];
  const distance = ((data.distanceM || 0) / per).toFixed(2);
  const pace = data.distanceM >= 20 ? clock(data.movingSec / (data.distanceM / per)) : null;
  const detail = `${distance} ${data.unit} · ${clock(data.movingSec || 0)}${pace ? ` · ${pace}/${data.unit}` : ''}`;
  await require('./activity/social').trackRunShared(uid, {
    runId: ref.id, detail, audience: aud,
    audienceListId: aud === 'innerCircle' ? (clean(audienceListId, 64) || null) : null, mapImageUrl: image
  });
  return { posted: true, runId: ref.id };
}

/** For the /app/run/<token> web page: who and whether it's live (no route, no position). */
async function publicPreview(token) {
  const { data } = await loadByToken(token);
  return { ownerName: data.ownerName, live: data.status === 'live' };
}

/** A posted run, for someone who tapped the feed row (the feed already gated it). */
async function getPostedRun(id, uid, viewerCanSee) {
  const { ref, data } = await load(id);
  if (!canView(data, uid) && !(data.postedAt && await viewerCanSee(data))) {
    throw new ServiceError(403, 'not_visible', "This run isn't shared with you");
  }
  return { run: toClientRun(ref.id, data, uid) };
}

module.exports = {
  startLive, invite, watch, getRun, progress, finish, cancel, cheer, listWatching, postToActivity, getPostedRun, publicPreview,
  // pure (tested)
  splitMessage, finishMessage, toClientRun, canView, CHEERS
};
