// controllers/video/videoShareController.js
// Moment share links and share metadata
// Split out of videoController.js (handlers unchanged).
// backend/controllers/videoController.js
const fs = require('fs');
const { sendServiceError } = require('../../utils/serviceError');
const path = require('path');
const { getFirestore } = require('../../config/firebase');
const { COLLECTIONS } = require('../../models/FirestoreModels');
const { momentMeta, renderMoment } = require('../../views/momentPage');
const { composePreview, fetchImage } = require('../../services/momentPreview');
const { isPubliclyViewableMoment } = require('../../services/publicProjection');
const { withCurrentMomentPlaces } = require('../../services/placeLookup');
const db = getFirestore();

const PAGE_TEMPLATE = path.join(__dirname, '..', '..', 'public', 'video-share.html');
const SHARE_BASE = () => process.env.SHARE_LINK_BASE_URL || 'https://api.favcircles.com';

// The three public share surfaces below answer to anyone — browsers, link
// preview crawlers, whoever was forwarded the link. They used to ignore the
// moment's audience and moderation, so a private (or reported-and-hidden)
// moment's place name and thumbnail went out to all of them (security audit
// 2026-10-01). Anything not public, live and un-moderated reads as missing.
const loadPublicMoment = async (videoId, { withPlace = true } = {}) => {
  const doc = await db.collection(COLLECTIONS.PLACE_VIDEOS).doc(videoId).get();
  if (!doc.exists) return null;
  const video = doc.data();
  // A disappearing moment that ran out reads as gone ("no longer available")
  if (require('../../services/momentExpiry').isExpired(video)) return null;
  if (!isPubliclyViewableMoment(video)) return null;
  if (!withPlace) return video;
  // The place line says what the place is called NOW, not at upload
  const [current] = await withCurrentMomentPlaces([video]);
  return current;
};

// @route GET /share/video/:videoId (public)
// The share page with this moment's title, place and preview image in its
// head, so the link card in Messages says what it is. The body is the
// static page (its script loads the moment); a missing moment still gets
// the page, which shows "no longer available".
exports.renderSharePage = async (req, res) => {
  const { videoId } = req.params;
  let video = null;
  try {
    video = await loadPublicMoment(videoId);
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
    const video = await loadPublicMoment(videoId, { withPlace: false }); // image only: no place line
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
    const video = await loadPublicMoment(videoId);

    if (!video) {
      return res.status(404).json({
        success: false,
        message: 'This moment is no longer available'
      });
    }

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
    sendServiceError(res, error, { log: 'Error fetching video share info', fallbackMessage: 'Failed to load moment' });
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
    
    // The place's current name, not the one stored at upload
    const [video] = await withCurrentMomentPlaces([videoDoc.data()]);
    
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
    sendServiceError(res, error, { log: 'Error generating share link', fallbackMessage: 'Failed to generate share link' });
  }
};
