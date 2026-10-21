// FavCircles' own Instagram (@favcircles): a queue of approved posts, one
// published per day by the `instagram-post` scheduled job (Wes, 2026-10-15:
// "Begin now with posting"). Posts come from Marketing/instagram-2026-10
// (seed-queue.js); the admin dashboard's Instagram tab pauses, approves and
// posts the next one now.
//
//   instagramPosts/{id}   { order, headline, imageUrl, caption, status, postedAt, mediaId, permalink, error }
//     status: approved → publishing → posted | failed;  paused = skipped by the job
//   integrations/instagram { accessToken, igUserId, tokenRefreshedAt }   (server-only; rules deny clients)
//
// Instagram API with Instagram Login (graph.instagram.com): create a media
// container from a public JPEG URL + caption, wait for it to finish, publish.
// The long-lived token lasts 60 days; it's renewed weekly here.
const { getFirestore } = require('../config/firebase');
const { localDateKey } = require('../utils/localClock');

const GRAPH = 'https://graph.instagram.com/v25.0';
const POSTS = 'instagramPosts';
const CONFIG = ['integrations', 'instagram'];
const TIME_ZONE = 'America/New_York';
const REFRESH_EVERY_MS = 7 * 86400000;
const PUBLISH_TRIES = 4;            // waits 5, 10, 15, 20 s between tries
const PUBLISH_RETRY_MS = 5000;

const nowIso = (now) => new Date(now()).toISOString();

async function call(fetchFn, method, path, params) {
  const url = new URL(path.startsWith('http') ? path : `${GRAPH}/${path}`);
  const init = { method };
  if (method === 'GET') {
    for (const [k, v] of Object.entries(params)) url.searchParams.set(k, v);
  } else {
    init.headers = { 'Content-Type': 'application/x-www-form-urlencoded' };
    init.body = new URLSearchParams(params).toString();
  }
  const res = await fetchFn(url.toString(), init);
  const body = await res.json().catch(() => ({}));
  if (!res.ok || body.error) {
    // Never echo the token: Instagram's messages don't include it, and the URL isn't logged
    throw new Error((body.error && body.error.message) || `Instagram answered ${res.status}`);
  }
  return body;
}

