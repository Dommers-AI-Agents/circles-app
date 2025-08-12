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
  VISIT_DRAFTS: 'visitDrafts',
  CHECK_INS: 'checkIns',
  ACTIVITY_REACTIONS: 'activityReactions',
  ACTIVITY_COMMENTS: 'activityComments',
  PLACE_VIDEOS: 'placeVideos',
  USER_VIDEO_QUOTAS: 'userVideoQuotas',
  VIDEO_LIKES: 'videoLikes',
  VIDEO_VIEWS: 'videoViews'
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
    zipcode: userData.zipcode || null,
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
    videos: placeData.videos || [],
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
    addedViaCheckIn: placeData.addedViaCheckIn || false, // Track places created from check-ins
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

// PlaceVideo model structure
const createPlaceVideo = (videoData, userId) => {
  const now = new Date().toISOString();
  return {
    userId: userId,
    placeId: videoData.placeId,
    placeName: videoData.placeName,
    videoUrl: videoData.videoUrl || null,
    previewUrl: videoData.previewUrl || null,
    thumbnailUrl: videoData.thumbnailUrl || null,
    title: videoData.title || '',
    description: videoData.description || '',
    duration: videoData.duration || 0, // seconds, max 30
    fileSize: videoData.fileSize || 0, // bytes after compression
    originalSize: videoData.originalSize || 0, // bytes before compression
    compressionRatio: videoData.compressionRatio || 0,
    visibility: videoData.visibility || 'public', // public, network, private
    viewCount: 0,
    lastViewedAt: null,
    likeCount: 0,
    commentCount: 0,
    tags: videoData.tags || [],
    uploadProgress: 0,
    uploadStatus: 'uploading', // uploading, processing, ready, failed
    storageClass: 'standard', // standard, archive
    createdAt: now,
    updatedAt: now,
    deletedAt: null
  };
};

// Validate place video
const validatePlaceVideo = (videoData) => {
  const errors = [];
  
  if (!videoData.placeId || videoData.placeId.trim().length === 0) {
    errors.push('Place ID is required');
  }
  
  if (!videoData.placeName || videoData.placeName.trim().length === 0) {
    errors.push('Place name is required');
  }
  
  if (videoData.duration && videoData.duration > 15) {
    errors.push('Video duration cannot exceed 15 seconds for Reels');
  }
  
  if (videoData.fileSize && videoData.fileSize > 52428800) { // 50MB
    errors.push('Video file size cannot exceed 50MB');
  }
  
  if (videoData.title && videoData.title.length > 100) {
    errors.push('Title must be 100 characters or less');
  }
  
  if (videoData.description && videoData.description.length > 500) {
    errors.push('Description must be 500 characters or less');
  }
  
  const validVisibility = ['public', 'network', 'private'];
  if (videoData.visibility && !validVisibility.includes(videoData.visibility)) {
    errors.push('Invalid visibility setting');
  }
  
  return errors;
};

