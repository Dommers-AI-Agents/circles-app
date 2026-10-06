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
app.use('/api/import', express.json({ limit: '5mb' }));
app.use('/api/users/contacts', express.json({ limit: '5mb' }));
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

// Connection invite link. With the Circles app installed, iOS opens this URL
// directly as a Universal Link (AASA paths include /connect/*) and
// auto-connects the two users — this handler is never hit. Without the app,
// the page tries the custom scheme (covers in-app browsers) then falls back
// to the App Store.
app.get('/connect/:userId', async (req, res) => {
  const userId = String(req.params.userId).replace(/[^a-zA-Z0-9_-]/g, '');
  // Carry the referral code and the signed invite token into the app link —
  // the token is what makes opening the link connect in one tap (security
  // audit 2026-10-01); both used to be dropped here
  const qs = new URLSearchParams();
  for (const key of ['code', 't']) {
    const v = typeof req.query[key] === 'string' ? req.query[key].replace(/[^a-zA-Z0-9._-]/g, '').slice(0, 600) : '';
    if (v) qs.set(key, v);
  }
  const appQuery = qs.toString() ? `?${qs.toString()}` : '';
  const appStoreUrl = 'https://apps.apple.com/us/app/favcircles/id6746807095';

  // Personalize the page and its link preview (OpenGraph) with the inviter's
  // name. Best-effort: any failure falls back to a generic invite.
  let inviterName = null;
  try {
    const { getFirestore } = require('./config/firebase');
    const userDoc = await getFirestore().collection('users').doc(userId).get();
    if (userDoc.exists) {
      inviterName = (userDoc.data().displayName || '').trim() || null;
    }
  } catch (e) {
    console.warn('Connect page: could not load inviter name:', e.message);
  }

  // Escape for safe embedding in HTML
  const safeName = inviterName
    ? inviterName.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;')
    : null;
  const ogTitle = safeName ? `Connect with ${safeName} on Circles` : 'Join me on Circles';
  const heading = safeName ? `${safeName} invited you to Circles` : 'Opening Circles…';

  res.send(`<!DOCTYPE html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>${ogTitle}</title>
<meta property="og:title" content="${ogTitle}">
<meta property="og:description" content="Share and discover favorite places together on Circles.">
<meta property="og:site_name" content="Circles">
<meta property="og:type" content="website">
<meta property="og:url" content="https://api.favcircles.com/connect/${userId}">
</head>
<body style="font-family:-apple-system,Helvetica,Arial,sans-serif;display:flex;justify-content:center;align-items:center;min-height:100vh;margin:0;background:#3182CE;color:#fff;text-align:center">
<div><h1>${heading}</h1><p>If nothing happens, get the app and join ${safeName ? 'them' : 'me'}:</p>
<a href="${appStoreUrl}" style="background:#fff;color:#3182CE;padding:12px 28px;border-radius:8px;text-decoration:none;font-weight:600;display:inline-block">Download FavCircles</a></div>
<script>
  window.location = 'circles://connect/${userId}${appQuery}';
  setTimeout(function(){ if (!document.hidden) window.location = '${appStoreUrl}'; }, 1500);
</script>
</body></html>`);
});

// Public circle share page. With the app installed, iOS opens this as a
// Universal Link (AASA /circle/*). Without it, circle-share.js renders the
// circle preview from /api/circles/:id/public with an App Store fallback.
app.get('/circle/:circleId', (req, res) => {
  res.sendFile(path.join(__dirname, 'public', 'circle-share.html'));
});

