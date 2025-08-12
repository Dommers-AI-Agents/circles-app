// PlaceMoment Model - Supports videos, photos, carousels, and embedded content
const admin = require('firebase-admin');
const { FieldValue } = admin.firestore;

const CONTENT_TYPES = {
  VIDEO_UPLOADED: 'video_uploaded',
  VIDEO_EMBEDDED: 'video_embedded', 
  PHOTO: 'photo',
  CAROUSEL: 'carousel'
};

const VISIBILITY_LEVELS = {
  PUBLIC: 'public',
  NETWORK: 'network',
  PRIVATE: 'private'
};

// Maximum limits for content
const LIMITS = {
  VIDEO_DURATION: 15, // seconds
  VIDEO_MAX_SIZE: 2 * 1024 * 1024, // 2MB after compression
  PHOTO_MAX_SIZE: 300 * 1024, // 300KB after compression
  CAROUSEL_MAX_PHOTOS: 5,
  CAROUSEL_MAX_TOTAL_SIZE: 1.5 * 1024 * 1024 // 1.5MB total
};

// Create a new PlaceMoment
const createPlaceMoment = (data) => {
  const now = new Date().toISOString();
  
  return {
    // Common fields
    userId: data.userId,
    placeId: data.placeId,
    placeName: data.placeName,
    title: data.title || '',
    description: data.description || '',
    contentType: data.contentType, // video_uploaded, video_embedded, photo, carousel
    visibility: data.visibility || VISIBILITY_LEVELS.PUBLIC,
    tags: data.tags || [],
    
    // Media URLs (for uploaded content)
    mediaUrls: data.mediaUrls || [], // Array for carousel support
    thumbnailUrl: data.thumbnailUrl || null,
    
    // Embedded content fields
    embedUrl: data.embedUrl || null,
    embedPlatform: data.embedPlatform || null, // tiktok, instagram, youtube, twitter
    embedHtml: data.embedHtml || null,
    embedMetadata: data.embedMetadata || null,
    
    // Video specific (for uploaded videos)
    duration: data.duration || null, // Max 15 seconds
    videoUrl: data.videoUrl || null,
    previewUrl: data.previewUrl || null,
    
    // Compression tracking
    fileSize: data.fileSize || 0,
    originalSize: data.originalSize || 0,
    compressionRatio: data.compressionRatio || 0,
    
    // Engagement metrics
    viewCount: 0,
    likeCount: 0,
    commentCount: 0,
    shareCount: 0,
    lastViewedAt: null,
    
    // Timestamps
    createdAt: now,
    updatedAt: now,
    deletedAt: null
  };
};

// Validate moment before creation
const validateMoment = (moment) => {
  const errors = [];
  
  // Validate content type
  if (!Object.values(CONTENT_TYPES).includes(moment.contentType)) {
    errors.push('Invalid content type');
  }
  
  // Validate based on content type
  switch (moment.contentType) {
    case CONTENT_TYPES.VIDEO_UPLOADED:
      if (moment.duration > LIMITS.VIDEO_DURATION) {
        errors.push(`Video duration must be ${LIMITS.VIDEO_DURATION} seconds or less`);
      }
      if (moment.fileSize > LIMITS.VIDEO_MAX_SIZE) {
        errors.push('Video file too large. Please compress further.');
      }
      if (!moment.videoUrl) {
        errors.push('Video URL is required for uploaded videos');
      }
      break;
      
    case CONTENT_TYPES.VIDEO_EMBEDDED:
      if (!moment.embedUrl) {
        errors.push('Embed URL is required for embedded videos');
      }
      if (!moment.embedPlatform) {
        errors.push('Platform must be specified for embedded videos');
      }
      break;
      
    case CONTENT_TYPES.PHOTO:
      if (!moment.mediaUrls || moment.mediaUrls.length === 0) {
        errors.push('Photo URL is required');
      }
      if (moment.fileSize > LIMITS.PHOTO_MAX_SIZE) {
        errors.push('Photo file too large. Please compress further.');
      }
      break;
      
    case CONTENT_TYPES.CAROUSEL:
      if (!moment.mediaUrls || moment.mediaUrls.length === 0) {
        errors.push('At least one photo is required for carousel');
      }
      if (moment.mediaUrls.length > LIMITS.CAROUSEL_MAX_PHOTOS) {
        errors.push(`Maximum ${LIMITS.CAROUSEL_MAX_PHOTOS} photos allowed in carousel`);
      }
      if (moment.fileSize > LIMITS.CAROUSEL_MAX_TOTAL_SIZE) {
        errors.push('Carousel total size too large. Please compress images.');
      }
      break;
  }
  
  // Validate place
  if (!moment.placeId || !moment.placeName) {
    errors.push('Place information is required');
  }
  
  // Validate visibility
  if (!Object.values(VISIBILITY_LEVELS).includes(moment.visibility)) {
    errors.push('Invalid visibility level');
  }
  
  return errors;
};

// Calculate compression ratio
const calculateCompressionRatio = (originalSize, compressedSize) => {
  if (originalSize === 0) return 0;
  return 1 - (compressedSize / originalSize);
};

// Format file size for display
const formatFileSize = (bytes) => {
  if (bytes < 1024) return bytes + ' B';
  if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB';
  return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
};

// Check if content meets compression requirements
const meetsCompressionRequirements = (moment) => {
  switch (moment.contentType) {
    case CONTENT_TYPES.VIDEO_UPLOADED:
      return moment.fileSize <= LIMITS.VIDEO_MAX_SIZE;
    case CONTENT_TYPES.PHOTO:
      return moment.fileSize <= LIMITS.PHOTO_MAX_SIZE;
    case CONTENT_TYPES.CAROUSEL:
      return moment.fileSize <= LIMITS.CAROUSEL_MAX_TOTAL_SIZE;
    case CONTENT_TYPES.VIDEO_EMBEDDED:
      return true; // No storage requirements for embedded
    default:
      return false;
  }
};

// Get storage cost estimate (in USD per month)
const estimateStorageCost = (moment) => {
  const COST_PER_GB = 0.025; // Firebase Storage pricing
  const sizeInGB = moment.fileSize / (1024 * 1024 * 1024);
  return sizeInGB * COST_PER_GB;
};

// Migration helper: Convert old PlaceVideo to PlaceMoment
const migrateFromPlaceVideo = (video) => {
  return {
    ...video,
    contentType: video.videoType === 'embedded' ? 
      CONTENT_TYPES.VIDEO_EMBEDDED : 
      CONTENT_TYPES.VIDEO_UPLOADED,
    mediaUrls: video.videoUrl ? [video.videoUrl] : [],
    fileSize: video.fileSize || 0,
    originalSize: video.originalSize || 0,
    compressionRatio: video.compressionRatio || 0
  };
};

module.exports = {
  CONTENT_TYPES,
  VISIBILITY_LEVELS,
  LIMITS,
  createPlaceMoment,
  validateMoment,
  calculateCompressionRatio,
  formatFileSize,
  meetsCompressionRequirements,
  estimateStorageCost,
  migrateFromPlaceVideo
};