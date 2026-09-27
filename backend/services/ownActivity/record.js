// backend/services/ownActivity/record.js
// Writes the rows only the owner ever sees on their Activity tab: a private
// check-in, a postcard sent, a printed postcard ordered, a Fridge Mail card
// mailed. Same collection and shape as every feed row (so one query lists
// them all), stamped `metadata.ownerOnly` so the feed gate hides them from
// everyone but the actor. Fire-and-forget: history never blocks the action.
const record = async (type, actorId, targetType, targetId, targetName, metadata = {}) => {
  try {
    // The feed's writer, required late: controllers/activityController pulls
    // in the whole feed stack, and this module is loaded by services it uses.
    const { createActivity } = require('../../controllers/activityController');
    await createActivity(type, actorId, targetType, targetId, targetName, { ...metadata, ownerOnly: true });
  } catch (error) {
    console.error(`[own-activity] ${type} not recorded: ${error.message}`);
  }
};

const recordPrivateCheckIn = (userId, checkIn, { checkInId, placeId, placePhoto, rating }) =>
  record('check_in', userId, 'check_in', checkInId, checkIn.placeName, {
    placeAddress: checkIn.placeAddress, message: checkIn.message, endTime: checkIn.endTime,
    placePhoto, placeId, placeCategory: checkIn.placeCategory || 'other', isPrivate: true, rating
  });

const recordPostcardSent = (userId, { messageId, recipientName, imageUrl, placeName, globalPlaceId }) =>
  record('postcard_sent', userId, 'postcard', messageId, recipientName || 'a friend', { imageUrl, placeName, globalPlaceId, recipientName });

const recordPostcardMailed = (userId, { orderId, recipientName, imageUrl, placeName }) =>
  record('postcard_mailed', userId, 'postcard_order', orderId, recipientName || 'someone', { imageUrl, placeName, recipientName, mailStatus: 'submitted' });

const recordFridgeMailSent = (userId, { rowId, recipientName, imageUrl, childName }) =>
  record('fridgemail_sent', userId, 'fridge_mail', rowId, recipientName || 'someone', { imageUrl, recipientName, childName, mailStatus: 'submitted' });

module.exports = { record, recordFridgeMailSent, recordPostcardMailed, recordPostcardSent, recordPrivateCheckIn };
