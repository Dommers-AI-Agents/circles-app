// backend/services/activityFeedOverlay.js
//
// A feed row stores the circle's name (and, for circle rows, its cover) and
// the reacting people's names as they were when the row was written. The
// feed shows them as they are NOW (Wes, 2026-10-31: "stored in the db and
// pulled from one place"): these pure helpers lay the live circle and user
// records over the stored copies. A stored value stays only when the circle
// or account is gone. Response shape unchanged.
const { withCurrentUser } = require('./userLookup');

const liveCircle = (circlesById, id) => {
  if (!id || !circlesById) return null;
  const c = circlesById.get(String(id));
  return c && !c.deletedAt ? c : null;
};

/**
 * The row with its circle's current name: circleName on any row about a
 * circle (its circleId, or the target of a circle row), and for circle rows
 * (targetType 'circle') also targetName and the cover, which every circle row
 * carries as metadata.placePhoto (services/activity/circles.js). Place rows
 * keep their own photo — their placePhoto is the place's, not the circle's.
 * Returns a NEW object; the row as stored when the circle is gone. Pure.
 * @param {object} activity  stored row
 * @param {Map<string, object>} circlesById  live circle docs (raw data)
 */
function withCurrentCircle(activity, circlesById) {
  if (!activity) return activity;
  const isCircleRow = activity.targetType === 'circle';
  const circle = liveCircle(circlesById, isCircleRow ? activity.targetId : activity.circleId);
  if (!circle) return activity;
  const out = { ...activity };
  if (circle.name) {
    out.circleName = circle.name;
    if (isCircleRow) out.targetName = circle.name;
  }
  if (isCircleRow && circle.coverImage) {
    out.metadata = { ...(activity.metadata || {}), placePhoto: circle.coverImage };
  }
  return out;
}

/**
 * Reaction summaries ({ emoji, count, users: [{ id, displayName, profilePicture }] })
 * with each person's current name and photo. Returns NEW arrays. Pure.
 * @param {Array} summaries
 * @param {Map} users  from userLookup.fetchUsersById
 */
function withCurrentReactors(summaries, users) {
  if (!Array.isArray(summaries) || !users || users.size === 0) return summaries;
  return summaries.map((s) => ({
    ...s,
    users: (s.users || []).map((u) => withCurrentUser(u, users, { id: 'id', name: 'displayName', photo: 'profilePicture' }))
  }));
}

module.exports = { withCurrentCircle, withCurrentReactors };
