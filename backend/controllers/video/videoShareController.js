// controllers/video/videoShareController.js
// Moment share links and share metadata
// Split out of videoController.js (handlers unchanged).
// backend/controllers/videoController.js
const fs = require('fs');
const path = require('path');
const { getFirestore } = require('../../config/firebase');
const { COLLECTIONS } = require('../../models/FirestoreModels');
const { momentMeta, renderMoment } = require('../../views/momentPage');
const { composePreview, fetchImage } = require('../../services/momentPreview');
const db = getFirestore();

const PAGE_TEMPLATE = path.join(__dirname, '..', '..', 'public', 'video-share.html');
const SHARE_BASE = () => process.env.SHARE_LINK_BASE_URL || 'https://api.favcircles.com';

// @route GET /share/video/:videoId (public)
// The share page with this moment's title, place and preview image in its
// head, so the link card in Messages says what it is. The body is the
// static page (its script loads the moment); a missing moment still gets
// the page, which shows "no longer available".
exports.renderSharePage = async (req, res) => {
  const { videoId } = req.params;
  let video = null;
  try {
    const doc = await db.collection(COLLECTIONS.PLACE_VIDEOS).doc(videoId).get();
    if (doc.exists) video = doc.data();
  } catch (error) {
    console.error('share page: moment read failed:', error.message);
  }
  let template;
  try {
    template = fs.readFileSync(PAGE_TEMPLATE, 'utf8');
  } catch (error) {
    return res.status(500).send('Share page unavailable');
  }
  res.set('Cache-Control', 'public, max-age=300');
  res.type('html').send(renderMoment(template, momentMeta(video || {}, { videoId, base: SHARE_BASE() })));
};

// @route GET /share/video/:videoId/preview.jpg (public)
// The link card's image: the thumbnail with a play badge for videos.
exports.sharePreviewImage = async (req, res) => {
  const { videoId } = req.params;
  try {
    const doc = await db.collection(COLLECTIONS.PLACE_VIDEOS).doc(videoId).get();
    const video = doc.exists ? doc.data() : null;
    if (!video || !video.thumbnailUrl) return res.redirect(302, `${SHARE_BASE()}/images/circles-preview.png`);
    const source = await fetchImage(video.thumbnailUrl);
    const jpeg = await composePreview(source, { play: (video.contentType || 'video') !== 'photo' });
    res.set('Cache-Control', 'public, max-age=86400');
    res.type('jpeg').send(jpeg);
  } catch (error) {
    console.error('share preview failed:', error.message);
    res.redirect(302, `${SHARE_BASE()}/images/circles-preview.png`);
  }
};

// Public metadata for the share landing page (no auth — the link is the
// grant). Lightweight fields only; watching the moment happens in the app.
exports.getVideoShareInfo = async (req, res) => {
  try {
    const { videoId } = req.params;
    const videoDoc = await db.collection(COLLECTIONS.PLACE_VIDEOS).doc(videoId).get();

    if (!videoDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'This moment is no longer available'
      });
    }

    const video = videoDoc.data();
    let userDisplayName = null;
    if (video.userId) {
      try {
        const userDoc = await db.collection(COLLECTIONS.USERS).doc(video.userId).get();
        if (userDoc.exists) userDisplayName = userDoc.data().displayName || null;
      } catch (e) { /* attribution is best-effort */ }
    }

    res.json({
      success: true,
      data: {
        videoId,
        title: video.title || null,
        placeName: video.placeName || null,
        thumbnailUrl: video.thumbnailUrl || null,
        contentType: video.contentType || 'video',
        userDisplayName,
        createdAt: video.createdAt || null
      }
    });
  } catch (error) {
    console.error('Error fetching video share info:', error);
    res.status(500).json({ success: false, message: 'Failed to load moment' });
  }
};

// Generate share link for video
exports.generateVideoShareLink = async (req, res) => {
  try {
    const { videoId } = req.params;
    const userId = req.user.uid;
    
    // Verify video exists and user has access
    const videoDoc = await db.collection(COLLECTIONS.PLACE_VIDEOS).doc(videoId).get();
    
    if (!videoDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Video not found'
      });
    }
    
    const video = videoDoc.data();
    
    // Generate share URL. circles-app.com is hosted on Vercel and never
    // routed /share/* to this backend — links must use a host that actually
    // reaches Cloud Run (same pattern as sticker QR links).
    const shareBaseUrl = process.env.SHARE_LINK_BASE_URL
      || 'https://api.favcircles.com';
    const shareUrl = `${shareBaseUrl}/share/video/${videoId}`;
    const deepLink = `circles://video/${videoId}`;
    
    // Create share text with place info
    const shareText = `Check out this moment at ${video.placeName || 'this place'} on Circles!`;
    
    res.json({
      success: true,
      data: {
        shareUrl,
        deepLink,
        shareText,
        videoTitle: video.title,
        placeName: video.placeName,
        thumbnailUrl: video.thumbnailUrl
      }
    });
  } catch (error) {
    console.error('Error generating share link:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to generate share link',
      error: error.message
    });
  }
};
