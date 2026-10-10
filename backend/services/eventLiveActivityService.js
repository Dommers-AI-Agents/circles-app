// backend/services/eventLiveActivityService.js
// An event on members' lock screens and Dynamic Islands (iOS Live Activity),
// kept current by push for everyone who turned it on (Wes, 2026-10-06).
//
// Each phone that shows it registers its Live Activity push token (plus its
// FCM token, which FCM needs to route the message) under
// events/{id}/liveTokens/{uid}. A change (photo, shout-out, song, roll call,
// challenges) schedules one update per event within REFRESH_DELAY_MS; ending
// the event ends everyone's display. Sent through FCM's HTTP v1 API directly:
// firebase-admin 13.3 has no live_activity_token field.

const { getFirestore } = require('../config/firebase');
const { nowIso } = require('../utils/ids');

const db = () => getFirestore();
const REFRESH_DELAY_MS = 10 * 1000;
const APNS_TOPIC = `${process.env.IOS_BUNDLE_ID || 'com.favcircles.circles'}.push-type.liveactivity`;
const pending = new Map(); // eventId → timer

const tokensCol = (eventId) => db().collection('events').doc(String(eventId)).collection('liveTokens');

/** Pure (tested): what the lock screen shows — keys match the app's
 *  EventActivityAttributes.ContentState exactly (no Dates: strings/ints). */
function contentState(data, topSong) {
  const members = (data.memberIds || []).length;
  const rc = data.rollCall && data.rollCall.id && !data.rollCall.closedAt ? data.rollCall : null;
  const hereCount = rc ? Object.keys(rc.here || {}).filter(uid => (data.memberIds || []).includes(uid)).length : 0;
  const rollCall = rc ? (hereCount >= members ? "Everyone's here 🙌" : `Roll call: ${hereCount} of ${members} here`) : null;
  // The newest thing that happened
  const candidates = [];
  if (data.lastPhoto && data.lastPhoto.at) {
    const n = data.lastPhoto.count || 1;
    const what = data.lastPhoto.kind === 'video' ? 'a video' : (n === 1 ? 'a photo' : `${n} photos`);
    candidates.push({ at: data.lastPhoto.at, text: `${data.lastPhoto.kind === 'video' ? '🎬' : '📸'} ${data.lastPhoto.by || 'Someone'} added ${what}` });
  }
  if (data.lastShoutout && data.lastShoutout.at) {
    candidates.push({ at: data.lastShoutout.at, text: `💬 ${data.lastShoutout.authorName}: ${data.lastShoutout.text}`.slice(0, 120) });
  }
  if (rc && rc.startedAt) candidates.push({ at: rc.startedAt, text: `🙋 ${rc.startedByName || data.hostName} called roll` });
  candidates.sort((a, b) => String(b.at).localeCompare(String(a.at)));
  const challenges = (data.challenges || []).length;
  return {
    members,
    photos: data.photoCount || 0,
    headline: data.endedAt ? `${data.name} has ended. See the recap ✨` : ((candidates[0] && candidates[0].text) || `${members} ${members === 1 ? 'person' : 'people'} in`),
    rollCall,
    song: topSong ? `🎵 ${topSong.title}${topSong.artist ? ` · ${topSong.artist}` : ''}` : null,
    challenges: challenges ? `${challenges} photo challenge${challenges === 1 ? '' : 's'}` : null,
    ended: !!data.endedAt
  };
}

async function register(eventId, uid, { token, fcmToken } = {}) {
  const ev = require('./eventService');
  await ev.loadAsMember(eventId, uid);
  const valid = (t) => typeof t === 'string' && /^[A-Za-z0-9:_\-.]{20,4096}$/.test(t);
  if (!valid(token) || !valid(fcmToken)) {
    const { ServiceError } = require('../utils/serviceError');
    throw new ServiceError(400, 'bad_token', 'Missing the lock-screen token');
  }
  await tokensCol(eventId).doc(uid).set({ token, fcmToken, updatedAt: nowIso() });
  return { registered: true };
}

async function unregister(eventId, uid) {
  await tokensCol(eventId).doc(uid).delete().catch(() => {});
  return { unregistered: true };
}

/** Something changed: update everyone's lock screen shortly (coalesced). */
function refreshSoon(eventId) {
  if (!eventId || pending.has(eventId)) return;
  pending.set(eventId, setTimeout(() => {
    pending.delete(eventId);
    pushUpdate(eventId).catch(err => console.error('🔒 event live update failed:', err.message));
  }, REFRESH_DELAY_MS));
}

async function topUnplayedSong(eventId) {
  const snap = await db().collection('events').doc(String(eventId)).collection('songs').orderBy('createdAt', 'desc').limit(100).get();
  return snap.docs.map(d => d.data()).filter(s => !s.playedAt)
    .sort((a, b) => (b.votes || []).length - (a.votes || []).length)[0] || null;
}

async function pushUpdate(eventId, { end = false } = {}) {
  const tokens = await tokensCol(eventId).get();
  if (tokens.empty) return { sent: 0 };
  const doc = await db().collection('events').doc(String(eventId)).get();
  if (!doc.exists) return { sent: 0 };
  const data = doc.data();
  const state = contentState(data, end ? null : await topUnplayedSong(eventId));
  const isEnd = end || !!data.endedAt;
  let sent = 0;
  for (const row of tokens.docs) {
    const { token, fcmToken } = row.data();
    // Members who left stop getting it
    if (!(data.memberIds || []).includes(row.id)) { await row.ref.delete().catch(() => {}); continue; }
    const ok = await sendLiveActivity({ fcmToken, token, state, end: isEnd, urgent: !!state.rollCall && !isEnd });
    if (ok === 'gone') await row.ref.delete().catch(() => {});
    else if (ok) sent++;
  }
  if (isEnd) await Promise.all(tokens.docs.map(r => r.ref.delete().catch(() => {})));
  return { sent };
}

async function endForEvent(eventId) {
  const timer = pending.get(eventId);
  if (timer) { clearTimeout(timer); pending.delete(eventId); }
  return pushUpdate(eventId, { end: true });
}

/** One Live Activity push through FCM v1. Returns true, false, or 'gone'. */
async function sendLiveActivity({ fcmToken, token, state, end, urgent }) {
  const admin = require('firebase-admin');
  const projectId = process.env.FIREBASE_PROJECT_ID || admin.app().options.projectId;
  const access = await admin.app().options.credential.getAccessToken();
  const now = Math.floor(Date.now() / 1000);
  const aps = { timestamp: now, event: end ? 'end' : 'update', 'content-state': state };
  if (end) aps['dismissal-date'] = now + 4 * 60 * 60; // the recap line stays a while
  else aps['stale-date'] = now + 6 * 60 * 60;
  const res = await fetch(`https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${access.access_token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      message: {
        token: fcmToken,
        apns: {
          live_activity_token: token,
          headers: { 'apns-push-type': 'liveactivity', 'apns-topic': APNS_TOPIC, 'apns-priority': urgent || end ? '10' : '5' },
          payload: { aps }
        }
      }
    })
  });
  if (res.ok) return true;
  const body = await res.text().catch(() => '');
  if (res.status === 404 || /UNREGISTERED|NOT_FOUND/.test(body)) return 'gone';
  console.error(`🔒 live activity push ${res.status}: ${body.slice(0, 200)}`);
  return false;
}

module.exports = { register, unregister, refreshSoon, endForEvent, pushUpdate, contentState };
