// backend/services/postcardShareService.js
// Public postcard pages: a sender turns a rendered postcard into a link
// (https://api.favcircles.com/postcard/<token>) that anyone — FavCircles
// user or not — can open in a browser. The page shows the card and pitches
// the app underneath. Tokens are unguessable and pages never expire.
const crypto = require('crypto');
const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');

// Share links use the friendly domain; favcircles.com's .htaccess forwards
// /postcard/* to the API page (website/favcircles.com/.htaccess).
const PUBLIC_BASE_URL = 'https://favcircles.com';
const MAX_MESSAGE_CHARS = 500;
const TOKEN_RE = /^[A-Za-z0-9_-]{16,32}$/;

class ShareError extends Error {
  constructor(status, code, message) { super(message); this.status = status; this.code = code; }
}

// Same bucket allow-list as the in-app postcard send.
function isAllowedImageUrl(url) {
  const bucket = process.env.FIREBASE_STORAGE_BUCKET
    || process.env.GCS_BUCKET_NAME
    || (process.env.FIREBASE_PROJECT_ID ? `${process.env.FIREBASE_PROJECT_ID}.appspot.com` : null);
  if (!bucket || typeof url !== 'string') return false;
  return url.startsWith(`https://firebasestorage.googleapis.com/v0/b/${bucket}/o/`)
    || url.startsWith(`https://storage.googleapis.com/${bucket}/`);
}

function newToken() {
  return crypto.randomBytes(15).toString('base64url'); // 20 url-safe chars
}

function normalizeShare({ senderId, senderName, imageUrl, message = '', templateId = 'classic', placeRef = null }) {
  if (!isAllowedImageUrl(imageUrl)) throw new ShareError(400, 'invalid_image', 'Upload the postcard first');
  if (typeof message !== 'string' || message.length > MAX_MESSAGE_CHARS) {
    throw new ShareError(400, 'invalid_message', `Message must be under ${MAX_MESSAGE_CHARS} characters`);
  }
  if (typeof templateId !== 'string' || !/^[a-z0-9_-]{1,32}$/.test(templateId)) {
    throw new ShareError(400, 'invalid_template', 'Unknown template');
  }
  const placeName = placeRef && placeRef.name ? String(placeRef.name).slice(0, 120) : null;
  const placeCity = placeRef && placeRef.city ? String(placeRef.city).slice(0, 80) : null;
  return {
    senderId,
    senderName: (senderName || 'A FavCircles member').slice(0, 80),
    imageUrl,
    message: message.trim(),
    templateId,
    placeName,
    placeCity,
    createdAt: new Date().toISOString(),
    views: 0
  };
}

class PostcardShareService {
  get db() { return getFirestore(); }
  get col() { return this.db.collection(COLLECTIONS.POSTCARD_SHARES); }

  async create(input) {
    // req.user may not carry the display name; read it from the user doc.
    let senderName = input.senderName;
    if (!senderName && input.senderId) {
      try {
        const doc = await this.db.collection(COLLECTIONS.USERS).doc(input.senderId).get();
        if (doc.exists) senderName = doc.data().displayName;
      } catch (_) { /* fall back to the generic name */ }
    }
    const data = normalizeShare({ ...input, senderName });
    const token = newToken();
    await this.col.doc(token).set(data);
    return { token, url: `${PUBLIC_BASE_URL}/postcard/${token}`, ...data };
  }

  // null for unknown/malformed tokens; bumps the view counter (best effort).
  async get(token) {
    if (!TOKEN_RE.test(String(token))) return null;
    const doc = await this.col.doc(token).get();
    if (!doc.exists) return null;
    this.col.doc(token).update({ views: (doc.data().views || 0) + 1 }).catch(() => {});
    return { token, ...doc.data() };
  }
}

module.exports = Object.assign(new PostcardShareService(), {
  ShareError, isAllowedImageUrl, normalizeShare, newToken, PUBLIC_BASE_URL, TOKEN_RE
});
