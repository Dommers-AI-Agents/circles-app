// backend/services/placeCommentRules.js
//
// Who may change a comment on a place (Wes, 2026-11-24: "Is there a way to
// delete or modify your comments of a place?"). Pure: no database.
//
// Comments belong to the venue (globalPlaceId), and everyone who saved the
// venue has their own save of it. So "the place's owner" can only mean the
// save the comment was written on: having saved the same venue gives no say
// over what other people wrote about it.
const { isSameUser } = require('./idService');

/**
 * `comment` and `place` are the stored documents, `placeId` the save the
 * request names, `userId` who is asking.
 * - belongs: the comment is on this save or on another save of the same venue
 * - canEdit: its author, nobody else (words are the writer's own)
 * - canDelete: its author, or the owner of the very save it was written on
 */
function commentPermissions({ comment, place, placeId, userId }) {
  const sameVenue = !!comment.globalPlaceId && !!place.globalPlaceId && comment.globalPlaceId === place.globalPlaceId;
  const onThisSave = comment.placeId === placeId;
  const belongs = onThisSave || sameVenue;
  const isAuthor = !!userId && isSameUser(comment.userId, userId);
  const ownsTheSave = onThisSave && !!userId && isSameUser(place.addedBy, userId);
  return { belongs, canEdit: belongs && isAuthor, canDelete: belongs && (isAuthor || ownsTheSave) };
}

/** The most a comment may say; the app's field has no limit of its own. */
const MAX_COMMENT_LENGTH = 2000;

module.exports = { commentPermissions, MAX_COMMENT_LENGTH };
