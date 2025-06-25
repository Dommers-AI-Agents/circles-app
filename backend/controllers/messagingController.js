// backend/controllers/messagingController.js
const { getFirestore } = require('../config/firebase');
const { 
  COLLECTIONS, 
  createConversation,
  createMessage,
  createMessageRead,
  validateConversation,
  validateMessage,
  serializeDoc, 
  serializeQuerySnapshot 
} = require('../models/FirestoreModels');

const db = getFirestore();

// @desc    Get all conversations for a user
// @route   GET /api/messages/conversations
// @access  Private
const getConversations = async (req, res) => {
  try {
    const userId = req.user.uid;

    // Get all conversations where user is a participant
    const conversationsQuery = db.collection(COLLECTIONS.CONVERSATIONS)
      .where('participants', 'array-contains', userId)
      .orderBy('lastMessageTime', 'desc');

    const snapshot = await conversationsQuery.get();
    const conversations = serializeQuerySnapshot(snapshot);

    // Populate participant details for each conversation
    const populatedConversations = await Promise.all(
      conversations.map(async (conversation) => {
        // Get participant details
        const participantIds = conversation.participants.filter(id => id !== userId);
        const participantPromises = participantIds.map(id => 
          db.collection(COLLECTIONS.USERS).doc(id).get()
        );
        
        const participantDocs = await Promise.all(participantPromises);
        conversation.participantDetails = participantDocs
          .filter(doc => doc.exists)
          .map(doc => serializeDoc(doc));

        return conversation;
      })
    );

    res.status(200).json({
      success: true,
      conversations: populatedConversations
    });
  } catch (error) {
    console.error('Error fetching conversations:', error);
    res.status(500).json({
      success: false,
      message: 'Server error',
      error: error.message
    });
  }
};

// @desc    Create a new conversation
// @route   POST /api/messages/conversations
// @access  Private
const createNewConversation = async (req, res) => {
  try {
    const userId = req.user.uid;
    const { type, participants, name, avatar } = req.body;

    // Ensure the current user is included in participants
    const allParticipants = participants.includes(userId) 
      ? participants 
      : [...participants, userId];

    // For direct conversations, ensure only 2 participants
    if (type === 'direct' && allParticipants.length !== 2) {
      return res.status(400).json({
        success: false,
        message: 'Direct conversations must have exactly 2 participants'
      });
    }

    // Check if a direct conversation already exists between these users
    if (type === 'direct') {
      const existingQuery = await db.collection(COLLECTIONS.CONVERSATIONS)
        .where('type', '==', 'direct')
        .where('participants', 'array-contains', allParticipants[0])
        .get();

      const existingConversation = existingQuery.docs.find(doc => {
        const data = doc.data();
        return data.participants.includes(allParticipants[1]) && 
               data.participants.length === 2;
      });

      if (existingConversation) {
        const conversation = serializeDoc(existingConversation);
        
        // Populate participant details
        const otherUserId = conversation.participants.find(id => id !== userId);
        const otherUserDoc = await db.collection(COLLECTIONS.USERS).doc(otherUserId).get();
        if (otherUserDoc.exists) {
          conversation.participantDetails = [serializeDoc(otherUserDoc)];
        }

        return res.status(200).json({
          success: true,
          conversation,
          message: 'Existing conversation returned'
        });
      }
    }

    // Create new conversation
    const conversationData = createConversation({
      type: type || 'direct',
      participants: allParticipants,
      name: name || null,
      avatar: avatar || null,
      createdBy: userId,
      unreadCounts: allParticipants.reduce((acc, id) => {
        acc[id] = 0;
        return acc;
      }, {})
    });

    // Validate conversation data
    const errors = validateConversation(conversationData);
    if (errors.length > 0) {
      return res.status(400).json({
        success: false,
        message: 'Validation error',
        errors
      });
    }

    // Add to Firestore
    const docRef = await db.collection(COLLECTIONS.CONVERSATIONS).add(conversationData);
    const newDoc = await docRef.get();
    const conversation = serializeDoc(newDoc);

    // Populate participant details
    const participantIds = conversation.participants.filter(id => id !== userId);
    const participantPromises = participantIds.map(id => 
      db.collection(COLLECTIONS.USERS).doc(id).get()
    );
    
    const participantDocs = await Promise.all(participantPromises);
    conversation.participantDetails = participantDocs
      .filter(doc => doc.exists)
      .map(doc => serializeDoc(doc));

    res.status(201).json({
      success: true,
      conversation
    });
  } catch (error) {
    console.error('Error creating conversation:', error);
    res.status(500).json({
      success: false,
      message: 'Server error',
      error: error.message
    });
  }
};

