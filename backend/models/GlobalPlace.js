// backend/models/GlobalPlace.js
// Global place model for normalized place data architecture

const { getFirestore } = require('../config/firebase');

// Global Place model structure for normalized place data
const createGlobalPlace = (placeData) => {
  const now = new Date().toISOString();
  
  return {
    // Core place identification
    googlePlaceId: placeData.googlePlaceId || null, // Primary deduplication key
    deduplicationKey: placeData.deduplicationKey, // Key used to identify and merge duplicate places
    legacyPlaceIds: placeData.legacyPlaceIds || [], // Array of original place IDs that were merged into this global place
    name: placeData.name,
    address: placeData.address,
    location: placeData.location, // GeoPoint { type: 'Point', coordinates: [lng, lat] }
    category: placeData.category,
    subcategory: placeData.subcategory || null,
    
    // Unified media with attribution
    photos: placeData.photos || [],
    videos: placeData.videos || [],
    
    // Public content shared across platform
    publicReviews: placeData.publicReviews || [],
    
    // Aggregated statistics
    userContributions: {
      totalPhotos: 0,
      totalVideos: 0, 
      totalReviews: 0,
      contributors: [] // Array of user IDs who have contributed
    },
    
    // Google Places API data (cached)
    googleData: {
      rating: placeData.rating || null,
      userRatingsTotal: placeData.userRatingsTotal || null,
      priceLevel: placeData.priceLevel || null,
      openingHours: placeData.openingHours || null,
      website: placeData.website || null,
      phone: placeData.phone || null,
      lastRefreshedAt: placeData.lastRefreshedAt || null
    },
    
    // Platform statistics
    totalCircleReferences: 0, // How many circles reference this place
    totalUserReferences: 0,   // How many users have added this place
    lastActivityAt: now,      // Last time someone interacted with this place
    
    createdAt: now,
    updatedAt: now,
    deletedAt: null // Soft delete support
  };
};

// Attributed media structure
const createAttributedPhoto = (photoData) => {
  const admin = require('firebase-admin');
  
  return {
    id: photoData.id || admin.firestore().collection('dummy').doc().id, // Generate unique ID
    url: photoData.url,
    uploadedBy: photoData.uploadedBy,
    uploadedByName: photoData.uploadedByName || null,
    uploadedAt: photoData.uploadedAt || new Date().toISOString(),
    source: photoData.source || 'user_upload', // 'user_upload', 'google_places'
    width: photoData.width || null,
    height: photoData.height || null,
    fileSize: photoData.fileSize || null
  };
};

const createAttributedVideo = (videoData) => {
  const admin = require('firebase-admin');
  
  return {
    id: videoData.id || admin.firestore().collection('dummy').doc().id, // Generate unique ID
    videoUrl: videoData.videoUrl,
    thumbnailUrl: videoData.thumbnailUrl || null,
    previewUrl: videoData.previewUrl || null,
    uploadedBy: videoData.uploadedBy,
    uploadedByName: videoData.uploadedByName || null,
    uploadedAt: videoData.uploadedAt || new Date().toISOString(),
    title: videoData.title || '',
    description: videoData.description || '',
    duration: videoData.duration || 0, // seconds
    fileSize: videoData.fileSize || 0,
    source: 'user_upload' // Always user upload for videos
  };
};

// Public review structure
const createPublicReview = (reviewData) => {
  return {
    userId: reviewData.userId,
    userName: reviewData.userName,
    userPhoto: reviewData.userPhoto || null,
    text: reviewData.text,
    rating: reviewData.rating || null, // 1-5 stars
    photos: reviewData.photos || [], // Array of photo URLs from this review
    createdAt: reviewData.createdAt || new Date().toISOString(),
    updatedAt: reviewData.updatedAt || new Date().toISOString(),
    likes: [], // Array of user IDs who liked this review
    likesCount: 0,
    isVerified: reviewData.isVerified || false, // For verified business owners
    helpfulCount: 0, // "Was this helpful?" votes
    reportCount: 0   // Number of times this review was reported
  };
};

