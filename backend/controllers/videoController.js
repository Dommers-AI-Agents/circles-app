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
const videoQuotaService = require('../services/videoQuotaService');

const db = getFirestore();
const bucket = getStorage().bucket();

// Helper function to ensure My Moments circle exists for a user
async function ensureMyMomentsCircle(userId) {
  try {
    // Check if My Moments circle already exists
    const circlesRef = db.collection(COLLECTIONS.CIRCLES);
    const myMomentsQuery = await circlesRef
      .where('userId', '==', userId)
      .where('isSystemCircle', '==', true)
      .where('name', '==', 'My Moments')
      .limit(1)
      .get();
    
    if (!myMomentsQuery.empty) {
      // My Moments circle already exists
      return { id: myMomentsQuery.docs[0].id, ...myMomentsQuery.docs[0].data() };
    }
    
    // Create My Moments circle
    const { createCircle } = require('../models/FirestoreModels');
    const myMomentsData = createCircle({
      name: 'My Moments',
      description: 'Places from your moments and memories',
      privacy: 'private',
      isSystemCircle: true // Special flag for system-created circles
    }, userId);
    
    const circleRef = await circlesRef.add(myMomentsData);
    console.log(`✨ Created My Moments circle for user ${userId}`);
    
    return { id: circleRef.id, ...myMomentsData };
  } catch (error) {
    console.error('Error ensuring My Moments circle:', error);
    throw error;
  }
}

