// backend/controllers/videoController.js
const { getFirestore, FieldValue } = require('../config/firebase');
const { getStorage } = require('firebase-admin/storage');
const { 
  COLLECTIONS, 
  createPlaceVideo,
  createUserVideoQuota,
  validatePlaceVideo,
  serializeDoc,
  serializeQuerySnapshot 
} = require('../models/FirestoreModels');
const { createActivity } = require('./activityController');

const db = getFirestore();
const bucket = getStorage().bucket();

// Check user's video quota
exports.checkVideoQuota = async (req, res) => {
  try {
    const userId = req.user.uid;
    const now = new Date();
    const currentMonth = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
    
    // Get or create user quota document
    const quotaRef = db.collection(COLLECTIONS.USER_VIDEO_QUOTAS).doc(userId);
    const quotaDoc = await quotaRef.get();
    
    let quotaData;
    if (!quotaDoc.exists) {
      // Create new quota record
      // TODO: Check user's subscription status to determine tier
      const newQuota = createUserVideoQuota(userId, 'free');
      await quotaRef.set(newQuota);
      quotaData = newQuota;
    } else {
      quotaData = quotaDoc.data();
      
      // Reset quota if new month
      if (quotaData.currentMonth !== currentMonth) {
        quotaData = {
          ...quotaData,
          currentMonth: currentMonth,
          videosUploaded: 0,
          totalSize: 0,
          lastResetDate: now.toISOString(),
          updatedAt: now.toISOString()
        };
        await quotaRef.update(quotaData);
      }
    }
    
    // Check if user has quota remaining
    const hasQuota = quotaData.videosUploaded < quotaData.quotaLimit;
    const remainingVideos = quotaData.quotaLimit - quotaData.videosUploaded;
    const remainingSize = quotaData.sizeLimit - quotaData.totalSize;
    
    res.json({
      success: true,
      data: {
        hasQuota,
        remainingVideos,
        remainingSize,
        quotaLimit: quotaData.quotaLimit,
        sizeLimit: quotaData.sizeLimit,
        videosUploaded: quotaData.videosUploaded,
        totalSize: quotaData.totalSize,
        subscriptionTier: quotaData.subscriptionTier
      }
    });
  } catch (error) {
    console.error('Error checking video quota:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to check video quota',
      error: error.message
    });
  }
};

// Initiate video upload
exports.initiateVideoUpload = async (req, res) => {
  try {
    const userId = req.user.uid;
    const { 
      placeId, 
      placeName, 
      duration, 
      fileSize,
      title,
      description,
      visibility,
      tags
    } = req.body;
    
    // Validate video data
    const errors = validatePlaceVideo(req.body);
    if (errors.length > 0) {
      return res.status(400).json({
        success: false,
        errors
      });
    }
    
    // Check quota
    const quotaRef = db.collection(COLLECTIONS.USER_VIDEO_QUOTAS).doc(userId);
    const quotaDoc = await quotaRef.get();
    
    if (!quotaDoc.exists) {
      return res.status(403).json({
        success: false,
        message: 'Video quota not initialized'
      });
    }
    
    const quotaData = quotaDoc.data();
    if (quotaData.videosUploaded >= quotaData.quotaLimit) {
      return res.status(403).json({
        success: false,
        message: 'Monthly video quota exceeded'
      });
    }
    
    if (quotaData.totalSize + fileSize > quotaData.sizeLimit) {
      return res.status(403).json({
        success: false,
        message: 'Monthly storage quota exceeded'
      });
    }
    
    // Create video document
    const videoData = createPlaceVideo({
      placeId,
      placeName,
      duration,
      fileSize,
      title,
      description,
      visibility,
      tags
    }, userId);
    
    const videoRef = await db.collection(COLLECTIONS.PLACE_VIDEOS).add(videoData);
    const videoId = videoRef.id;
    
    // Generate signed URLs for upload
    const timestamp = Date.now();
    const videoPath = `videos/${userId}/full/${videoId}_${timestamp}.mp4`;
    const previewPath = `videos/${userId}/preview/${videoId}_${timestamp}.mp4`;
    const thumbnailPath = `videos/${userId}/thumbnails/${videoId}_${timestamp}.jpg`;
    
    const [videoUrl] = await bucket.file(videoPath).getSignedUrl({
      version: 'v4',
      action: 'write',
      expires: Date.now() + 30 * 60 * 1000, // 30 minutes
      contentType: 'video/mp4',
    });
    
    const [previewUrl] = await bucket.file(previewPath).getSignedUrl({
      version: 'v4',
      action: 'write',
      expires: Date.now() + 30 * 60 * 1000, // 30 minutes
      contentType: 'video/mp4',
    });
    
    const [thumbnailUploadUrl] = await bucket.file(thumbnailPath).getSignedUrl({
      version: 'v4',
      action: 'write',
      expires: Date.now() + 30 * 60 * 1000, // 30 minutes
      contentType: 'image/jpeg',
    });
    
    res.json({
      success: true,
      data: {
        videoId,
        uploadUrls: {
          video: videoUrl,
          preview: previewUrl,
          thumbnail: thumbnailUploadUrl
        },
        storagePaths: {
          video: videoPath,
          preview: previewPath,
          thumbnail: thumbnailPath
        }
      }
    });
  } catch (error) {
    console.error('Error initiating video upload:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to initiate video upload',
      error: error.message
    });
  }
};

