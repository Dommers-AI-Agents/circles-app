// backend/utils/firestorePaging.js
//
// Read a big collection a page at a time instead of one `.get()`.
//
// Viral-growth review 2026-10-01: scheduled jobs loaded the WHOLE users
// collection into memory in one read. Fine at a few hundred users; at tens of
// thousands that is a multi-hundred-MB snapshot, one giant RPC, and a job that
// times out before it sends anything. Paging keeps memory flat (one page alive
// at a time) and lets a job stop at a deadline and resume where it left off.
//
// Ordering is by document id, which every equality / `in` filter can serve
// from Firestore's automatic single-field indexes — no composite index needed.
// Do NOT pass a query with an inequality filter (`!=`, `<`, `>`): Firestore
// requires the inequality field to be the first orderBy, and this helper
// orders by document id.
const { FieldPath } = require('firebase-admin/firestore');

const DEFAULT_PAGE_SIZE = 300;

/**
 * Yields arrays of document snapshots, page by page, in document-id order.
 *
 *   for await (const docs of pagedQuery(db.collection('users'))) { ... }
 *
 * opts.pageSize   docs per read (default 300)
 * opts.select     field names to read; omit to read whole documents. Only
 *                 use when every consumer of the docs is known to need just
 *                 those fields — anything else silently reads `undefined`.
 * opts.startAfter document id (or snapshot) to resume after
 */
async function* pagedQuery(query, { pageSize = DEFAULT_PAGE_SIZE, select = null, startAfter = null } = {}) {
  let base = query.orderBy(FieldPath.documentId());
  if (Array.isArray(select)) base = base.select(...select);
  let cursor = startAfter;
  for (;;) {
    let page = base;
    if (cursor) page = page.startAfter(typeof cursor === 'string' ? cursor : cursor.id);
    const snap = await page.limit(pageSize).get();
    if (snap.empty) return;
    yield snap.docs;
    if (snap.docs.length < pageSize) return;
    cursor = snap.docs[snap.docs.length - 1].id;
  }
}

/**
 * Runs `fn(docs)` for every page. Returns how far it got:
 *   { pages, docs, lastId, complete }
 * `complete` is false when it stopped early — `deadlineMs` elapsed (checked
 * between pages) or `fn` returned `false` — so the caller can store `lastId`
 * and resume from it next run.
 *
 * opts: pageSize, select, startAfter (as pagedQuery), plus
 *   deadlineMs  stop starting new pages after this many ms
 *   now         clock, for tests
 */
async function forEachPage(query, fn, { deadlineMs = null, now = Date.now, ...pageOpts } = {}) {
  const startedAt = now();
  let pages = 0;
  let docs = 0;
  let lastId = pageOpts.startAfter
    ? (typeof pageOpts.startAfter === 'string' ? pageOpts.startAfter : pageOpts.startAfter.id)
    : null;
  for await (const page of pagedQuery(query, pageOpts)) {
    pages += 1;
    docs += page.length;
    lastId = page[page.length - 1].id;
    const keepGoing = await fn(page);
    if (keepGoing === false) return { pages, docs, lastId, complete: false };
    if (deadlineMs !== null && now() - startedAt >= deadlineMs) {
      // We don't know whether more pages exist; the next run finds out.
      return { pages, docs, lastId, complete: false };
    }
  }
  return { pages, docs, lastId, complete: true };
}

// ---- resumable runs: a tiny cursor doc per job (`jobCursors/{job}`)

const JOB_CURSORS = 'jobCursors';

/**
 * Where `job` stands for this run: `{ lastId, done }`. A cursor written for a
 * different `runKey` (e.g. yesterday's date) is stale and ignored, so a daily
 * job starts from the top each new day, resumes within the same day, and once
 * `done` stays done until the key changes (a repeat tick is then a no-op).
 */
async function readJobCursor(db, job, runKey = null) {
  const snap = await db.collection(JOB_CURSORS).doc(job).get();
  const data = snap.exists ? (snap.data() || {}) : {};
  if (!snap.exists || (runKey !== null && data.runKey !== runKey)) return { lastId: null, done: false };
  return { lastId: data.lastId || null, done: data.done === true };
}

/** Saves where `job` stopped (`lastId`), or that it finished this run (`done`). */
async function writeJobCursor(db, job, { lastId = null, done = false, runKey = null } = {}) {
  await db.collection(JOB_CURSORS).doc(job).set({
    job,
    lastId: done ? null : (lastId || null),
    done: !!done,
    runKey,
    updatedAt: new Date().toISOString()
  });
}

module.exports = {
  DEFAULT_PAGE_SIZE,
  JOB_CURSORS,
  pagedQuery,
  forEachPage,
  readJobCursor,
  writeJobCursor
};