// Helper function to create a place in My Moments circle
async function createPlaceInMyMoments(userId, circleId, placeData) {
  try {
    const { createPlace } = require('../models/FirestoreModels');
    
    // Create location object if coordinates provided
    let location = null;
    if (placeData.coordinates && placeData.coordinates.length === 2) {
      location = {
        type: 'Point',
        coordinates: placeData.coordinates // [longitude, latitude]
      };
    }
    
    const newPlace = createPlace({
      circleId,
      name: placeData.name,
      description: placeData.description || '',
      address: placeData.address || '',
      location,
      website: placeData.website || '',
      phone: placeData.phone || '',
      category: placeData.category || 'other',
      privacy: 'private', // Default to private for My Moments
      addedViaCheckIn: false,
      notes: '',
      tags: []
    }, userId);
    
    const placeRef = await db.collection(COLLECTIONS.PLACES).add(newPlace);
    
    return { id: placeRef.id, ...newPlace };
  } catch (error) {
    console.error('Error creating place in My Moments:', error);
    throw error;
  }
}

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
      // Create new quota record with correct tier based on subscription status
      const tier = await videoQuotaService.getUserSubscriptionTier(userId);
      const newQuota = createUserVideoQuota(userId, tier);
      await quotaRef.set(newQuota);
      quotaData = newQuota;
    } else {
      quotaData = quotaDoc.data();
      
      // Reset quota if new month
      if (quotaData.currentMonth !== currentMonth) {
        // Also update tier when resetting for new month
        const currentTier = await videoQuotaService.getUserSubscriptionTier(userId);
        quotaData = {
          ...quotaData,
          currentMonth: currentMonth,
          videosUploaded: 0,
          totalSize: 0,
          lastResetDate: now.toISOString(),
          updatedAt: now.toISOString(),
          subscriptionTier: currentTier,
          quotaLimit: currentTier === 'free' ? 5 : 50,
          sizeLimit: currentTier === 'free' ? 262144000 : 2147483648
        };
        await quotaRef.update(quotaData);
      } else {
        // Check if subscription tier has changed
        const currentTier = await videoQuotaService.getUserSubscriptionTier(userId);
        if (quotaData.subscriptionTier !== currentTier) {
          // Update quota limits based on new tier
          const updates = {
            subscriptionTier: currentTier,
            quotaLimit: currentTier === 'free' ? 5 : 50,
            sizeLimit: currentTier === 'free' ? 262144000 : 2147483648, // 250MB : 2GB
            updatedAt: now.toISOString()
          };
          await quotaRef.update(updates);
          quotaData = { ...quotaData, ...updates };
        }
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
      tags,
      contentType, // 'photo' or 'video'
      // New place data for creating places
      placeAddress,
      placeCoordinates,
      placeCategory,
      placeDescription,
      placePhone,
      placeWebsite,
      isNewPlace // Flag to indicate if place needs to be created
    } = req.body;
    
    // Validate video data
    const errors = validatePlaceVideo(req.body);
    if (errors.length > 0) {
      return res.status(400).json({
        success: false,
        errors
      });
    }
    
    // Check quota - create if doesn't exist
    const now = new Date();
    const currentMonth = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
    
    const quotaRef = db.collection(COLLECTIONS.USER_VIDEO_QUOTAS).doc(userId);
    const quotaDoc = await quotaRef.get();
    
    let quotaData;
    if (!quotaDoc.exists) {
      // Create new quota record with correct tier based on subscription status
      const tier = await videoQuotaService.getUserSubscriptionTier(userId);
      const newQuota = createUserVideoQuota(userId, tier);
      await quotaRef.set(newQuota);
      quotaData = newQuota;
      console.log(`📹 Created new video quota for user ${userId} with ${tier} tier`);
    } else {
      quotaData = quotaDoc.data();
      
      // Reset quota if new month
      if (quotaData.currentMonth !== currentMonth) {
        // Also update tier when resetting for new month
        const currentTier = await videoQuotaService.getUserSubscriptionTier(userId);
        quotaData = {
          ...quotaData,
          currentMonth: currentMonth,
          videosUploaded: 0,
          totalSize: 0,
          lastResetDate: now.toISOString(),
          updatedAt: now.toISOString(),
          subscriptionTier: currentTier,
          quotaLimit: currentTier === 'free' ? 5 : 50,
          sizeLimit: currentTier === 'free' ? 262144000 : 2147483648
        };
        await quotaRef.update(quotaData);
        console.log(`📹 Reset monthly quota for user ${userId} with ${currentTier} tier`);
      } else {
        // Check if subscription tier has changed
        const currentTier = await videoQuotaService.getUserSubscriptionTier(userId);
        if (quotaData.subscriptionTier !== currentTier) {
          // Update quota limits based on new tier
          const updates = {
            subscriptionTier: currentTier,
            quotaLimit: currentTier === 'free' ? 5 : 50,
            sizeLimit: currentTier === 'free' ? 262144000 : 2147483648, // 250MB : 2GB
            updatedAt: now.toISOString()
          };
          await quotaRef.update(updates);
          quotaData = { ...quotaData, ...updates };
          console.log(`📹 Updated quota tier for user ${userId} from ${quotaData.subscriptionTier} to ${currentTier}`);
        }
      }
    }
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
    
    // Handle new place creation if needed
    let finalPlaceId = placeId;
    let finalPlaceName = placeName;
    
    if (isNewPlace) {
      // Ensure My Moments circle exists for the user
      const myMomentsCircle = await ensureMyMomentsCircle(userId);
      
      // Create the new place in My Moments circle
      const newPlace = await createPlaceInMyMoments(userId, myMomentsCircle.id, {
        name: placeName,
        address: placeAddress,
        coordinates: placeCoordinates,
        category: placeCategory || 'other',
        description: placeDescription,
        phone: placePhone,
        website: placeWebsite
      });
      
      finalPlaceId = newPlace.id;
      finalPlaceName = newPlace.name;
      
      console.log(`📍 Created new place "${finalPlaceName}" in My Moments circle for user ${userId}`);
    }
    
    // Create video document (also used for photos in Reels)
    const videoData = createPlaceVideo({
      placeId: finalPlaceId,
      placeName: finalPlaceName,
      duration: contentType === 'photo' ? 0 : duration, // Photos have 0 duration
      fileSize,
      title,
      description,
      visibility,
      tags,
      contentType: contentType || 'video' // Store content type
    }, userId);
    
    const videoRef = await db.collection(COLLECTIONS.PLACE_VIDEOS).add(videoData);
    const videoId = videoRef.id;
    
    // Generate signed URLs for upload
    const timestamp = Date.now();
    const isPhoto = contentType === 'photo';
    const fileExtension = isPhoto ? 'jpg' : 'mp4';
    const videoPath = isPhoto ? null : `videos/${userId}/full/${videoId}_${timestamp}.${fileExtension}`;
    const previewPath = isPhoto ? null : `videos/${userId}/preview/${videoId}_${timestamp}.mp4`;
    const thumbnailPath = `videos/${userId}/thumbnails/${videoId}_${timestamp}.jpg`;
    
    // Generate upload URLs based on content type
    let videoUrl = null;
    let previewUrl = null;
    
    if (!isPhoto && videoPath) {
      [videoUrl] = await bucket.file(videoPath).getSignedUrl({
        version: 'v4',
        action: 'write',
        expires: Date.now() + 30 * 60 * 1000, // 30 minutes
        contentType: 'video/mp4',
      });
      
      [previewUrl] = await bucket.file(previewPath).getSignedUrl({
        version: 'v4',
        action: 'write',
        expires: Date.now() + 30 * 60 * 1000, // 30 minutes
        contentType: 'video/mp4',
      });
    }
    
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
    // Use firebasestorage.googleapis.com for Firebase Storage public URLs
    const bucketName = process.env.FIREBASE_STORAGE_BUCKET || bucket.name || 'circles-app-83b67.firebasestorage.app';
    const baseUrl = `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o`;
    const videoUrl = storagePaths.video ? `${baseUrl}/${encodeURIComponent(storagePaths.video)}?alt=media` : null;
    const previewUrl = storagePaths.preview ? `${baseUrl}/${encodeURIComponent(storagePaths.preview)}?alt=media` : null;
    const thumbnailUrl = `${baseUrl}/${encodeURIComponent(storagePaths.thumbnail)}?alt=media`;
    
    // Debug logging
    console.log('📹 Completing video upload:', {
      videoId,
      storagePaths,
      bucketName,
      videoUrl,
      previewUrl,
      thumbnailUrl,
      contentType: videoData.contentType
    });
    
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
    
    // Create activity and store the ID
    const activityRef = await db.collection(COLLECTIONS.ACTIVITIES).add({
      type: 'video_uploaded',
      actorId: userId,
      targetType: 'place_video',
      targetId: videoId,
      targetName: videoData.placeName,
      circleId: null,
      circleName: null,
      metadata: {
        videoTitle: videoData.title,
        videoThumbnail: thumbnailUrl,
        videoDuration: videoData.duration,
        placeId: videoData.placeId
      },
      timestamp: FieldValue.serverTimestamp(),
      isRead: false,
      viewers: [],
      reactionCount: 0,
      commentCount: 0
    });
    
    // Store activity ID in video document
    await videoRef.update({
      activityId: activityRef.id
    });
    
    // Get updated video
    const updatedDoc = await videoRef.get();
    const updatedVideo = serializeDoc(updatedDoc);
    
    // Fetch user data
    const userDoc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
    if (userDoc.exists) {
      const userData = userDoc.data();
      updatedVideo.user = {
        id: userDoc.id,
        displayName: userData.displayName,
        username: userData.username,
        profilePicture: userData.profilePicture,
        bio: userData.bio
      };
    }
    
    res.json({
      success: true,
      data: updatedVideo
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
    
    // Populate user details
    const userIds = [...new Set(videos.map(v => v.userId))];
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
          username: userData.username,
          profilePicture: userData.profilePicture,
          bio: userData.bio
        };
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
    
    // Return all URLs correctly without overwriting
    // The iOS app expects both videoUrl and previewUrl to be present
    const response = {
      ...serializeDoc(videoDoc)
      // Don't override videoUrl - keep both URLs intact
    };
    
    // Get user details
    const userDoc = await db.collection(COLLECTIONS.USERS).doc(videoData.userId).get();
    if (userDoc.exists) {
      const userData = userDoc.data();
      // Add _id field for iOS compatibility
      response.user = {
        _id: userDoc.id,
        ...userData
      };
    }
    
    // Check if current user has liked this video
    if (userId) {
      const likeDoc = await db.collection(COLLECTIONS.VIDEO_LIKES)
        .doc(`${userId}_${videoId}`)
        .get();
      response.likedByCurrentUser = likeDoc.exists;
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
    
    // Delete files from storage to save space
    try {
      const bucketName = process.env.FIREBASE_STORAGE_BUCKET || 'circles-app-83b67.firebasestorage.app';
      
      // Extract file paths from URLs
      const extractPath = (url) => {
        if (!url) return null;
        // Handle both firebasestorage.googleapis.com and firebasestorage.app URLs
        const patterns = [
          `https://firebasestorage.googleapis.com/v0/b/${bucketName}/o/`,
          `https://${bucketName}/`
        ];
        
        for (const pattern of patterns) {
          if (url.includes(pattern)) {
            const path = url.split(pattern)[1];
            // Remove query parameters and decode
            return decodeURIComponent(path.split('?')[0]);
          }
        }
        return null;
      };
      
      // Delete all associated files from storage
      const filesToDelete = [];
      
      if (videoData.videoUrl) {
        const videoPath = extractPath(videoData.videoUrl);
        if (videoPath) filesToDelete.push(bucket.file(videoPath).delete().catch(err => {
          console.log(`Failed to delete video file: ${err.message}`);
        }));
      }
      
      if (videoData.previewUrl) {
        const previewPath = extractPath(videoData.previewUrl);
        if (previewPath) filesToDelete.push(bucket.file(previewPath).delete().catch(err => {
          console.log(`Failed to delete preview file: ${err.message}`);
        }));
      }
      
      if (videoData.thumbnailUrl) {
        const thumbnailPath = extractPath(videoData.thumbnailUrl);
        if (thumbnailPath) filesToDelete.push(bucket.file(thumbnailPath).delete().catch(err => {
          console.log(`Failed to delete thumbnail file: ${err.message}`);
        }));
      }
      
      // Delete all files from storage
      if (filesToDelete.length > 0) {
        await Promise.all(filesToDelete);
        console.log(`✅ Deleted ${filesToDelete.length} files from storage for video ${videoId}`);
      }
    } catch (storageError) {
      console.error('Error deleting files from storage:', storageError);
      // Continue with database deletion even if storage deletion fails
    }
    
    // Hard delete from database (completely remove the document)
    await videoRef.delete();
    console.log(`✅ Permanently deleted video ${videoId} from database`);
    
    // Update user quota
    const quotaRef = db.collection(COLLECTIONS.USER_VIDEO_QUOTAS).doc(userId);
    await quotaRef.update({
      videosUploaded: FieldValue.increment(-1),
      totalSize: FieldValue.increment(-(videoData.fileSize || 0)),
      updatedAt: new Date().toISOString()
    });
    
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

// Helper function to fetch activity data for videos
const fetchActivityDataForVideos = async (videos, userId) => {
  const videoIds = videos.map(v => v.id);
  if (videoIds.length === 0) return {};
  
  // Fetch activities for these videos
  const activitiesQuery = await db.collection(COLLECTIONS.ACTIVITIES)
    .where('targetType', '==', 'place_video')
    .where('targetId', 'in', videoIds.slice(0, 10)) // Firestore 'in' limit
    .get();
  
  const activitiesMap = {};
  activitiesQuery.docs.forEach(doc => {
    const activity = serializeDoc(doc);
    activitiesMap[activity.targetId] = activity;
  });
  
  // Fetch remaining activities if more than 10 videos
  if (videoIds.length > 10) {
    const remainingActivitiesQuery = await db.collection(COLLECTIONS.ACTIVITIES)
      .where('targetType', '==', 'place_video')
      .where('targetId', 'in', videoIds.slice(10))
      .get();
    
    remainingActivitiesQuery.docs.forEach(doc => {
      const activity = serializeDoc(doc);
      activitiesMap[activity.targetId] = activity;
    });
  }
  
  // Check user reactions
  const activityIds = Object.values(activitiesMap).map(a => a.id);
  if (activityIds.length > 0) {
    const reactionsQuery = await db.collection(COLLECTIONS.ACTIVITY_REACTIONS)
      .where('activityId', 'in', activityIds.slice(0, 10))
      .where('userId', '==', userId)
      .get();
    
    const userReactions = {};
    reactionsQuery.docs.forEach(doc => {
      const reaction = doc.data();
      userReactions[reaction.activityId] = reaction.emoji;
    });
    
    // Add user reaction to activities
    Object.values(activitiesMap).forEach(activity => {
      activity.userReaction = userReactions[activity.id] || null;
    });
  }
  
  return activitiesMap;
};

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
      // Limit to 10 connections to avoid Firestore query limits
      // Randomly select if more than 10 for variety on refresh
      const connectionArray = Array.from(connectionIds);
      const selectedConnections = connectionArray.length > 10 
        ? connectionArray.sort(() => 0.5 - Math.random()).slice(0, 10)
        : connectionArray;
      
      console.log(`📹 Fetching reels from ${selectedConnections.length} connections (out of ${connectionArray.length} total)`);
      
      const followingVideos = await db.collection(COLLECTIONS.PLACE_VIDEOS)
        .where('userId', 'in', selectedConnections)
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
    
    // Check which videos are liked by current user
    const videoIds = paginatedVideos.map(v => v.id);
    const likesQuery = await db.collection(COLLECTIONS.VIDEO_LIKES)
      .where('userId', '==', userId)
      .where('videoId', 'in', videoIds.slice(0, 10)) // Firestore 'in' limit
      .get();
    
    const likedVideoIds = new Set();
    likesQuery.docs.forEach(doc => {
      const [_, videoId] = doc.id.split('_');
      likedVideoIds.add(videoId);
    });
    
    // Check remaining videos if more than 10
    if (videoIds.length > 10) {
      const remainingLikesQuery = await db.collection(COLLECTIONS.VIDEO_LIKES)
        .where('userId', '==', userId)
        .where('videoId', 'in', videoIds.slice(10))
        .get();
      
      remainingLikesQuery.docs.forEach(doc => {
        const [_, videoId] = doc.id.split('_');
        likedVideoIds.add(videoId);
      });
    }
    
    // Fetch activity data for videos
    const activitiesMap = await fetchActivityDataForVideos(paginatedVideos, userId);
    
    // Add user details, like status, and activity data to videos
    const videosWithUsers = paginatedVideos.map(video => {
      const activity = activitiesMap[video.id];
      return {
        ...video,
        user: usersMap[video.userId] || null,
        likedByCurrentUser: likedVideoIds.has(video.id),
        activityId: activity?.id || null,
        activityReactionCount: activity?.reactionCount || 0,
        activityCommentCount: activity?.commentCount || 0,
        userActivityReaction: activity?.userReaction || null
      };
    });
    
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
    const currentUserId = req.user.uid;
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
    
    // Check which videos are liked by current user
    if (videos.length > 0) {
      const videoIds = videos.map(v => v.id);
      const likesQuery = await db.collection(COLLECTIONS.VIDEO_LIKES)
        .where('userId', '==', currentUserId)
        .where('videoId', 'in', videoIds.slice(0, 10)) // Firestore 'in' limit
        .get();
      
      const likedVideoIds = new Set();
      likesQuery.docs.forEach(doc => {
        const [_, videoId] = doc.id.split('_');
        likedVideoIds.add(videoId);
      });
      
      // Check remaining videos if more than 10
      if (videoIds.length > 10) {
        const remainingLikesQuery = await db.collection(COLLECTIONS.VIDEO_LIKES)
          .where('userId', '==', currentUserId)
          .where('videoId', 'in', videoIds.slice(10))
          .get();
        
        remainingLikesQuery.docs.forEach(doc => {
          const [_, videoId] = doc.id.split('_');
          likedVideoIds.add(videoId);
        });
      }
      
      // Add like status to videos
      videos.forEach(video => {
        video.likedByCurrentUser = likedVideoIds.has(video.id);
      });
    }
    
    // Fetch activity data for videos
    const activitiesMap = await fetchActivityDataForVideos(videos, currentUserId);
    
    // Add activity data to videos
    const videosWithActivity = videos.map(video => {
      const activity = activitiesMap[video.id];
      return {
        ...video,
        activityId: activity?.id || null,
        activityReactionCount: activity?.reactionCount || 0,
        activityCommentCount: activity?.commentCount || 0,
        userActivityReaction: activity?.userReaction || null
      };
    });
    
    res.json({
      success: true,
      data: videosWithActivity,
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
const sseService = require('../services/sseService');

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
      timestamp: new Date().toISOString()
    });
    
    // Update video like count
    await videoRef.update({
      likeCount: FieldValue.increment(1)
    });
    
    // Get video details for SSE notification
    const videoDoc = await videoRef.get();
    if (videoDoc.exists) {
      const videoData = videoDoc.data();
      
      // Notify video owner of the like (if not self-like)
      if (videoData.userId && videoData.userId !== userId) {
        sseService.notifyUser(videoData.userId, 'video_liked', {
          videoId,
          likedBy: userId,
          videoTitle: videoData.title,
          timestamp: new Date().toISOString()
        });
      }
      
      // Broadcast to all users viewing this video
      sseService.broadcastVideoEngagement(videoId, 'like', {
        userId,
        videoId,
        type: 'like',
        timestamp: new Date().toISOString()
      });
    }
    
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
    
    // Get video details for SSE notification
    const videoDoc = await videoRef.get();
    if (videoDoc.exists) {
      const videoData = videoDoc.data();
      
      // Broadcast to all users viewing this video
      sseService.broadcastVideoEngagement(videoId, 'unlike', {
        userId,
        videoId,
        type: 'unlike',
        timestamp: new Date().toISOString()
      });
    }
    
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

// MARK: - Video Comments

// Get comments for a video
exports.getVideoComments = async (req, res) => {
  try {
    const { videoId } = req.params;
    const { limit = 20, offset = 0 } = req.query;
    
    // Verify video exists
    const videoDoc = await db.collection(COLLECTIONS.PLACE_VIDEOS).doc(videoId).get();
    if (!videoDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Video not found'
      });
    }
    
    // Get top-level comments (not replies)
    const commentsQuery = await db.collection('video_comments')
      .where('videoId', '==', videoId)
      .where('parentCommentId', '==', null)
      .orderBy('createdAt', 'desc')
      .limit(parseInt(limit))
      .offset(parseInt(offset))
      .get();
    
    const comments = [];
    for (const doc of commentsQuery.docs) {
      const comment = serializeDoc(doc);
      
      // Get user details
      const userDoc = await db.collection(COLLECTIONS.USERS).doc(comment.userId).get();
      if (userDoc.exists) {
        comment.user = serializeDoc(userDoc);
      }
      
      // Get reply count
      const replyCountQuery = await db.collection('video_comments')
        .where('parentCommentId', '==', doc.id)
        .count()
        .get();
      
      comment.replyCount = replyCountQuery.data().count || 0;
      comments.push(comment);
    }
    
    res.json({
      success: true,
      data: comments,
      hasMore: comments.length === parseInt(limit)
    });
  } catch (error) {
    console.error('Error getting video comments:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get comments',
      error: error.message
    });
  }
};

