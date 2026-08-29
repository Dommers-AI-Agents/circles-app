// backend/services/googleListResolver.js
//
// Turns a shared Google Maps LIST link into its places.
//
// Google has no public API for saved lists. The Maps web app loads a list's
// contents from an internal endpoint, /maps/preview/entitylist/getlist, whose
// `pb` protobuf parameter was captured from the real web app (headless-Chrome
// network log, 2026-08-29) and reduced to the minimal form that still answers:
//
//   pb=!1m4!1s<listId>!2e1!3m1!1e1!2e2!3e2!4i500
//
// No session token, cookie, or browser User-Agent is required (verified with a
// plain CFNetwork UA). `4i500` is the page size. Response is `)]}'` + JSON:
//
//   [0][3]  author  [name, avatarUrl, gaiaId]
//   [0][4]  list name
//   [0][5]  list description
//   [0][8]  entries
//   [0][12] total item count
//   entry[2]        place name          entry[3] author's note
//   entry[1][2]     "Name, full address" entry[1][4] address (may be "")
//   entry[1][5]     [null, null, lat, lng]
//   entry[1][6]     [featureId, CID] as SIGNED decimal int64 strings
//   entry[1][7]     knowledge-graph id ("/g/11g0lffl0_")
//
// ⚠️ Undocumented and can change without notice. Everything here is server
// side so a breakage is a deploy, not an app release.
//
// Security: this module fetches user-supplied URLs. Hosts are allow-listed,
// redirects are followed manually with the allow-list re-checked per hop, and
// the list request itself is built from the validated ID only — a client can
// never make this service fetch an arbitrary URL.

const MAPS_SHORT_HOSTS = new Set(['maps.app.goo.gl', 'goo.gl']);
const MAPS_HOSTS = new Set(['www.google.com', 'google.com', 'maps.google.com']);
const MAX_REDIRECTS = 4;
const FETCH_TIMEOUT_MS = 8000;
const PAGE_SIZE = 500;
// Deliberately NOT a browser UA: Google's redirector 302s plain clients but
// serves real browsers a JS interstitial with no target in it.
const USER_AGENT = 'FavCircles CFNetwork Darwin';

const LIST_ID_RE = /^[A-Za-z0-9_-]{8,128}$/;

class GoogleListError extends Error {
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

const isAllowedHost = (url) =>
  MAPS_SHORT_HOSTS.has(url.hostname) ||
  (MAPS_HOSTS.has(url.hostname) && url.pathname.startsWith('/maps'));

/**
 * Pull a list id out of any of the URL shapes Google uses for lists:
 *   /maps/@/data=!4m3!11m2!2s<id>!3e3   (share-link redirect target)
 *   /maps/@/data=!4m2!11m1!2s<id>       (placelists page redirect target)
 *   /maps/placelists/list/<id>
 */
function extractListId(urlString) {
  if (!urlString) return null;
  const decoded = decodeURIComponent(urlString);
  const m = decoded.match(/!11m\d+!2s([A-Za-z0-9_-]{8,128})/) ||
            decoded.match(/\/maps\/placelists\/list\/([A-Za-z0-9_-]{8,128})/);
  return m ? m[1] : null;
}

async function fetchWithTimeout(url, options = {}) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);
  try {
    return await fetch(url, { ...options, signal: controller.signal });
  } finally {
    clearTimeout(timer);
  }
}

/**
 * Follow a share link's redirect chain manually (allow-list checked at every
 * hop) until a URL that carries a list id appears, or we run out of hops.
 * Returns { listId, finalUrl } — listId null when the link isn't a list.
 */
async function expandToListId(inputUrl) {
  let current;
  try {
    current = new URL(inputUrl.trim());
  } catch (_) {
    throw new GoogleListError('INVALID_URL', 'That is not a valid link');
  }
  if (!['http:', 'https:'].includes(current.protocol) || !isAllowedHost(current)) {
    throw new GoogleListError('NOT_GOOGLE_MAPS', 'Only Google Maps links are supported');
  }

  // Google's share sheet appends ?g_st=<share-target-id>; with it present the
  // redirector answers 200 with an interstitial instead of the 302.
  current.searchParams.delete('g_st');

  for (let hop = 0; hop <= MAX_REDIRECTS; hop++) {
    const found = extractListId(current.href);
    if (found) return { listId: found, finalUrl: current.href };

    const response = await fetchWithTimeout(current.href, {
      method: 'GET',
      redirect: 'manual',
      headers: { 'User-Agent': USER_AGENT, 'Accept-Language': 'en' }
    });
    const location = response.headers.get('location');
    // Drain the body so the socket is released
    try { await response.arrayBuffer(); } catch (_) { /* ignore */ }

    if (!location) break;
    let next;
    try {
      next = new URL(location, current);
    } catch (_) {
      break;
    }
    if (next.protocol !== 'https:' || !isAllowedHost(next)) {
      throw new GoogleListError('NOT_GOOGLE_MAPS', 'That link does not lead to Google Maps');
    }
    current = next;
  }
  return { listId: null, finalUrl: current.href };
}