// User-Place relationship structure
const createUserPlaceRelation = (relationData) => {
  const now = new Date().toISOString();
  
  return {
    userId: relationData.userId,
    placeId: relationData.placeId, // Reference to globalPlaces collection
    circleId: relationData.circleId,
    
    // User-specific data
    privateNotes: relationData.privateNotes || null,
    personalRating: relationData.personalRating || null,
    visitDates: relationData.visitDates || [],
    tags: relationData.tags || [],
    
    // Relationship metadata
    addedAt: relationData.addedAt || now,
    lastVisited: relationData.lastVisited || null,
    privacy: relationData.privacy || 'followCircle', // followCircle, public, myNetwork, private
    
    // Activity tracking
    lastAccessedAt: now,
    viewCount: 0,
    shareCount: 0,
    
    createdAt: now,
    updatedAt: now
  };
};

// Custom category structure (for user-defined categories)
const createCustomCategory = (categoryData, userId) => {
  const now = new Date().toISOString();
  
  return {
    name: categoryData.name,
    description: categoryData.description || null,
    iconName: categoryData.iconName || 'tag.fill',
    colorHex: categoryData.colorHex || '#718096',
    userId: userId, // Owner of this custom category
    isPublic: categoryData.isPublic || false, // Can other users use this category?
    usageCount: 0, // How many places use this category
    
    createdAt: now,
    updatedAt: now
  };
};

// Place discovery/suggestion structure
const createPlaceDiscovery = (discoveryData) => {
  const now = new Date().toISOString();
  
  return {
    placeId: discoveryData.placeId,
    discoveredBy: discoveryData.discoveredBy, // User ID who discovered/imported this place
    discoveryMethod: discoveryData.discoveryMethod, // 'google_search', 'user_submission', 'check_in', 'import'
    discoveryData: discoveryData.discoveryData || {}, // Additional context about how it was discovered
    
    // Quality metrics
    dataCompleteness: 0.0, // 0.0-1.0 score based on available data
    verificationStatus: 'unverified', // 'unverified', 'user_verified', 'business_verified'
    qualityScore: 0.0, // 0.0-1.0 based on photos, reviews, completeness
    
    createdAt: now
  };
};

// Validation functions
const validateGlobalPlace = (placeData) => {
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
  
  // Validate photos array structure
  if (placeData.photos && Array.isArray(placeData.photos)) {
    placeData.photos.forEach((photo, index) => {
      if (!photo.url || !photo.uploadedBy) {
        errors.push(`Photo at index ${index} missing required fields (url, uploadedBy)`);
      }
    });
  }
  
  // Validate videos array structure
  if (placeData.videos && Array.isArray(placeData.videos)) {
    placeData.videos.forEach((video, index) => {
      if (!video.videoUrl || !video.uploadedBy) {
        errors.push(`Video at index ${index} missing required fields (videoUrl, uploadedBy)`);
      }
    });
  }
  
  return errors;
};

const validateUserPlaceRelation = (relationData) => {
  const errors = [];
  
  if (!relationData.userId || relationData.userId.trim().length === 0) {
    errors.push('User ID is required');
  }
  
  if (!relationData.placeId || relationData.placeId.trim().length === 0) {
    errors.push('Place ID is required');
  }
  
  if (!relationData.circleId || relationData.circleId.trim().length === 0) {
    errors.push('Circle ID is required');
  }
  
  const validPrivacyLevels = ['followCircle', 'public', 'myNetwork', 'private'];
  if (relationData.privacy && !validPrivacyLevels.includes(relationData.privacy)) {
    errors.push('Invalid privacy level');
  }
  
  if (relationData.personalRating && (relationData.personalRating < 1 || relationData.personalRating > 5)) {
    errors.push('Personal rating must be between 1 and 5');
  }
  
  return errors;
};

const validatePublicReview = (reviewData) => {
  const errors = [];
  
  if (!reviewData.userId || reviewData.userId.trim().length === 0) {
    errors.push('User ID is required');
  }
  
  if (!reviewData.userName || reviewData.userName.trim().length === 0) {
    errors.push('User name is required');
  }
  
  if (!reviewData.text || reviewData.text.trim().length === 0) {
    errors.push('Review text is required');
  }
  
  if (reviewData.text && reviewData.text.length > 2000) {
    errors.push('Review text must be 2000 characters or less');
  }
  
  if (reviewData.rating && (reviewData.rating < 1 || reviewData.rating > 5)) {
    errors.push('Rating must be between 1 and 5');
  }
  
  return errors;
};