// Create a comment on a video
exports.createVideoComment = async (req, res) => {
  try {
    const userId = req.user.uid;
    const { videoId } = req.params;
    const { text } = req.body;
    
    // Validate input
    if (!text || text.trim().length === 0) {
      return res.status(400).json({
        success: false,
        message: 'Comment text is required'
      });
    }
    
    // Verify video exists
    const videoRef = db.collection(COLLECTIONS.PLACE_VIDEOS).doc(videoId);
    const videoDoc = await videoRef.get();
    
    if (!videoDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Video not found'
      });
    }
    
    const video = videoDoc.data();
    
    // Create comment
    const commentData = {
      videoId,
      userId,
      text: text.trim(),
      parentCommentId: null,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
      editedAt: null,
      deletedAt: null
    };
    
    const commentRef = await db.collection('video_comments').add(commentData);
    const commentDoc = await commentRef.get();
    const comment = serializeDoc(commentDoc);
    
    // Get user details
    const userDoc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
    if (userDoc.exists) {
      comment.user = serializeDoc(userDoc);
    }
    
    // Update video comment count
    await videoRef.update({
      commentCount: FieldValue.increment(1)
    });
    
    // Send SSE notification
    const userData = comment.user || {};
    
    // Notify video owner of the comment (if not self-comment)
    if (video.userId && video.userId !== userId) {
      sseService.notifyUser(video.userId, 'video_comment', {
        videoId,
        commentBy: userId,
        commentByName: userData.displayName || 'Unknown User',
        videoTitle: video.title,
        commentText: text.trim(),
        timestamp: new Date().toISOString()
      });
    }
    
    // Broadcast to all users viewing this video
    sseService.broadcastVideoEngagement(videoId, 'comment', {
      userId,
      videoId,
      type: 'comment',
      comment: comment,
      timestamp: new Date().toISOString()
    });
    
    res.json({
      success: true,
      data: comment
    });
  } catch (error) {
    console.error('Error creating video comment:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to create comment',
      error: error.message
    });
  }
};