// Public place share page. Universal Link target (AASA /place/*) — with the
// app installed iOS opens the place directly (carrying ?ref= attribution).
// Without it, this page shows a preview and falls back to the App Store.
app.get('/place/:placeId', async (req, res) => {
  const placeId = String(req.params.placeId).replace(/[^a-zA-Z0-9_-]/g, '');
  const ref = String(req.query.ref || '').replace(/[^a-zA-Z0-9._-]/g, '');
  const appStoreUrl = 'https://apps.apple.com/us/app/favcircles/id6746807095';

  // Personalize the page + link preview with the place's details. Best-effort:
  // failures fall back to a generic page.
  let name = null;
  let address = null;
  let photoUrl = null;
  // Only a place an anonymous viewer could see is described (security audit
  // 2026-10-01 — see services/placeSharePreview.js). Everything else gets the
  // generic page; the deep link still opens the app, where the viewer's own
  // access decides.
  try {
    const { getFirestore } = require('./config/firebase');
    const { publicPlacePreview } = require('./services/placeSharePreview');
    const preview = await publicPlacePreview(getFirestore(), placeId);
    if (preview) ({ name, address, photoUrl } = preview);
  } catch (e) {
    console.warn('Place share page: could not load place:', e.message);
  }

  const esc = (s) => String(s)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const ogTitle = name ? `${esc(name)} on Circles` : 'A favorite place on Circles';
  const heading = name ? esc(name) : 'Opening Circles…';
  const deepLink = `circles://place/${placeId}${ref ? `?ref=${ref}` : ''}`;

  res.send(`<!DOCTYPE html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>${ogTitle}</title>
<meta property="og:title" content="${ogTitle}">
<meta property="og:description" content="${address ? esc(address) + ' · ' : ''}Saved and recommended on Circles — favorite places from people you trust.">
<meta property="og:site_name" content="Circles">
<meta property="og:type" content="website">
${photoUrl ? `<meta property="og:image" content="${esc(photoUrl)}">` : ''}
<meta property="og:url" content="https://api.favcircles.com/place/${placeId}">
</head>
<body style="font-family:-apple-system,Helvetica,Arial,sans-serif;display:flex;justify-content:center;align-items:center;min-height:100vh;margin:0;background:#3182CE;color:#fff;text-align:center;padding:24px">
<div>${photoUrl ? `<img src="${esc(photoUrl)}" alt="" style="width:96px;height:96px;border-radius:16px;object-fit:cover;margin-bottom:16px">` : ''}
<h1 style="margin:0 0 4px">${heading}</h1>
${address ? `<p style="margin:0 0 16px;opacity:.85">${esc(address)}</p>` : ''}
<p>See it — and who recommends it — in the Circles app:</p>
<a href="${appStoreUrl}" style="background:#fff;color:#3182CE;padding:12px 28px;border-radius:8px;text-decoration:none;font-weight:600;display:inline-block">Download Circles</a></div>
<script>
  window.location = '${deepLink}';
  setTimeout(function(){ if (!document.hidden) window.location = '${appStoreUrl}'; }, 1500);
</script>
</body></html>`);
});
// Public postcard pages (image proxy, QR, share page) — routes/postcardPublicRoutes.js
app.use(require('./routes/postcardPublicRoutes'));

// instead of a 404 JSON blob.
app.get(['/app/open', '/app/daily-summary', '/daily-summary', '/app/import'], (req, res) => {
  res.redirect('https://favcircles.com');
});

// Weekly map-digest email target (AASA /app/*): installed devices open the
// app's map directly; browsers land on the marketing site.
app.get('/app/map', (req, res) => {
  res.redirect('https://favcircles.com');
});

// Public user profile share page. Universal Link target (AASA /user/*) —
// opens the profile in-app when installed, App Store fallback otherwise.
app.get('/user/:userId', async (req, res) => {
  const userId = String(req.params.userId).replace(/[^a-zA-Z0-9._-]/g, '');
  const appStoreUrl = 'https://apps.apple.com/us/app/favcircles/id6746807095';

  let name = null;
  let photoUrl = null;
  try {
    const { getFirestore } = require('./config/firebase');
    const userDoc = await getFirestore().collection('users').doc(userId).get();
    if (userDoc.exists) {
      name = (userDoc.data().displayName || '').trim() || null;
      photoUrl = userDoc.data().profilePicture || null;
    }
  } catch (e) {
    console.warn('User share page: could not load user:', e.message);
  }

  const esc = (s) => String(s)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const ogTitle = name ? `${esc(name)} on Circles` : 'A profile on Circles';
  const heading = name ? esc(name) : 'Opening Circles…';

  res.send(`<!DOCTYPE html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>${ogTitle}</title>
<meta property="og:title" content="${ogTitle}">
<meta property="og:description" content="Follow their favorite places on Circles — recommendations from people you trust.">
<meta property="og:site_name" content="Circles">
<meta property="og:type" content="profile">
${photoUrl ? `<meta property="og:image" content="${esc(photoUrl)}">` : ''}
<meta property="og:url" content="https://api.favcircles.com/user/${userId}">
</head>
<body style="font-family:-apple-system,Helvetica,Arial,sans-serif;display:flex;justify-content:center;align-items:center;min-height:100vh;margin:0;background:#3182CE;color:#fff;text-align:center;padding:24px">
<div>${photoUrl ? `<img src="${esc(photoUrl)}" alt="" style="width:96px;height:96px;border-radius:48px;object-fit:cover;margin-bottom:16px">` : ''}
<h1 style="margin:0 0 16px">${heading}</h1>
<p>See their circles and favorite places in the app:</p>
<a href="${appStoreUrl}" style="background:#fff;color:#3182CE;padding:12px 28px;border-radius:8px;text-decoration:none;font-weight:600;display:inline-block">Download Circles</a></div>
<script>
  window.location = 'circles://user/${userId}';
  setTimeout(function(){ if (!document.hidden) window.location = '${appStoreUrl}'; }, 1500);
</script>
</body></html>`);
});

