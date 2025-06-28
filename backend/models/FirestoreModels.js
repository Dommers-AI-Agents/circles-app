// backend/models/FirestoreModels.js
// Firestore collection models and validation

const { getFirestore } = require('../config/firebase');

// Collection names
const COLLECTIONS = {
  USERS: 'users',
  CIRCLES: 'circles', 
  PLACES: 'places',
  FRIEND_REQUESTS: 'friendRequests',
  CONNECTIONS: 'connections',
  CIRCLE_SHARES: 'circleShares',
  CONVERSATIONS: 'conversations',
  MESSAGES: 'messages',
  MESSAGE_READS: 'messageReads',
  SUGGESTIONS: 'suggestions',
  COMMENTS: 'comments'
};

// User model structure
const createUser = (userData) => {
  const now = new Date().toISOString();
  return {
    email: userData.email || null,
    displayName: userData.displayName || userData.name,
    profilePicture: userData.profilePicture || userData.picture || null,
    bio: userData.bio || null,
    location: userData.location || null,
    friends: userData.friends || [],
    friendRequests: userData.friendRequests || [],
    linkedProviders: userData.linkedProviders || {},
    circleOrder: userData.circleOrder || [],
    createdAt: now,
    updatedAt: now,
    // Firebase UID from authentication
    uid: userData.uid
  };
};

// Circle model structure  
const createCircle = (circleData, ownerId) => {
  const now = new Date().toISOString();
  return {
    name: circleData.name,
    description: circleData.description || null,
    coverImage: circleData.coverImage || null,
    owner: ownerId,
    places: circleData.places || [],
    privacy: circleData.privacy || 'myNetwork', // public, myNetwork, private
    allowNetworkEdit: circleData.allowNetworkEdit || false,
    category: circleData.category || 'other', // travel, food, services, shopping, healthcare, entertainment, other
    location: circleData.location || null,
    tags: circleData.tags || [],
    sharedWith: circleData.sharedWith || [],
    followers: circleData.followers || [],
    activeShares: circleData.activeShares || [],
    shareSettings: circleData.shareSettings || {
      allowGuestShares: true,
      defaultAccessLevel: 'view_only',
      requireApproval: false,
      maxShareDuration: null,
      allowReshare: false
    },
    createdAt: now,
    updatedAt: now
  };
};

// Place model structure
const createPlace = (placeData, circleId, addedBy) => {
  const now = new Date().toISOString();
  return {
    name: placeData.name,
    description: placeData.description || null,
    address: placeData.address,
    location: {
      type: 'Point',
      coordinates: placeData.location.coordinates // [longitude, latitude]
    },
    website: placeData.website || null,
    phone: placeData.phone || null,
    googlePlaceId: placeData.googlePlaceId || null,
    photos: placeData.photos || [],
    category: placeData.category, // restaurant, cafe, bar, hotel, retail, service, attraction, entertainment, healthcare, fitness, education, outdoor, transport, finance, other
    customCategory: placeData.customCategory || null,
    subcategory: placeData.subcategory || null,
    rating: placeData.rating || null,
    userRatingsTotal: placeData.userRatingsTotal || null,
    notes: placeData.notes || null,
    tags: placeData.tags || [],
    reviews: placeData.reviews || [],
    openingHours: placeData.openingHours || null,
    priceLevel: placeData.priceLevel || null,
    circleId: circleId,
    addedBy: addedBy,
    privacy: placeData.privacy || 'followCircle', // followCircle, public, myNetwork, private
    createdAt: now,
    updatedAt: now
  };
};

// Friend request model
const createFriendRequest = (fromUserId, toUserId) => {
  const now = new Date().toISOString();
  return {
    from: fromUserId,
    to: toUserId,
    status: 'pending', // pending, accepted, rejected
    createdAt: now,
    updatedAt: now
  };
};

// Connection model
const createConnection = (userId, connectedUserId, message = null) => {
  const now = new Date().toISOString();
  return {
    userId: userId,
    connectedUserId: connectedUserId,
    status: 'pending', // pending, accepted, blocked
    message: message,
    sharedCircles: [],
    createdAt: now,
    acceptedAt: null,
    updatedAt: now
  };
};

// Circle share model
const createCircleShare = (shareData) => {
  const now = new Date().toISOString();
  return {
    circleId: shareData.circleId,
    sharedBy: shareData.sharedBy,
    sharedWith: shareData.sharedWith || null, // userId or email
    shareType: shareData.shareType, // 'registered_user', 'email', 'link'
    accessLevel: shareData.accessLevel || 'view_only', // 'view_only', 'can_add_places', 'can_edit'
    shareLink: shareData.shareLink || null,
    expiresAt: shareData.expiresAt || null,
    lastAccessedAt: null,
    createdAt: now,
    updatedAt: now
  };
};

