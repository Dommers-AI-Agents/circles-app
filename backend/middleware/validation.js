// Input validation middleware using express-validator
const { body, param, query, validationResult } = require('express-validator');

// Helper function to check validation results
const handleValidationErrors = (req, res, next) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    console.warn(`⚠️ Validation errors on ${req.path}:`, errors.array());
    
    // Group errors by field for better client-side handling
    const fieldErrors = {};
    const errorArray = errors.array();
    
    errorArray.forEach(error => {
      const field = error.path || error.param;
      if (!fieldErrors[field]) {
        fieldErrors[field] = [];
      }
      fieldErrors[field].push(error.msg);
    });
    
    // Create a user-friendly message based on the first error
    let userMessage = 'Validation failed';
    if (errorArray.length > 0) {
      const firstError = errorArray[0];
      const field = firstError.path || firstError.param;
      userMessage = `${field}: ${firstError.msg}`;
    }
    
    return res.status(400).json({
      success: false,
      message: userMessage,
      errors: fieldErrors,
      rawErrors: errorArray // Keep raw errors for backwards compatibility
    });
  }
  next();
};

// User registration validation
exports.validateUserRegistration = [
  body('email')
    .isEmail()
    .normalizeEmail()
    .withMessage('Please enter a valid email address'),
  body('password')
    .custom((value) => {
      const errors = [];
      
      if (!value || value.length < 8) {
        errors.push('Password must be at least 8 characters long');
      }
      
      if (value && !/[A-Z]/.test(value)) {
        errors.push('Password must contain at least one uppercase letter');
      }
      
      if (value && !/[a-z]/.test(value)) {
        errors.push('Password must contain at least one lowercase letter');
      }
      
      if (value && !/\d/.test(value)) {
        errors.push('Password must contain at least one number');
      }
      
      if (errors.length > 0) {
        throw new Error(errors.join(', '));
      }
      
      return true;
    }),
  body('displayName')
    .trim()
    .isLength({ min: 2, max: 50 })
    .withMessage('Display name must be between 2 and 50 characters')
    .matches(/^[a-zA-Z0-9\s._-]+$/)
    .withMessage('Display name can only contain letters, numbers, spaces, dots, underscores, and hyphens'),
  handleValidationErrors
];

// User login validation
exports.validateUserLogin = [
  body('email')
    .isEmail()
    .normalizeEmail()
    .withMessage('Valid email is required'),
  body('password')
    .notEmpty()
    .withMessage('Password is required'),
  handleValidationErrors
];

// Circle creation validation
exports.validateCircleCreation = [
  body('name')
    .trim()
    .isLength({ min: 1, max: 50 })
    .withMessage('Circle name must be between 1 and 50 characters'),
  body('description')
    .optional()
    .trim()
    .isLength({ max: 500 })
    .withMessage('Description must be less than 500 characters'),
  body('privacy')
    .isIn(['public', 'myNetwork', 'private'])
    .withMessage('Invalid privacy setting'),
  body('category')
    .optional()
    .isIn(['travel', 'food', 'services', 'shopping', 'healthcare', 'entertainment', 'other'])
    .withMessage('Invalid category'),
  handleValidationErrors
];

// Place creation validation
exports.validatePlaceCreation = [
  body('name')
    .trim()
    .isLength({ min: 1, max: 100 })
    .withMessage('Place name must be between 1 and 100 characters'),
  body('address')
    .trim()
    .isLength({ min: 1, max: 200 })
    .withMessage('Address must be between 1 and 200 characters'),
  body('location.coordinates')
    .isArray({ min: 2, max: 2 })
    .withMessage('Coordinates must be [longitude, latitude]'),
  body('location.coordinates.*')
    .isFloat()
    .withMessage('Coordinates must be valid numbers'),
  body('category')
    .isIn(['restaurant', 'cafe', 'bar', 'hotel', 'retail', 'service', 'attraction', 
           'entertainment', 'healthcare', 'fitness', 'education', 'outdoor', 
           'transport', 'finance', 'home', 'work', 'other'])
    .withMessage('Invalid category'),
  body('notes')
    .optional()
    .trim()
    .isLength({ max: 1000 })
    .withMessage('Notes must be less than 1000 characters'),
  handleValidationErrors
];

// Message validation
exports.validateMessage = [
  body('text')
    .if(body('type').equals('text'))
    .trim()
    .isLength({ min: 1, max: 5000 })
    .withMessage('Message must be between 1 and 5000 characters'),
  body('type')
    .isIn(['text', 'image', 'location', 'circle_share', 'place_share'])
    .withMessage('Invalid message type'),
  body('conversationId')
    .notEmpty()
    .withMessage('Conversation ID is required'),
  handleValidationErrors
];

// Video upload validation
exports.validateVideoUpload = [
  body('placeId')
    .notEmpty()
    .withMessage('Place ID is required'),
  body('placeName')
    .trim()
    .isLength({ min: 1, max: 100 })
    .withMessage('Place name must be between 1 and 100 characters'),
  body('duration')
    .isInt({ min: 0, max: 3600 })
    .withMessage('Duration must be between 0 and 3600 seconds'),
  body('fileSize')
    .isInt({ min: 0, max: 104857600 }) // 100MB max
    .withMessage('File size must be less than 100MB'),
  body('visibility')
    .isIn(['public', 'network', 'private'])
    .withMessage('Invalid visibility setting'),
  handleValidationErrors
];

// Comment validation
exports.validateComment = [
  body('text')
    .trim()
    .isLength({ min: 1, max: 500 })
    .withMessage('Comment must be between 1 and 500 characters'),
  handleValidationErrors
];

// MongoDB ObjectId validation
exports.validateObjectId = (paramName) => [
  param(paramName)
    .matches(/^[a-fA-F0-9]{24}$|^[a-zA-Z0-9_-]+$/)
    .withMessage(`Invalid ${paramName}`),
  handleValidationErrors
];

// Pagination validation
exports.validatePagination = [
  query('limit')
    .optional()
    .isInt({ min: 1, max: 100 })
    .withMessage('Limit must be between 1 and 100'),
  query('offset')
    .optional()
    .isInt({ min: 0 })
    .withMessage('Offset must be a positive number'),
  handleValidationErrors
];

// Search query validation
exports.validateSearchQuery = [
  query('q')
    .trim()
    .isLength({ min: 1, max: 100 })
    .withMessage('Search query must be between 1 and 100 characters')
    .matches(/^[a-zA-Z0-9\s._-]+$/)
    .withMessage('Search query contains invalid characters'),
  handleValidationErrors
];

// URL validation for embedded videos
exports.validateVideoUrl = [
  body('url')
    .isURL({ protocols: ['http', 'https'] })
    .withMessage('Invalid URL')
    .custom((value) => {
      const allowedDomains = [
        'youtube.com', 'youtu.be',
        'tiktok.com',
        'instagram.com',
        'twitter.com', 'x.com'
      ];
      const url = new URL(value);
      const isAllowed = allowedDomains.some(domain => 
        url.hostname.includes(domain)
      );
      if (!isAllowed) {
        throw new Error('URL must be from YouTube, TikTok, Instagram, or Twitter/X');
      }
      return true;
    }),
  handleValidationErrors
];

module.exports = {
  handleValidationErrors,
  ...exports
};