function createPublisher(deps = {}) {
  const db = deps.db || getFirestore();
  const fetchFn = deps.fetch || ((...a) => fetch(...a));
  const now = deps.now || (() => Date.now());
  const sleep = deps.sleep || ((ms) => new Promise((r) => setTimeout(r, ms)));
  const alert = deps.alertAdmin || ((a) => require('./adminAlerts').alertAdmin(a));
  const configRef = () => db.collection(CONFIG[0]).doc(CONFIG[1]);

  async function config() {
    const snap = await configRef().get();
    const c = snap.exists ? snap.data() : {};
    if (!c.accessToken || !c.igUserId) throw new Error('Instagram is not connected (integrations/instagram has no token)');
    return c;
  }

  /** Renews the 60-day token once a week; alerts if Instagram refuses. */
  async function refreshTokenIfDue() {
    const c = await config();
    const last = Date.parse(c.tokenRefreshedAt || 0) || 0;
    if (now() - last < REFRESH_EVERY_MS) return { refreshed: false };
    try {
      const r = await call(fetchFn, 'GET', 'https://graph.instagram.com/refresh_access_token',
        { grant_type: 'ig_refresh_token', access_token: c.accessToken });
      await configRef().set({ accessToken: r.access_token, tokenRefreshedAt: nowIso(now),
        tokenExpiresAt: new Date(now() + (r.expires_in || 0) * 1000).toISOString() }, { merge: true });
      return { refreshed: true };
    } catch (e) {
      alert({ key: 'instagram_token', title: "Instagram login couldn't be renewed",
        body: `Instagram refused to renew the posting token: ${e.message}\nIf it expires, posts stop. Generate a new token in the FavCircles Posting app (Meta developer dashboard).` });
      return { refreshed: false, error: e.message };
    }
  }

  async function list() {
    const snap = await db.collection(POSTS).get();
    return snap.docs.map((d) => ({ id: d.id, ...d.data() })).sort((a, b) => (a.order || 0) - (b.order || 0));
  }

  /**
   * Publishes the next approved post. Once per New York calendar day unless
   * `force` (the dashboard's "Post next now").
   */
  /**
   * media_publish, retried. Instagram sometimes answers "Media ID is not
   * available" right after the container reports FINISHED (2026-10-21), and
   * sometimes a failed publish went out anyway. So between tries, look for
   * the post on the account first, and never publish it twice.
   */
  async function publishContainer(c, containerId, caption, startedAt) {
    let lastError;
    for (let attempt = 0; attempt < PUBLISH_TRIES; attempt++) {
      try {
        return await call(fetchFn, 'POST', `${c.igUserId}/media_publish`, { creation_id: containerId, access_token: c.accessToken });
      } catch (e) {
        lastError = e;
      }
      await sleep(PUBLISH_RETRY_MS * (attempt + 1));
      const recent = await call(fetchFn, 'GET', `${c.igUserId}/media`, { fields: 'id,timestamp,caption', limit: '5', access_token: c.accessToken })
        .catch(() => ({ data: [] }));
      const went = (recent.data || []).find((m) => (m.caption || '').trim() === String(caption || '').trim()
        && Date.parse(m.timestamp) >= startedAt - 60000);
      if (went) return { id: went.id };
    }
    throw lastError;
  }

  async function publishNext({ force = false } = {}) {
    const c = await config();
    const posts = await list();
    const today = localDateKey(TIME_ZONE, new Date(now()));
    if (!force && posts.some((p) => p.postedAt && localDateKey(TIME_ZONE, new Date(p.postedAt)) === today)) {
      return { posted: false, reason: 'already posted today' };
    }
    const next = posts.find((p) => p.status === 'approved');
    if (!next) {
      alert({ key: 'instagram_queue_empty', minIntervalMs: 7 * 86400000, title: 'Instagram queue is empty',
        body: 'Every approved post has gone out. Add or approve more in the admin dashboard → Instagram.' });
      return { posted: false, reason: 'queue empty' };
    }

    // Claim it so an overlapping run can't post the same card twice
    const ref = db.collection(POSTS).doc(next.id);
    const claimed = await db.runTransaction(async (tx) => {
      const fresh = await tx.get(ref);
      if (!fresh.exists || fresh.data().status !== 'approved') return false;
      tx.update(ref, { status: 'publishing', updatedAt: nowIso(now) });
      return true;
    });
    if (!claimed) return { posted: false, reason: 'taken by another run' };

    const startedAt = now();
    try {
      const container = await call(fetchFn, 'POST', `${c.igUserId}/media`,
        { image_url: next.imageUrl, caption: next.caption, access_token: c.accessToken });
      let status = 'IN_PROGRESS';
      for (let i = 0; i < 20 && status !== 'FINISHED'; i++) {
        const s = await call(fetchFn, 'GET', container.id, { fields: 'status_code', access_token: c.accessToken });
        status = s.status_code;
        if (status === 'ERROR' || status === 'EXPIRED') throw new Error(`Instagram couldn't process the image (${status})`);
        if (status !== 'FINISHED') await sleep(3000);
      }
      if (status !== 'FINISHED') throw new Error('Instagram was still processing the image after a minute');
      const published = await publishContainer(c, container.id, next.caption, startedAt);
      const media = await call(fetchFn, 'GET', published.id, { fields: 'permalink', access_token: c.accessToken }).catch(() => ({}));
      await ref.update({ status: 'posted', postedAt: nowIso(now), mediaId: published.id, permalink: media.permalink || null, error: null, updatedAt: nowIso(now) });
      return { posted: true, id: next.id, mediaId: published.id, permalink: media.permalink || null };
    } catch (e) {
      await ref.update({ status: 'failed', error: String(e.message).slice(0, 500), updatedAt: nowIso(now) });
      alert({ key: `instagram_failed_${next.id}`, title: "An Instagram post didn't go out",
        body: `"${next.headline}" failed: ${e.message}\nIt's marked failed in the admin dashboard → Instagram; approve it again to retry.` });
      return { posted: false, id: next.id, error: e.message };
    }
  }

  async function setStatus(id, status) {
    if (!['approved', 'paused'].includes(status)) throw Object.assign(new Error('status must be approved or paused'), { status: 400 });
    const ref = db.collection(POSTS).doc(String(id));
    const snap = await ref.get();
    if (!snap.exists) throw Object.assign(new Error('No such post'), { status: 404 });
    if (['posted', 'publishing'].includes(snap.data().status)) throw Object.assign(new Error('That post has already gone out'), { status: 409 });
    await ref.update({ status, error: null, updatedAt: nowIso(now) });
    return { id, status };
  }

  /** The dashboard's view: the queue plus whether Instagram is connected. */
  async function dashboard() {
    const snap = await configRef().get();
    const c = snap.exists ? snap.data() : {};
    return {
      connected: !!(c.accessToken && c.igUserId),
      tokenRefreshedAt: c.tokenRefreshedAt || null,
      tokenExpiresAt: c.tokenExpiresAt || null,
      posts: (await list()).map(({ id, order, headline, imageUrl, caption, status, postedAt, permalink, error }) =>
        ({ id, order, headline, imageUrl, caption, status, postedAt: postedAt || null, permalink: permalink || null, error: error || null }))
    };
  }

  return { refreshTokenIfDue, publishNext, setStatus, dashboard, list };
}

module.exports = { createPublisher, TIME_ZONE };
