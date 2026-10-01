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

// Opaque payload fields the XSS regexes must never touch: base64 receipts and
// signed JWS blobs are not HTML, and stripping "on…=" runs from them corrupts
// the payload (Apple then rejects the receipt as malformed, error 21002).
const SANITIZE_EXEMPT_KEYS = new Set([
  'receipt', 'receiptData', 'signedPayload', 'signedTransaction',
  // WebAuthn payloads are unpadded base64url (regex-safe today, but exempting
  // binary blobs from XSS munging is correctness, not convenience)
  'clientDataJSON', 'attestationObject', 'authenticatorData', 'signature', 'userHandle', 'rawId',
  // Base64 image uploads (/api/upload/image, postcard print upload): a padded
  // tail like "…onAB=" matches the event-handler pattern and corrupted the
  // JPEG; skipping them also spares a 1–6 MB regex pass (security audit 2026-10-01)
  'image'
]);

// Strip <tag …>…</tag> blocks (case-insensitive), first open tag to the next
// closing tag — the same matches the old regex made, but in linear time. The
// old /<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>/ rescanned to the end
// of the string from every unclosed "<script", so a body of repeated
// "<script<script…" pinned a CPU (security audit 2026-10-01). An unclosed tag
// is left alone, as before.
const BLOCK_TAGS = {
  script: { open: /<script\b/gi, close: /<\/script>/gi },
  iframe: { open: /<iframe\b/gi, close: /<\/iframe>/gi }
};

const stripBlocks = (str, tag) => {
  const { open, close } = BLOCK_TAGS[tag];
  open.lastIndex = 0;
  let out = '';
  let cursor = 0;
  let match;
  while ((match = open.exec(str)) !== null) {
    close.lastIndex = match.index;
    const end = close.exec(str);
    if (!end) break; // no closing tag anywhere after this: nothing more to strip
    out += str.slice(cursor, match.index);
    cursor = end.index + end[0].length;
    open.lastIndex = cursor;
  }
  return cursor === 0 ? str : out + str.slice(cursor);
};

const sanitizeString = (str) => {
  let out = str;
  if (out.indexOf('<') !== -1) {
    out = stripBlocks(out, 'script');
    out = stripBlocks(out, 'iframe');
  }
  return out
    .replace(/javascript:/gi, '')
    // Event handlers ("onclick ="). Bounded runs keep this linear: the old
    // unbounded on\w+\s*= backtracked quadratically over "ononon…"
    // (security audit 2026-10-01). Real handler names are well under 32 chars.
    .replace(/on\w{1,32}\s{0,16}=/gi, '');
};

