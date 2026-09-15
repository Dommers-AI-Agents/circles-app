// backend/services/messagingService.js
//
// Direct-conversation lookup and message append, extracted from
// messagingController so other features (the Widgets postcard) can drop a
// message into a chat without importing a controller. The controller's own
// handlers are untouched; this is the same logic minus the HTTP plumbing.

const { getFirestore } = require('../config/firebase');
const {
  COLLECTIONS,
  createConversation,
  createMessage,
  validateMessage,
  serializeDoc
} = require('../models/FirestoreModels');
const { isSameUser } = require('./idService');
const sseService = require('./sseService');

// What the conversation list shows for the latest message. Postcards say
// so (with the place) instead of falling back to "[image]".
function messagePreview({ type, content, metadata }) {
  if (metadata && metadata.kind === 'postcard') {
    const place = metadata.placeName ? ` from ${metadata.placeName}` : '';
    return content ? `📮 Postcard${place}: ${content}` : `📮 Postcard${place}`;
  }
  return content || `[${type}]`;
}

const db = getFirestore();

class MessagingService {
  // Finds the 2-participant direct conversation between userA and userB, or
  // creates one. Participant matching is normalized (isSameUser) because
  // legacy docs can carry composite ids.
  async findOrCreateDirectConversation(userA, userB) {
    const existing = await db.collection(COLLECTIONS.CONVERSATIONS)
      .where('type', '==', 'direct')
      .where('participants', 'array-contains', userA)
      .get();

    for (const doc of existing.docs) {
      const participants = doc.data().participants || [];
      if (participants.length === 2 && participants.some(id => isSameUser(id, userB))) {
        return { id: doc.id, created: false };
      }
    }

    const conversationData = createConversation({
      type: 'direct',
      participants: [userA, userB],
      name: null,
      avatar: null
    });
    const ref = await db.collection(COLLECTIONS.CONVERSATIONS).add(conversationData);
    return { id: ref.id, created: true };
  }

  // Appends one message: message doc + conversation lastMessage/unreadCounts
  // in a single batch, then push + SSE to every other participant. Returns
  // the serialized message (with senderDetails), same shape as POST
  // /api/messages/conversations/:id/messages.
  async appendMessage(conversationId, senderId, { type, content, mediaUrl, metadata } = {}) {
    const conversationRef = db.collection(COLLECTIONS.CONVERSATIONS).doc(conversationId);
    const conversationDoc = await conversationRef.get();
    if (!conversationDoc.exists) {
      const err = new Error('Conversation not found');
      err.code = 'conversation_not_found';
      throw err;
    }
    const conversation = conversationDoc.data();
    if (!(conversation.participants || []).includes(senderId)) {
      const err = new Error('Sender is not a participant');
      err.code = 'not_participant';
      throw err;
    }

    const messageData = createMessage({ type, content, mediaUrl, metadata }, conversationId, senderId);
    const errors = validateMessage(messageData);
    if (errors.length > 0) {
      const err = new Error(`Validation error: ${errors.join(', ')}`);
      err.code = 'invalid_message';
      err.errors = errors;
      throw err;
    }

    // Fetched before the write so the sender's name can be denormalised onto
    // the conversation: the list endpoint doesn't load group participants, so
    // this is how a group row can show "Alex: ..." without extra reads.
    const senderDoc = await db.collection(COLLECTIONS.USERS).doc(senderId).get();
    const senderDetails = senderDoc.exists ? serializeDoc(senderDoc) : null;

    const batch = db.batch();
    const messageRef = db.collection(COLLECTIONS.MESSAGES).doc();
    batch.set(messageRef, messageData);

    const now = new Date().toISOString();
    const conversationUpdate = {
      lastMessage: messagePreview({ type, content, metadata }),
      lastMessageTime: now,
      lastMessageSenderId: senderId,
      lastMessageSenderName: senderDetails?.displayName || null,
      updatedAt: now
    };
    const recipientIds = conversation.participants.filter(id => id !== senderId);
    recipientIds.forEach(participantId => {
      const currentUnread = conversation.unreadCounts?.[participantId] || 0;
      conversationUpdate[`unreadCounts.${participantId}`] = currentUnread + 1;
    });
    batch.update(conversationRef, conversationUpdate);
    await batch.commit();

    const message = serializeDoc(await messageRef.get());
    if (senderDetails) {
      message.senderDetails = senderDetails;
    }

    // Lazy require: notificationService pulls in a lot at load and the
    // controller does the same to avoid a circular import.
    const notificationService = require('./notificationService');
    for (const recipientId of recipientIds) {
      try {
        await notificationService.notifyNewMessage(senderId, recipientId, message);
        sseService.notifyUser(recipientId, 'new_message', {
          messageId: message.id,
          conversationId,
          senderId,
          senderName: message.senderDetails?.displayName || 'Someone',
          content,
          type
        });
      } catch (notificationError) {
        // A failed push must never fail the message itself
        console.error(`🔔 Failed to notify ${recipientId} of new message:`, notificationError.message);
      }
    }

    return message;
  }
}

module.exports = new MessagingService();