// Complete video upload
exports.completeVideoUpload = async (req, res) => {
  try {
    const userId = req.user.uid;
    const { videoId } = req.params;
    const { 
      storagePaths,
      originalSize,
      compressionRatio 
    } = req.body;
    
    // Verify video exists and belongs to user
    const videoRef = db.collection(COLLECTIONS.PLACE_VIDEOS).doc(videoId);
    const videoDoc = await videoRef.get();
    
    if (!videoDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Video not found'
      });
    }
    
    const videoData = videoDoc.data();
    if (videoData.userId !== userId) {
      return res.status(403).json({
        success: false,
        message: 'Unauthorized'
      });
    }
    
    // Generate public URLs for the uploaded files
    const baseUrl = `https://storage.googleapis.com/${bucket.name}`;
    const videoUrl = `${baseUrl}/${storagePaths.video}`;
    const previewUrl = `${baseUrl}/${storagePaths.preview}`;
    const thumbnailUrl = `${baseUrl}/${storagePaths.thumbnail}`;
    
    // Update video document
    await videoRef.update({
      videoUrl,
      previewUrl,
      thumbnailUrl,
      originalSize,
      compressionRatio,
      uploadStatus: 'ready',
      uploadProgress: 100,
      updatedAt: new Date().toISOString()
    });
    
    // Update user quota
    const quotaRef = db.collection(COLLECTIONS.USER_VIDEO_QUOTAS).doc(userId);
    await quotaRef.update({
      videosUploaded: FieldValue.increment(1),
      totalSize: FieldValue.increment(videoData.fileSize),
      updatedAt: new Date().toISOString()
    });
    
    // Create activity
    await createActivity(
      'video_uploaded',
      userId,
      'place_video',
      videoId,
      videoData.placeName,
      {
        videoTitle: videoData.title,
        videoThumbnail: thumbnailUrl,
        videoDuration: videoData.duration,
        placeId: videoData.placeId
      }
    );
    
    // Get updated video
    const updatedDoc = await videoRef.get();
    
    res.json({
      success: true,
      data: serializeDoc(updatedDoc)
    });
  } catch (error) {
    console.error('Error completing video upload:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to complete video upload',
      error: error.message
    });
  }
};

// Get videos for a place
exports.getPlaceVideos = async (req, res) => {
  try {
    const { placeId } = req.params;
    const { limit = 20, offset = 0 } = req.query;
    
    const videosQuery = await db.collection(COLLECTIONS.PLACE_VIDEOS)
      .where('placeId', '==', placeId)
      .where('uploadStatus', '==', 'ready')
      .where('deletedAt', '==', null)
      .orderBy('createdAt', 'desc')
      .limit(parseInt(limit))
      .offset(parseInt(offset))
      .get();
    
    const videos = serializeQuerySnapshot(videosQuery);
    
    res.json({
      success: true,
      data: videos,
      hasMore: videos.length === parseInt(limit)
    });
  } catch (error) {
    console.error('Error getting place videos:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get place videos',
      error: error.message
    });
  }
};