// @desc    Get messages for a conversation
// @route   GET /api/messages/conversations/:conversationId/messages
// @access  Private
const getMessages = async (req, res) => {
  try {
    const userId = req.user.uid;
    const { conversationId } = req.params;
    const { limit = 50, before } = req.query;

    // Verify user is part of this conversation
    const conversationDoc = await db.collection(COLLECTIONS.CONVERSATIONS).doc(conversationId).get();
    if (!conversationDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Conversation not found'
      });
    }

    const conversation = conversationDoc.data();
    if (!conversation.participants.includes(userId)) {
      return res.status(403).json({
        success: false,
        message: 'Not authorized to view this conversation'
      });
    }

    // Build query
    let messagesQuery = db.collection(COLLECTIONS.MESSAGES)
      .where('conversationId', '==', conversationId)
      .orderBy('createdAt', 'desc')
      .limit(parseInt(limit));

    // Add pagination if before timestamp provided
    if (before) {
      messagesQuery = messagesQuery.where('createdAt', '<', before);
    }

    const snapshot = await messagesQuery.get();
    const messages = serializeQuerySnapshot(snapshot);

    // Mark messages as read
    const unreadMessages = messages.filter(msg => 
      msg.senderId !== userId && !msg.readBy.includes(userId)
    );

    if (unreadMessages.length > 0) {
      const batch = db.batch();
      
      // Update messages to mark as read
      unreadMessages.forEach(msg => {
        const msgRef = db.collection(COLLECTIONS.MESSAGES).doc(msg.id);
        batch.update(msgRef, {
          readBy: [...msg.readBy, userId]
        });

        // Create read receipt
        const readReceipt = createMessageRead(msg.id, userId, conversationId);
        const readRef = db.collection(COLLECTIONS.MESSAGE_READS).doc();
        batch.set(readRef, readReceipt);
      });

      // Update conversation unread count
      const conversationRef = db.collection(COLLECTIONS.CONVERSATIONS).doc(conversationId);
      batch.update(conversationRef, {
        [`unreadCounts.${userId}`]: 0,
        updatedAt: new Date().toISOString()
      });

      await batch.commit();
    }

    // Populate sender details
    const populatedMessages = await Promise.all(
      messages.map(async (message) => {
        const senderDoc = await db.collection(COLLECTIONS.USERS).doc(message.senderId).get();
        if (senderDoc.exists) {
          message.senderDetails = serializeDoc(senderDoc);
        }
        return message;
      })
    );

    res.status(200).json({
      success: true,
      messages: populatedMessages.reverse() // Return in chronological order
    });
  } catch (error) {
    console.error('Error fetching messages:', error);
    res.status(500).json({
      success: false,
      message: 'Server error',
      error: error.message
    });
  }
};

