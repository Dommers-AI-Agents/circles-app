// backend/models/FirestoreModels.js
// Firestore collection models and validation

const { getFirestore } = require('../config/firebase');

// Collection names
const COLLECTIONS = {
  USERS: 'users',
  CIRCLES: 'circles', 
  PLACES: 'places',
  FRIEND_REQUESTS: 'friendRequests'
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
    privacy: circleData.privacy || 'friends', // public, friends, private
    category: circleData.category || 'other', // travel, food, services, shopping, healthcare, entertainment, other
    location: circleData.location || null,
    tags: circleData.tags || [],
    sharedWith: circleData.sharedWith || [],
    followers: circleData.followers || [],
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
    rating: placeData.rating || null,
    notes: placeData.notes || null,
    tags: placeData.tags || [],
    reviews: placeData.reviews || [],
    openingHours: placeData.openingHours || null,
    priceLevel: placeData.priceLevel || null,
    circleId: circleId,
    addedBy: addedBy,
    privacy: placeData.privacy || 'followCircle', // followCircle, public, friends, private
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
  
  const validPrivacyLevels = ['public', 'friends', 'private'];
  if (circleData.privacy && !validPrivacyLevels.includes(circleData.privacy)) {
    errors.push('Privacy must be public, friends, or private');
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
                          'education', 'outdoor', 'transport', 'finance', 'other'];
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

module.exports = {
  COLLECTIONS,
  createUser,
  createCircle,
  createPlace,
  createFriendRequest,
  validateCircle,
  validatePlace,
  serializeDoc,
  serializeQuerySnapshot
};