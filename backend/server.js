// backend/server.js
require('dotenv').config();
const express = require('express');
const cors = require('cors');
const morgan = require('morgan');
const { initializeFirebase } = require('./config/firebase');
const errorHandler = require('./middleware/errorHandler');

// Initialize Firebase
const firebaseInitialized = initializeFirebase();

// Route imports (Firebase versions)
const firebaseAuthRoutes = require('./routes/firebaseAuthRoutes');
const firebaseUserRoutes = require('./routes/firebaseUserRoutes');
const firebaseCircleRoutes = require('./routes/firebaseCircleRoutes');
const firebasePlaceRoutes = require('./routes/firebasePlaceRoutes');
const uploadRoutes = require('./routes/uploadRoutes');

// Import Firebase Place controller for circle-specific routes
const { getPlacesByCircleId } = require('./controllers/firebasePlaceController');
const { protect } = require('./middleware/firebaseAuth');

const app = express();

// Middleware
app.use(cors({
  origin: true, // Allow all origins in development
  credentials: true
}));
app.use(express.json({ limit: '10mb' })); // Increase limit for image uploads
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

// API Routes
app.use('/api/auth', firebaseAuthRoutes);
app.use('/api/users', firebaseUserRoutes);
app.use('/api/circles', firebaseCircleRoutes);
app.use('/api/places', firebasePlaceRoutes);
app.use('/api/upload', uploadRoutes);

// LinkedIn OAuth callback route (outside /api prefix)
const linkedinCallback = require('./routes/linkedinCallback');
app.use('/', linkedinCallback);

// Special route for circle-specific places
app.get('/api/circles/:circleId/places', protect, getPlacesByCircleId);

// 404 handler
app.use('*', (req, res) => {
  res.status(404).json({
    success: false,
    message: `Route ${req.originalUrl} not found`
  });
});

// Error handling middleware
app.use(errorHandler);

const PORT = process.env.PORT || 3001;

app.listen(PORT, () => {
  console.log(`🚀 Circles API server running on port ${PORT}`);
  console.log(`🔥 Firebase status: ${firebaseInitialized ? 'Connected' : 'Mock Mode'}`);
  console.log(`📊 Environment: ${process.env.NODE_ENV || 'development'}`);
  
  if (!firebaseInitialized) {
    console.log('\n📝 To enable real Firebase:');
    console.log('   1. Create a Firebase project at https://console.firebase.google.com');
    console.log('   2. Download service account key');
    console.log('   3. Save as backend/config/firebase-service-account.json');
    console.log('   4. Update .env with your Firebase project ID\n');
  }
});