// Get activity for a video
exports.getVideoActivity = async (req, res) => {
  try {
    const { videoId } = req.params;
    const userId = req.user.uid;
    
    // Find activity for this video
    const activityQuery = await db.collection(COLLECTIONS.ACTIVITIES)
      .where('targetType', '==', 'place_video')
      .where('targetId', '==', videoId)
      .limit(1)
      .get();
    
    if (activityQuery.empty) {
      return res.status(404).json({
        success: false,
        message: 'Activity not found for this video'
      });
    }
    
    const activity = serializeDoc(activityQuery.docs[0]);
    
    // Check if user has reacted
    const reactionQuery = await db.collection(COLLECTIONS.ACTIVITY_REACTIONS)
      .where('activityId', '==', activity.id)
      .where('userId', '==', userId)
      .limit(1)
      .get();
    
    if (!reactionQuery.empty) {
      activity.userReaction = reactionQuery.docs[0].data().emoji;
    } else {
      activity.userReaction = null;
    }
    
    // Get reaction summary
    const reactionsQuery = await db.collection(COLLECTIONS.ACTIVITY_REACTIONS)
      .where('activityId', '==', activity.id)
      .get();
    
    const reactionCounts = {};
    reactionsQuery.docs.forEach(doc => {
      const emoji = doc.data().emoji;
      reactionCounts[emoji] = (reactionCounts[emoji] || 0) + 1;
    });
    
    activity.reactionSummary = Object.entries(reactionCounts)
      .map(([emoji, count]) => ({ emoji, count }))
      .sort((a, b) => b.count - a.count)
      .slice(0, 3);
    
    res.json({
      success: true,
      data: activity
    });
  } catch (error) {
    console.error('Error getting video activity:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get video activity',
      error: error.message
    });
  }
};

