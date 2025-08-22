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
const { normalizeUserId, isSameUser } = require('../services/idService');
const sseService = require('../services/sseService');

const db = getFirestore();

// @desc    Get all conversations for a user
// @route   GET /api/messages/conversations
// @access  Private
const getConversations = async (req, res) => {
  try {
    console.log('🔍 getConversations called for user:', req.user.uid);
    const userId = req.user.uid;

    // Get all conversations where user is a participant
    // Simplified query to avoid complex index requirements
    const conversationsQuery = db.collection(COLLECTIONS.CONVERSATIONS)
      .where('participants', 'array-contains', userId);

    const snapshot = await conversationsQuery.get();
    
    // Filter out system conversations and sort in JavaScript
    const conversations = serializeQuerySnapshot(snapshot)
      .filter(conv => conv.type !== 'system')
      .sort((a, b) => {
        // Handle cases where lastMessageTime might be missing
        const timeA = a.lastMessageTime || a.createdAt || '0';
        const timeB = b.lastMessageTime || b.createdAt || '0';
        return timeB.localeCompare(timeA); // Descending order
      });

    // Populate participant details for each conversation
    const populatedConversations = await Promise.all(
      conversations.map(async (conversation) => {
        // Log unreadCounts for debugging
        if (conversation.unreadCounts && Object.keys(conversation.unreadCounts).length > 0) {
          console.log(`📊 Conversation ${conversation.id} unreadCounts for user ${userId}:`, conversation.unreadCounts[userId] || 0);
        }
        
        // Clean up unreadCounts to ensure it's a flat structure
        if (conversation.unreadCounts) {
          const cleanedUnreadCounts = {};
          for (const [key, value] of Object.entries(conversation.unreadCounts)) {
            // Only keep entries where value is a number and >= 0
            if (typeof value === 'number' && value >= 0) {
              cleanedUnreadCounts[key] = value;
            } else if (value !== undefined && value !== null) {
              console.log(`⚠️ Removing invalid unreadCount for user ${key}:`, value);
            }
          }
          conversation.unreadCounts = cleanedUnreadCounts;
        }
        
        // Get participant details (limit to direct conversations for performance)
        if (conversation.type === 'direct') {
          const participantIds = conversation.participants.filter(id => id !== userId);
          const participantPromises = participantIds.map(id => 
            db.collection(COLLECTIONS.USERS).doc(id).get()
          );
          
          const participantDocs = await Promise.all(participantPromises);
          conversation.participantDetails = participantDocs
            .filter(doc => doc.exists)
            .map(doc => serializeDoc(doc));
        } else {
          // For group conversations, we'll fetch details on demand
          conversation.participantDetails = [];
        }

        // Check if we need to find a better "last message" to display
        // This handles cases where:
        // 1. The last message is a connection request sent by current user (shouldn't show)
        // 2. The last message is a connection request for a connection that's already accepted
        if (conversation.lastMessageType === 'connection_request' || 
            (conversation.lastMessage && conversation.lastMessage.includes('wants to connect'))) {
          
          // Get the last few messages to find one that should be shown
          const messagesSnapshot = await db.collection(COLLECTIONS.MESSAGES)
            .where('conversationId', '==', conversation.id)
            .orderBy('createdAt', 'desc')
            .limit(10)
            .get();
          
          const messages = serializeQuerySnapshot(messagesSnapshot);
          
          // Find the first message that should be visible in conversation list
          const visibleMessage = messages.find(msg => {
            // Skip connection requests sent by current user
            if (msg.type === 'connection_request' && msg.senderId === userId) {
              return false;
            }
            
            // For connection request messages, check if connection is still pending
            if (msg.type === 'connection_request') {
              // TODO: Could add connection status check here for better filtering
              // For now, show connection requests from others
              return msg.senderId !== userId;
            }
            
            return true;
          });
          
          if (visibleMessage) {
            conversation.lastMessage = visibleMessage.content || visibleMessage.displayContent;
            conversation.lastMessageTime = visibleMessage.createdAt;
            conversation.lastMessageType = visibleMessage.type;
            conversation.lastMessageSenderId = visibleMessage.senderId;
          } else {
            // No visible messages, clear the last message info
            conversation.lastMessage = null;
            conversation.lastMessageTime = conversation.createdAt;
            conversation.lastMessageType = null;
            conversation.lastMessageSenderId = null;
          }
        }

        return conversation;
      })
    );

    res.status(200).json({
      success: true,
      conversations: populatedConversations
    });
  } catch (error) {
    console.error('❌ Error fetching conversations:', error);
    console.error('Error stack:', error.stack);
    
    // Check if it's a Firestore index error
    if (error.code === 'failed-precondition' || 
        (error.message && error.message.includes('index'))) {
      console.error('⚠️ This appears to be a Firestore index error. The required index may need to be created.');
    }
    
    res.status(500).json({
      success: false,
      message: 'Server error',
      error: error.message,
      details: process.env.NODE_ENV === 'development' ? error.stack : undefined
    });
  }
};