// Get user's videos
exports.getUserVideos = async (req, res) => {
  try {
    const { userId } = req.params;
    const { limit = 20, offset = 0 } = req.query;
    
    const videosQuery = await db.collection(COLLECTIONS.PLACE_VIDEOS)
      .where('userId', '==', userId)
      .where('uploadStatus', '==', 'ready')
      .where('deletedAt', '==', null)
      .orderBy('createdAt', 'desc')
      .limit(parseInt(limit))
      .offset(parseInt(offset))
      .get();
    
    const videos = serializeQuerySnapshot(videosQuery);
    
    res.json({
      success: true,
      data: videos,
      hasMore: videos.length === parseInt(limit)
    });
  } catch (error) {
    console.error('Error getting user videos:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get user videos',
      error: error.message
    });
  }
};

// Get video feed
exports.getVideoFeed = async (req, res) => {
  try {
    const userId = req.user.uid;
    const { limit = 20, offset = 0 } = req.query;
    
    // Get user's connections
    const [connections1, connections2] = await Promise.all([
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', userId)
        .where('status', '==', 'accepted')
        .get(),
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('connectedUserId', '==', userId)
        .where('status', '==', 'accepted')
        .get()
    ]);
    
    const connectionIds = new Set([userId]); // Include self
    connections1.docs.forEach(doc => connectionIds.add(doc.data().connectedUserId));
    connections2.docs.forEach(doc => connectionIds.add(doc.data().userId));
    
    // Get videos from connections
    const videosQuery = await db.collection(COLLECTIONS.PLACE_VIDEOS)
      .where('userId', 'in', Array.from(connectionIds))
      .where('uploadStatus', '==', 'ready')
      .where('deletedAt', '==', null)
      .where('visibility', 'in', ['public', 'network'])
      .orderBy('createdAt', 'desc')
      .limit(parseInt(limit))
      .offset(parseInt(offset))
      .get();
    
    const videos = serializeQuerySnapshot(videosQuery);
    
    // Populate user details
    const userIds = [...new Set(videos.map(v => v.userId))];
    const userDocs = await Promise.all(
      userIds.map(id => db.collection(COLLECTIONS.USERS).doc(id).get())
    );
    
    const usersMap = {};
    userDocs.forEach(doc => {
      if (doc.exists) {
        usersMap[doc.id] = doc.data();
      }
    });
    
    // Add user details to videos
    const videosWithUsers = videos.map(video => ({
      ...video,
      user: usersMap[video.userId] || null
    }));
    
    res.json({
      success: true,
      data: videosWithUsers,
      hasMore: videos.length === parseInt(limit)
    });
  } catch (error) {
    console.error('Error getting video feed:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get video feed',
      error: error.message
    });
  }
};

// Get video details (and track view)
exports.getVideoDetails = async (req, res) => {
  try {
    const { videoId } = req.params;
    const { quality = 'preview' } = req.query; // preview or full
    const userId = req.user?.uid;
    
    const videoRef = db.collection(COLLECTIONS.PLACE_VIDEOS).doc(videoId);
    const videoDoc = await videoRef.get();
    
    if (!videoDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Video not found'
      });
    }
    
    const videoData = videoDoc.data();
    
    // Check visibility
    if (videoData.visibility === 'private' && videoData.userId !== userId) {
      return res.status(403).json({
        success: false,
        message: 'Video is private'
      });
    }
    
    // Update view count and last viewed
    if (userId && userId !== videoData.userId) {
      await videoRef.update({
        viewCount: FieldValue.increment(1),
        lastViewedAt: new Date().toISOString()
      });
    }
    
    // Return appropriate URL based on quality
    const response = {
      ...serializeDoc(videoDoc),
      videoUrl: quality === 'full' ? videoData.videoUrl : videoData.previewUrl
    };
    
    // Get user details
    const userDoc = await db.collection(COLLECTIONS.USERS).doc(videoData.userId).get();
    if (userDoc.exists) {
      response.user = userDoc.data();
    }
    
    res.json({
      success: true,
      data: response
    });
  } catch (error) {
    console.error('Error getting video details:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get video details',
      error: error.message
    });
  }
};

