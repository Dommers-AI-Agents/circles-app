// services/checkInVisibility.js
// Who may see a check-in. One rule for every read path (active feed, at-place
// list): the owner always; anyone it was explicitly sent to; a connection
// when it was posted to the activity feed. A private check-in (notify no one,
// keep off the feed) is therefore visible to its owner only.

const isPrivateCheckIn = (checkIn) => checkIn.isPrivate === true;

/**
 * @param {object} checkIn  the stored check-in (userId, notifiedUsers,
 *                          notifiedGroups, showInActivityFeed, isPrivate)
 * @param {string} viewerId
 * @param {object} ctx      { connectionIds: Set<string>,
 *                            isInAnyGroup: async (viewerId, groupIds) => bool }
 */
const isCheckInVisibleTo = async (checkIn, viewerId, ctx) => {
  if (checkIn.userId === viewerId) return true;
  if (isPrivateCheckIn(checkIn)) return false;
  if ((checkIn.notifiedUsers || []).includes(viewerId)) return true;
  if (ctx.connectionIds && ctx.connectionIds.has(checkIn.userId) && checkIn.showInActivityFeed) return true;
  if (ctx.isInAnyGroup && (checkIn.notifiedGroups || []).length > 0) {
    return ctx.isInAnyGroup(viewerId, checkIn.notifiedGroups);
  }
  return false;
};

module.exports = { isPrivateCheckIn, isCheckInVisibleTo };