// @desc    Get or create a direct conversation with a user
// @route   POST /api/messages/conversations/direct/:userId
// @access  Private
const getOrCreateDirectConversation = async (req, res) => {
  try {
    const currentUserId = req.user.uid;
    let targetUserId = req.params.userId;
    
    console.log(`🔍 getOrCreateDirectConversation - Raw params: ${req.params.userId}`);
    console.log(`🔍 getOrCreateDirectConversation - Current user ID: ${currentUserId}`);
    
    // Normalize the target user ID to handle both simple and complex formats
    targetUserId = normalizeUserId(targetUserId);
    
    console.log(`🔍 getOrCreateDirectConversation - currentUserId: ${currentUserId}, targetUserId: ${targetUserId} (original: ${req.params.userId})`);

    // Check for self-conversation using normalized IDs
    if (isSameUser(currentUserId, targetUserId)) {
      console.log(`❌ getOrCreateDirectConversation - Attempted to create conversation with self`);
      return res.status(400).json({
        success: false,
        message: 'Cannot create conversation with yourself'
      });
    }

    // First verify target user exists
    const targetUserDoc = await db.collection(COLLECTIONS.USERS).doc(targetUserId).get();
    if (!targetUserDoc.exists) {
      console.error(`Target user not found with ID: ${targetUserId}`);
      return res.status(404).json({
        success: false,
        message: 'Target user not found'
      });
    }

    // Check if users are connected (LinkedIn-style: only connections can message)
    console.log('🔒 Checking if users are connected before allowing messaging');
    const [connection1, connection2] = await Promise.all([
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', currentUserId)
        .where('connectedUserId', '==', targetUserId)
        .where('status', '==', 'accepted')
        .get(),
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', targetUserId)
        .where('connectedUserId', '==', currentUserId)
        .where('status', '==', 'accepted')
        .get()
    ]);

    const isConnected = !connection1.empty || !connection2.empty;
    
    if (!isConnected) {
      console.log(`❌ Users ${currentUserId} and ${targetUserId} are not connected - messaging not allowed`);
      
      // Check if they are followers
      const currentUserDoc = await db.collection(COLLECTIONS.USERS).doc(currentUserId).get();
      const targetUserData = targetUserDoc.data();
      const isFollowing = currentUserDoc.exists && (currentUserDoc.data().following || []).includes(targetUserId);
      const isFollower = targetUserData && (targetUserData.followers || []).includes(currentUserId);
      
      if (isFollowing || isFollower) {
        return res.status(403).json({
          success: false,
          message: 'You must be connected to send messages. Followers cannot message each other.'
        });
      }
      
      return res.status(403).json({
        success: false,
        message: 'You must be connected to this user to send messages'
      });
    }
    
    console.log(`✅ Users ${currentUserId} and ${targetUserId} are connected - messaging allowed`);

    // Check if a direct conversation already exists between these users
    console.log(`🔍 getOrCreateDirectConversation - Checking for existing conversation`);
    const existingQuery1 = await db.collection(COLLECTIONS.CONVERSATIONS)
      .where('type', '==', 'direct')
      .where('participants', 'array-contains', currentUserId)
      .get();

    console.log(`🔍 getOrCreateDirectConversation - Found ${existingQuery1.size} conversations with current user`);

    let existingConversation = null;
    for (const doc of existingQuery1.docs) {
      const conv = doc.data();
      console.log(`🔍 Checking conversation ${doc.id} with participants: ${JSON.stringify(conv.participants)}`);
      
      // Check if any participant matches the target user (using normalized comparison)
      const hasTargetUser = conv.participants.some(participantId => {
        const matches = isSameUser(participantId, targetUserId);
        if (matches) {
          console.log(`✅ Found matching participant: ${participantId} matches ${targetUserId}`);
        }
        return matches;
      });
      
      if (hasTargetUser && conv.participants.length === 2) {
        existingConversation = { id: doc.id, ...conv };
        console.log(`✅ Found existing conversation: ${doc.id}`);
        break;
      }
    }

    if (existingConversation) {
      // Get participant details
      const participantIds = existingConversation.participants.filter(id => id !== currentUserId);
      const participantPromises = participantIds.map(id => 
        db.collection(COLLECTIONS.USERS).doc(id).get()
      );
      
      const participantDocs = await Promise.all(participantPromises);
      existingConversation.participantDetails = participantDocs
        .filter(doc => doc.exists)
        .map(doc => serializeDoc(doc));

      return res.status(200).json({
        success: true,
        conversation: serializeDoc({ id: existingConversation.id, data: () => existingConversation, exists: true })
      });
    }

    // Create new conversation
    const conversationData = createConversation({
      type: 'direct',
      participants: [currentUserId, targetUserId],
      name: null,
      avatar: null
    });

    const conversationRef = await db.collection(COLLECTIONS.CONVERSATIONS).add(conversationData);
    
    // Get participant details
    const participantIds = [targetUserId];
    const participantPromises = participantIds.map(id => 
      db.collection(COLLECTIONS.USERS).doc(id).get()
    );
    
    const participantDocs = await Promise.all(participantPromises);
    const conversation = {
      _id: conversationRef.id,
      id: conversationRef.id,
      ...conversationData,
      participantDetails: participantDocs
        .filter(doc => doc.exists)
        .map(doc => serializeDoc(doc))
    };

    res.status(201).json({
      success: true,
      conversation
    });

  } catch (error) {
    console.error('Error in getOrCreateDirectConversation:', error);
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
        
        // Clean up unreadCounts to ensure it's a flat structure
        if (conversation.unreadCounts) {
          const cleanedUnreadCounts = {};
          for (const [key, value] of Object.entries(conversation.unreadCounts)) {
            // Only keep entries where value is a number
            if (typeof value === 'number') {
              cleanedUnreadCounts[key] = value;
            }
          }
          conversation.unreadCounts = cleanedUnreadCounts;
        }
        
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
    let messages = serializeQuerySnapshot(snapshot);

    // Filter out connection request messages sent by the current user
    // Connection requests should only be visible to the recipient
    messages = messages.filter(msg => {
      if (msg.type === 'connection_request' && msg.senderId === userId) {
        return false; // Don't show connection requests you sent
      }
      return true;
    });

    // Don't automatically mark messages as read when fetching
    // This should only happen when explicitly requested via markMessagesAsRead endpoint

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
        const currentUnread = conversation.unreadCounts?.[participantId] || 0;
        const newUnread = currentUnread + 1;
        conversationUpdate[`unreadCounts.${participantId}`] = newUnread;
        console.log(`📨 Updating unread count for ${participantId}: ${currentUnread} -> ${newUnread}`);
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

    // Send push notifications to other participants
    const notificationService = require('../services/notificationService');
    
    // Get recipient IDs (everyone except the sender)
    const recipientIds = conversation.participants.filter(participantId => participantId !== userId);
    
    // Send notification to each recipient
    for (const recipientId of recipientIds) {
      try {
        await notificationService.notifyNewMessage(userId, recipientId, message);
        console.log(`🔔 Sent message notification to user ${recipientId}`);
        
        // Send real-time SSE notification
        sseService.notifyUser(recipientId, 'new_message', {
          messageId: message.id,
          conversationId: conversationId,
          senderId: userId,
          senderName: message.senderDetails?.displayName || 'Someone',
          content: content,
          type: type
        });
      } catch (notificationError) {
        console.error(`🔔 Failed to send notification to ${recipientId}:`, notificationError);
        // Don't fail the whole request if notification fails
      }
    }

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
        // Check if readBy exists (for backward compatibility with older messages)
        const readByArray = message.readBy || [];
        if (message.senderId !== userId && !readByArray.includes(userId)) {
          batch.update(messageDoc.ref, {
            readBy: [...readByArray, userId]
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
      
      console.log(`✅ Marking ${validMessageCount} messages as read for user ${userId}`);
      console.log(`📊 Updating unread count: ${currentUnreadCount} -> ${newUnreadCount}`);
      
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

// @desc    Debug endpoint to test conversation fetching
// @route   GET /api/messages/conversations/debug
// @access  Private
const debugGetConversations = async (req, res) => {
  try {
    console.log('🔍 DEBUG: getConversations called');
    console.log('🔍 DEBUG: User ID:', req.user.uid);
    console.log('🔍 DEBUG: User object:', JSON.stringify(req.user, null, 2));
    
    const userId = req.user.uid;
    
    // Try a simple query first
    console.log('🔍 DEBUG: Attempting simple query...');
    const snapshot = await db.collection(COLLECTIONS.CONVERSATIONS)
      .where('participants', 'array-contains', userId)
      .limit(10)
      .get();
    
    console.log('🔍 DEBUG: Query executed successfully');
    console.log('🔍 DEBUG: Found', snapshot.size, 'conversations');
    
    const conversations = [];
    snapshot.forEach(doc => {
      const data = doc.data();
      console.log('🔍 DEBUG: Conversation', doc.id, 'data:', JSON.stringify(data, null, 2));
      conversations.push({
        id: doc.id,
        ...data
      });
    });
    
    res.status(200).json({
      success: true,
      debug: true,
      userId: userId,
      conversationCount: conversations.length,
      conversations: conversations
    });
  } catch (error) {
    console.error('❌ DEBUG ERROR:', error);
    console.error('❌ DEBUG ERROR Stack:', error.stack);
    res.status(500).json({
      success: false,
      debug: true,
      error: error.message,
      stack: error.stack,
      code: error.code
    });
  }
};

// @desc    Delete a conversation
// @route   DELETE /api/messages/conversations/:conversationId
// @access  Private
const deleteConversation = async (req, res) => {
  try {
    const userId = req.user.uid;
    const { conversationId } = req.params;

    // Get the conversation to verify permissions
    const conversationDoc = await db.collection(COLLECTIONS.CONVERSATIONS).doc(conversationId).get();
    
    if (!conversationDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Conversation not found'
      });
    }

    const conversation = conversationDoc.data();
    
    // Verify user is part of this conversation
    if (!conversation.participants.includes(userId)) {
      return res.status(403).json({
        success: false,
        message: 'Not authorized to delete this conversation'
      });
    }

    // Use batch to delete conversation and all its messages
    const batch = db.batch();

    // Delete the conversation document
    batch.delete(conversationDoc.ref);

    // Delete all messages in the conversation
    const messagesSnapshot = await db.collection(COLLECTIONS.MESSAGES)
      .where('conversationId', '==', conversationId)
      .get();

    messagesSnapshot.docs.forEach(doc => {
      batch.delete(doc.ref);
    });

    // Delete all message reads for this conversation
    const messageReadsSnapshot = await db.collection(COLLECTIONS.MESSAGE_READS)
      .where('conversationId', '==', conversationId)
      .get();

    messageReadsSnapshot.docs.forEach(doc => {
      batch.delete(doc.ref);
    });

    // Commit the batch
    await batch.commit();

    res.status(200).json({
      success: true,
      message: 'Conversation deleted successfully'
    });

  } catch (error) {
    console.error('Error deleting conversation:', error);
    res.status(500).json({
      success: false,
      message: 'Server error',
      error: error.message
    });
  }
};

// @desc    Update conversation (name, avatar)
// @route   PUT /api/messages/conversations/:conversationId
// @access  Private (participants only)
const updateConversation = async (req, res) => {
  try {
    const { conversationId } = req.params;
    const { name, avatar } = req.body;
    const userId = req.user.uid;
    
    console.log(`📝 updateConversation called - conversationId: ${conversationId}, userId: ${userId}`);
    console.log(`📝 Update data:`, { name, avatar: avatar ? 'URL provided' : 'null' });
    
    // Get conversation
    const conversationDoc = await db.collection(COLLECTIONS.CONVERSATIONS).doc(conversationId).get();
    if (!conversationDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Conversation not found'
      });
    }
    
    const conversation = conversationDoc.data();
    
    // Check if user is a participant
    if (!conversation.participants.includes(userId)) {
      return res.status(403).json({
        success: false,
        message: 'Not authorized to update this conversation'
      });
    }
    
    // Only allow updating group conversations
    if (conversation.type !== 'group') {
      return res.status(400).json({
        success: false,
        message: 'Only group conversations can be updated'
      });
    }
    
    // Validate inputs
    if (name !== undefined && (typeof name !== 'string' || name.trim().length === 0)) {
      return res.status(400).json({
        success: false,
        message: 'Group name must be a non-empty string'
      });
    }
    
    if (name && name.length > 50) {
      return res.status(400).json({
        success: false,
        message: 'Group name must be 50 characters or less'
      });
    }
    
    if (avatar !== undefined && avatar !== null && typeof avatar !== 'string') {
      return res.status(400).json({
        success: false,
        message: 'Avatar must be a valid URL string or null'
      });
    }
    
    // Build update object
    const updateData = {
      updatedAt: new Date().toISOString()
    };
    
    if (name !== undefined) {
      updateData.name = name.trim();
    }
    
    if (avatar !== undefined) {
      updateData.avatar = avatar;
    }
    
    // Update conversation
    await conversationDoc.ref.update(updateData);
    
    // Get updated conversation
    const updatedDoc = await conversationDoc.ref.get();
    const updatedConversation = serializeDoc(updatedDoc);
    
    console.log(`✅ Conversation ${conversationId} updated by user ${userId}`);
    
    res.status(200).json({
      success: true,
      conversation: updatedConversation
    });
    
  } catch (error) {
    console.error('Error updating conversation:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to update conversation'
    });
  }
};