// Get video likes list
exports.getVideoLikes = async (req, res) => {
  try {
    const { videoId } = req.params;
    const { limit = 50, offset = 0 } = req.query;
    
    // Get likes for the video
    const likesQuery = await db.collection(COLLECTIONS.VIDEO_LIKES)
      .where('videoId', '==', videoId)
      .orderBy('timestamp', 'desc')
      .limit(parseInt(limit))
      .offset(parseInt(offset))
      .get();
    
    // Get user details for each like
    const userIds = likesQuery.docs.map(doc => doc.data().userId);
    
    if (userIds.length === 0) {
      return res.json({
        success: true,
        data: []
      });
    }
    
    // Fetch user details
    const usersQuery = await db.collection(COLLECTIONS.USERS)
      .where(admin.firestore.FieldPath.documentId(), 'in', userIds)
      .get();
    
    const usersMap = {};
    usersQuery.docs.forEach(doc => {
      const user = serializeDoc(doc);
      usersMap[user.id] = user;
    });
    
    // Combine likes with user details
    const likes = likesQuery.docs.map(doc => {
      const likeData = doc.data();
      const user = usersMap[likeData.userId] || {};
      
      return {
        userId: likeData.userId,
        displayName: user.displayName || 'Unknown User',
        profilePicture: user.profilePicture || null,
        timestamp: likeData.timestamp || new Date()
      };
    });
    
    res.json({
      success: true,
      data: likes
    });
  } catch (error) {
    console.error('Error getting video likes:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get video likes',
      error: error.message
    });
  }
};

