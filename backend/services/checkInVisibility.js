// services/checkInVisibility.js
// Who may see a check-in. One rule for every read path (active feed, at-place
// list): the owner always; anyone it was explicitly sent to; a connection
// when it was posted to the activity feed. A private check-in (notify no one,
// keep off the feed) is therefore visible to its owner only.
//
// A check-in with audience 'innerCircle' stops at the owner's Inner Circle.
// That is checked BEFORE the connection rule, so turning the feed on cannot
// widen it — the tier is the ceiling, and the people it was explicitly sent
// to are the one exception above it.
//
// `audienceListId` names WHICH of the owner's lists. A check-in written
// before lists existed carries none, and means any of them.

const isPrivateCheckIn = (checkIn) => checkIn.isPrivate === true;

/**
 * @param {object} checkIn  the stored check-in (userId, notifiedUsers,
 *                          notifiedGroups, showInActivityFeed, isPrivate)
 * @param {string} viewerId
 * @param {object} ctx      { connectionIds: Set<string>,
 *                            innerCircleGrantors: Set<string>,
 *                            innerCircleLists: Map<string, Set<string>>,
 *                            isInAnyGroup: async (viewerId, groupIds) => bool }
 */
const isCheckInVisibleTo = async (checkIn, viewerId, ctx) => {
  if (checkIn.userId === viewerId) return true;
  if (isPrivateCheckIn(checkIn)) return false;
  if ((checkIn.notifiedUsers || []).includes(viewerId)) return true;
  if (checkIn.audience === 'innerCircle') {
    if (!checkIn.audienceListId) {
      return !!(ctx.innerCircleGrantors && ctx.innerCircleGrantors.has(checkIn.userId));
    }
    // Named a list, so only that list — and if the caller didn't bring the
    // per-list map, nobody, because guessing here shows it to the wrong people.
    const lists = ctx.innerCircleLists && ctx.innerCircleLists.get(checkIn.userId);
    return !!(lists && lists.has(checkIn.audienceListId));
  }
  if (ctx.connectionIds && ctx.connectionIds.has(checkIn.userId) && checkIn.showInActivityFeed) return true;
  if (ctx.isInAnyGroup && (checkIn.notifiedGroups || []).length > 0) {
    return ctx.isInAnyGroup(viewerId, checkIn.notifiedGroups);
  }
  return false;
};

module.exports = { isPrivateCheckIn, isCheckInVisibleTo };
