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
  COMMENTS: 'comments',
  PLACE_COMMENTS: 'placeComments',
  CIRCLE_COMMENTS: 'circleComments',
  NOTIFICATIONS: 'notifications',
  ACTIVITIES: 'activities',
  USER_CATEGORIES: 'userCategories',
  PLACE_VISITS: 'placeVisits',
  VISIT_DRAFTS: 'visitDrafts'
};

// User model structure
const createUser = (userData) => {
  const now = new Date().toISOString();
  return {
    email: userData.email || null,
    alternateEmails: userData.alternateEmails || [],
    displayName: userData.displayName || userData.name,
    firstName: userData.firstName || null,
    lastName: userData.lastName || null,
    phoneNumber: userData.phoneNumber || null,
    profilePicture: userData.profilePicture || userData.picture || null,
    bio: userData.bio || null,
    location: userData.location || null,
    friends: userData.friends || [],
    friendRequests: userData.friendRequests || [],
    linkedProviders: userData.linkedProviders || {},
    circleOrder: userData.circleOrder || [],
    deviceTokens: userData.deviceTokens || [],
    // Instagram-style follower system
    followers: userData.followers || [],
    following: userData.following || [],
    followersCount: userData.followersCount || 0,
    followingCount: userData.followingCount || 0,
    connectionsCount: userData.connectionsCount || 0,
    // Pinned places (max 6)
    pinnedPlaces: userData.pinnedPlaces || [],
    // Subscription fields
    subscriptionStatus: userData.subscriptionStatus || 'none',
    subscriptionExpiryDate: userData.subscriptionExpiryDate || null,
    trialStartDate: userData.trialStartDate || null,
    trialEndDate: userData.trialEndDate || null,
    // Referral fields
    referralCode: userData.referralCode || null,
    referredBy: userData.referredBy || null,
    referralCount: userData.referralCount || 0,
    referralRewards: userData.referralRewards || [],
    notificationPreferences: userData.notificationPreferences || {
      newMessages: true,
      newSuggestions: true,
      newPlaces: true,
      connectionRequests: true,
      circleInvites: true,
      newFollowers: true,
      dailyDigest: false,
      // New notification preferences
      dailySummary: true,
      summaryTime: '12:00',
      timezone: 'America/New_York',
      socialActivity: true,
      discoveryPrompts: true,
      milestones: true,
      weekendRecommendations: true,
      reengagement: true,
      frequency: 'normal', // 'minimal', 'normal', 'all'
      // Quiet hours
      quietHoursEnabled: false,
      quietHoursStart: '22:00',
      quietHoursEnd: '08:00'
    },
    preferences: userData.preferences || {
      defaultHomeView: 'map', // 'list' or 'map'
      visitTracking: {
        enabled: false,
        minVisitDuration: 5, // minutes
        excludeHomeWork: true,
        trackingSchedule: null, // e.g., { start: '09:00', end: '18:00' }
        autoSuggestCircles: true
      }
    },
    // Onboarding status
    onboardingCompleted: userData.onboardingCompleted || false,
    hasCompletedTutorial: userData.hasCompletedTutorial || false,
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
    editors: circleData.editors || [], // Array of user IDs who can edit this circle
    places: circleData.places || [],
    placesCount: circleData.placesCount || 0, // Count of places for efficient display
    privacy: circleData.privacy || 'myNetwork', // public, myNetwork, private
    allowNetworkEdit: circleData.allowNetworkEdit || false,
    category: circleData.category || 'other', // travel, food, services, shopping, healthcare, entertainment, other
    customCategoryId: circleData.customCategoryId || null, // Reference to user's custom category
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
    likes: circleData.likes || [],
    likesCount: circleData.likesCount || 0,
    commentsCount: circleData.commentsCount || 0,
    createdAt: now,
    updatedAt: now
  };
};