// Helper functions for data migration
const mergeGooglePlaceData = (existingData, newData) => {
  return {
    rating: newData.rating || existingData.rating,
    userRatingsTotal: newData.userRatingsTotal || existingData.userRatingsTotal,
    priceLevel: newData.priceLevel || existingData.priceLevel,
    openingHours: newData.openingHours || existingData.openingHours,
    website: newData.website || existingData.website,
    phone: newData.phone || existingData.phone,
    lastRefreshedAt: new Date().toISOString()
  };
};

const calculateDataCompleteness = (placeData) => {
  let score = 0.0;
  let maxScore = 10.0;
  
  // Basic data (4 points)
  if (placeData.name) score += 1.0;
  if (placeData.address) score += 1.0;
  if (placeData.location) score += 1.0;
  if (placeData.category) score += 1.0;
  
  // Google data (3 points)
  if (placeData.googleData?.rating) score += 1.0;
  if (placeData.googleData?.phone) score += 1.0;
  if (placeData.googleData?.website) score += 1.0;
  
  // User content (3 points)
  if (placeData.photos?.length > 0) score += 1.0;
  if (placeData.publicReviews?.length > 0) score += 1.0;
  if (placeData.videos?.length > 0) score += 1.0;
  
  return Math.round((score / maxScore) * 100) / 100;
};

const calculateQualityScore = (placeData) => {
  let score = 0.0;
  
  // Data completeness (40%)
  score += calculateDataCompleteness(placeData) * 0.4;
  
  // User engagement (30%)
  const engagementScore = Math.min(1.0, (
    (placeData.photos?.length || 0) * 0.1 +
    (placeData.publicReviews?.length || 0) * 0.2 +
    (placeData.videos?.length || 0) * 0.3 +
    (placeData.userContributions?.contributors?.length || 0) * 0.1
  ) / 2.0);
  score += engagementScore * 0.3;
  
  // Freshness (20%)
  const lastActivity = new Date(placeData.lastActivityAt || placeData.createdAt);
  const daysSinceActivity = (Date.now() - lastActivity.getTime()) / (1000 * 60 * 60 * 24);
  const freshnessScore = Math.max(0, 1.0 - (daysSinceActivity / 365)); // Decay over a year
  score += freshnessScore * 0.2;
  
  // Verification bonus (10%)
  const verificationScore = placeData.googlePlaceId ? 1.0 : 0.5; // Google Places verified gets full score
  score += verificationScore * 0.1;
  
  return Math.round(score * 100) / 100;
};

// Helper function to generate a consistent place key for deduplication
const generatePlaceKey = (place) => {
  // Primary: Use Google Place ID if available
  if (place.googlePlaceId && place.googlePlaceId.trim()) {
    return `google:${place.googlePlaceId}`;
  }
  
  // Fallback: Use normalized name + address
  const normalizedName = place.name.toLowerCase().trim().replace(/[^\w\s]/g, '');
  const normalizedAddress = place.address.toLowerCase().trim().replace(/[^\w\s,]/g, '');
  
  return `manual:${normalizedName}:${normalizedAddress}`;
};

// Collection names for the new architecture
const GLOBAL_COLLECTIONS = {
  GLOBAL_PLACES: 'globalPlaces',
  USER_PLACE_RELATIONS: 'userPlaceRelations', 
  CUSTOM_CATEGORIES: 'customCategories',
  PLACE_DISCOVERIES: 'placeDiscoveries',
  PUBLIC_REVIEWS: 'publicReviews' // Could be embedded in globalPlaces or separate
};

module.exports = {
  GLOBAL_COLLECTIONS,
  createGlobalPlace,
  createAttributedPhoto,
  createAttributedVideo,
  createPublicReview,
  createUserPlaceRelation,
  createCustomCategory,
  createPlaceDiscovery,
  validateGlobalPlace,
  validateUserPlaceRelation,
  validatePublicReview,
  mergeGooglePlaceData,
  calculateDataCompleteness,
  calculateQualityScore,
  generatePlaceKey
};