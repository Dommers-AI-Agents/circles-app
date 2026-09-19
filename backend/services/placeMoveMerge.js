// backend/services/placeMoveMerge.js
//
// Moving a place into a circle that already holds the same venue is a
// merge, not an error: the copy being moved goes away and anything the
// person wrote on it that the target copy lacks comes along. Pure helpers
// so the rule is testable; the controller does the Firestore writes.

/** Same real-world venue: canonical id first, then Google id, then name+address. */
function sameVenue(a, b) {
  if (!a || !b) return false;
  if (a.globalPlaceId && b.globalPlaceId) return a.globalPlaceId === b.globalPlaceId;
  if (a.googlePlaceId && b.googlePlaceId) return a.googlePlaceId === b.googlePlaceId;
  const norm = (s) => String(s || '').trim().toLowerCase();
  return !!norm(a.name) && norm(a.name) === norm(b.name) && norm(a.address) === norm(b.address);
}

const isBlank = (v) => v === undefined || v === null || (typeof v === 'string' && v.trim() === '') || (Array.isArray(v) && v.length === 0);

/**
 * Fields to copy from the record being moved onto the record that stays,
 * only where the staying one has nothing. Notes and tags fill blanks;
 * photos are unioned so nothing a person uploaded is lost.
 */
function carryOverPatch(source, target) {
  const patch = {};
  for (const key of ['privateNotes', 'publicNotes', 'customCategoryId', 'userRating']) {
    if (!isBlank(source[key]) && isBlank(target[key])) patch[key] = source[key];
  }
  if (Array.isArray(source.tags) && source.tags.length) {
    const merged = [...new Set([...(Array.isArray(target.tags) ? target.tags : []), ...source.tags])];
    if (merged.length !== (Array.isArray(target.tags) ? target.tags.length : 0)) patch.tags = merged;
  }
  if (Array.isArray(source.photos) && source.photos.length) {
    const key = (p) => (typeof p === 'string' ? p : (p && (p.url || p.id)) || JSON.stringify(p));
    const have = new Set((Array.isArray(target.photos) ? target.photos : []).map(key));
    const extra = source.photos.filter((p) => !have.has(key(p)));
    if (extra.length) patch.photos = [...(Array.isArray(target.photos) ? target.photos : []), ...extra];
  }
  return patch;
}

module.exports = { sameVenue, carryOverPatch };
