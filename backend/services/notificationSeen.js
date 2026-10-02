// services/notificationSeen.js
//
// A notification is news until you've seen the thing it's about. Opening the
// conversation, the place, the post, the moment, the profile or the check-in
// settles the bell rows that point at it, so the red dot (and the icon badge)
// go away without a trip to the Notifications list (Wes, 2026-10-02).
//
// One table: which request means "I opened X" (ORIGIN_ROUTES), and which row
// types each kind of X settles (SETTLES). middleware/notificationSeen.js runs
// the table after every successful request; nothing else calls in here.
const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');

/** Row types each origin settles, and the row `data` keys that name it. */
const SETTLES = {
  conversation: { types: ['new_message'], keys: ['conversationId'] },
  place: { types: ['place_like', 'place_comment', 'new_suggestion'], keys: ['placeId', 'globalPlaceId'] },
  // check_in rows name the check-in, not the post: markSeen adds the post's checkInId
  activity: { types: ['activity_reaction', 'activity_comment', 'check_in'], keys: ['activityId', 'checkInId'] },
  video: { types: ['moment_tag'], keys: ['videoId'] },
  person: { types: ['connection_accepted', 'new_follower'], keys: ['fromUserId', 'followerId'] },
  connection: { types: ['connection_request'], keys: ['connectionId'] },
  checkIn: { types: ['check_in', 'check_in_response'], keys: ['checkInId'] },
  carePlan: {
    types: ['care_invite', 'care_accepted', 'care_silence', 'care_watcher_request', 'care_watcher_invite',
      'care_watcher_accepted', 'care_watcher_declined', 'care_watcher_joined', 'care_watcher_removed'],
    keys: ['planId']
  }
};

const seg = '([^/?]+)';
/** [method, path pattern under /api, origin kind, where the id comes from] */
const ORIGIN_ROUTES = [
  ['POST', `^/messages/conversations/${seg}/read$`, 'conversation'],
  ['GET', `^/places/global/${seg}$`, 'place'],
  ['GET', `^/places/${seg}$`, 'place'],
  ['GET', `^/places/${seg}/comments$`, 'place'],
  ['GET', `^/activities/${seg}/comments$`, 'activity'],
  ['GET', `^/videos/${seg}$`, 'video'],
  ['POST', `^/videos/reels/${seg}/view$`, 'video'],
  ['GET', `^/users/${seg}$`, 'person'],
  ['POST', `^/connections/${seg}/accept$`, 'connection'],
  ['DELETE', `^/connections/${seg}/decline$`, 'connection'],
  ['GET', `^/check-ins/${seg}$`, 'checkIn'],
  ['POST', `^/widgets/care/plans/${seg}/respond$`, 'carePlan'],
  ['POST', `^/widgets/care/plans/${seg}/watchers/[^/]+/respond$`, 'carePlan'],
  ['GET', '^/widgets/care/asks$', 'carePlan', 'planId']
].map(([method, pattern, kind, queryKey]) => ({ method, re: new RegExp(pattern), kind, queryKey }));

// Words under /places and /users that are lists, not one thing
const NOT_IDS = new Set(['me', 'global', 'search', 'nearby', 'feed', 'recent', 'popular', 'batch', 'trending', 'my-save', 'contacts']);

/** The thing a request opened, or null. Pure. `path` is relative to /api. */
function originFor(method, path, query = {}) {
  const clean = String(path || '').split('?')[0].replace(/\/+$/, '');
  for (const route of ORIGIN_ROUTES) {
    if (route.method !== method) continue;
    const m = clean.match(route.re);
    if (!m) continue;
    const id = route.queryKey ? query[route.queryKey] : decodeURIComponent(m[1]);
    if (!id || NOT_IDS.has(String(id))) return null;
    return { kind: route.kind, id: String(id) };
  }
  return null;
}

/** Does this unread row point at `ids` for an origin of `kind`? Pure. */
function rowMatches(row, kind, ids) {
  const rule = SETTLES[kind];
  if (!rule || !rule.types.includes(row.type)) return false;
  const data = row.data || {};
  const refs = [data, data.sourceRef || {}];
  return rule.keys.some((key) => refs.some((ref) => ref[key] !== undefined && ref[key] !== null && ids.has(String(ref[key]))));
}

/**
 * Mark the viewer's unread rows about this origin read. Returns how many.
 * Places are matched through the venue: a like on Sal's save of a café is
 * seen when you open the café from anywhere.
 */
async function markSeen(userId, origin, { db = getFirestore(), now = new Date().toISOString() } = {}) {
  if (!userId || !origin || !SETTLES[origin.kind]) return 0;
  const snap = await db.collection(COLLECTIONS.NOTIFICATIONS)
    .where('userId', '==', String(userId)).where('read', '==', false).get();
  const candidates = snap.docs.filter((d) => SETTLES[origin.kind].types.includes(d.data().type));
  if (candidates.length === 0) return 0;

  const ids = new Set([origin.id]);
  let saveVenue = new Map();
  if (origin.kind === 'place') {
    // The opened id may be a save or a venue; rows may name either
    const rowSaveIds = candidates.map((d) => (d.data().data || {}).placeId).filter(Boolean).map(String);
    const lookups = [...new Set([origin.id, ...rowSaveIds])];
    const docs = await db.getAll(...lookups.map((id) => db.collection(COLLECTIONS.PLACES).doc(id)));
    saveVenue = new Map(docs.filter((d) => d.exists && d.data().globalPlaceId).map((d) => [d.id, String(d.data().globalPlaceId)]));
    if (saveVenue.has(origin.id)) ids.add(saveVenue.get(origin.id));
  }

  if (origin.kind === 'activity' && candidates.some((d) => d.data().type === 'check_in')) {
    const post = await db.collection(COLLECTIONS.ACTIVITIES).doc(origin.id).get();
    const p = post.exists ? post.data() : {};
    const meta = p.metadata || {};
    [p.checkInId, meta.checkInId, p.sourceId, meta.sourceId].filter(Boolean).forEach((v) => ids.add(String(v)));
  }

  const hits = candidates.filter((d) => {
    const row = d.data();
    if (rowMatches(row, origin.kind, ids)) return true;
    const savedAt = saveVenue.get(String((row.data || {}).placeId));
    return origin.kind === 'place' && !!savedAt && ids.has(savedAt);
  });
  await Promise.all(hits.map((d) => d.ref.update({ read: true, readAt: now, seenVia: origin.kind })));
  return hits.length;
}

module.exports = { SETTLES, ORIGIN_ROUTES, originFor, rowMatches, markSeen };
