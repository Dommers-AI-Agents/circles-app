// One cache for every Local-tab source: in memory per instance, then a
// Firestore doc so all instances share a fetch. A failed load is remembered
// briefly so an outage or a bad key doesn't cost a call per tab open.
const { getFirestore } = require('../../config/firebase');

const COLLECTION = 'nearbyEventsCache';
const memory = new Map();

/**
 * `loader()` returns the value to cache, or null when it failed.
 * Returns the cached or freshly loaded value, or `fallback` on failure.
 */
async function cached(key, { memoryMs, storeMs, failMs = 5 * 60 * 1000, now = Date.now() }, loader, fallback = []) {
  const hit = memory.get(key);
  if (hit && now < hit.until) return hit.value;

  const ref = getFirestore().collection(COLLECTION).doc(key.replace(/\//g, '_'));
  try {
    const doc = await ref.get();
    const data = doc.exists ? doc.data() : null;
    if (data && data.value !== undefined && data.fetchedAtMs && now - data.fetchedAtMs < storeMs) {
      memory.set(key, { until: now + memoryMs, value: data.value });
      return data.value;
    }
  } catch (err) {
    console.warn(`[localEvents] cache read failed (${key}):`, err.message);
  }

  let value = null;
  try {
    value = await loader();
  } catch (err) {
    console.warn(`[localEvents] load failed (${key}):`, err.name === 'AbortError' ? 'timeout' : err.message);
  }
  if (value === null || value === undefined) {
    memory.set(key, { until: now + failMs, value: fallback });
    return fallback;
  }
  memory.set(key, { until: now + memoryMs, value });
  ref.set({ value, fetchedAtMs: now, expiresAt: new Date(now + storeMs) })
    .catch((err) => console.warn(`[localEvents] cache write failed (${key}):`, err.message));
  return value;
}

/** fetch() with a timeout; resolves to parsed JSON, or null on a non-2xx. */
async function fetchJson(url, { timeoutMs = 4000, headers = {}, label = 'source' } = {}) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetch(url, { signal: controller.signal, headers });
    if (!res.ok) {
      console.warn(`[localEvents] ${label} answered ${res.status}`);
      return null;
    }
    return await res.json();
  } finally {
    clearTimeout(timer);
  }
}

module.exports = { cached, fetchJson, _memory: memory };
