// backend/utils/circleOrder.js
//
// Single source of truth for "the user's own circle order" — the arrangement
// they set by drag-reordering the circles grid on their profile
// (users/{uid}.circleOrder, written by PUT /users/me/circles/reorder).
//
// Every endpoint that returns the current user's own circles must run them
// through this so the add-place picker, move-to-circle picker, home screen,
// map picker, etc. all read in exactly the same order as the profile grid.
//
// Rules:
//   1. circles listed in circleOrder, in that order
//   2. circles not yet in circleOrder (created since the last drag-reorder)
//      append AFTER the arranged ones, oldest first — so a brand-new circle
//      lands at the bottom of the list, where the user expects it (Wes,
//      2026-08-29). With no arrangement at all, newest first.
//   3. the auto-created "Places I Follow" circle always sinks to the very end

const circleTimestamp = (circle) => {
  const raw = circle.createdAt || circle.updatedAt || '';
  const ms = raw instanceof Date ? raw.getTime() : new Date(raw).getTime();
  return Number.isFinite(ms) ? ms : 0;
};

/**
 * @param {Array<Object>} circles  serialized circle docs (have `id` or `_id`)
 * @param {Array<string>|undefined} circleOrder  users/{uid}.circleOrder
 * @returns {Array<Object>} new array in the user's order
 */
const sortCirclesByUserOrder = (circles, circleOrder) => {
  const order = Array.isArray(circleOrder) ? circleOrder : [];
  const orderIndex = new Map(order.map((id, i) => [id, i]));
  const idOf = (c) => c.id || c._id;

  return [...circles].sort((a, b) => {
    const aFollow = a.isFollowedPlacesCircle === true;
    const bFollow = b.isFollowedPlacesCircle === true;
    if (aFollow !== bFollow) return aFollow ? 1 : -1;

    const ai = orderIndex.has(idOf(a)) ? orderIndex.get(idOf(a)) : Infinity;
    const bi = orderIndex.has(idOf(b)) ? orderIndex.get(idOf(b)) : Infinity;
    if (ai !== bi) return ai - bi;

    // Both unlisted: append in creation order under an arrangement, newest
    // first when the user has never arranged anything
    return order.length > 0
      ? circleTimestamp(a) - circleTimestamp(b)
      : circleTimestamp(b) - circleTimestamp(a);
  });
};

module.exports = { sortCirclesByUserOrder };