// Delete video
exports.deleteVideo = async (req, res) => {
  try {
    const userId = req.user.uid;
    const { videoId } = req.params;
    
    const videoRef = db.collection(COLLECTIONS.PLACE_VIDEOS).doc(videoId);
    const videoDoc = await videoRef.get();
    
    if (!videoDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Video not found'
      });
    }
    
    const videoData = videoDoc.data();
    if (videoData.userId !== userId) {
      return res.status(403).json({
        success: false,
        message: 'Unauthorized'
      });
    }
    
    // Soft delete
    await videoRef.update({
      deletedAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    });
    
    // Update user quota
    const quotaRef = db.collection(COLLECTIONS.USER_VIDEO_QUOTAS).doc(userId);
    await quotaRef.update({
      videosUploaded: FieldValue.increment(-1),
      totalSize: FieldValue.increment(-videoData.fileSize),
      updatedAt: new Date().toISOString()
    });
    
    // Delete files from storage (optional - could keep for a grace period)
    // const videoFile = bucket.file(videoData.videoUrl.replace(`https://storage.googleapis.com/${bucket.name}/`, ''));
    // const previewFile = bucket.file(videoData.previewUrl.replace(`https://storage.googleapis.com/${bucket.name}/`, ''));
    // const thumbnailFile = bucket.file(videoData.thumbnailUrl.replace(`https://storage.googleapis.com/${bucket.name}/`, ''));
    // await Promise.all([
    //   videoFile.delete().catch(() => {}),
    //   previewFile.delete().catch(() => {}),
    //   thumbnailFile.delete().catch(() => {})
    // ]);
    
    res.json({
      success: true,
      message: 'Video deleted successfully'
    });
  } catch (error) {
    console.error('Error deleting video:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to delete video',
      error: error.message
    });
  }
};

// Update video details
exports.updateVideo = async (req, res) => {
  try {
    const userId = req.user.uid;
    const { videoId } = req.params;
    const { title, description, visibility, tags } = req.body;
    
    const videoRef = db.collection(COLLECTIONS.PLACE_VIDEOS).doc(videoId);
    const videoDoc = await videoRef.get();
    
    if (!videoDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Video not found'
      });
    }
    
    const videoData = videoDoc.data();
    if (videoData.userId !== userId) {
      return res.status(403).json({
        success: false,
        message: 'Unauthorized'
      });
    }
    
    // Validate updates
    const updates = {};
    if (title !== undefined) {
      if (title.length > 100) {
        return res.status(400).json({
          success: false,
          message: 'Title must be 100 characters or less'
        });
      }
      updates.title = title;
    }
    
    if (description !== undefined) {
      if (description.length > 500) {
        return res.status(400).json({
          success: false,
          message: 'Description must be 500 characters or less'
        });
      }
      updates.description = description;
    }
    
    if (visibility !== undefined) {
      const validVisibility = ['public', 'network', 'private'];
      if (!validVisibility.includes(visibility)) {
        return res.status(400).json({
          success: false,
          message: 'Invalid visibility setting'
        });
      }
      updates.visibility = visibility;
    }
    
    if (tags !== undefined) {
      updates.tags = tags;
    }
    
    updates.updatedAt = new Date().toISOString();
    
    await videoRef.update(updates);
    
    const updatedDoc = await videoRef.get();
    
    res.json({
      success: true,
      data: serializeDoc(updatedDoc)
    });
  } catch (error) {
    console.error('Error updating video:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to update video',
      error: error.message
    });
  }
};

// MARK: - Reels Specific Endpoints

