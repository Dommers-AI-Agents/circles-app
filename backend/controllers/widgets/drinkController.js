// backend/controllers/widgets/drinkController.js
// Make Me a Drink: send a drink recipe to a connection's chat.
//
// A private message only — nothing about drinks is ever posted to a feed or
// an activity timeline (Wes, 2026-10-01). Like the postcard, it is an image
// message (the recipe card), so older builds that don't know `kind: 'drink'`
// still show the card.
//
// The recipient may get a FavCoin bonus PAID BY FAVCIRCLES (reason
// drink_received): coins are never moved between users. Once ever per
// sender→recipient pair, 3 a day per recipient (config/piggyBankConfig.js).
const { getFirestore } = require('../../config/firebase');
const { COLLECTIONS } = require('../../models/FirestoreModels');
const { normalizeUserId } = require('../../services/idService');
const { isBlockedEitherWay } = require('../../services/moderationService');
const { getConnectedUserIds } = require('../../utils/networkAccess');
const { isAllowedImageUrl } = require('../../services/postcardShareService');
const messagingService = require('../../services/messagingService');
const piggyBankService = require('../../services/piggyBankService');

const db = getFirestore();

const DRINK_ID_RE = /^[a-z0-9-]{1,48}$/;
const NAME_MAX = 60;
const NOTE_MAX = 200;
const piggyEnabled = () => process.env.WIDGET_PIGGY_ENABLED === '1';

const fail = (res, status, code, message) => res.status(status).json({ success: false, code, message });

/** Pure: validate and shape a send request. Returns { error } or { value }. */
const parseDrinkSend = (body, senderId) => {
  const { recipientId, drinkId, drinkName, imageUrl, note } = body || {};
  const recipient = normalizeUserId(recipientId);
  if (!recipient) return { error: [400, 'invalid_recipient', 'recipientId is required'] };
  if (recipient === senderId) return { error: [400, 'invalid_recipient', "You can't send a drink to yourself"] };
  if (typeof drinkId !== 'string' || !DRINK_ID_RE.test(drinkId)) return { error: [400, 'invalid_drink', 'drinkId is required'] };
  const name = typeof drinkName === 'string' ? drinkName.trim() : '';
  if (!name || name.length > NAME_MAX) return { error: [400, 'invalid_drink', 'drinkName is required'] };
  const text = typeof note === 'string' ? note.trim() : '';
  if (text.length > NOTE_MAX) return { error: [400, 'note_too_long', `Note must be ${NOTE_MAX} characters or fewer`] };
  if (!isAllowedImageUrl(imageUrl)) return { error: [400, 'invalid_image', 'imageUrl must be an uploaded FavCircles image'] };
  return { value: { recipient, drinkId, name, note: text, imageUrl } };
};

// @desc    Send a drink recipe to a connection's chat
// @route   POST /api/widgets/drink/send
// @access  Private
exports.sendDrink = async (req, res) => {
  try {
    const senderId = req.user.uid;
    const parsed = parseDrinkSend(req.body, senderId);
    if (parsed.error) return fail(res, ...parsed.error);
    const { recipient, drinkId, name, note, imageUrl } = parsed.value;

    const recipientDoc = await db.collection(COLLECTIONS.USERS).doc(recipient).get();
    if (!recipientDoc.exists) return fail(res, 404, 'user_not_found', 'Recipient not found');
    if (isBlockedEitherWay(req.user, recipient)) return fail(res, 403, 'blocked', "You can't send messages to this user");
    const connected = await getConnectedUserIds(senderId);
    if (!connected.has(recipient)) return fail(res, 403, 'not_connected', 'You must be connected to send a drink');

    const conversation = await messagingService.findOrCreateDirectConversation(senderId, recipient);
    const sent = await messagingService.appendMessage(conversation.id, senderId, {
      type: 'image',
      mediaUrl: imageUrl,
      content: note || `Try a ${name} 🍸`,
      metadata: { kind: 'drink', drinkId, drinkName: name, sentAt: new Date().toISOString() }
    });

    // FavCircles' thank-you to the RECIPIENT (never the sender's coins)
    let recipientCredited = false;
    if (piggyEnabled()) {
      const bonus = await piggyBankService.credit({
        userId: recipient,
        eventType: 'drink_received',
        sourceRef: { senderId, messageId: sent.id }
      });
      recipientCredited = !!(bonus && bonus.credited);
      if (recipientCredited) {
        // The chat card shows "+1 FavCoin 🌵 from FavCircles"
        await db.collection(COLLECTIONS.MESSAGES).doc(sent.id)
          .update({ 'metadata.favCoins': String(bonus.coins) })
          .catch((e) => console.error('🍸 drink bonus stamp failed:', e.message));
      }
    }

    res.status(201).json({ success: true, messageId: sent.id, conversationId: conversation.id, recipientCredited });
  } catch (error) {
    console.error('🍸 sendDrink failed:', error.message);
    res.status(500).json({ success: false, message: 'Failed to send the drink' });
  }
};

exports.parseDrinkSend = parseDrinkSend;