// @desc    Toggle notification settings for a conversation
// @route   PUT /api/messages/conversations/:conversationId/notifications
// @access  Private
const toggleNotifications = async (req, res) => {
  try {
    const { conversationId } = req.params;
    const { enabled } = req.body;
    const userId = req.user.uid;

    console.log(`🔔 toggleNotifications called - conversationId: ${conversationId}, userId: ${userId}, enabled: ${enabled}`);

    // Get the conversation
    const conversationRef = db.collection(COLLECTIONS.CONVERSATIONS).doc(conversationId);
    const conversationDoc = await conversationRef.get();

    if (!conversationDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Conversation not found'
      });
    }

    const conversation = conversationDoc.data();

    // Check if user is a participant
    if (!conversation.participants.includes(userId)) {
      return res.status(403).json({
        success: false,
        message: 'You are not a participant in this conversation'
      });
    }

    // Update notification settings
    const notificationSettings = conversation.notificationSettings || {};
    notificationSettings[userId] = enabled;

    await conversationRef.update({
      notificationSettings,
      updatedAt: new Date().toISOString()
    });

    console.log(`✅ Notification settings updated for user ${userId} in conversation ${conversationId}`);

    res.status(200).json({
      success: true,
      message: `Notifications ${enabled ? 'enabled' : 'disabled'} for this conversation`
    });

  } catch (error) {
    console.error('Error toggling notifications:', error);
    res.status(500).json({
      success: false,
      message: 'Server error',
      error: error.message
    });
  }
};