// Shared widget link (AASA /app/*). A device with the app installed never
// renders this — the Universal Link opens the widget's page directly. This is
// what everyone else sees, and its job is the App Store, because these links
// are shared precisely with people who don't have FavCircles yet.
app.get('/app/widget/:id', (req, res) => {
  const id = String(req.params.id).replace(/[^a-zA-Z0-9_-]/g, '').slice(0, 64);
  const appStoreUrl = 'https://apps.apple.com/us/app/favcircles/id6746807095';
  const { widgetCopy } = require('./config/widgetCatalog');
  const copy = widgetCopy(id);

  const esc = (s) => String(s)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const title = esc(copy.title);
  const blurb = esc(copy.blurb);

  res.send(`<!DOCTYPE html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>${title} on FavCircles</title>
<meta property="og:title" content="${title} on FavCircles">
<meta property="og:description" content="${blurb}">
<meta property="og:site_name" content="FavCircles">
<meta property="og:type" content="website">
<meta property="og:url" content="https://api.favcircles.com/app/widget/${id}">
</head>
<body style="font-family:-apple-system,Helvetica,Arial,sans-serif;display:flex;justify-content:center;align-items:center;min-height:100vh;margin:0;background:#3182CE;color:#fff;text-align:center;padding:24px">
<div><div style="font-size:64px;line-height:1;margin-bottom:16px">${copy.emoji}</div>
<h1 style="margin:0 0 8px">${title}</h1>
<p style="margin:0 0 24px;opacity:.9">${blurb}</p>
<a href="${appStoreUrl}" style="background:#fff;color:#3182CE;padding:12px 28px;border-radius:8px;text-decoration:none;font-weight:600;display:inline-block">Get FavCircles</a></div>
<script>
  window.location = 'circles://widget/${id}';
  setTimeout(function(){ if (!document.hidden) window.location = '${appStoreUrl}'; }, 1500);
</script>
</body></html>`);
});

