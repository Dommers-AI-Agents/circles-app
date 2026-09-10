// controllers/video/videoShareController.js
// Moment share links and share metadata
// Split out of videoController.js (handlers unchanged).
// backend/controllers/videoController.js
const { getFirestore } = require('../../config/firebase');
const { COLLECTIONS } = require('../../models/FirestoreModels');
const db = getFirestore();

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
