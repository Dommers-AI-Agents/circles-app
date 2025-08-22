// backend/server.js
require('dotenv').config();
const express = require('express');
const cors = require('cors');
const morgan = require('morgan');
const { initializeFirebase } = require('./config/firebase');
const errorHandler = require('./middleware/errorHandler');
const { 
  generalLimiter, 
  authLimiter, 
  uploadLimiter,
  messageLimiter,
  securityHeaders, 
  sanitizeInput,
  securityLogger 
} = require('./middleware/security');

// CRITICAL ENVIRONMENT VARIABLES for Cloud Run deployment:
// 
// EXISTING ENVIRONMENT VARIABLES (as of January 2025):
// DO NOT OVERWRITE THESE - Use --update-env-vars, NOT --set-env-vars!
// - EMAIL_USER: 'noreply@circles-app.com'
// - APP_URL: 'https://circles-app.com'
// - GMAIL_USER: 'circles.app.notifications@gmail.com'
// - GMAIL_APP_PASSWORD: [app-specific password]
// - JWT_SECRET: [secret key for JWT tokens]
// - JWT_EXPIRE: '30d'
// - FIREBASE_PROJECT_ID: 'circles-app-83b67'
// - FIREBASE_STORAGE_BUCKET: 'circles-app-83b67.appspot.com'
//
// IMPORTANT: Always use --update-env-vars to add/modify variables:
// gcloud run services update circles-backend --update-env-vars KEY=value --region us-central1
//
// NEVER use --set-env-vars as it will DELETE all existing variables!
//
// To fix 500 errors on image upload, ensure FIREBASE_STORAGE_BUCKET is set:
// gcloud run services update circles-backend --update-env-vars FIREBASE_STORAGE_BUCKET=circles-app-83b67.appspot.com --region us-central1

// Initialize Firebase
const firebaseInitialized = initializeFirebase();

// Route imports (Firebase versions)
const firebaseAuthRoutes = require('./routes/firebaseAuthRoutes');
const firebaseUserRoutes = require('./routes/firebaseUserRoutes');
const firebaseCircleRoutes = require('./routes/firebaseCircleRoutes');
const firebasePlaceRoutes = require('./routes/firebasePlaceRoutes');
const uploadRoutes = require('./routes/uploadRoutes');
const linkedinAuthRoutes = require('./routes/linkedinAuthRoutes');
const connectionRoutes = require('./routes/connectionRoutes');
const networkRoutes = require('./routes/networkRoutes');
const messagingRoutes = require('./routes/messagingRoutes');
const suggestionRoutes = require('./routes/suggestionRoutes');
const notificationRoutes = require('./routes/notificationRoutes');
const sseRoutes = require('./routes/sseRoutes');
const activityRoutes = require('./routes/activityRoutes');
const userCategoriesRoutes = require('./routes/userCategoriesRoutes');
const emailTestRoutes = require('./routes/emailTestRoutes');
const userContactsRoutes = require('./routes/userContactsRoutes');
const taskRoutes = require('./routes/taskRoutes');
const visitRoutes = require('./routes/visitRoutes');
const checkInRoutes = require('./routes/checkInRoutes');
const videoRoutes = require('./routes/videoRoutes');

// Import Firebase Place controller for circle-specific routes
const { getPlacesByCircleId, getPlacesByCircleIdPublic, reorderPlacesInCircle } = require('./controllers/firebasePlaceController');
const { protect } = require('./middleware/firebaseAuth');

const app = express();
const path = require('path');

// Request logging middleware
app.use((req, res, next) => {
  // Request logging (reduced verbosity)
  console.log(`🌐 ${req.method} ${req.path}`);
  next();
});

// Middleware - CORS with production security for Cloud Run
const corsOptions = {
  origin: function (origin, callback) {
    // Production allowed origins
    const allowedOrigins = [
      'https://circles-app.com',
      'https://www.circles-app.com',
      'capacitor://localhost', // iOS app
      'ionic://localhost', // iOS app alternative
      'http://localhost' // iOS app WebView
    ];
    
    // Allow requests with no origin (mobile apps, Postman, etc.)
    if (!origin) {
      return callback(null, true);
    }
    
    // In production, check against whitelist
    if (process.env.NODE_ENV === 'production') {
      if (allowedOrigins.some(allowed => origin.startsWith(allowed))) {
        callback(null, true);
      } else {
        console.warn(`🚫 CORS blocked origin: ${origin}`);
        callback(new Error('Not allowed by CORS'));
      }
    } else {
      // In development, allow all origins
      callback(null, true);
    }
  },
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization'],
  exposedHeaders: ['X-RateLimit-Limit', 'X-RateLimit-Remaining', 'X-RateLimit-Reset']
};

app.use(cors(corsOptions));
app.use(express.json({ limit: '50mb' })); // Increased limit for image uploads
app.use(express.urlencoded({ limit: '50mb', extended: true })); // Also handle URL encoded data
app.use(morgan('combined'));

// Security middleware
app.use(securityHeaders);
app.use(securityLogger);
app.use(sanitizeInput);

// Apply general rate limiting to all requests
app.use('/api/', generalLimiter);

// Serve static files from public directory
app.use('/public', express.static(path.join(__dirname, 'public')));

// Images are now served from Firebase Storage, not local filesystem

