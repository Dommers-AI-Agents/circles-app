// backend/controllers/widgets/motivationController.js
// Motivation widget: send one of Coach Mane's lines to a connection's chat
// ("Send to someone who needs to hear it", Wes 2026-10-02).
//
// A private message only — never a feed post. Like the drink and the
// postcard it is an image message (the Coach Mane card), so older builds
// that don't know `kind: 'motivation'` still show the card; the text is
// what the push and the conversation list show. No FavCoins.
//
// The line comes from the app (the banks live in the FavWidgets package).
// The sender could already message this connection any text, so taking it
// as given opens no new path; it is length-capped like any message.
const { getFirestore } = require('../../config/firebase');
const { COLLECTIONS } = require('../../models/FirestoreModels');
const { normalizeUserId } = require('../../services/idService');
const { isBlockedEitherWay } = require('../../services/moderationService');
const { getConnectedUserIds } = require('../../utils/networkAccess');
const { isAllowedImageUrl } = require('../../services/postcardShareService');
const messagingService = require('../../services/messagingService');
const { ServiceError, sendServiceError } = require('../../utils/serviceError');

const db = getFirestore();

const LINE_ID_RE = /^[0-9a-f]{8}$/;
const LINE_MAX = 160;

/** Pure: validate and shape a send request, or throw a ServiceError. */
const parseMotivationSend = (body, senderId) => {
  const { recipientId, lineId, line, imageUrl } = body || {};
  const recipient = normalizeUserId(recipientId);
  if (!recipient) throw new ServiceError(400, 'invalid_recipient', 'recipientId is required');
  if (recipient === senderId) throw new ServiceError(400, 'invalid_recipient', "You can't send this to yourself");
  if (typeof lineId !== 'string' || !LINE_ID_RE.test(lineId)) throw new ServiceError(400, 'invalid_line', 'lineId is required');
  const text = typeof line === 'string' ? line.trim() : '';
  if (!text || text.length > LINE_MAX) throw new ServiceError(400, 'invalid_line', `line must be 1–${LINE_MAX} characters`);
  if (!isAllowedImageUrl(imageUrl)) throw new ServiceError(400, 'invalid_image', 'imageUrl must be an uploaded FavCircles image');
  return { recipient, lineId, line: text, imageUrl };
};

/** What the friend's chat, push and conversation list show. */
const chatText = (line) => `📣 Coach Mane says: ${line}`;

// @desc    Send a Coach Mane line to a connection's chat
// @route   POST /api/widgets/motivation/send
// @access  Private
exports.sendMotivation = async (req, res) => {
  try {
    const senderId = req.user.uid;
    const { recipient, lineId, line, imageUrl } = parseMotivationSend(req.body, senderId);

    const recipientDoc = await db.collection(COLLECTIONS.USERS).doc(recipient).get();
    if (!recipientDoc.exists) throw new ServiceError(404, 'user_not_found', 'Recipient not found');
    if (isBlockedEitherWay(req.user, recipient)) throw new ServiceError(403, 'blocked', "You can't send messages to this user");
    const connected = await getConnectedUserIds(senderId);
    if (!connected.has(recipient)) throw new ServiceError(403, 'not_connected', 'You must be connected to send this');

    const conversation = await messagingService.findOrCreateDirectConversation(senderId, recipient);
    const sent = await messagingService.appendMessage(conversation.id, senderId, {
      type: 'image',
      mediaUrl: imageUrl,
      content: chatText(line),
      metadata: { kind: 'motivation', lineId, sentAt: new Date().toISOString() }
    });

    return res.json({ success: true, conversationId: conversation.id, messageId: sent && sent.id });
  } catch (error) {
    return sendServiceError(res, error, { log: '📣 sendMotivation failed', fallbackMessage: "Couldn't send" });
  }
};

exports.parseMotivationSend = parseMotivationSend;
exports.chatText = chatText;