// Delete a video comment
exports.deleteVideoComment = async (req, res) => {
  try {
    const userId = req.user.uid;
    const { videoId, commentId } = req.params;
    
    // Get the comment
    const commentRef = db.collection('video_comments').doc(commentId);
    const commentDoc = await commentRef.get();
    
    if (!commentDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Comment not found'
      });
    }
    
    const comment = commentDoc.data();
    
    // Check if comment belongs to this video
    if (comment.videoId !== videoId) {
      return res.status(400).json({
        success: false,
        message: 'Comment does not belong to this video'
      });
    }
    
    // Check if user owns the comment
    if (comment.userId !== userId) {
      return res.status(403).json({
        success: false,
        message: 'You can only delete your own comments'
      });
    }
    
    // Soft delete the comment
    await commentRef.update({
      deletedAt: new Date().toISOString(),
      text: '[deleted]'
    });
    
    // Update video comment count
    const videoRef = db.collection(COLLECTIONS.PLACE_VIDEOS).doc(videoId);
    await videoRef.update({
      commentCount: FieldValue.increment(-1)
    });
    
    res.json({
      success: true,
      message: 'Comment deleted successfully'
    });
  } catch (error) {
    console.error('Error deleting video comment:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to delete comment',
      error: error.message
    });
  }
};

