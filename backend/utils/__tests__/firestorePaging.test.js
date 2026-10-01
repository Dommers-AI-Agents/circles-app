// The pager every whole-collection job now streams through (viral-growth
// review 2026-10-01). These pin the three things a job relies on: every doc
// is visited exactly once, a stop leaves a cursor that resumes cleanly, and a
// job cursor only resumes within the run it was written for.
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const { pagedQuery, forEachPage, readJobCursor, writeJobCursor } = require('../firestorePaging');

const seed = (db, n, extra = () => ({})) => {
  for (let i = 0; i < n; i++) {
    const id = `u${String(i).padStart(3, '0')}`;
    db.rows('users').set(id, { n: i, ...extra(i) });
  }
};

describe('pagedQuery', () => {
  test('visits every doc once, in id order, a page at a time', async () => {
    const db = new FakeFirestore({ namespaced: true });
    seed(db, 23);
    const pages = [];
    for await (const docs of pagedQuery(db.collection('users'), { pageSize: 10 })) {
      pages.push(docs.map((d) => d.id));
    }
    expect(pages.map((p) => p.length)).toEqual([10, 10, 3]);
    const all = pages.flat();
    expect(all).toHaveLength(23);
    expect(new Set(all).size).toBe(23);
    expect(all).toEqual([...all].sort());
  });

  test('an exact multiple of the page size ends without an extra empty page', async () => {
    const db = new FakeFirestore({ namespaced: true });
    seed(db, 20);
    const sizes = [];
    for await (const docs of pagedQuery(db.collection('users'), { pageSize: 10 })) sizes.push(docs.length);
    expect(sizes).toEqual([10, 10]);
  });

  test('keeps the query filters', async () => {
    const db = new FakeFirestore({ namespaced: true });
    seed(db, 30, (i) => ({ even: i % 2 === 0 }));
    const ids = [];
    for await (const docs of pagedQuery(db.collection('users').where('even', '==', true), { pageSize: 4 })) {
      docs.forEach((d) => ids.push(d.data().n));
    }
    expect(ids).toEqual([0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28]);
  });

  test('resumes after a given id', async () => {
    const db = new FakeFirestore({ namespaced: true });
    seed(db, 5);
    const ids = [];
    for await (const docs of pagedQuery(db.collection('users'), { pageSize: 2, startAfter: 'u002' })) {
      docs.forEach((d) => ids.push(d.id));
    }
    expect(ids).toEqual(['u003', 'u004']);
  });

  test('an empty collection yields nothing', async () => {
    const db = new FakeFirestore({ namespaced: true });
    let pages = 0;
    for await (const docs of pagedQuery(db.collection('users'))) pages += docs.length ? 1 : 0;
    expect(pages).toBe(0);
  });
});

describe('forEachPage', () => {
  test('reports a complete pass', async () => {
    const db = new FakeFirestore({ namespaced: true });
    seed(db, 7);
    const seen = [];
    const result = await forEachPage(db.collection('users'), (docs) => { docs.forEach((d) => seen.push(d.id)); }, { pageSize: 3 });
    expect(seen).toHaveLength(7);
    expect(result).toEqual({ pages: 3, docs: 7, lastId: 'u006', complete: true });
  });

  test('stops at the deadline and the cursor resumes with no gap or repeat', async () => {
    const db = new FakeFirestore({ namespaced: true });
    seed(db, 10);
    let clock = 0;
    const seen = [];
    const visit = (docs) => { docs.forEach((d) => seen.push(d.id)); clock += 100; };
    const first = await forEachPage(db.collection('users'), visit, { pageSize: 3, deadlineMs: 150, now: () => clock });
    expect(first.complete).toBe(false);
    expect(first.docs).toBe(6);
    const second = await forEachPage(db.collection('users'), visit, { pageSize: 3, startAfter: first.lastId });
    expect(second.complete).toBe(true);
    expect(seen).toEqual(Array.from({ length: 10 }, (_, i) => `u00${i}`));
  });

  test('a page handler returning false stops the run', async () => {
    const db = new FakeFirestore({ namespaced: true });
    seed(db, 10);
    const result = await forEachPage(db.collection('users'), () => false, { pageSize: 4 });
    expect(result).toMatchObject({ pages: 1, docs: 4, lastId: 'u003', complete: false });
  });
});

