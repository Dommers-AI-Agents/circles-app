// backend/server.js
require('dotenv').config();
const express = require('express');
const cors = require('cors');
const morgan = require('morgan');
const { initializeFirebase } = require('./config/firebase');
const errorHandler = require('./middleware/errorHandler');

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

// Import Firebase Place controller for circle-specific routes
const { getPlacesByCircleId, getPlacesByCircleIdPublic, reorderPlacesInCircle } = require('./controllers/firebasePlaceController');
const { protect } = require('./middleware/firebaseAuth');

const app = express();

// Request logging middleware
app.use((req, res, next) => {
  console.log('🌐 SERVER: Incoming request');
  console.log('🌐 SERVER: Method:', req.method);
  console.log('🌐 SERVER: Path:', req.path);
  console.log('🌐 SERVER: Query:', JSON.stringify(req.query));
  console.log('🌐 SERVER: Headers:', JSON.stringify(req.headers, null, 2));
  next();
});

// Middleware
app.use(cors({
  origin: true, // Allow all origins in development
  credentials: true
}));
app.use(express.json({ limit: '50mb' })); // Increased limit for image uploads
app.use(express.urlencoded({ limit: '50mb', extended: true })); // Also handle URL encoded data
app.use(morgan('combined'));

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

// Debug middleware for all user routes
app.use('/api/users', (req, res, next) => {
  console.log('🔍 User route hit:', req.method, req.path, req.originalUrl);
  if (req.path.includes('categories')) {
    console.log('✅ Categories path detected in user route');
  }
  next();
});

// API Routes
app.use('/api/auth', firebaseAuthRoutes);
app.use('/api/auth', linkedinAuthRoutes); // LinkedIn auth routes
// Mount categories routes at a separate path to avoid conflicts with user /:id routes
app.use('/api/categories', userCategoriesRoutes);
app.use('/api/users', firebaseUserRoutes);
app.use('/api/circles', firebaseCircleRoutes);
app.use('/api/places', firebasePlaceRoutes);
app.use('/api/upload', uploadRoutes);
app.use('/api/connections', connectionRoutes);
app.use('/api/network', networkRoutes);
app.use('/api/messages', messagingRoutes);
app.use('/api/suggestions', suggestionRoutes);
app.use('/api/notifications', notificationRoutes);
app.use('/api/sse', sseRoutes);
app.use('/api', activityRoutes);
app.use('/api/app', require('./routes/appRoutes'));
app.use('/api/email', emailTestRoutes);

// LinkedIn OAuth callback route (outside /api prefix)
const linkedinCallback = require('./routes/linkedinCallback');
app.use('/', linkedinCallback);

// Special route for circle-specific places
app.get('/api/circles/:circleId/places', protect, getPlacesByCircleId);
app.get('/api/circles/:circleId/places/public', getPlacesByCircleIdPublic); // Public access endpoint
app.put('/api/circles/:id/places/reorder', protect, reorderPlacesInCircle);

// 404 handler
app.use('*', (req, res) => {
  console.log('❌ 404 Error - Route not found:', req.originalUrl);
  console.log('❌ Method:', req.method);
  console.log('❌ Headers:', req.headers);
  res.status(404).json({
    success: false,
    message: `Route ${req.originalUrl} not found`
  });
});

// Error handling middleware
app.use(errorHandler);

const PORT = process.env.PORT || 3001;

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
    console.log('🧹 Running initial activity cleanup...');
    try {
      await activityService.cleanupOldActivity(1); // Keep only last 24 hours
      console.log('✅ Initial activity cleanup completed');
    } catch (error) {
      console.error('❌ Error in initial activity cleanup:', error);
    }
  }, 10000); // Wait 10 seconds after startup
  
  // Schedule daily cleanup
  setInterval(async () => {
    console.log('🧹 Running scheduled daily activity cleanup...');
    try {
      await activityService.cleanupOldActivity(1); // Keep only last 24 hours
      console.log('✅ Scheduled activity cleanup completed');
    } catch (error) {
      console.error('❌ Error in scheduled activity cleanup:', error);
    }
  }, 24 * 60 * 60 * 1000); // Run every 24 hours
});