// @desc    Send a message
// @route   POST /api/messages/conversations/:conversationId/messages
// @access  Private
const sendMessage = async (req, res) => {
  try {
    const userId = req.user.uid;
    const { conversationId } = req.params;
    const { type, content, mediaUrl, metadata } = req.body;

    // Verify user is part of this conversation
    const conversationDoc = await db.collection(COLLECTIONS.CONVERSATIONS).doc(conversationId).get();
    if (!conversationDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Conversation not found'
      });
    }

    const conversation = conversationDoc.data();
    if (!conversation.participants.includes(userId)) {
      return res.status(403).json({
        success: false,
        message: 'Not authorized to send messages to this conversation'
      });
    }

    // Create message
    const messageData = createMessage({
      type,
      content,
      mediaUrl,
      metadata
    }, conversationId, userId);

    // Validate message
    const errors = validateMessage(messageData);
    if (errors.length > 0) {
      return res.status(400).json({
        success: false,
        message: 'Validation error',
        errors
      });
    }

    // Use a batch write for atomicity
    const batch = db.batch();

    // Add message
    const messageRef = db.collection(COLLECTIONS.MESSAGES).doc();
    batch.set(messageRef, messageData);

    // Update conversation
    const now = new Date().toISOString();
    const conversationUpdate = {
      lastMessage: content || `[${type}]`,
      lastMessageTime: now,
      lastMessageSenderId: userId,
      updatedAt: now
    };

    // Update unread counts for other participants
    conversation.participants.forEach(participantId => {
      if (participantId !== userId) {
        conversationUpdate[`unreadCounts.${participantId}`] = (conversation.unreadCounts?.[participantId] || 0) + 1;
      }
    });

    const conversationRef = db.collection(COLLECTIONS.CONVERSATIONS).doc(conversationId);
    batch.update(conversationRef, conversationUpdate);

    // Commit the batch
    await batch.commit();

    // Get the created message
    const newMessageDoc = await messageRef.get();
    const message = serializeDoc(newMessageDoc);

    // Populate sender details
    const senderDoc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
    if (senderDoc.exists) {
      message.senderDetails = serializeDoc(senderDoc);
    }

    // TODO: Send push notifications to other participants
    // This would be implemented with FCM (Firebase Cloud Messaging)

    res.status(201).json({
      success: true,
      message
    });
  } catch (error) {
    console.error('Error sending message:', error);
    res.status(500).json({
      success: false,
      message: 'Server error',
      error: error.message
    });
  }
};

// @desc    Edit a message
// @route   PUT /api/messages/:messageId
// @access  Private
const editMessage = async (req, res) => {
  try {
    const userId = req.user.uid;
    const { messageId } = req.params;
    const { content } = req.body;

    if (!content || content.trim().length === 0) {
      return res.status(400).json({
        success: false,
        message: 'Message content is required'
      });
    }

    // Get the message
    const messageDoc = await db.collection(COLLECTIONS.MESSAGES).doc(messageId).get();
    if (!messageDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Message not found'
      });
    }

    const message = messageDoc.data();

    // Verify user is the sender
    if (message.senderId !== userId) {
      return res.status(403).json({
        success: false,
        message: 'Not authorized to edit this message'
      });
    }

    // Can only edit text messages
    if (message.type !== 'text') {
      return res.status(400).json({
        success: false,
        message: 'Can only edit text messages'
      });
    }

    // Update the message
    const now = new Date().toISOString();
    await messageDoc.ref.update({
      content,
      editedAt: now
    });

    // Get updated message
    const updatedDoc = await messageDoc.ref.get();
    const updatedMessage = serializeDoc(updatedDoc);

    // Populate sender details
    const senderDoc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
    if (senderDoc.exists) {
      updatedMessage.senderDetails = serializeDoc(senderDoc);
    }

    res.status(200).json({
      success: true,
      message: updatedMessage
    });
  } catch (error) {
    console.error('Error editing message:', error);
    res.status(500).json({
      success: false,
      message: 'Server error',
      error: error.message
    });
  }
};

// @desc    Delete a message
// @route   DELETE /api/messages/:messageId
// @access  Private
const deleteMessage = async (req, res) => {
  try {
    const userId = req.user.uid;
    const { messageId } = req.params;

    // Get the message
    const messageDoc = await db.collection(COLLECTIONS.MESSAGES).doc(messageId).get();
    if (!messageDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Message not found'
      });
    }

    const message = messageDoc.data();

    // Verify user is the sender
    if (message.senderId !== userId) {
      return res.status(403).json({
        success: false,
        message: 'Not authorized to delete this message'
      });
    }

    // Soft delete - just mark as deleted
    const now = new Date().toISOString();
    await messageDoc.ref.update({
      deletedAt: now,
      content: '[Message deleted]'
    });

    res.status(200).json({
      success: true,
      message: 'Message deleted successfully'
    });
  } catch (error) {
    console.error('Error deleting message:', error);
    res.status(500).json({
      success: false,
      message: 'Server error',
      error: error.message
    });
  }
};