/** Signed decimal int64 string → unsigned decimal string (Google CID form). */
function unsignedCid(value) {
  if (value === null || value === undefined) return null;
  try {
    let n = BigInt(String(value));
    if (n < 0n) n += 1n << 64n;
    return n.toString();
  } catch (_) {
    return null;
  }
}

function deriveAddress(entryInfo, name) {
  const short = typeof entryInfo[4] === 'string' ? entryInfo[4].trim() : '';
  if (short) return short;
  const full = typeof entryInfo[2] === 'string' ? entryInfo[2].trim() : '';
  if (!full) return null;
  const prefix = `${name}, `;
  if (name && full.startsWith(prefix)) return full.slice(prefix.length).trim() || null;
  return full === name ? null : full;
}

function parseEntry(entry) {
  if (!Array.isArray(entry)) return null;
  const info = Array.isArray(entry[1]) ? entry[1] : [];
  const name = typeof entry[2] === 'string' ? entry[2].trim() : '';
  if (!name) return null;

  const coords = Array.isArray(info[5]) ? info[5] : [];
  const lat = typeof coords[2] === 'number' ? coords[2] : null;
  const lng = typeof coords[3] === 'number' ? coords[3] : null;
  const ids = Array.isArray(info[6]) ? info[6] : [];
  const cid = unsignedCid(ids[1]);

  return {
    name,
    address: deriveAddress(info, name),
    lat,
    lng,
    notes: typeof entry[3] === 'string' && entry[3].trim() ? entry[3].trim() : null,
    cid,
    kgId: typeof info[7] === 'string' ? info[7] : null,
    // Stable per-venue key for re-import dedupe, and a canonical Maps URL
    sourceExternalId: cid ? `gcid:${cid}` : null,
    sourceUrl: cid ? `https://www.google.com/maps?cid=${cid}` : null
  };
}

/**
 * Fetch and parse a list by id. Throws GoogleListError on any failure.
 */
async function fetchList(listId) {
  if (!LIST_ID_RE.test(listId)) {
    throw new GoogleListError('INVALID_LIST_ID', 'Invalid list id');
  }
  const pb = `!1m4!1s${listId}!2e1!3m1!1e1!2e2!3e2!4i${PAGE_SIZE}`;
  const url = `https://www.google.com/maps/preview/entitylist/getlist?authuser=0&hl=en&gl=us&pb=${encodeURIComponent(pb)}`;

  const response = await fetchWithTimeout(url, {
    headers: { 'User-Agent': USER_AGENT, 'Accept-Language': 'en' }
  });
  if (response.status === 404 || response.status === 400) {
    throw new GoogleListError('LIST_NOT_FOUND', 'That list is private or no longer exists');
  }
  if (!response.ok) {
    throw new GoogleListError('UPSTREAM', `Google answered ${response.status}`);
  }
  const text = await response.text();
  const start = text.indexOf('[');
  if (start < 0) throw new GoogleListError('UPSTREAM', 'Unexpected response from Google');

  let data;
  try {
    data = JSON.parse(text.slice(start));
  } catch (_) {
    throw new GoogleListError('UPSTREAM', 'Could not read the list from Google');
  }
  const top = Array.isArray(data) ? data[0] : null;
  if (!Array.isArray(top)) throw new GoogleListError('UPSTREAM', 'Could not read the list from Google');

  const author = Array.isArray(top[3]) ? top[3] : [];
  const entries = Array.isArray(top[8]) ? top[8] : [];
  const places = entries.map(parseEntry).filter(Boolean);
  const totalCount = typeof top[12] === 'number' ? top[12] : places.length;

  return {
    id: listId,
    name: (typeof top[4] === 'string' && top[4].trim()) || 'Google Maps list',
    description: typeof top[5] === 'string' && top[5].trim() ? top[5].trim() : null,
    author: typeof author[0] === 'string' ? author[0] : null,
    url: `https://www.google.com/maps/placelists/list/${listId}`,
    totalCount,
    truncated: totalCount > places.length,
    places
  };
}

/**
 * One-shot: any Google Maps link → { list } or throws GoogleListError with a
 * `code` the API layer maps to a status. NOT_A_LIST means it was a single
 * place (or something else) — the caller should fall back to the normal
 * single-place share flow.
 */
async function resolveGoogleList(inputUrl) {
  const { listId, finalUrl } = await expandToListId(inputUrl);
  if (!listId) {
    throw new GoogleListError('NOT_A_LIST', 'That link is a single place, not a list');
  }
  const list = await fetchList(listId);
  return { ...list, sharedUrl: finalUrl };
}

module.exports = {
  GoogleListError,
  extractListId,
  expandToListId,
  fetchList,
  resolveGoogleList,
  _internal: { unsignedCid, parseEntry, deriveAddress }
};
