const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const { createPublisher } = require('../instagramPublisher');

// Instagram's API, scripted: records every call and answers by path
// failPublish: true = always, or how many tries fail; wentAnyway: a failed
// publish still shows up on the account (Instagram does that)
function fakeInstagram({ failPublish = false, wentAnyway = false, statuses = ['IN_PROGRESS', 'FINISHED'] } = {}) {
  const calls = [];
  let polls = 0;
  let publishTries = 0;
  const posted = [];
  const fetch = async (url, init = {}) => {
    const u = new URL(url);
    const params = init.body ? Object.fromEntries(new URLSearchParams(init.body)) : Object.fromEntries(u.searchParams);
    calls.push({ method: init.method, path: u.pathname, params });
    const json = (body, ok = true) => ({ ok, status: ok ? 200 : 400, json: async () => body });
    if (u.pathname.endsWith('/refresh_access_token')) return json({ access_token: 'IGnew', expires_in: 5184000 });
    if (u.pathname.endsWith('/media') && init.method === 'GET') return json({ data: posted });
    if (u.pathname.endsWith('/media')) return json({ id: 'container1' });
    if (u.pathname.endsWith('/container1')) return json({ status_code: statuses[Math.min(polls++, statuses.length - 1)] });
    if (u.pathname.endsWith('/media_publish')) {
      publishTries++;
      const fails = failPublish === true || publishTries <= Number(failPublish || 0);
      if (fails && wentAnyway) posted.push({ id: 'media9', timestamp: '2026-10-15T16:00:05+0000', caption: 'cap a' });
      return fails ? json({ error: { message: 'Media ID is not available' } }, false) : json({ id: 'media9' });
    }
    if (u.pathname.endsWith('/media9')) return json({ permalink: 'https://www.instagram.com/p/abc/' });
    return json({ error: { message: 'unexpected ' + u.pathname } }, false);
  };
  return { fetch, calls };
}

async function setup(opts = {}) {
  const db = new FakeFirestore({ namespaced: true });
  await db.collection('integrations').doc('instagram').set({ accessToken: 'IGtoken', igUserId: '1784', tokenRefreshedAt: opts.refreshedAt || '2026-10-15T00:00:00Z' });
  for (const [i, id] of ['a', 'b', 'c'].entries()) {
    await db.collection('instagramPosts').doc(id).set({ order: i, headline: id.toUpperCase(), imageUrl: `https://favcircles.com/ig/posts/${id}.jpg`, caption: `cap ${id}`, status: opts.firstPaused && id === 'a' ? 'paused' : 'approved' });
  }
  const ig = fakeInstagram(opts);
  const alerts = [];
  const now = { t: Date.parse(opts.now || '2026-10-15T16:00:00Z') };
  const publisher = createPublisher({ db, fetch: ig.fetch, now: () => now.t, sleep: async () => {}, alertAdmin: (a) => alerts.push(a) });
  const doc = async (id) => (await db.collection('instagramPosts').doc(id).get()).data();
  return { db, publisher, ig, alerts, now, doc };
}

describe('instagramPublisher', () => {
  it('publishes the next approved post: container, wait, publish, permalink', async () => {
    const { publisher, ig, doc } = await setup();
    const r = await publisher.publishNext();
    expect(r).toMatchObject({ posted: true, id: 'a', mediaId: 'media9', permalink: 'https://www.instagram.com/p/abc/' });
    expect(ig.calls[0]).toMatchObject({ method: 'POST', path: '/v25.0/1784/media', params: { image_url: 'https://favcircles.com/ig/posts/a.jpg', caption: 'cap a', access_token: 'IGtoken' } });
    expect(ig.calls.find((c) => c.path.endsWith('/media_publish')).params.creation_id).toBe('container1');
    expect(await doc('a')).toMatchObject({ status: 'posted', mediaId: 'media9' });
    expect((await doc('b')).status).toBe('approved');
  });

  it('posts once a New York day unless forced, and skips paused posts', async () => {
    const { publisher, now } = await setup({ firstPaused: true });
    expect((await publisher.publishNext()).id).toBe('b');
    expect(await publisher.publishNext()).toMatchObject({ posted: false, reason: 'already posted today' });
    expect((await publisher.publishNext({ force: true })).id).toBe('c');
    now.t = Date.parse('2026-10-16T16:00:00Z');
    expect(await publisher.publishNext()).toMatchObject({ posted: false, reason: 'queue empty' });
  });

  it('a failed publish marks the post failed and alerts; approving it again retries it', async () => {
    const { publisher, alerts, doc } = await setup({ failPublish: true });
    const r = await publisher.publishNext();
    expect(r).toMatchObject({ posted: false, id: 'a', error: 'Media ID is not available' });
    expect((await doc('a')).status).toBe('failed');
    expect(alerts[0].title).toMatch(/didn't go out/);
    await publisher.setStatus('a', 'approved');
    expect((await doc('a')).status).toBe('approved');
  });

  it('"Media ID is not available" is retried until it goes out', async () => {
    const { publisher, ig, doc } = await setup({ failPublish: 2 });
    expect(await publisher.publishNext()).toMatchObject({ posted: true, id: 'a', mediaId: 'media9' });
    expect(ig.calls.filter((c) => c.path.endsWith('/media_publish')).length).toBe(3);
    expect((await doc('a')).status).toBe('posted');
  });

  it('a publish that errored but went out anyway is found, not posted twice', async () => {
    const { publisher, ig, doc } = await setup({ failPublish: true, wentAnyway: true });
    expect(await publisher.publishNext()).toMatchObject({ posted: true, id: 'a', mediaId: 'media9' });
    expect(ig.calls.filter((c) => c.path.endsWith('/media_publish')).length).toBe(1);
    expect((await doc('a')).status).toBe('posted');
  });

  it('an image Instagram rejects fails without publishing', async () => {
    const { publisher, ig, doc } = await setup({ statuses: ['ERROR'] });
    expect((await publisher.publishNext()).posted).toBe(false);
    expect(ig.calls.some((c) => c.path.endsWith('/media_publish'))).toBe(false);
    expect((await doc('a')).error).toMatch(/couldn't process/);
  });

  it('renews the token weekly, not daily', async () => {
    const fresh = await setup({ refreshedAt: '2026-10-14T00:00:00Z' });
    expect(await fresh.publisher.refreshTokenIfDue()).toEqual({ refreshed: false });
    const stale = await setup({ refreshedAt: '2026-10-01T00:00:00Z' });
    expect(await stale.publisher.refreshTokenIfDue()).toEqual({ refreshed: true });
    const cfg = (await stale.db.collection('integrations').doc('instagram').get()).data();
    expect(cfg.accessToken).toBe('IGnew');
  });

  it("a posted post can't be paused; the dashboard never exposes the token", async () => {
    const { publisher } = await setup();
    await publisher.publishNext();
    await expect(publisher.setStatus('a', 'paused')).rejects.toThrow(/already gone out/);
    const d = await publisher.dashboard();
    expect(d.connected).toBe(true);
    expect(JSON.stringify(d)).not.toMatch(/IGtoken/);
    expect(d.posts.map((p) => p.status)).toEqual(['posted', 'approved', 'approved']);
  });
});
