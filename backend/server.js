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
const notificationTestRoutes = require('./routes/notificationTestRoutes');
const globalPlaceRoutes = require('./routes/globalPlaceRoutes');

// Import Firebase Place controller for circle-specific routes
const { getPlacesByCircleId, getPlacesByCircleIdPublic, reorderPlacesInCircle } = require('./controllers/places/placeController');
const { protect } = require('./middleware/firebaseAuth');

const app = express();
const path = require('path');

// Trust proxy for Cloud Run (required for rate limiting)
app.set('trust proxy', 1);

// Request logging middleware
app.use((req, res, next) => {
  // Request logging (reduced verbosity)
  console.log(`🌐 ${req.method} ${req.path}`);
  next();
});

// order.favcircles.com/<slug> is the same app: the ordering host is folded
// onto /order (routes/orderWebRoutes) so one router serves both hosts.
// /order, /public and /.well-known already mean the same thing there.
const ORDER_HOST = (process.env.ORDER_PAGE_BASE_URL || 'https://order.favcircles.com').replace(/^https?:\/\//, '').split('/')[0];
app.use((req, res, next) => {
  const host = String(req.headers.host || '').split(':')[0].toLowerCase();
  if (host === ORDER_HOST && !/^\/(order(\/|$)|public\/|\.well-known\/)/.test(req.url)) {
    req.url = `/order${req.url === '/' ? '' : req.url}`;
    req.orderHost = true;
  }
  next();
});

// Middleware - CORS with production security for Cloud Run
const corsOptions = {
  origin: function (origin, callback) {
    // Production allowed origins
    const allowedOrigins = [
      'https://circles-app.com',
      'https://www.circles-app.com',
      'https://favcircles.com',
      'https://www.favcircles.com',
      'https://api.favcircles.com', // the admin dashboard, served by this server
      'https://order.favcircles.com', // store ordering pages (routes/orderWebRoutes)
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
      // Exact match: the old startsWith let look-alikes such as
      // https://favcircles.com.evil.example through (security audit 2026-10-01)
      if (allowedOrigins.includes(origin) || /^http:\/\/localhost(:\d+)?$/.test(origin)) {
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

// gzip responses. The SSE stream must be excluded: compression buffers the
// response body, which would hold events in the gzip buffer indefinitely.
const compression = require('compression');
app.use(compression({
  // req.originalUrl, NOT req.path: compression evaluates this filter at
  // header-write time, when mounted routers have already rewritten req.path
  // (inside sseRoutes it's just '/stream', which would dodge the exclusion).
  filter: (req, res) => req.originalUrl.startsWith('/api/sse')
    ? false
    : compression.filter(req, res)
}));

// Force revalidation on API GETs: Express emits weak ETags but no
// Cache-Control, and without one URLSession applies heuristic freshness and
// may serve stale responses without contacting the server. no-cache =
// "revalidate every time" (304 when unchanged), never "don't cache".
app.use('/api', (req, res, next) => {
  if (req.method === 'GET') {
    res.set('Cache-Control', 'no-cache');
  }
  next();
});

// One memo per GET: connections, Inner Circle lists and the viewer's user doc
// are read once however many helpers ask (utils/requestMemo).
app.use('/api', require('./utils/requestMemo').requestMemoMiddleware);

// Vendor webhooks for printed postcards. These MUST be mounted above the
// JSON parser below: both Stripe and Lob sign the raw request body, and a
// parsed-then-restringified body no longer matches the signature. They also
// arrive with no JWT, which is why they can't live on the widget router.
{
  const postcardMail = require('./controllers/widgets/postcardMailController');
  const rawJson = express.raw({ type: 'application/json' });
  app.post('/api/widgets/postcard/mail/stripe-webhook', rawJson, postcardMail.stripeWebhook);
  app.post('/api/widgets/postcard/mail/lob-webhook', rawJson, postcardMail.lobWebhook);
}

// Body limits (security audit 2026-10-01): a 50 MB global JSON limit let any
// anonymous caller make every instance buffer and parse 50 MB per request.
// The global limit is 1 MB; the few routes that legitimately take bigger JSON
// get their own parser first (body-parser skips a body already parsed):
//   /api/upload                        base64 image, capped at 1 MB of chars + envelope
//   /api/widgets/postcard/mail/upload  base64 print artwork, capped at 6 MB
//   /api/import                        up to 300 places per call, with notes
//   /api/users/contacts                the whole address book in one sync (unchunked on iOS)
//   /api/users/subscription            base64 App Store receipt, grows with purchase history
app.use('/api/upload', express.json({ limit: '2mb' }));
app.use('/api/users/subscription', express.json({ limit: '2mb' }));
app.use('/api/widgets/postcard/mail/upload', express.json({ limit: '8mb' }));
app.use('/api/widgets/workouts/history', express.json({ limit: '3mb' }));
app.use('/api/import', express.json({ limit: '5mb' }));
app.use('/api/users/contacts', express.json({ limit: '5mb' }));
// Store-owner scans: up to 4 photos as base64 (≤ 8 MB decoded, services/scan/images)
app.use(/^\/api\/rewards\/venues\/[^/]+\/scan$/, express.json({ limit: '12mb' }));
app.use(express.json({ limit: '1mb' }));
// Mirror message<->error keys on all error responses (see middleware file)
app.use(require('./middleware/responseNormalizer'));
app.use(express.urlencoded({ limit: '1mb', extended: true })); // Also handle URL encoded data
app.use(morgan('tiny'));

// Security middleware
app.use(securityHeaders);
app.use(securityLogger);
// 5xx spike → admin alert (security audit 2026-10-01)
app.use(require('./middleware/errorRateMonitor').errorRateMonitor());
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

// Apple App Site Association file for Universal Links
app.get('/.well-known/apple-app-site-association', (req, res) => {
  res.setHeader('Content-Type', 'application/json');
  res.sendFile(path.join(__dirname, 'public', 'apple-app-site-association'));
});

// Also serve at root for compatibility
app.get('/apple-app-site-association', (req, res) => {
  res.setHeader('Content-Type', 'application/json');
  res.sendFile(path.join(__dirname, 'public', 'apple-app-site-association'));
});

// Shared-link pages (connect, circle, place, user, widget, tab, quote, event,
// club, run, workout, postcard, store ordering) — routes/sharePageRoutes.js
app.use(require('./routes/sharePageRoutes'));

// Route debug middleware (reduced logging)
app.use('/api/users', (req, res, next) => {
  next();
});

// Opening something settles the bell rows about it (red dot clears)
app.use('/api', require('./middleware/notificationSeen'));

// API Routes with specific rate limiting
app.use('/api/auth', authLimiter, firebaseAuthRoutes);
app.use('/api/auth', authLimiter, linkedinAuthRoutes); // LinkedIn auth routes
// Mount categories routes at a separate path to avoid conflicts with user /:id routes
app.use('/api/categories', userCategoriesRoutes);
// Mount contacts routes BEFORE generic user routes to avoid conflicts
// Subscription routes MUST mount before the general /api/users routers: those
// apply router-level auth, and an express app dispatches in mount order — the
// Apple webhook (public by design) was being captured there and 401'd, so NO
// App Store notification (renewal, cancellation, refund) was ever processed.
app.use('/api/users/subscription', require('./routes/subscriptionRoutes'));
app.use('/api/users/contacts', userContactsRoutes);
app.use('/api/users', firebaseUserRoutes);
app.use('/api/circles/groups', require('./routes/circleGroupsRoutes'));
app.use('/api/circles', firebaseCircleRoutes);
app.use('/api/places', globalPlaceRoutes); // Global places routes (must come first - more specific)
app.use('/api/places', firebasePlaceRoutes);
app.use('/api/upload', uploadLimiter, uploadRoutes);
app.use('/api/import', require('./routes/importRoutes')); // Import places from other platforms (Mapstr, Google, Swarm)
app.use('/api/browse', require('./routes/browseRoutes')); // Location/category browse lens over saved places
app.use('/api/connections', connectionRoutes);
app.use('/api/network', networkRoutes);
app.use('/api/messages', messageLimiter, messagingRoutes);
app.use('/api/suggestions', suggestionRoutes);
app.use('/api/notifications', notificationRoutes);
app.use('/api/sse', sseRoutes);
app.use('/api', activityRoutes);
app.use('/api/app', require('./routes/appRoutes'));
// Block / unblock (App Store guideline 1.2). The router existed but was never
// mounted, so every block in the app failed with a 404 (security audit 2026-10-01).
app.use('/api/blocks', require('./routes/blockRoutes'));
app.use('/api/email', require('./routes/emailPreferenceRoutes')); // one-click unsubscribe, signed links
// Test sends take any `toEmail` — an open relay from favcircles.com in
// production (security audit 2026-10-01). Local/dev only.
if (process.env.NODE_ENV !== 'production') app.use('/api/email', emailTestRoutes);
app.use('/api/contact', require('./routes/contactRoutes')); // Website contact form (public)
// Business values the app shows (limits, amounts, App Store link) — one source (public)
app.get('/api/config/client', require('./controllers/clientConfigController').getClientConfig);
app.use('/api/diagnostics', require('./routes/diagnosticRoutes'));
app.use('/api/tasks', taskRoutes);
app.use('/api/trash', require('./routes/trashRoutes'));
// User/content reporting — required for store compliance (Play + App Store)
app.use('/api/reports', require('./routes/reportRoutes'));
app.use('/api/visits', visitRoutes);
app.use('/api/check-ins', checkInRoutes);
app.use('/api/videos', videoRoutes);

// Shared moment: the page (per-moment link-card tags) and its preview image
const videoShare = require('./controllers/video/videoShareController');
app.get('/share/video/:videoId/preview.jpg', videoShare.sharePreviewImage);
app.get('/share/video/:videoId', videoShare.renderSharePage);
app.use('/api/users/referral', require('./routes/referralRoutes'));
app.use('/api/rewards', require('./routes/rewardRoutes'));
app.use('/api/clip', require('./routes/clipRoutes')); // iOS App Clip (public venue preview + install conversion)
app.use('/api/leads', require('./routes/leadRoutes')); // favcircles.com email capture (public)
app.use('/api/piggy-bank', require('./routes/piggyBankRoutes')); // FavCoin piggy bank (separate from store-loyalty rewards)
app.use('/api/home', require('./routes/dashboardRoutes'));
// Order ahead from a store's menu, pay at pickup (services/orders)
app.use('/api/orders', require('./routes/orderRoutes'));
app.use('/api/widgets', require('./routes/widgetRoutes')); // Home Widgets tab: per-widget JSON docs + postcard send

// Notification test routes (development only)
if (process.env.NODE_ENV !== 'production') {
  app.use('/api/notifications/test', notificationTestRoutes);
  console.log('🔔 Notification test routes enabled at /api/notifications/test/*');
}

// LinkedIn OAuth callback route (outside /api prefix)
const linkedinCallback = require('./routes/linkedinCallback');
app.use('/', linkedinCallback);

// App redirect routes for deep linking from emails
const appRedirectRoutes = require('./routes/appRedirectRoutes');
app.use('/app', appRedirectRoutes);

// Partner link-outs: the Reserve chip lands on the restaurant's OpenTable page
app.get('/go/opentable', require('./controllers/opentableLinkController').redirect);

// Admin dashboard: the page is public HTML (it asks you to sign in); every
// number comes from /api/admin/dashboard, which is super-user only.
app.use('/api/admin/dashboard', require('./routes/adminDashboardRoutes'));
// The app-wide CSP only allows our own scripts; the dashboard also loads
// Chart.js from cdnjs and the Inter font from Google Fonts.
const ADMIN_CSP = [
  "default-src 'self'",
  "script-src 'self' https://cdnjs.cloudflare.com",
  "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com",
  "font-src 'self' https://fonts.gstatic.com",
  "img-src 'self' data: https:",
  "connect-src 'self'",
  "object-src 'none'",
  "base-uri 'self'",
  "form-action 'self'",
  "frame-ancestors 'none'",
  "script-src-attr 'none'"
].join('; ');
const adminFile = (file, type) => (req, res) => {
  res.set('Content-Security-Policy', ADMIN_CSP);
  res.set('X-Robots-Tag', 'noindex, nofollow');
  res.set('Cache-Control', 'no-cache');
  if (type) res.type(type);
  res.sendFile(path.join(__dirname, 'public', 'admin', file));
};
app.get(['/admin', '/admin/'], adminFile('index.html'));
app.get('/admin/app.js', adminFile('app.js', 'application/javascript'));

// Physical sticker QR landing pages (public; AASA covers /s/* for Universal Links)
app.use('/s', require('./routes/stickerPublicRoutes'));

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

// A production instance without its signing secret must not serve
require('./config/secrets').assertSecretsAtBoot();

const PORT = process.env.PORT || 8080;

app.listen(PORT, '0.0.0.0', () => {
  console.log(`🚀 Circles API server running on port ${PORT}`);
  console.log(`🔥 Firebase status: ${firebaseInitialized ? 'Connected' : 'Mock Mode'}`);
  console.log(`📊 Environment: ${process.env.NODE_ENV || 'development'}`);
  console.log(`🔐 JWT_SECRET configured: ${!!process.env.JWT_SECRET}`);
  console.log(`🔐 JWT_EXPIRE: ${process.env.JWT_EXPIRE || 'Not set'}`);
  console.log(`📧 Email service configured: ${require('./services/emailService').isConfigured === true} (${process.env.EMAIL_SERVICE || 'gmail'})`);
  console.log(`🗄️ Firebase Project ID: ${process.env.FIREBASE_PROJECT_ID || 'Not set'}`);
  console.log(`🗄️ Firebase Storage Bucket: ${process.env.FIREBASE_STORAGE_BUCKET || 'Not set'}`);
  
  // dataAggregationJob deliberately NOT started (2026-08-20): it fed a
  // per-instance in-memory warm cache consumed only by /home/homescreen's
  // fast path, whose hit rate across Cloud Run instances was ~zero — every
  // instance paid recurring Firestore reads every 10 minutes for a cache
  // nobody hit. The endpoint's live path (which effectively always ran) is
  // untouched; delete the endpoint + backgroundAggregationService once the
  // App Store build that stops calling it has rolled out.
  
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