// Create a reply to a video comment
exports.createVideoCommentReply = async (req, res) => {
  try {
    const userId = req.user.uid;
    const { videoId, commentId } = req.params;
    const { text } = req.body;
    
    // Validate input
    if (!text || text.trim().length === 0) {
      return res.status(400).json({
        success: false,
        message: 'Reply text is required'
      });
    }
    
    // Verify parent comment exists
    const parentCommentRef = db.collection('video_comments').doc(commentId);
    const parentCommentDoc = await parentCommentRef.get();
    
    if (!parentCommentDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Parent comment not found'
      });
    }
    
    const parentComment = parentCommentDoc.data();
    
    // Ensure parent comment belongs to the video
    if (parentComment.videoId !== videoId) {
      return res.status(400).json({
        success: false,
        message: 'Comment does not belong to this video'
      });
    }
    
    // Create reply
    const replyData = {
      videoId,
      userId,
      text: text.trim(),
      parentCommentId: commentId,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
      editedAt: null,
      deletedAt: null
    };
    
    const replyRef = await db.collection('video_comments').add(replyData);
    const replyDoc = await replyRef.get();
    const reply = serializeDoc(replyDoc);
    
    // Get user details
    const userDoc = await db.collection(COLLECTIONS.USERS).doc(userId).get();
    if (userDoc.exists) {
      reply.user = serializeDoc(userDoc);
    }
    
    // TODO: Send notification to parent comment author
    
    res.json({
      success: true,
      data: reply
    });
  } catch (error) {
    console.error('Error creating video comment reply:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to create reply',
      error: error.message
    });
  }
};