// @desc    Add participant to group conversation
// @route   POST /api/messages/conversations/:conversationId/participants
// @access  Private (participants only)
const addParticipant = async (req, res) => {
  try {
    const { conversationId } = req.params;
    const { userId } = req.body;
    const currentUserId = req.user.uid;
    
    console.log(`👥 addParticipant called - conversationId: ${conversationId}, userId: ${userId}, currentUserId: ${currentUserId}`);
    
    if (!userId) {
      return res.status(400).json({
        success: false,
        message: 'User ID is required'
      });
    }
    
    // Get conversation
    const conversationDoc = await db.collection(COLLECTIONS.CONVERSATIONS).doc(conversationId).get();
    if (!conversationDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Conversation not found'
      });
    }
    
    const conversation = conversationDoc.data();
    
    // Check if current user is a participant
    if (!conversation.participants.includes(currentUserId)) {
      return res.status(403).json({
        success: false,
        message: 'You are not authorized to add participants'
      });
    }
    
    // Only allow adding to group conversations
    if (conversation.type !== 'group') {
      return res.status(400).json({
        success: false,
        message: 'Can only add participants to group conversations'
      });
    }
    
    // Check if user is already a participant
    if (conversation.participants.includes(userId)) {
      return res.status(400).json({
        success: false,
        message: 'User is already a participant'
      });
    }
    
    // Verify target user exists
    const targetUserDoc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
    if (!targetUserDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Target user not found'
      });
    }
    
    // Add user to participants array and initialize unread count
    const updatedParticipants = [...conversation.participants, userId];
    const updatedUnreadCounts = { ...conversation.unreadCounts };
    updatedUnreadCounts[userId] = 0;
    
    await conversationDoc.ref.update({
      participants: updatedParticipants,
      unreadCounts: updatedUnreadCounts,
      updatedAt: new Date().toISOString()
    });
    
    console.log(`✅ Added participant ${userId} to conversation ${conversationId}`);
    
    res.status(200).json({
      success: true,
      message: 'Participant added successfully'
    });
    
  } catch (error) {
    console.error('Error adding participant:', error);
    res.status(500).json({
      success: false,
      message: 'Server error',
      error: error.message
    });
  }
};