// Suggestion model structure
const createSuggestion = (suggestionData, userId) => {
  const now = new Date().toISOString();
  const tomorrow = new Date();
  tomorrow.setHours(tomorrow.getHours() + 24);
  
  return {
    userId: userId,
    message: suggestionData.message,
    placeId: suggestionData.placeId || null,
    placeDetails: suggestionData.placeDetails || null,
    imageUrl: suggestionData.imageUrl || null,
    mentionedPlaces: suggestionData.mentionedPlaces || [],
    likes: suggestionData.likes || [],
    likesCount: suggestionData.likesCount || 0,
    createdAt: now,
    updatedAt: now,
    expiresAt: tomorrow.toISOString() // Suggestions expire after 24 hours
  };
};

// Validation functions
const validateCircle = (circleData) => {
  const errors = [];
  
  if (!circleData.name || circleData.name.trim().length === 0) {
    errors.push('Circle name is required');
  }
  
  if (circleData.name && circleData.name.length > 50) {
    errors.push('Circle name must be 50 characters or less');
  }
  
  if (circleData.description && circleData.description.length > 500) {
    errors.push('Description must be 500 characters or less');
  }
  
  const validPrivacyLevels = ['public', 'myNetwork', 'private'];
  if (circleData.privacy && !validPrivacyLevels.includes(circleData.privacy)) {
    errors.push('Privacy must be public, myNetwork, or private');
  }
  
  const validCategories = ['travel', 'food', 'services', 'shopping', 'healthcare', 'entertainment', 'other'];
  if (circleData.category && !validCategories.includes(circleData.category)) {
    errors.push('Invalid category');
  }
  
  return errors;
};

const validatePlace = (placeData) => {
  const errors = [];
  
  if (!placeData.name || placeData.name.trim().length === 0) {
    errors.push('Place name is required');
  }
  
  if (!placeData.address || placeData.address.trim().length === 0) {
    errors.push('Place address is required');
  }
  
  if (!placeData.location || !placeData.location.coordinates || 
      !Array.isArray(placeData.location.coordinates) || 
      placeData.location.coordinates.length !== 2) {
    errors.push('Valid location coordinates are required');
  }
  
  if (!placeData.category) {
    errors.push('Place category is required');
  }
  
  const validCategories = ['restaurant', 'cafe', 'bar', 'hotel', 'retail', 'service', 
                          'attraction', 'entertainment', 'healthcare', 'fitness', 
                          'education', 'outdoor', 'transport', 'finance', 'home', 
                          'work', 'other'];
  if (placeData.category && !validCategories.includes(placeData.category)) {
    errors.push('Invalid place category');
  }
  
  return errors;
};

// Helper function to serialize document for API response
const serializeDoc = (doc) => {
  if (!doc.exists) return null;
  
  const data = doc.data();
  // Ensure we always have an id field
  const id = doc.id || data.uid || data.id;
  
  // Remove uid from data to avoid duplication
  const { uid, ...restData } = data;
  
  return {
    _id: id, // Use _id for consistency with iOS models
    id: id, // Also include id for backward compatibility
    ...restData
  };
};

// Helper function to serialize query snapshot
const serializeQuerySnapshot = (querySnapshot) => {
  return querySnapshot.docs.map(doc => serializeDoc(doc)).filter(doc => doc !== null);
};

// Validation functions for new models
const validateConnection = (connectionData) => {
  const errors = [];
  
  if (!connectionData.connectedUserId || connectionData.connectedUserId.trim().length === 0) {
    errors.push('Connected user ID is required');
  }
  
  return errors;
};

const validateCircleShare = (shareData) => {
  const errors = [];
  
  if (!shareData.circleId || shareData.circleId.trim().length === 0) {
    errors.push('Circle ID is required');
  }
  
  if (!shareData.shareType || !['registered_user', 'email', 'link'].includes(shareData.shareType)) {
    errors.push('Valid share type is required (registered_user, email, or link)');
  }
  
  if (!shareData.accessLevel || !['view_only', 'can_add_places', 'can_edit'].includes(shareData.accessLevel)) {
    errors.push('Valid access level is required (view_only, can_add_places, or can_edit)');
  }
  
  if (shareData.shareType === 'registered_user' && (!shareData.sharedWith || shareData.sharedWith.trim().length === 0)) {
    errors.push('User ID is required for registered user shares');
  }
  
  if (shareData.shareType === 'email' && (!shareData.sharedWith || !shareData.sharedWith.includes('@'))) {
    errors.push('Valid email is required for email shares');
  }
  
  return errors;
};