// Health check
app.get('/', (req, res) => {
  res.json({
    message: 'Circles API with Firebase is running! 🔥',
    timestamp: new Date().toISOString(),
    firebase: firebaseInitialized ? 'Connected' : 'Mock Mode',
    version: '2.0.0'
  });
});

// Route debug middleware (reduced logging)
app.use('/api/users', (req, res, next) => {
  next();
});

// API Routes with specific rate limiting
app.use('/api/auth', authLimiter, firebaseAuthRoutes);
app.use('/api/auth', authLimiter, linkedinAuthRoutes); // LinkedIn auth routes
// Mount categories routes at a separate path to avoid conflicts with user /:id routes
app.use('/api/categories', userCategoriesRoutes);
// Mount contacts routes BEFORE generic user routes to avoid conflicts
app.use('/api/users/contacts', userContactsRoutes);
app.use('/api/users', firebaseUserRoutes);
app.use('/api/circles/groups', require('./routes/circleGroupsRoutes'));
app.use('/api/circles', firebaseCircleRoutes);
app.use('/api/places', firebasePlaceRoutes);
app.use('/api/upload', uploadLimiter, uploadRoutes);
app.use('/api/connections', connectionRoutes);
app.use('/api/network', networkRoutes);
app.use('/api/messages', messageLimiter, messagingRoutes);
app.use('/api/suggestions', suggestionRoutes);
app.use('/api/notifications', notificationRoutes);
app.use('/api/sse', sseRoutes);
app.use('/api', activityRoutes);
app.use('/api/app', require('./routes/appRoutes'));
app.use('/api/email', emailTestRoutes);
app.use('/api/diagnostics', require('./routes/diagnosticRoutes'));
app.use('/api/tasks', taskRoutes);
app.use('/api/visits', visitRoutes);
app.use('/api/check-ins', checkInRoutes);
app.use('/api/videos', videoRoutes);

// Share page route - serves HTML for shared video links
app.get('/share/video/:videoId', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'video-share.html'));
});
app.use('/api/users/subscription', require('./routes/subscriptionRoutes'));
app.use('/api/users/referral', require('./routes/referralRoutes'));
app.use('/api/home', require('./routes/dashboardRoutes'));

// LinkedIn OAuth callback route (outside /api prefix)
const linkedinCallback = require('./routes/linkedinCallback');
app.use('/', linkedinCallback);

// App redirect routes for deep linking from emails
const appRedirectRoutes = require('./routes/appRedirectRoutes');
app.use('/app', appRedirectRoutes);

// Special route for circle-specific places
app.get('/api/circles/:circleId/places', protect, getPlacesByCircleId);
app.get('/api/circles/:circleId/places/public', getPlacesByCircleIdPublic); // Public access endpoint
app.put('/api/circles/:id/places/reorder', protect, reorderPlacesInCircle);

// 404 handler
app.use('*', (req, res) => {
  console.log('❌ 404 Error - Route not found:', req.originalUrl);
  res.status(404).json({
    success: false,
    message: `Route ${req.originalUrl} not found`
  });
});

// Error handling middleware
app.use(errorHandler);

const PORT = process.env.PORT || 8080;

app.listen(PORT, '0.0.0.0', () => {
  console.log(`🚀 Circles API server running on port ${PORT}`);
  console.log(`🔥 Firebase status: ${firebaseInitialized ? 'Connected' : 'Mock Mode'}`);
  console.log(`📊 Environment: ${process.env.NODE_ENV || 'development'}`);
  console.log(`🔐 JWT_SECRET configured: ${!!process.env.JWT_SECRET}`);
  console.log(`🔐 JWT_EXPIRE: ${process.env.JWT_EXPIRE || 'Not set'}`);
  console.log(`📧 Email service configured: ${!!process.env.GMAIL_USER && !!process.env.GMAIL_APP_PASSWORD}`);
  console.log(`🗄️ Firebase Project ID: ${process.env.FIREBASE_PROJECT_ID || 'Not set'}`);
  console.log(`🗄️ Firebase Storage Bucket: ${process.env.FIREBASE_STORAGE_BUCKET || 'Not set'}`);
  
  if (!firebaseInitialized) {
    console.log('\n📝 To enable real Firebase:');
    console.log('   1. Create a Firebase project at https://console.firebase.google.com');
    console.log('   2. Download service account key');
    console.log('   3. Save as backend/config/firebase-service-account.json');
    console.log('   4. Update .env with your Firebase project ID\n');
  }
  
  // Schedule activity cleanup
  const activityService = require('./services/activityService');
  
  // Run cleanup on startup after a delay
  setTimeout(async () => {
    try {
      await activityService.cleanupOldActivity(1); // Keep only last 24 hours
    } catch (error) {
      console.error('❌ Error in initial activity cleanup:', error);
    }
  }, 10000); // Wait 10 seconds after startup
  
  // Schedule daily cleanup
  setInterval(async () => {
    try {
      await activityService.cleanupOldActivity(1); // Keep only last 24 hours
    } catch (error) {
      console.error('❌ Error in scheduled activity cleanup:', error);
    }
  }, 24 * 60 * 60 * 1000); // Run every 24 hours
  
  // Initialize scheduled notifications
  // DISABLED: Using Cloud Scheduler instead of node-cron in production
  // This prevents double execution of scheduled tasks
  // const scheduledNotifications = require('./services/scheduledNotifications');
  // scheduledNotifications.initialize();
  // console.log('🔔 Scheduled notifications initialized');
});