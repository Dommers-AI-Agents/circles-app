// backend/utils/pagination.js
//
// Clamp client-supplied ?limit / ?offset before they reach a Firestore query.
// Uncapped, `?limit=100000` reads (and bills) the whole collection, and
// Firestore bills every document an `offset` skips, so `?offset=1000000` is
// the same attack (security audit 2026-10-01). Garbage input ("abc", -5)
// falls back to the default instead of throwing inside the query.

function toInt(value, fallback) {
  const n = parseInt(value, 10);
  return Number.isFinite(n) ? n : fallback;
}

/**
 * @param {object} query  req.query (or any { limit, offset })
 * @param {object} [opts]
 * @param {number} [opts.defaultLimit=20]
 * @param {number} [opts.maxLimit=100]
 * @param {number} [opts.maxOffset=1000]
 * @returns {{ limit: number, offset: number }}
 */
function clampPagination(query = {}, { defaultLimit = 20, maxLimit = 100, maxOffset = 1000 } = {}) {
  const limit = Math.min(Math.max(toInt(query.limit, defaultLimit), 1), maxLimit);
  const offset = Math.min(Math.max(toInt(query.offset, 0), 0), maxOffset);
  return { limit, offset };
}

module.exports = { clampPagination };
