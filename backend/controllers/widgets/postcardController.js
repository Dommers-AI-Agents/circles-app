// backend/controllers/widgets/postcardController.js
// Digital postcard: drops an image message into the sender's direct chat
// with a connection. Deliberately NOT a new message type — old builds decode
// the whole thread and would break on an unknown type; they see "📷 Photo".
const { getFirestore } = require('../../config/firebase');
const { COLLECTIONS } = require('../../models/FirestoreModels');
const { normalizeUserId } = require('../../services/idService');
const { isBlockedEitherWay } = require('../../services/moderationService');
const { getConnectedUserIds } = require('../../utils/networkAccess');
const messagingService = require('../../services/messagingService');
const piggyBankService = require('../../services/piggyBankService');

const db = getFirestore();

const MESSAGE_MAX_CHARS = 500;
const TEMPLATE_ID_RE = /^[a-z0-9_-]{1,32}$/;
const piggyEnabled = () => process.env.WIDGET_PIGGY_ENABLED === '1';

// Only images our own upload route produced may be stamped into a message.
// Same bucket fallback chain as services/storage.js; with no bucket
// configured nothing is allowed (fail closed).
function allowedImagePrefixes() {
  const bucket = process.env.FIREBASE_STORAGE_BUCKET
    || process.env.GCS_BUCKET_NAME
    || (process.env.FIREBASE_PROJECT_ID ? `${process.env.FIREBASE_PROJECT_ID}.appspot.com` : null);
  if (!bucket) return [];
  return [
    `https://firebasestorage.googleapis.com/v0/b/${bucket}/o/`,
    `https://storage.googleapis.com/${bucket}/`
  ];
}

const isAllowedImageUrl = (url) =>
  typeof url === 'string' && allowedImagePrefixes().some(prefix => url.startsWith(prefix));

const fail = (res, status, code, message) =>
  res.status(status).json({ success: false, code, message });

// Firestore rejects undefined field values, so every metadata scalar is
// coerced to a string or null. Flat map only: Message.swift keeps just the
// flat metadata values.
const scalarOrNull = (v, max = 200) =>
  (typeof v === 'string' && v.trim()) ? v.trim().slice(0, max) : null;

// @desc    Send a postcard (image + caption) to a connection's chat
// @route   POST /api/widgets/postcard/send
// @access  Private
exports.sendPostcard = async (req, res) => {
  try {
    const senderId = req.user.uid;
    const { recipientId, imageUrl, message, templateId, placeRef } = req.body || {};

    const recipient = normalizeUserId(recipientId);
    if (!recipient) return fail(res, 400, 'invalid_recipient', 'recipientId is required');
    if (recipient === senderId) return fail(res, 400, 'invalid_recipient', 'You can\'t send a postcard to yourself');
    if (!isAllowedImageUrl(imageUrl)) return fail(res, 400, 'invalid_image', 'imageUrl must be an uploaded FavCircles image');
    const caption = typeof message === 'string' ? message.trim() : '';
    if (caption.length > MESSAGE_MAX_CHARS) {
      return fail(res, 400, 'message_too_long', `Message must be ${MESSAGE_MAX_CHARS} characters or fewer`);
    }
    if (typeof templateId !== 'string' || !TEMPLATE_ID_RE.test(templateId)) {
      return fail(res, 400, 'invalid_template', 'templateId is required');
    }

    const recipientDoc = await db.collection(COLLECTIONS.USERS).doc(recipient).get();
    if (!recipientDoc.exists) return fail(res, 404, 'user_not_found', 'Recipient not found');

    if (isBlockedEitherWay(req.user, recipient)) {
      return fail(res, 403, 'blocked', 'You can\'t send messages to this user');
    }
    const connected = await getConnectedUserIds(senderId);
    if (!connected.has(recipient)) {
      return fail(res, 403, 'not_connected', 'You must be connected to send a postcard');
    }

    const conversation = await messagingService.findOrCreateDirectConversation(senderId, recipient);
    const sent = await messagingService.appendMessage(conversation.id, senderId, {
      type: 'image',
      mediaUrl: imageUrl,
      content: caption,
      metadata: {
        kind: 'postcard',
        templateId,
        placeName: scalarOrNull(placeRef?.name),
        placeCity: scalarOrNull(placeRef?.city),
        globalPlaceId: scalarOrNull(placeRef?.globalPlaceId),
        sentAt: new Date().toISOString()
      }
    });

    let piggyBank;
    if (piggyEnabled()) {
      piggyBank = await piggyBankService.credit({
        userId: senderId,
        eventType: 'postcard_sent',
        sourceRef: { messageId: sent.id, recipientId: recipient }
      });
    }

    res.status(201).json({
      success: true,
      messageId: sent.id,
      conversationId: conversation.id,
      ...(piggyBank && piggyBank.credited ? { piggyBank } : {})
    });
  } catch (error) {
    console.error('📮 sendPostcard failed:', error.message);
    res.status(500).json({ success: false, message: 'Failed to send postcard' });
  }
};
