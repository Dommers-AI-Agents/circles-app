// Security middleware for production deployment
const rateLimit = require('express-rate-limit');
const helmet = require('helmet');

// Rate limiting configurations for different endpoints
const createRateLimiter = (windowMs, max, message) => {
  return rateLimit({
    windowMs,
    max,
    message,
    standardHeaders: true,
    legacyHeaders: false,
    // Store configuration for Cloud Run (uses memory by default)
    handler: (req, res) => {
      console.warn(`🚫 Rate limit exceeded for ${req.ip} on ${req.path}`);
      res.status(429).json({
        success: false,
        message: message || 'Too many requests, please try again later.'
      });
    }
  });
};

// General API rate limiter
exports.generalLimiter = createRateLimiter(
  15 * 60 * 1000, // 15 minutes
  2000, // limit each IP to 2000 requests per windowMs (increased to prevent blocking legitimate users)
  'Too many requests from this IP, please try again later.'
);

// Strict rate limiter for auth endpoints
exports.authLimiter = createRateLimiter(
  15 * 60 * 1000, // 15 minutes
  50, // limit each IP to 50 requests per windowMs (increased for better UX)
  'Too many authentication attempts, please try again later.'
);

// Upload rate limiter
exports.uploadLimiter = createRateLimiter(
  60 * 60 * 1000, // 1 hour
  50, // limit each IP to 50 uploads per hour
  'Upload limit exceeded, please try again later.'
);

// Message rate limiter
exports.messageLimiter = createRateLimiter(
  60 * 1000, // 1 minute
  60, // limit each IP to 60 messages per minute
  'Message rate limit exceeded, please slow down.'
);

// Security headers middleware using Helmet
exports.securityHeaders = helmet({
  contentSecurityPolicy: {
    directives: {
      defaultSrc: ["'self'"],
      styleSrc: ["'self'", "'unsafe-inline'"],
      scriptSrc: ["'self'"],
      imgSrc: ["'self'", "data:", "https:", "blob:"],
      connectSrc: ["'self'"],
      fontSrc: ["'self'"],
      objectSrc: ["'none'"],
      mediaSrc: ["'self'", "https:"],
      frameSrc: ["'self'", "https://www.tiktok.com", "https://www.instagram.com", "https://www.youtube.com"]
    }
  },
  crossOriginEmbedderPolicy: false // Allow embedding from social media platforms
});

// Input sanitization middleware
exports.sanitizeInput = (req, res, next) => {
  // Recursively sanitize strings in request body
  const sanitize = (obj) => {
    if (typeof obj === 'string') {
      // Remove any script tags and dangerous HTML
      return obj
        .replace(/<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>/gi, '')
        .replace(/<iframe\b[^<]*(?:(?!<\/iframe>)<[^<]*)*<\/iframe>/gi, '')
        .replace(/javascript:/gi, '')
        .replace(/on\w+\s*=/gi, ''); // Remove event handlers
    } else if (Array.isArray(obj)) {
      return obj.map(sanitize);
    } else if (obj !== null && typeof obj === 'object') {
      const sanitized = {};
      for (const key in obj) {
        if (obj.hasOwnProperty(key)) {
          sanitized[key] = sanitize(obj[key]);
        }
      }
      return sanitized;
    }
    return obj;
  };

  if (req.body) {
    req.body = sanitize(req.body);
  }
  
  next();
};

// Request size limiter (already handled by express.json, but adding for clarity)
exports.requestSizeLimiter = (req, res, next) => {
  const contentLength = req.headers['content-length'];
  const maxSize = 50 * 1024 * 1024; // 50MB
  
  if (contentLength && parseInt(contentLength) > maxSize) {
    return res.status(413).json({
      success: false,
      message: 'Request entity too large'
    });
  }
  
  next();
};

// Security logging middleware
exports.securityLogger = (req, res, next) => {
  // Log suspicious activities
  const suspiciousPatterns = [
    /\.\.\//, // Directory traversal
    /<script/i, // Script tags
    /union.*select/i, // SQL injection attempts
    /\' or \'/i, // SQL injection attempts
    /exec\(/i, // Command execution
    /eval\(/i // Code evaluation
  ];
  
  const checkSuspicious = (str) => {
    if (typeof str !== 'string') return false;
    return suspiciousPatterns.some(pattern => pattern.test(str));
  };
  
  // Check URL
  if (checkSuspicious(req.url)) {
    console.error(`🚨 SECURITY: Suspicious URL pattern detected from ${req.ip}: ${req.url}`);
  }
  
  // Check body
  if (req.body) {
    const bodyStr = JSON.stringify(req.body);
    if (checkSuspicious(bodyStr)) {
      console.error(`🚨 SECURITY: Suspicious body content from ${req.ip}: ${req.path}`);
    }
  }
  
  next();
};