// Get reels feed with algorithm
exports.getReelsFeed = async (req, res) => {
  try {
    const userId = req.user.uid;
    const { limit = 20, offset = 0 } = req.query;
    
    // Get user's connections and following list
    const [connections1, connections2, userDoc] = await Promise.all([
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('userId', '==', userId)
        .where('status', '==', 'accepted')
        .get(),
      db.collection(COLLECTIONS.CONNECTIONS)
        .where('connectedUserId', '==', userId)
        .where('status', '==', 'accepted')
        .get(),
      db.collection(COLLECTIONS.USERS).doc(userId).get()
    ]);
    
    const connectionIds = new Set([userId]);
    connections1.docs.forEach(doc => connectionIds.add(doc.data().connectedUserId));
    connections2.docs.forEach(doc => connectionIds.add(doc.data().userId));
    
    const following = userDoc.data()?.following || [];
    following.forEach(id => connectionIds.add(id));
    
    // Algorithm: Mix of following (40%), popular (30%), nearby (20%), random (10%)
    const videos = [];
    const seenVideoIds = new Set();
    
    // 1. Following/connections videos (40%)
    if (connectionIds.size > 1) {
      const followingVideos = await db.collection(COLLECTIONS.PLACE_VIDEOS)
        .where('userId', 'in', Array.from(connectionIds))
        .where('uploadStatus', '==', 'ready')
        .where('deletedAt', '==', null)
        .where('visibility', 'in', ['public', 'network'])
        .orderBy('createdAt', 'desc')
        .limit(8)
        .get();
      
      followingVideos.docs.forEach(doc => {
        if (!seenVideoIds.has(doc.id)) {
          videos.push({ ...serializeDoc(doc), algorithm: 'following' });
          seenVideoIds.add(doc.id);
        }
      });
    }
    
    // 2. Popular videos (30% - based on view count)
    const popularVideos = await db.collection(COLLECTIONS.PLACE_VIDEOS)
      .where('uploadStatus', '==', 'ready')
      .where('deletedAt', '==', null)
      .where('visibility', '==', 'public')
      .orderBy('viewCount', 'desc')
      .limit(6)
      .get();
    
    popularVideos.docs.forEach(doc => {
      if (!seenVideoIds.has(doc.id)) {
        videos.push({ ...serializeDoc(doc), algorithm: 'popular' });
        seenVideoIds.add(doc.id);
      }
    });
    
    // 3. Recent videos (20%)
    const recentVideos = await db.collection(COLLECTIONS.PLACE_VIDEOS)
      .where('uploadStatus', '==', 'ready')
      .where('deletedAt', '==', null)
      .where('visibility', '==', 'public')
      .orderBy('createdAt', 'desc')
      .limit(4)
      .get();
    
    recentVideos.docs.forEach(doc => {
      if (!seenVideoIds.has(doc.id)) {
        videos.push({ ...serializeDoc(doc), algorithm: 'recent' });
        seenVideoIds.add(doc.id);
      }
    });
    
    // 4. Random discovery (10%)
    const randomVideos = await db.collection(COLLECTIONS.PLACE_VIDEOS)
      .where('uploadStatus', '==', 'ready')
      .where('deletedAt', '==', null)
      .where('visibility', '==', 'public')
      .limit(50)
      .get();
    
    const randomDocs = randomVideos.docs
      .filter(doc => !seenVideoIds.has(doc.id))
      .sort(() => Math.random() - 0.5)
      .slice(0, 2);
    
    randomDocs.forEach(doc => {
      videos.push({ ...serializeDoc(doc), algorithm: 'discovery' });
    });
    
    // Shuffle for variety
    const shuffledVideos = videos.sort(() => Math.random() - 0.5);
    
    // Apply pagination
    const paginatedVideos = shuffledVideos.slice(parseInt(offset), parseInt(offset) + parseInt(limit));
    
    // Populate user details
    const userIds = [...new Set(paginatedVideos.map(v => v.userId))];
    const userDocs = await Promise.all(
      userIds.map(id => db.collection(COLLECTIONS.USERS).doc(id).get())
    );
    
    const usersMap = {};
    userDocs.forEach(doc => {
      if (doc.exists) {
        const userData = doc.data();
        usersMap[doc.id] = {
          id: doc.id,
          displayName: userData.displayName,
          profilePicture: userData.profilePicture,
          isVerified: userData.isVerified || false
        };
      }
    });
    
    // Add user details to videos
    const videosWithUsers = paginatedVideos.map(video => ({
      ...video,
      user: usersMap[video.userId] || null
    }));
    
    res.json({
      success: true,
      data: videosWithUsers,
      hasMore: shuffledVideos.length > parseInt(offset) + parseInt(limit)
    });
  } catch (error) {
    console.error('Error getting reels feed:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get reels feed',
      error: error.message
    });
  }
};