// Place model structure
const createPlace = (placeData, circleId, addedBy) => {
  const now = new Date().toISOString();
  
  // Validate and sanitize location coordinates
  let location = null;
  if (placeData.location && placeData.location.coordinates) {
    const [longitude, latitude] = placeData.location.coordinates;
    
    // Validate coordinates are within valid ranges
    if (typeof longitude === 'number' && typeof latitude === 'number' &&
        longitude >= -180 && longitude <= 180 &&
        latitude >= -90 && latitude <= 90 &&
        // Reject coordinates at exactly -180, -180 (invalid/default values)
        !(longitude === -180 && latitude === -180)) {
      location = {
        type: 'Point',
        coordinates: [longitude, latitude]
      };
    } else {
      console.warn('⚠️ Invalid coordinates rejected:', { longitude, latitude, placeName: placeData.name });
    }
  }
  
  return {
    name: placeData.name,
    description: placeData.description || null,
    address: placeData.address,
    location: location,
    website: placeData.website || null,
    phone: placeData.phone || null,
    googlePlaceId: placeData.googlePlaceId || null,
    photos: placeData.photos || [],
    category: placeData.category, // restaurant, cafe, bar, hotel, retail, service, attraction, entertainment, healthcare, fitness, education, outdoor, transport, finance, other
    customCategoryId: placeData.customCategoryId || null, // Reference to user's custom category
    subcategory: placeData.subcategory || null,
    rating: placeData.rating || null,
    userRatingsTotal: placeData.userRatingsTotal || null,
    notes: placeData.notes || null, // Legacy field - kept for backward compatibility
    publicNotes: placeData.publicNotes || null, // Notes visible to all users who can see the place
    privateNotes: placeData.privateNotes || null, // Notes only visible to the user who added them
    tags: placeData.tags || [],
    reviews: placeData.reviews || [],
    openingHours: placeData.openingHours || null,
    priceLevel: placeData.priceLevel || null,
    likes: placeData.likes || [],
    likesCount: placeData.likesCount || 0,
    circleId: circleId,
    addedBy: addedBy,
    privacy: placeData.privacy || 'followCircle', // followCircle, public, myNetwork, private
    deletedAt: null, // Soft delete timestamp
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
    // Activity tracking fields
    lastInteractionAt: null,
    interactionCount: 0,
    lastAccessedCircles: [], // Array of {circleId, accessedAt}
    recentActivity: [], // Array of {type: 'circle'|'place'|'suggestion', entityId, entityName, circleId?, circleName?, createdAt, viewedBy: []}
    hasNewActivity: false, // Flag for red dot notification
    viewCount: 0, // Number of times this connection's profile was viewed
    lastViewedAt: null, // Last time this connection was viewed
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
    updatedAt: now
    // Removed expiresAt - suggestions no longer expire
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
  } else {
    // Validate coordinate values
    const [longitude, latitude] = placeData.location.coordinates;
    if (typeof longitude !== 'number' || typeof latitude !== 'number' ||
        longitude < -180 || longitude > 180 ||
        latitude < -90 || latitude > 90 ||
        (longitude === -180 && latitude === -180)) {
      errors.push('Location coordinates must be valid latitude (-90 to 90) and longitude (-180 to 180) values');
    }
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
  
  // Convert any Firestore timestamps and GeoPoints to proper format
  const serializedData = {};
  for (const [key, value] of Object.entries(restData)) {
    if (value && value._seconds) {
      // Firestore timestamp object
      serializedData[key] = new Date(value._seconds * 1000).toISOString();
    } else if (value && value.toDate && typeof value.toDate === 'function') {
      // Firestore Timestamp class
      serializedData[key] = value.toDate().toISOString();
    } else if (value instanceof Date) {
      // JavaScript Date object
      serializedData[key] = value.toISOString();
    } else if (value && typeof value === 'object' && '_latitude' in value && '_longitude' in value) {
      // Firestore GeoPoint object
      serializedData[key] = {
        latitude: value._latitude,
        longitude: value._longitude
      };
    } else {
      serializedData[key] = value;
    }
  }
  
  return {
    _id: id, // Use _id for consistency with iOS models
    id: id, // Also include id for backward compatibility
    ...serializedData
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

// Helper function to generate default group name
const generateDefaultGroupName = (participants, createdBy) => {
  // If we have participant count, create a generic name
  if (participants && participants.length > 0) {
    const participantCount = participants.length;
    return `Group Chat (${participantCount} members)`;
  }
  return 'Group Chat';
};

// Conversation model structure
const createConversation = (conversationData) => {
  const now = new Date().toISOString();
  
  // Auto-generate group name if not provided for group conversations
  let conversationName = conversationData.name;
  if (conversationData.type === 'group' && (!conversationName || conversationName.trim().length === 0)) {
    conversationName = generateDefaultGroupName(conversationData.participants, conversationData.createdBy);
  }
  
  return {
    type: conversationData.type || 'direct', // direct or group
    participants: conversationData.participants || [], // Array of user IDs
    name: conversationName || null, // For group chats
    avatar: conversationData.avatar || null, // For group chats
    lastMessage: conversationData.lastMessage || null,
    lastMessageTime: conversationData.lastMessageTime || now, // Initialize with current time if not provided
    lastMessageSenderId: conversationData.lastMessageSenderId || null,
    unreadCounts: conversationData.unreadCounts || {}, // Map of userId to unread count
    notificationSettings: conversationData.notificationSettings || {}, // Map of userId to boolean (true = notifications on)
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
  
  if (!message.type || !['text', 'image', 'location', 'circle_share', 'place_share', 'connection_request'].includes(message.type)) {
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

// Create circle comment object for Firestore
const createCircleComment = (commentData) => {
  const now = new Date().toISOString();
  return {
    circleId: commentData.circleId,
    userId: commentData.userId,
    text: commentData.text,
    likes: commentData.likes || [],
    likesCount: commentData.likesCount || 0,
    parentCommentId: commentData.parentCommentId || null, // For replies
    replyCount: commentData.replyCount || 0, // Number of replies to this comment
    createdAt: now
  };
};

// Create place comment object for Firestore
const createPlaceComment = (commentData) => {
  const now = new Date().toISOString();
  return {
    placeId: commentData.placeId,
    userId: commentData.userId,
    text: commentData.text,
    likes: commentData.likes || [],
    likesCount: commentData.likesCount || 0,
    parentCommentId: commentData.parentCommentId || null, // For replies
    replyCount: commentData.replyCount || 0, // Number of replies to this comment
    createdAt: now
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

// Validate circle comment
const validateCircleComment = (commentData) => {
  const errors = [];
  
  if (!commentData.text || commentData.text.trim().length === 0) {
    errors.push('Comment text is required');
  }
  
  if (commentData.text && commentData.text.length > 500) {
    errors.push('Comment must be 500 characters or less');
  }
  
  if (!commentData.circleId) {
    errors.push('Circle ID is required');
  }
  
  // If parentCommentId is provided, validate it's a valid string
  if (commentData.parentCommentId && typeof commentData.parentCommentId !== 'string') {
    errors.push('Parent comment ID must be a valid string');
  }
  
  return errors;
};

// Validate place comment
const validatePlaceComment = (commentData) => {
  const errors = [];
  
  if (!commentData.text || commentData.text.trim().length === 0) {
    errors.push('Comment text is required');
  }
  
  if (commentData.text && commentData.text.length > 500) {
    errors.push('Comment must be 500 characters or less');
  }
  
  if (!commentData.placeId) {
    errors.push('Place ID is required');
  }
  
  // If parentCommentId is provided, validate it's a valid string
  if (commentData.parentCommentId && typeof commentData.parentCommentId !== 'string') {
    errors.push('Parent comment ID must be a valid string');
  }
  
  return errors;
};

// Create notification object for Firestore
const createNotification = (notificationData) => {
  const now = new Date().toISOString();
  return {
    userId: notificationData.userId, // Recipient user ID
    type: notificationData.type, // 'place_like', 'place_comment'
    title: notificationData.title,
    body: notificationData.body,
    data: notificationData.data || {}, // Additional data (fromUserId, placeId, etc.)
    read: false,
    createdAt: now
  };
};

// Validate notification
const validateNotification = (notificationData) => {
  const errors = [];
  
  if (!notificationData.userId) {
    errors.push('User ID is required');
  }
  
  if (!notificationData.type || !['place_like', 'place_comment', 'new_follower'].includes(notificationData.type)) {
    errors.push('Valid notification type is required');
  }
  
  if (!notificationData.title) {
    errors.push('Title is required');
  }
  
  if (!notificationData.body) {
    errors.push('Body is required');
  }
  
  return errors;
};

// PlaceVisit model structure
const createPlaceVisit = (visitData, userId) => {
  const now = new Date().toISOString();
  return {
    userId: userId,
    placeId: visitData.placeId || null,
    placeName: visitData.placeName,
    placeAddress: visitData.placeAddress,
    location: visitData.location || null, // Firestore GeoPoint
    category: visitData.category || null,
    visitedAt: visitData.visitedAt || now,
    duration: visitData.duration || 0, // minutes
    autoDetected: visitData.autoDetected || false,
    reviewed: visitData.reviewed || false,
    dismissed: visitData.dismissed || false,
    addedToCircles: visitData.addedToCircles || [], // circle IDs
    placeData: visitData.placeData || {}, // Cached place details from API
    notes: visitData.notes || null,
    photos: visitData.photos || [],
    createdAt: now,
    updatedAt: now
  };
};

// Validate place visit
const validatePlaceVisit = (visitData) => {
  const errors = [];
  
  if (!visitData.placeName || visitData.placeName.trim().length === 0) {
    errors.push('Place name is required');
  }
  
  if (!visitData.placeAddress || visitData.placeAddress.trim().length === 0) {
    errors.push('Place address is required');
  }
  
  if (visitData.duration && visitData.duration < 0) {
    errors.push('Visit duration cannot be negative');
  }
  
  if (visitData.notes && visitData.notes.length > 1000) {
    errors.push('Notes must be 1000 characters or less');
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
  createCircleComment,
  createPlaceComment,
  createConversation,
  createMessage,
  createMessageRead,
  createNotification,
  createPlaceVisit,
  validateCircle,
  validatePlace,
  validateConnection,
  validateCircleShare,
  validateSuggestion,
  validateComment,
  validateCircleComment,
  validatePlaceComment,
  validateConversation,
  validateMessage,
  validateNotification,
  validatePlaceVisit,
  serializeDoc,
  serializeQuerySnapshot
};