// @desc    Mark messages as read
// @route   POST /api/messages/conversations/:conversationId/read
// @access  Private
const markMessagesAsRead = async (req, res) => {
  try {
    const userId = req.user.uid;
    const { conversationId } = req.params;
    const { messageIds } = req.body;

    if (!messageIds || !Array.isArray(messageIds) || messageIds.length === 0) {
      return res.status(400).json({
        success: false,
        message: 'Message IDs are required'
      });
    }

    // Verify user is part of this conversation
    const conversationDoc = await db.collection(COLLECTIONS.CONVERSATIONS).doc(conversationId).get();
    if (!conversationDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Conversation not found'
      });
    }

    const conversation = conversationDoc.data();
    if (!conversation.participants.includes(userId)) {
      return res.status(403).json({
        success: false,
        message: 'Not authorized to mark messages in this conversation'
      });
    }

    // Batch update messages
    const batch = db.batch();
    let validMessageCount = 0;

    for (const messageId of messageIds) {
      const messageDoc = await db.collection(COLLECTIONS.MESSAGES).doc(messageId).get();
      
      if (messageDoc.exists) {
        const message = messageDoc.data();
        
        // Only mark if not already read and not sent by current user
        if (message.senderId !== userId && !message.readBy.includes(userId)) {
          batch.update(messageDoc.ref, {
            readBy: [...message.readBy, userId]
          });

          // Create read receipt
          const readReceipt = createMessageRead(messageId, userId, conversationId);
          const readRef = db.collection(COLLECTIONS.MESSAGE_READS).doc();
          batch.set(readRef, readReceipt);

          validMessageCount++;
        }
      }
    }

    // Update conversation unread count
    if (validMessageCount > 0) {
      const conversationRef = db.collection(COLLECTIONS.CONVERSATIONS).doc(conversationId);
      const currentUnreadCount = conversation.unreadCounts?.[userId] || 0;
      const newUnreadCount = Math.max(0, currentUnreadCount - validMessageCount);
      
      batch.update(conversationRef, {
        [`unreadCounts.${userId}`]: newUnreadCount,
        updatedAt: new Date().toISOString()
      });
    }

    await batch.commit();

    res.status(200).json({
      success: true,
      message: `Marked ${validMessageCount} messages as read`
    });
  } catch (error) {
    console.error('Error marking messages as read:', error);
    res.status(500).json({
      success: false,
      message: 'Server error',
      error: error.message
    });
  }
};

// @desc    Get unread message count
// @route   GET /api/messages/unread-count
// @access  Private
const getUnreadCount = async (req, res) => {
  try {
    const userId = req.user.uid;

    // Get all conversations where user is a participant
    const conversationsQuery = db.collection(COLLECTIONS.CONVERSATIONS)
      .where('participants', 'array-contains', userId);

    const snapshot = await conversationsQuery.get();
    
    let totalUnread = 0;
    const unreadByConversation = {};

    snapshot.docs.forEach(doc => {
      const conversation = doc.data();
      const unreadCount = conversation.unreadCounts?.[userId] || 0;
      
      if (unreadCount > 0) {
        totalUnread += unreadCount;
        unreadByConversation[doc.id] = unreadCount;
      }
    });

    res.status(200).json({
      success: true,
      totalUnread,
      unreadByConversation
    });
  } catch (error) {
    console.error('Error getting unread count:', error);
    res.status(500).json({
      success: false,
      message: 'Server error',
      error: error.message
    });
  }
};

module.exports = {
  getConversations,
  createNewConversation,
  getMessages,
  sendMessage,
  editMessage,
  deleteMessage,
  markMessagesAsRead,
  getUnreadCount
};