// Get user's reels
exports.getUserReels = async (req, res) => {
  try {
    const { userId } = req.params;
    const { limit = 20, offset = 0 } = req.query;
    
    const videosQuery = await db.collection(COLLECTIONS.PLACE_VIDEOS)
      .where('userId', '==', userId)
      .where('uploadStatus', '==', 'ready')
      .where('deletedAt', '==', null)
      .orderBy('createdAt', 'desc')
      .limit(parseInt(limit))
      .offset(parseInt(offset))
      .get();
    
    const videos = serializeQuerySnapshot(videosQuery);
    
    res.json({
      success: true,
      data: videos,
      hasMore: videos.length === parseInt(limit)
    });
  } catch (error) {
    console.error('Error getting user reels:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get user reels',
      error: error.message
    });
  }
};

// Get place's reels
exports.getPlaceReels = async (req, res) => {
  try {
    const { placeId } = req.params;
    const { limit = 20, offset = 0 } = req.query;
    
    const videosQuery = await db.collection(COLLECTIONS.PLACE_VIDEOS)
      .where('placeId', '==', placeId)
      .where('uploadStatus', '==', 'ready')
      .where('deletedAt', '==', null)
      .orderBy('createdAt', 'desc')
      .limit(parseInt(limit))
      .offset(parseInt(offset))
      .get();
    
    const videos = serializeQuerySnapshot(videosQuery);
    
    res.json({
      success: true,
      data: videos,
      hasMore: videos.length === parseInt(limit)
    });
  } catch (error) {
    console.error('Error getting place reels:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get place reels',
      error: error.message
    });
  }
};

// Like a reel
exports.likeReel = async (req, res) => {
  try {
    const userId = req.user.uid;
    const { videoId } = req.params;
    
    const videoRef = db.collection(COLLECTIONS.PLACE_VIDEOS).doc(videoId);
    
    // Check if already liked
    const likeRef = db.collection(COLLECTIONS.VIDEO_LIKES)
      .doc(`${userId}_${videoId}`);
    
    const likeDoc = await likeRef.get();
    
    if (likeDoc.exists) {
      return res.status(400).json({
        success: false,
        message: 'Already liked this video'
      });
    }
    
    // Add like
    await likeRef.set({
      userId,
      videoId,
      createdAt: new Date().toISOString()
    });
    
    // Update video like count
    await videoRef.update({
      likeCount: FieldValue.increment(1)
    });
    
    res.json({
      success: true,
      message: 'Video liked successfully'
    });
  } catch (error) {
    console.error('Error liking reel:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to like video',
      error: error.message
    });
  }
};

// Unlike a reel
exports.unlikeReel = async (req, res) => {
  try {
    const userId = req.user.uid;
    const { videoId } = req.params;
    
    const videoRef = db.collection(COLLECTIONS.PLACE_VIDEOS).doc(videoId);
    const likeRef = db.collection(COLLECTIONS.VIDEO_LIKES)
      .doc(`${userId}_${videoId}`);
    
    const likeDoc = await likeRef.get();
    
    if (!likeDoc.exists) {
      return res.status(400).json({
        success: false,
        message: 'Video not liked'
      });
    }
    
    // Remove like
    await likeRef.delete();
    
    // Update video like count
    await videoRef.update({
      likeCount: FieldValue.increment(-1)
    });
    
    res.json({
      success: true,
      message: 'Video unliked successfully'
    });
  } catch (error) {
    console.error('Error unliking reel:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to unlike video',
      error: error.message
    });
  }
};