// @desc    Remove participant from group conversation
// @route   DELETE /api/messages/conversations/:conversationId/participants/:userId
// @access  Private (participants only)
const removeParticipant = async (req, res) => {
  try {
    const { conversationId, userId } = req.params;
    const currentUserId = req.user.uid;
    
    console.log(`👥 removeParticipant called - conversationId: ${conversationId}, userId: ${userId}, currentUserId: ${currentUserId}`);
    
    // Get conversation
    const conversationDoc = await db.collection(COLLECTIONS.CONVERSATIONS).doc(conversationId).get();
    if (!conversationDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Conversation not found'
      });
    }
    
    const conversation = conversationDoc.data();
    
    // Check if current user is a participant
    if (!conversation.participants.includes(currentUserId)) {
      return res.status(403).json({
        success: false,
        message: 'You are not authorized to remove participants'
      });
    }
    
    // Only allow removing from group conversations
    if (conversation.type !== 'group') {
      return res.status(400).json({
        success: false,
        message: 'Can only remove participants from group conversations'
      });
    }
    
    // Check if user is a participant
    if (!conversation.participants.includes(userId)) {
      return res.status(400).json({
        success: false,
        message: 'User is not a participant'
      });
    }
    
    // Allow users to remove themselves, or group creator to remove others
    const canRemove = (userId === currentUserId) || (conversation.createdBy === currentUserId);
    
    if (!canRemove) {
      return res.status(403).json({
        success: false,
        message: 'You can only remove yourself or you must be the group creator'
      });
    }
    
    // Don't allow removing the last participant
    if (conversation.participants.length <= 2) {
      return res.status(400).json({
        success: false,
        message: 'Cannot remove participant - group must have at least 2 members'
      });
    }
    
    // Remove user from participants array and unread counts
    const updatedParticipants = conversation.participants.filter(id => id !== userId);
    const updatedUnreadCounts = { ...conversation.unreadCounts };
    delete updatedUnreadCounts[userId];
    
    // Also remove from notification settings
    const updatedNotificationSettings = { ...conversation.notificationSettings };
    delete updatedNotificationSettings[userId];
    
    await conversationDoc.ref.update({
      participants: updatedParticipants,
      unreadCounts: updatedUnreadCounts,
      notificationSettings: updatedNotificationSettings,
      updatedAt: new Date().toISOString()
    });
    
    console.log(`✅ Removed participant ${userId} from conversation ${conversationId}`);
    
    res.status(200).json({
      success: true,
      message: 'Participant removed successfully'
    });
    
  } catch (error) {
    console.error('Error removing participant:', error);
    res.status(500).json({
      success: false,
      message: 'Server error',
      error: error.message
    });
  }
};

module.exports = {
  getConversations,
  getOrCreateDirectConversation,
  createNewConversation,
  getMessages,
  sendMessage,
  editMessage,
  deleteMessage,
  markMessagesAsRead,
  getUnreadCount,
  deleteConversation,
  debugGetConversations,
  toggleNotifications,
  updateConversation,
  addParticipant,
  removeParticipant
};