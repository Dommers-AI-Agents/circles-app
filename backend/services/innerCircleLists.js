// services/innerCircleLists.js
//
// The shape of the Inner Circle lists, with no database in it, so the same
// rules can be read by the writer (innerCircleService) and by the reverse
// lookup (utils/networkAccess) without either importing the other.
//
// A user may keep several named lists — "Family", "Gym crew" — and content
// set to the Inner Circle tier may name one of them. Two fields hold this:
//
//   users/{uid}.innerCircles  [{ id, name, userIds }]  the named lists
//   users/{uid}.innerCircle   [uid]                    everyone on any list
//
// The flat array is not a duplicate for its own sake: it is the index. The
// question every feed asks is "whose lists am I on?", and one
// array-contains on a single-field index answers it for all of someone's
// lists at once. It also means accounts written before lists existed need
// no migration — their `innerCircle` is simply their one list.

/** Anyone who never named a list still has one; this is what it's called. */
const DEFAULT_LIST_ID = 'default';
const DEFAULT_LIST_NAME = 'Inner Circle';
const MAX_LISTS = 20;
const NAME_MAX = 40;

const asIdArray = (value) =>
  Array.isArray(value) ? [...new Set(value.filter(id => typeof id === 'string' && id.length > 0).map(String))] : [];

const cleanName = (value, fallback = DEFAULT_LIST_NAME) => {
  const text = String(value === undefined || value === null ? '' : value).replace(/\s+/g, ' ').trim();
  return text ? text.slice(0, NAME_MAX) : fallback;
};

const normalizeStored = (list) => {
  if (!list || typeof list !== 'object') return null;
  const id = typeof list.id === 'string' && list.id ? list.id : null;
  if (!id) return null;
  return { id, name: cleanName(list.name), userIds: asIdArray(list.userIds) };
};

/**
 * The user's lists, whichever era their document is from.
 *
 * @param {object} userData raw user doc
 * @returns {{id: string, name: string, userIds: string[]}[]}
 */
const listsFrom = (userData = {}) => {
  const stored = Array.isArray(userData && userData.innerCircles)
    ? userData.innerCircles.map(normalizeStored).filter(Boolean)
    : [];
  if (stored.length) return stored;
  const legacy = asIdArray(userData && userData.innerCircle);
  return legacy.length ? [{ id: DEFAULT_LIST_ID, name: DEFAULT_LIST_NAME, userIds: legacy }] : [];
};

/** Everyone on any of the lists: what the flat `innerCircle` field holds. */
const unionOf = (lists) => [...new Set((lists || []).flatMap(list => list.userIds || []))];

/**
 * Which lists a viewer is on, by a caller-supplied comparison (ids arrive in
 * more than one shape for Apple accounts, so the caller owns that rule).
 */
const listIdsContaining = (lists, viewerId, isSame = (a, b) => String(a) === String(b)) =>
  new Set((lists || []).filter(list => (list.userIds || []).some(id => isSame(id, viewerId))).map(list => list.id));

/**
 * The list id to store next to a privacy tier.
 *
 * Only an Inner Circle item may name a list; anything else is stored as null
 * so a tier change can never leave a stale audience behind, quietly aimed at
 * a list the person no longer meant.
 */
const listIdFor = (tier, value) => {
  const normalized = String(tier === undefined || tier === null ? '' : tier).trim().toLowerCase().replace(/[\s_-]/g, '');
  if (normalized !== 'innercircle') return null;
  const id = typeof value === 'string' ? value.trim() : '';
  return id ? id.slice(0, 64) : null;
};

module.exports = { listIdFor, DEFAULT_LIST_ID, DEFAULT_LIST_NAME, MAX_LISTS, NAME_MAX, asIdArray, cleanName, listsFrom, unionOf, listIdsContaining };