const validateSuggestion = (suggestionData) => {
  const errors = [];
  
  if (!suggestionData.message || suggestionData.message.trim().length === 0) {
    errors.push('Suggestion message is required');
  }
  
  if (suggestionData.message && suggestionData.message.length > 500) {
    errors.push('Suggestion message must be 500 characters or less');
  }
  
  return errors;
};

// Conversation model structure
const createConversation = (conversationData) => {
  const now = new Date().toISOString();
  return {
    type: conversationData.type || 'direct', // direct or group
    participants: conversationData.participants || [], // Array of user IDs
    name: conversationData.name || null, // For group chats
    avatar: conversationData.avatar || null, // For group chats
    lastMessage: conversationData.lastMessage || null,
    lastMessageTime: conversationData.lastMessageTime || null,
    lastMessageSenderId: conversationData.lastMessageSenderId || null,
    unreadCounts: conversationData.unreadCounts || {}, // Map of userId to unread count
    createdAt: now,
    updatedAt: now,
    createdBy: conversationData.createdBy || null
  };
};

// Message model structure
const createMessage = (messageData, conversationId, senderId) => {
  const now = new Date().toISOString();
  return {
    conversationId: conversationId,
    senderId: senderId,
    type: messageData.type || 'text', // text, image, location, circle_share, place_share
    content: messageData.content || '',
    mediaUrl: messageData.mediaUrl || null,
    metadata: messageData.metadata || {}, // For attachments, shares, etc.
    readBy: messageData.readBy || [senderId], // Array of user IDs who have read
    deliveredTo: messageData.deliveredTo || [], // Array of user IDs
    editedAt: messageData.editedAt || null,
    deletedAt: messageData.deletedAt || null,
    createdAt: now
  };
};

// Message read receipt model
const createMessageRead = (messageId, userId, conversationId) => {
  const now = new Date().toISOString();
  return {
    messageId: messageId,
    userId: userId,
    conversationId: conversationId,
    readAt: now
  };
};

// Validation functions for messaging
const validateConversation = (conversation) => {
  const errors = [];
  
  if (!conversation.type || !['direct', 'group'].includes(conversation.type)) {
    errors.push('Invalid conversation type');
  }
  
  if (!conversation.participants || conversation.participants.length < 2) {
    errors.push('Conversation must have at least 2 participants');
  }
  
  if (conversation.type === 'direct' && conversation.participants.length > 2) {
    errors.push('Direct conversation can only have 2 participants');
  }
  
  if (conversation.type === 'group' && !conversation.name) {
    errors.push('Group conversation must have a name');
  }
  
  return errors;
};

const validateMessage = (message) => {
  const errors = [];
  
  if (!message.conversationId) {
    errors.push('Message must belong to a conversation');
  }
  
  if (!message.senderId) {
    errors.push('Message must have a sender');
  }
  
  if (!message.type || !['text', 'image', 'location', 'circle_share', 'place_share'].includes(message.type)) {
    errors.push('Invalid message type');
  }
  
  if (message.type === 'text' && !message.content) {
    errors.push('Text message must have content');
  }
  
  if (['image', 'location'].includes(message.type) && !message.mediaUrl) {
    errors.push(`${message.type} message must have mediaUrl`);
  }
  
  return errors;
};

// Create comment object for Firestore
const createComment = (commentData) => {
  const now = new Date().toISOString();
  return {
    suggestionId: commentData.suggestionId,
    userId: commentData.userId,
    message: commentData.message,
    createdAt: now,
    updatedAt: now
  };
};

// Validate comment
const validateComment = (commentData) => {
  const errors = [];
  
  if (!commentData.message || commentData.message.trim().length === 0) {
    errors.push('Comment message is required');
  }
  
  if (commentData.message && commentData.message.length > 500) {
    errors.push('Comment must be 500 characters or less');
  }
  
  if (!commentData.suggestionId) {
    errors.push('Suggestion ID is required');
  }
  
  return errors;
};

module.exports = {
  COLLECTIONS,
  createUser,
  createCircle,
  createPlace,
  createFriendRequest,
  createConnection,
  createCircleShare,
  createSuggestion,
  createComment,
  createConversation,
  createMessage,
  createMessageRead,
  validateCircle,
  validatePlace,
  validateConnection,
  validateCircleShare,
  validateSuggestion,
  validateComment,
  validateConversation,
  validateMessage,
  serializeDoc,
  serializeQuerySnapshot
};