// UserVideoQuota model structure
const createUserVideoQuota = (userId, tier = 'free') => {
  const now = new Date();
  const currentMonth = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
  
  return {
    userId: userId,
    currentMonth: currentMonth,
    videosUploaded: 0,
    totalSize: 0, // Total bytes this month
    subscriptionTier: tier, // free or premium
    quotaLimit: tier === 'free' ? 5 : 50, // Videos per month
    sizeLimit: tier === 'free' ? 262144000 : 2147483648, // 250MB for free, 2GB for premium
    lastResetDate: now.toISOString(),
    createdAt: now.toISOString(),
    updatedAt: now.toISOString()
  };
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

// Check-in model
const createCheckIn = (checkInData, userId, userData) => {
  const now = new Date().toISOString();
  const startTime = checkInData.startTime || now;
  
  // Calculate end time based on duration
  let endTime;
  if (checkInData.duration === 'until_leave') {
    // Max 6 hours for "until I leave" option
    endTime = new Date(new Date(startTime).getTime() + 6 * 60 * 60 * 1000).toISOString();
  } else {
    const durationMinutes = parseInt(checkInData.duration) || 60;
    endTime = new Date(new Date(startTime).getTime() + durationMinutes * 60 * 1000).toISOString();
  }
  
  return {
    userId: userId,
    userName: userData.displayName || userData.firstName || 'User',
    userPhoto: userData.profilePicture || null,
    placeId: checkInData.placeId || null,
    placeName: checkInData.placeName,
    placeAddress: checkInData.placeAddress,
    location: checkInData.location || null, // GeoPoint will be created in controller
    placeCategory: checkInData.placeCategory || 'other',
    circleId: checkInData.circleId || null, // if place is from user's circle
    message: checkInData.message || '',
    startTime: startTime,
    endTime: endTime,
    duration: checkInData.duration, // '30', '60', '120', 'until_leave'
    
    // Notification settings
    notifiedGroups: checkInData.notifiedGroups || [], // conversation IDs
    notifiedUsers: checkInData.notifiedUsers || [], // individual user IDs
    
    // Activity feed visibility
    showInActivityFeed: checkInData.showInActivityFeed !== false, // default true
    
    // Responses
    responses: [],
    
    active: true,
    createdAt: now,
    updatedAt: now
  };
};

// Validate check-in
const validateCheckIn = (checkInData) => {
  const errors = [];
  
  if (!checkInData.placeName || checkInData.placeName.trim().length === 0) {
    errors.push('Place name is required');
  }
  
  if (!checkInData.placeAddress || checkInData.placeAddress.trim().length === 0) {
    errors.push('Place address is required');
  }
  
  // Must notify at least one group or user
  const hasNotifications = 
    (checkInData.notifiedGroups && checkInData.notifiedGroups.length > 0) ||
    (checkInData.notifiedUsers && checkInData.notifiedUsers.length > 0);
    
  if (!hasNotifications) {
    errors.push('Must select at least one group or person to notify');
  }
  
  if (checkInData.message && checkInData.message.length > 200) {
    errors.push('Message must be 200 characters or less');
  }
  
  const validDurations = ['30', '60', '120', 'until_leave'];
  if (checkInData.duration && !validDurations.includes(checkInData.duration)) {
    errors.push('Invalid duration');
  }
  
  return errors;
};

// Create activity reaction object for Firestore
const createActivityReaction = (reactionData) => {
  const now = new Date().toISOString();
  return {
    activityId: reactionData.activityId,
    userId: reactionData.userId,
    userName: reactionData.userName || 'User',
    userPhoto: reactionData.userPhoto || null,
    emoji: reactionData.emoji, // '❤️', '😍', '😂', '😮', '👍', etc.
    createdAt: now
  };
};

// Create activity comment object for Firestore
const createActivityComment = (commentData) => {
  const now = new Date().toISOString();
  return {
    activityId: commentData.activityId,
    userId: commentData.userId,
    userName: commentData.userName || 'User',
    userPhoto: commentData.userPhoto || null,
    text: commentData.text,
    likes: [],
    likesCount: 0,
    parentCommentId: commentData.parentCommentId || null, // For replies
    replyCount: 0,
    createdAt: now
  };
};

// Validate activity reaction
const validateActivityReaction = (reactionData) => {
  const errors = [];
  
  if (!reactionData.activityId || reactionData.activityId.trim().length === 0) {
    errors.push('Activity ID is required');
  }
  
  if (!reactionData.emoji || reactionData.emoji.trim().length === 0) {
    errors.push('Reaction emoji is required');
  }
  
  // Validate emoji is one of the allowed ones (LinkedIn-style reactions)
  const allowedEmojis = ['👍', '❤️', '🎉', '💪', '💡', '😆'];
  if (!allowedEmojis.includes(reactionData.emoji)) {
    errors.push('Invalid reaction emoji');
  }
  
  return errors;
};

// Validate activity comment
const validateActivityComment = (commentData) => {
  const errors = [];
  
  if (!commentData.activityId || commentData.activityId.trim().length === 0) {
    errors.push('Activity ID is required');
  }
  
  if (!commentData.text || commentData.text.trim().length === 0) {
    errors.push('Comment text is required');
  }
  
  if (commentData.text && commentData.text.length > 500) {
    errors.push('Comment must be 500 characters or less');
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
  createCheckIn,
  createActivityReaction,
  createActivityComment,
  createPlaceVideo,
  createUserVideoQuota,
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
  validateCheckIn,
  validateActivityReaction,
  validateActivityComment,
  validatePlaceVideo,
  serializeDoc,
  serializeQuerySnapshot
};