// Shared quote link (AASA /app/*). With the app installed the Universal Link
// opens the quote reel on this quote. Everyone else sees the quote itself,
// set like the reel, with the way to get more.
//
// Deliberately no og:image: Messages then draws a compact card (the quote as
// its title, the app icon beside it) instead of a big image bubble.
app.get('/app/quote/:id', async (req, res) => {
  const id = String(req.params.id).replace(/[^a-zA-Z0-9_-]/g, '').slice(0, 64);
  const appStoreUrl = 'https://apps.apple.com/us/app/favcircles/id6746807095';
  const iconUrl = 'https://favcircles.com/app-icon.png';

  let quote = null;
  try {
    const { getFirestore } = require('./config/firebase');
    const doc = id ? await getFirestore().collection('quotes').doc(id).get() : null;
    if (doc && doc.exists && doc.data().enabled !== false) quote = doc.data();
  } catch (e) {
    console.warn('Quote share page: could not load quote:', e.message);
  }

  const esc = (s) => String(s)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const text = quote && quote.text ? String(quote.text).trim() : null;
  const author = quote && quote.author ? String(quote.author).trim() : null;
  const ogTitle = text ? `“${esc(text.length > 180 ? `${text.slice(0, 177)}…` : text)}”` : 'Quotes on FavCircles';
  const ogDescription = author
    ? `— ${esc(author)} · More quotes on FavCircles`
    : 'A good line a few times a day, on the topics you pick.';

  res.send(`<!DOCTYPE html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>${ogTitle}</title>
<meta property="og:title" content="${ogTitle}">
<meta property="og:description" content="${ogDescription}">
<meta property="og:site_name" content="FavCircles">
<meta property="og:type" content="article">
<meta property="og:url" content="https://api.favcircles.com/app/quote/${id}">
<link rel="apple-touch-icon" href="${iconUrl}">
<link rel="icon" href="${iconUrl}">
</head>
<body style="font-family:-apple-system,Helvetica,Arial,sans-serif;min-height:100vh;margin:0;background:#000;color:#fff;display:flex;align-items:center;padding:32px;box-sizing:border-box">
<div style="max-width:560px;margin:0 auto">
${text ? `<p style="font-family:'New York',ui-serif,Georgia,serif;font-weight:600;font-size:30px;line-height:1.25;margin:0 0 20px">${esc(text)}</p>` : '<p style="font-family:ui-serif,Georgia,serif;font-size:28px;margin:0 0 20px">Quotes on FavCircles</p>'}
${author ? `<p style="color:#7C6BD6;font-size:18px;font-weight:500;margin:0 0 36px">— ${esc(author)}</p>` : ''}
<p style="color:#8e8e93;font-size:15px;margin:0 0 16px">Swipe through more quotes like this in FavCircles.</p>
<a href="${appStoreUrl}" style="background:#7C6BD6;color:#fff;padding:12px 28px;border-radius:10px;text-decoration:none;font-weight:600;display:inline-block">Get FavCircles</a>
</div>
<script>
  window.location = 'circles://quote/${id}';
  setTimeout(function(){ if (!document.hidden) window.location = '${appStoreUrl}'; }, 1500);
</script>
</body></html>`);
});

// Event invite link (Events widget / Party Bus). The app installed: the
// Universal Link opens its join screen. Otherwise this page explains the event
// and the two steps to join. No member names or photos here.
app.get('/app/event/:token', async (req, res) => {
  const token = String(req.params.token).replace(/[^a-zA-Z0-9_-]/g, '').slice(0, 64);
  const { renderEventInvite } = require('./views/eventPage');
  let preview = null;
  try {
    preview = await require('./services/eventService').publicPreview(token);
  } catch (e) {
    if (e.status !== 404) console.warn('Event invite page:', e.message);
  }
  res.status(preview ? 200 : 404).send(renderEventInvite(token, preview));
});

// Watch-a-run link (FavRun). The app installed: the Universal Link opens
// the run in FavRun. Otherwise: who's running and how to get the app — no
// route, no position.
app.get('/app/run/:token', async (req, res) => {
  const token = String(req.params.token).replace(/[^a-zA-Z0-9_-]/g, '').slice(0, 64);
  const { escapeHtml } = require('./utils/text');
  let preview = null;
  try { preview = await require('./services/runShareService').publicPreview(token); } catch (e) { /* unknown link */ }
  const who = preview ? escapeHtml(preview.ownerName) : 'Someone';
  const line = preview && preview.live ? `${who} is out for a run right now` : `${who} shared a run with you`;
  const appStoreUrl = 'https://apps.apple.com/app/id6746807095';
  res.status(preview ? 200 : 404).send(`<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex">
<title>Watch the run · FavCircles</title>
<meta property="og:title" content="${line} 🏃"><meta property="og:description" content="Follow along live in FavCircles: the route, the pace, a ping every mile.">
<style>body{margin:0;font-family:-apple-system,Helvetica,Arial,sans-serif;background:#DD6B20;color:#fff;display:flex;min-height:100vh;align-items:center;justify-content:center;text-align:center}
.c{padding:32px;max-width:420px}h1{font-size:28px;margin:12px 0}p{opacity:.9;line-height:1.4}a{display:inline-block;margin-top:18px;background:#fff;color:#DD6B20;font-weight:700;padding:14px 26px;border-radius:999px;text-decoration:none}</style></head>
<body><div class="c"><div style="font-size:56px">🏃</div><h1>${line}</h1>
<p>Get FavCircles to follow along live: the route on a map, the pace, and a ping every mile. Then open this link again.</p>
<a href="${appStoreUrl}">Get FavCircles</a></div></body></html>`);
});