// Track reel view
exports.trackReelView = async (req, res) => {
  try {
    const userId = req.user?.uid;
    const { videoId } = req.params;
    
    const videoRef = db.collection(COLLECTIONS.PLACE_VIDEOS).doc(videoId);
    
    // Update view count and last viewed
    const updates = {
      viewCount: FieldValue.increment(1),
      lastViewedAt: new Date().toISOString()
    };
    
    await videoRef.update(updates);
    
    // Track individual view if user is logged in
    if (userId) {
      const viewRef = db.collection(COLLECTIONS.VIDEO_VIEWS)
        .doc(`${userId}_${videoId}_${Date.now()}`);
      
      await viewRef.set({
        userId,
        videoId,
        viewedAt: new Date().toISOString()
      });
    }
    
    res.json({
      success: true,
      message: 'View tracked successfully'
    });
  } catch (error) {
    console.error('Error tracking view:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to track view',
      error: error.message
    });
  }
};

// Add embedded video link
exports.addEmbeddedVideo = async (req, res) => {
  const oembedService = require('../services/oembedService');
  
  try {
    const userId = req.user.uid;
    const {
      url,
      placeId,
      placeName,
      title,
      description,
      visibility = 'public',
      tags = []
    } = req.body;
    
    // Validate URL
    if (!url || !url.startsWith('http')) {
      return res.status(400).json({
        success: false,
        message: 'Invalid video URL'
      });
    }
    
    // Fetch video metadata from platform
    let metadata;
    try {
      metadata = await oembedService.fetchMetadata(url);
    } catch (error) {
      return res.status(400).json({
        success: false,
        message: 'Unable to fetch video information. Please check the URL and try again.'
      });
    }
    
    // Create video document
    const videoData = {
      placeId,
      placeName,
      userId,
      title: title || metadata.title,
      description: description || '',
      visibility,
      tags,
      
      // Embedded video specific fields
      videoType: 'embedded',
      embedUrl: url,
      embedPlatform: metadata.platform,
      embedHtml: oembedService.sanitizeEmbedHtml(metadata.embedHtml),
      embedMetadata: {
        author: metadata.author,
        authorUrl: metadata.authorUrl,
        providerName: metadata.providerName,
        providerUrl: metadata.providerUrl,
        width: metadata.width,
        height: metadata.height
      },
      
      // Use thumbnail from platform
      thumbnailUrl: metadata.thumbnailUrl,
      
      // Standard fields
      duration: metadata.duration || 0,
      viewCount: 0,
      likeCount: 0,
      commentCount: 0,
      uploadStatus: 'ready', // Embedded videos are immediately ready
      
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
      deletedAt: null
    };
    
    const videoRef = await db.collection(COLLECTIONS.PLACE_VIDEOS).add(videoData);
    const videoId = videoRef.id;
    
    // Create activity
    await createActivity({
      type: 'videoUploaded',
      actorId: userId,
      objectType: 'video',
      objectId: videoId,
      placeId: placeId,
      placeName: placeName,
      metadata: {
        videoTitle: videoData.title,
        platform: metadata.platform
      }
    });
    
    res.json({
      success: true,
      data: {
        ...videoData,
        _id: videoId
      }
    });
  } catch (error) {
    console.error('Error adding embedded video:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to add embedded video',
      error: error.message
    });
  }
};

// Get video metadata from URL (for preview)
exports.getVideoMetadata = async (req, res) => {
  const oembedService = require('../services/oembedService');
  
  try {
    const { url } = req.query;
    
    if (!url) {
      return res.status(400).json({
        success: false,
        message: 'URL is required'
      });
    }
    
    const metadata = await oembedService.fetchMetadata(url);
    
    res.json({
      success: true,
      data: metadata
    });
  } catch (error) {
    console.error('Error fetching video metadata:', error);
    res.status(400).json({
      success: false,
      message: error.message || 'Failed to fetch video metadata'
    });
  }
};