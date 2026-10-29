// backend/utils/requestMemo.js
//
// Per-request memo for the reads every visibility decision repeats: the
// viewer's connections, the Inner Circle lists they're on, their user doc.
// One map/search request used to read each of them two or three times
// (getAllowedCircleIds and buildViewerContext each loaded them, and so did the
// loved-places and browse helpers on the same request).
//
// AsyncLocalStorage carries one memo through everything a request awaits, so
// no call site has to pass anything. GET requests only: a write handler that
// changes a connection and then re-reads must see the change, so writes run
// without a memo and every read hits Firestore as before.
const { AsyncLocalStorage } = require('async_hooks');

const storage = new AsyncLocalStorage();

/** Express middleware: GETs run inside a fresh memo. */
function requestMemoMiddleware(req, res, next) {
  if (req.method !== 'GET') return next();
  storage.run(new Map(), next);
}

/** Runs `fn` with a fresh memo (scheduled tasks, tests). */
function withRequestMemo(fn) {
  return storage.run(new Map(), fn);
}

/**
 * The value of `fn()` for `key`, computed once per request. Outside a request
 * memo it just calls `fn`. A failed read is forgotten, so a retry reads again.
 * Callers get a COPY of Set/Map results — one handler mutating its set must
 * not change what the next caller sees.
 */
function memo(key, fn) {
  const store = storage.getStore();
  if (!store) return fn();
  if (!store.has(key)) {
    const pending = Promise.resolve().then(fn);
    pending.catch(() => store.delete(key));
    store.set(key, pending);
  }
  return store.get(key).then(copy);
}

function copy(value) {
  if (value instanceof Set) return new Set(value);
  if (value instanceof Map) return new Map(value);
  return value;
}

/** True inside a request memo (for tests and diagnostics). */
const isMemoActive = () => Boolean(storage.getStore());

module.exports = { requestMemoMiddleware, withRequestMemo, memo, isMemoActive };