// Input sanitization middleware
exports.sanitizeInput = (req, res, next) => {
  // Recursively sanitize strings in request body
  const sanitize = (obj) => {
    if (typeof obj === 'string') {
      // Remove any script tags and dangerous HTML
      return sanitizeString(obj);
    } else if (Array.isArray(obj)) {
      return obj.map(sanitize);
    } else if (obj !== null && typeof obj === 'object') {
      const sanitized = {};
      for (const key in obj) {
        if (obj.hasOwnProperty(key)) {
          sanitized[key] = SANITIZE_EXEMPT_KEYS.has(key) ? obj[key] : sanitize(obj[key]);
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

// Security logging middleware. Log-only (it blocks nothing) and it runs before
// auth and rate limiting on every request, so it must stay cheap whatever an
// anonymous caller sends. Only the first 10 KB of the URL and body are
// inspected and every pattern is linear: the old /union.*select/i over a
// multi-MB stringified body was quadratic (security audit 2026-10-01).
const SECURITY_SCAN_MAX_CHARS = 10 * 1024;
const SUSPICIOUS_PATTERNS = [
  /\.\.\//, // Directory traversal
  /<script/i, // Script tags
  /\bunion\b[\s\S]{0,40}\bselect\b/i, // SQL injection attempts
  /' or '/i, // SQL injection attempts
  /exec\(/i, // Command execution
  /eval\(/i // Code evaluation
];

const looksSuspicious = (str) => {
  if (typeof str !== 'string') return false;
  const head = str.length > SECURITY_SCAN_MAX_CHARS ? str.slice(0, SECURITY_SCAN_MAX_CHARS) : str;
  return SUSPICIOUS_PATTERNS.some(pattern => pattern.test(head));
};

// The first SECURITY_SCAN_MAX_CHARS of the stringified body. Long string
// fields are clipped inside the replacer so a 1 MB base64 image isn't copied
// just to be thrown away.
const bodyHead = (body) => {
  if (typeof body === 'string') return body.slice(0, SECURITY_SCAN_MAX_CHARS);
  try {
    const json = JSON.stringify(body, (key, value) => (
      typeof value === 'string' && value.length > SECURITY_SCAN_MAX_CHARS
        ? value.slice(0, SECURITY_SCAN_MAX_CHARS)
        : value
    ));
    return json ? json.slice(0, SECURITY_SCAN_MAX_CHARS) : '';
  } catch (_) {
    return '';
  }
};

exports.securityLogger = (req, res, next) => {
  // Check URL
  if (looksSuspicious(req.url)) {
    console.error(`🚨 SECURITY: Suspicious URL pattern detected from ${req.ip}: ${String(req.url).slice(0, 500)}`);
  }

  // Check body
  if (req.body && looksSuspicious(bodyHead(req.body))) {
    console.error(`🚨 SECURITY: Suspicious body content from ${req.ip}: ${req.path}`);
  }

  next();
};

exports.looksSuspicious = looksSuspicious;
exports.bodyHead = bodyHead;
exports.sanitizeString = sanitizeString;

// ---------------------------------------------------------------------------
// perUserLimit — a per-account rate limit shared by every Cloud Run instance.
//
// The express-rate-limit limiters above keep their counters in each
// instance's memory, so with up to 100 instances the effective limit is 100×
// what's written, and they key on IP. Expensive authed routes (Google Places
// spend, upload URLs) need a limit that holds per account across the fleet
// (security audit 2026-10-01).
//
// Fixed window, one Firestore doc per bucket+user+window:
//   rateLimits/{bucket}_{uid}_{windowStart}  { count, expiresAt }
// `expiresAt` is there for a Firestore TTL policy on the collection, so old
// windows clean themselves up.
//
// Mount AFTER auth (it keys on req.user.uid). With no user it does nothing,
// so it never costs a Firestore call on an unauthenticated request. Fails
// OPEN: a Firestore error or a slow transaction lets the request through —
// this guards cost, it must never take the feature down.
// ---------------------------------------------------------------------------
const RATE_LIMIT_COLLECTION = 'rateLimits';
const PER_USER_LIMIT_TIMEOUT_MS = 2000;
// Windows already known to be over the limit on this instance, so a client
// hammering a blocked route costs no further Firestore reads until the
// window rolls over. key → windowEnd.
const knownBlocked = new Map();
const KNOWN_BLOCKED_MAX = 10000;

const rememberBlocked = (key, windowEnd, now) => {
  if (knownBlocked.size >= KNOWN_BLOCKED_MAX) {
    for (const [k, end] of knownBlocked) {
      if (end <= now) knownBlocked.delete(k);
    }
    if (knownBlocked.size >= KNOWN_BLOCKED_MAX) knownBlocked.clear();
  }
  knownBlocked.set(key, windowEnd);
};

const withTimeout = (promise, ms) => new Promise((resolve, reject) => {
  const timer = setTimeout(() => reject(new Error(`perUserLimit timed out after ${ms}ms`)), ms);
  promise.then(
    (value) => { clearTimeout(timer); resolve(value); },
    (error) => { clearTimeout(timer); reject(error); }
  );
});

exports.perUserLimit = ({ bucket, windowMs, max, message } = {}) => {
  if (!bucket || !/^[A-Za-z0-9-]+$/.test(bucket)) {
    throw new Error('perUserLimit: bucket must be letters, digits and dashes');
  }
  if (!(windowMs > 0) || !(max > 0)) {
    throw new Error('perUserLimit: windowMs and max must be positive');
  }
  const refusal = message || 'You are doing that too often. Please try again later.';

  return async (req, res, next) => {
    const uid = req.user && (req.user.uid || req.user.id);
    if (!uid) return next();

    const now = Date.now();
    const windowStart = Math.floor(now / windowMs) * windowMs;
    const windowEnd = windowStart + windowMs;
    const key = `${bucket}_${String(uid).replace(/\//g, '_')}_${windowStart}`;

    const refuse = () => {
      res.set('Retry-After', String(Math.max(1, Math.ceil((windowEnd - Date.now()) / 1000))));
      console.warn(`🚫 Per-user limit '${bucket}' exceeded for ${uid} on ${req.originalUrl || req.path}`);
      return res.status(429).json({ success: false, message: refusal });
    };

    const blockedUntil = knownBlocked.get(key);
    if (blockedUntil && blockedUntil > now) return refuse();

    let allowed;
    try {
      const db = require('../config/firebase').getFirestore();
      const ref = db.collection(RATE_LIMIT_COLLECTION).doc(key);
      allowed = await withTimeout(db.runTransaction(async (tx) => {
        const snap = await tx.get(ref);
        const count = snap.exists ? (Number(snap.data().count) || 0) : 0;
        if (count >= max) return false;
        tx.set(ref, {
          bucket,
          userId: String(uid),
          count: count + 1,
          windowStart: new Date(windowStart),
          expiresAt: new Date(windowEnd + 24 * 60 * 60 * 1000)
        });
        return true;
      }), PER_USER_LIMIT_TIMEOUT_MS);
    } catch (error) {
      console.warn(`⚠️ perUserLimit '${bucket}' failed open: ${error.message}`);
      return next();
    }

    if (allowed) return next();
    rememberBlocked(key, windowEnd, now);
    return refuse();
  };
};

// Test hook: forget the instance-local "already blocked" memo.
exports._resetPerUserLimitMemo = () => knownBlocked.clear();