describe('runResumableJob', () => {
  const { runResumableJob } = require('../firestorePaging');

  test('a run that fits finishes in one go and a repeat tick is a no-op', async () => {
    const db = new FakeFirestore({ namespaced: true });
    seed(db, 5);
    const seen = [];
    const onPage = async (docs) => { docs.forEach((d) => seen.push(d.id)); };
    const first = await runResumableJob({ db, job: 'j', runKey: 'day1', query: db.collection('users'), onPage, pageSize: 2 });
    expect(first).toMatchObject({ complete: true, docs: 5, resumedFrom: null });
    expect(await runResumableJob({ db, job: 'j', runKey: 'day1', query: db.collection('users'), onPage })).toEqual({ skipped: 'already_done' });
    expect(seen).toHaveLength(5);
    // A new day starts over.
    const next = await runResumableJob({ db, job: 'j', runKey: 'day2', query: db.collection('users'), onPage });
    expect(next.complete).toBe(true);
    expect(seen).toHaveLength(10);
  });

  test('a run cut off by the deadline is resumed by the next tick, no gaps or repeats', async () => {
    const db = new FakeFirestore({ namespaced: true });
    seed(db, 9);
    let clock = 0;
    const seen = [];
    const onPage = async (docs) => { docs.forEach((d) => seen.push(d.id)); clock += 100; };
    const opts = { db, job: 'j', runKey: 'day1', query: db.collection('users'), onPage, pageSize: 2, deadlineMs: 150, now: () => clock };
    const first = await runResumableJob(opts);
    expect(first.complete).toBe(false);
    clock += 10 * 60 * 1000; // next tick, after the lease
    let r = first;
    while (!r.complete) r = await runResumableJob(opts);
    expect(seen).toEqual(Array.from({ length: 9 }, (_, i) => `u00${i}`));
  });

  test('an overlapping invocation is turned away while the lease is held', async () => {
    const db = new FakeFirestore({ namespaced: true });
    seed(db, 3);
    let inner = null;
    const onPage = async () => {
      inner = await runResumableJob({ db, job: 'j', runKey: 'day1', query: db.collection('users'), onPage: async () => {} });
    };
    await runResumableJob({ db, job: 'j', runKey: 'day1', query: db.collection('users'), onPage });
    expect(inner).toEqual({ skipped: 'running' });
  });

  test('a continuous sweep (no run key) wraps to the top when it ends', async () => {
    const db = new FakeFirestore({ namespaced: true });
    seed(db, 3);
    const seen = [];
    const onPage = async (docs) => { docs.forEach((d) => seen.push(d.id)); };
    await runResumableJob({ db, job: 's', query: db.collection('users'), onPage });
    await runResumableJob({ db, job: 's', query: db.collection('users'), onPage });
    expect(seen).toEqual(['u000', 'u001', 'u002', 'u000', 'u001', 'u002']);
  });
});

describe('job cursors', () => {
  test('resume within the same run key, ignored for another', async () => {
    const db = new FakeFirestore({ namespaced: true });
    expect(await readJobCursor(db, 'reminders', '2026-10-01')).toEqual({ lastId: null, done: false });
    await writeJobCursor(db, 'reminders', { lastId: 'u100', runKey: '2026-10-01' });
    expect(await readJobCursor(db, 'reminders', '2026-10-01')).toEqual({ lastId: 'u100', done: false });
    expect(await readJobCursor(db, 'reminders', '2026-10-02')).toEqual({ lastId: null, done: false });
  });

  test('a finished run stays finished until the key changes', async () => {
    const db = new FakeFirestore({ namespaced: true });
    await writeJobCursor(db, 'reminders', { lastId: 'u100', done: true, runKey: '2026-10-01' });
    expect(await readJobCursor(db, 'reminders', '2026-10-01')).toEqual({ lastId: null, done: true });
    expect(await readJobCursor(db, 'reminders', '2026-10-02')).toEqual({ lastId: null, done: false });
  });
});