// Like or unlike a video comment
exports.likeVideoComment = async (req, res) => {
  try {
    const userId = req.user.uid;
    const { videoId, commentId } = req.params;
    
    // Get the comment
    const commentRef = db.collection('video_comments').doc(commentId);
    const commentDoc = await commentRef.get();
    
    if (!commentDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Comment not found'
      });
    }
    
    const comment = commentDoc.data();
    
    // Check if comment belongs to this video
    if (comment.videoId !== videoId) {
      return res.status(400).json({
        success: false,
        message: 'Comment does not belong to this video'
      });
    }
    
    // Get current likes array or initialize
    let likes = comment.likes || [];
    let liked = false;
    
    // Toggle like status
    if (likes.includes(userId)) {
      // Unlike - remove user from likes array
      likes = likes.filter(id => id !== userId);
      liked = false;
    } else {
      // Like - add user to likes array
      likes.push(userId);
      liked = true;
    }
    
    // Update comment with new likes array and count
    await commentRef.update({
      likes: likes,
      likesCount: likes.length,
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    });
    
    // Log activity if liking (not unliking)
    if (liked && comment.userId !== userId) {
      try {
        await logActivity({
          type: 'comment_liked',
          actorId: userId,
          targetType: 'comment',
          targetId: commentId,
          targetName: comment.text.substring(0, 50) + (comment.text.length > 50 ? '...' : ''),
          metadata: {
            videoId: videoId,
            commentId: commentId,
            commentAuthorId: comment.userId
          }
        });
      } catch (activityError) {
        console.error('Failed to log like activity:', activityError);
        // Don't fail the request if activity logging fails
      }
    }
    
    res.json({
      success: true,
      liked: liked,
      likesCount: likes.length
    });
    
  } catch (error) {
    console.error('Error liking video comment:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to update comment like',
      error: error.message
    });
  }
};

// Get replies for a video comment
exports.getVideoCommentReplies = async (req, res) => {
  try {
    const { videoId, commentId } = req.params;
    
    // Verify parent comment exists
    const parentCommentDoc = await db.collection('video_comments').doc(commentId).get();
    
    if (!parentCommentDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Parent comment not found'
      });
    }
    
    const parentComment = parentCommentDoc.data();
    
    if (parentComment.videoId !== videoId) {
      return res.status(400).json({
        success: false,
        message: 'Comment does not belong to this video'
      });
    }
    
    // Get replies
    const repliesQuery = await db.collection('video_comments')
      .where('parentCommentId', '==', commentId)
      .orderBy('createdAt', 'asc')
      .get();
    
    const replies = [];
    for (const replyDoc of repliesQuery.docs) {
      const reply = serializeDoc(replyDoc);
      
      // Get user details
      const userDoc = await db.collection(COLLECTIONS.USERS).doc(reply.userId).get();
      if (userDoc.exists) {
        reply.user = serializeDoc(userDoc);
      }
      
      replies.push(reply);
    }
    
    res.json({
      success: true,
      data: replies
    });
  } catch (error) {
    console.error('Error getting video comment replies:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to get replies',
      error: error.message
    });
  }
};