// Texted workout link (AASA /app/*). With the app installed the Universal
// Link opens the workout in the Workouts widget (view it, copy it, try the
// widget). Everyone else sees the workout here and the way to get the app.
// No og:image: the sender's share sheet hands Messages the card image itself.
app.get('/app/workout/:token', async (req, res) => {
  const token = String(req.params.token).replace(/[^a-zA-Z0-9_-]/g, '').slice(0, 64);
  const appStoreUrl = 'https://apps.apple.com/us/app/favcircles/id6746807095';
  const iconUrl = 'https://favcircles.com/app-icon.png';
  let post = null;
  let author = null;
  try {
    const doc = await require('./services/workoutFeedService').postByLink(token);
    if (doc) {
      post = doc.data();
      const user = await require('./config/firebase').getFirestore().collection('users').doc(String(post.userId)).get();
      author = user.exists ? (user.data().displayName || null) : null;
    }
  } catch (e) {
    console.warn('Workout share page: could not load workout:', e.message);
  }
  const esc = (v) => String(v)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const s = post ? post.summary || {} : null;
  const first = author ? String(author).split(' ')[0] : null;
  const minutes = s ? Math.max(1, Math.round((s.durationSeconds || 0) / 60)) : 0;
  const exercises = s && Array.isArray(s.exercises) ? s.exercises : [];
  const cardio = s && Array.isArray(s.cardio) ? s.cardio : [];
  const stats = s ? [`${minutes} min`, exercises.length ? `${exercises.length} exercise${exercises.length === 1 ? '' : 's'}` : null,
    s.completedSets ? `${s.completedSets} sets` : null].filter(Boolean).join(' · ') : '';
  const day = s && s.startedAt ? new Date(s.startedAt).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric', timeZone: 'UTC' }) : '';
  const ogTitle = s ? `${first ? `${esc(first)}'s workout: ` : ''}${esc(s.name || 'Workout')}` : 'Workouts on FavCircles';
  const ogDescription = s ? `${esc(stats)} · Log yours with FavCircles` : 'Log workouts, copy routines from friends.';
  const rows = [...exercises.map((e) => [e.name, `${e.bestSet || ''}${e.isPR ? ' 🏆' : ''}`]), ...cardio.map((c) => [c.name, c.detail || ''])]
    .map(([n, d]) => `<div style="display:flex;justify-content:space-between;gap:12px;padding:9px 0;border-top:1px solid rgba(255,255,255,.12)"><span>${esc(n)}</span><span style="color:#cfd8ff">${esc(d)}</span></div>`).join('');
  res.send(`<!DOCTYPE html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>${ogTitle}</title>
<meta property="og:title" content="${ogTitle}">
<meta property="og:description" content="${ogDescription}">
<meta property="og:site_name" content="FavCircles">
<meta property="og:type" content="article">
<meta property="og:url" content="https://api.favcircles.com/app/workout/${token}">
<link rel="apple-touch-icon" href="${iconUrl}">
<link rel="icon" href="${iconUrl}">
</head>
<body style="font-family:-apple-system,Helvetica,Arial,sans-serif;margin:0;background:#0b1020;color:#fff;padding:28px 20px;box-sizing:border-box">
<div style="max-width:520px;margin:0 auto">
${s ? `<div style="background:linear-gradient(135deg,#2f6fd6,#4b4fc9);border-radius:20px;padding:22px 20px">
<div style="font-size:26px;font-weight:700">${esc(s.name || 'Workout')}</div>
<div style="color:#dbe4ff;font-size:14px;margin:4px 0 14px">${first ? `${esc(first)} · ` : ''}${esc(day)}</div>
<div style="font-size:15px;font-weight:600;margin-bottom:10px">${esc(stats)}</div>
${rows}
</div>` : '<p style="font-size:22px">This workout isn\'t available anymore.</p>'}
<p style="color:#9aa3b8;font-size:15px;margin:22px 0 14px">Track your own workouts, copy this one as a routine, and see what your friends are lifting — in FavCircles.</p>
<a href="circles://workout/${token}" style="background:#fff;color:#0b1020;padding:12px 22px;border-radius:10px;text-decoration:none;font-weight:600;display:inline-block;margin:0 8px 10px 0">Open in FavCircles</a>
<a href="${appStoreUrl}" style="background:#2f6fd6;color:#fff;padding:12px 22px;border-radius:10px;text-decoration:none;font-weight:600;display:inline-block">Get FavCircles</a>
</div>
</body></html>`);
});

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