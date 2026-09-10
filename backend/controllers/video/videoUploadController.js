// controllers/video/videoUploadController.js
// Moment upload lifecycle: quota, initiate/complete, embeds, tags, edit, delete, status
// Split out of videoController.js (handlers unchanged).
// backend/controllers/videoController.js
const { getFirestore, FieldValue, admin } = require('../../config/firebase');
const { getStorage } = require('firebase-admin/storage');
const { COLLECTIONS, createPlaceVideo, createUserVideoQuota, validatePlaceVideo, serializeDoc } = require('../../models/FirestoreModels');
const { createActivity } = require('../activityController');
const videoQuotaService = require('../../services/videoQuotaService');
const axios = require('axios');
const db = getFirestore();
const bucket = getStorage().bucket();
// Initiate video upload
// Tags on a moment: accepted connections only, capped, resolved to
// denormalized {id, displayName, profilePicture} at write time. Never trusts
// the client list — every id is re-checked against the connections collection.
const notificationService = require('../../services/notificationService');
const MAX_MOMENT_TAGS = 10;

// Helper function to verify video processing is complete
async function verifyVideoProcessing(videoUrl, previewUrl, thumbnailUrl) {
  try {
    const timeout = 10000; // 10 second timeout
    
    // Check if main files are accessible using axios
    const checks = [
      axios.head(videoUrl, { timeout }),
      axios.head(thumbnailUrl, { timeout })
    ];
    
    // Only check preview if it exists (photos don't have preview)
    if (previewUrl) {
      checks.push(axios.head(previewUrl, { timeout }));
    }
    
    const results = await Promise.allSettled(checks);
    
    // Check if all requests succeeded
    const allSuccessful = results.every(result => 
      result.status === 'fulfilled' && 
      result.value.status >= 200 && 
      result.value.status < 400
    );
    
    console.log('📹 Video processing verification:', {
      videoUrl: results[0].status === 'fulfilled' && results[0].value?.status < 400,
      thumbnailUrl: results[1].status === 'fulfilled' && results[1].value?.status < 400,
      previewUrl: previewUrl ? (results[2]?.status === 'fulfilled' && results[2]?.value?.status < 400) : 'N/A',
      allSuccessful
    });
    
    return allSuccessful;
  } catch (error) {
    console.error('❌ Video processing verification failed:', error);
    // Return true to avoid blocking uploads due to verification errors
    return true;
  }
}

// Helper function to ensure My Moments circle exists for a user
async function ensureMyMomentsCircle(userId) {
  try {
    // Check if My Moments circle already exists.
    // Circles key ownership on `owner` — the old `userId` filter matched
    // nothing, so every moment-with-new-place minted a fresh circle.
    const circlesRef = db.collection(COLLECTIONS.CIRCLES);
    const myMomentsQuery = await circlesRef
      .where('owner', '==', userId)
      .where('isSystemCircle', '==', true)
      .where('name', '==', 'My Moments')
      .limit(1)
      .get();
    
    if (!myMomentsQuery.empty) {
      // My Moments circle already exists
      return { id: myMomentsQuery.docs[0].id, ...myMomentsQuery.docs[0].data() };
    }
    
    // Create My Moments circle
    const { createCircle } = require('../../models/FirestoreModels');
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

// Venue-level lookup: does this user already have a live save of this place?
// Same normalized name within 250m counts as the same venue regardless of
// address formatting — creating a second save fragments likes/comments across
// two canonical records (the "Leroy Fox saved twice" bug; import dedup got
// the same tier 2026-08-12). Without coordinates there's no safe match —
// name alone would collapse chains ("Planet Fitness").
async function findExistingUserPlaceForVenue(userId, name, coordinates) {
  if (!name || !Array.isArray(coordinates) || coordinates.length !== 2) return null;

  const norm = s => (s || '').toLowerCase().trim().replace(/[^\w\s]/g, '').replace(/\s+/g, ' ');
  const target = norm(name);
  const [lng, lat] = coordinates;

  const distanceMeters = (lat1, lng1, lat2, lng2) => {
    const R = 6371000;
    const dLat = (lat2 - lat1) * Math.PI / 180;
    const dLng = (lng2 - lng1) * Math.PI / 180;
    const s = Math.sin(dLat / 2) ** 2 +
      Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) * Math.sin(dLng / 2) ** 2;
    return 2 * R * Math.asin(Math.sqrt(s));
  };

  const snapshot = await db.collection(COLLECTIONS.PLACES)
    .where('addedBy', '==', userId)
    .get();

  let match = null;
  snapshot.forEach(doc => {
    if (match) return;
    const place = doc.data();
    if (place.deletedAt) return;
    if (norm(place.name) !== target) return;
    const coords = place.location && place.location.coordinates;
    if (Array.isArray(coords) && coords.length === 2 &&
        distanceMeters(lat, lng, coords[1], coords[0]) < 250) {
      match = { id: doc.id, ...place };
    }
  });
  return match;
}

// Helper function to create a place in My Moments circle
async function createPlaceInMyMoments(userId, circleId, placeData) {
  try {
    const { createPlace } = require('../../models/FirestoreModels');
    
    // Create location object if coordinates provided
    let location = null;
    if (placeData.coordinates && placeData.coordinates.length === 2) {
      location = {
        type: 'Point',
        coordinates: placeData.coordinates // [longitude, latitude]
      };
    }
    
    // Prepare place data object (without circleId)
    const placeDataForCreation = {
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
    };
    
    // Call createPlace with correct parameter order: placeData, circleId, addedBy
    const newPlace = createPlace(placeDataForCreation, circleId, userId);

    const placeRef = await db.collection(COLLECTIONS.PLACES).add(newPlace);

    // Track membership on the circle doc too — every other save path does,
    // and the circle screen counts on places[]/placesCount
    const { FieldValue } = require('firebase-admin').firestore;
    await db.collection(COLLECTIONS.CIRCLES).doc(circleId).update({
      places: FieldValue.arrayUnion(placeRef.id),
      placesCount: FieldValue.increment(1),
      updatedAt: new Date().toISOString()
    });

    // Link the save to its canonical venue record (best-effort)
    const { ensureGlobalPlaceLink } = require('../../services/globalPlaceResolver');
    const globalPlaceId = await ensureGlobalPlaceLink(await placeRef.get());

    // Keep the browse location tree fresh (best-effort)
    const { indexSavedPlace } = require('../../services/circleLocationSummary');
    indexSavedPlace(circleId, placeDataForCreation);

    return { id: placeRef.id, ...newPlace, ...(globalPlaceId ? { globalPlaceId } : {}) };
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

async function resolveTaggedConnections(userId, requestedIds) {
  const ids = [...new Set((Array.isArray(requestedIds) ? requestedIds : [])
    .filter(id => typeof id === 'string' && id.trim() && id !== userId))]
    .slice(0, MAX_MOMENT_TAGS);
  if (ids.length === 0) return { taggedUserIds: [], taggedUsers: [] };

  const [outgoing, incoming] = await Promise.all([
    db.collection(COLLECTIONS.CONNECTIONS)
      .where('userId', '==', userId).where('status', '==', 'accepted').get(),
    db.collection(COLLECTIONS.CONNECTIONS)
      .where('connectedUserId', '==', userId).where('status', '==', 'accepted').get()
  ]);
  const connected = new Set();
  outgoing.forEach(doc => connected.add(doc.data().connectedUserId));
  incoming.forEach(doc => connected.add(doc.data().userId));

  const accepted = ids.filter(id => connected.has(id));
  const taggedUsers = [];
  for (const id of accepted) {
    const userDoc = await db.collection(COLLECTIONS.USERS).doc(id).get();
    if (!userDoc.exists) continue;
    const data = userDoc.data();
    taggedUsers.push({
      id,
      displayName: data.displayName || 'Someone',
      profilePicture: data.profilePicture || null
    });
  }
  return { taggedUserIds: taggedUsers.map(u => u.id), taggedUsers };
}

async function notifyMomentTags(videoData, videoId, taggerId) {
  if (!Array.isArray(videoData.taggedUserIds) || videoData.taggedUserIds.length === 0) return;
  try {
    const taggerDoc = await db.collection(COLLECTIONS.USERS).doc(taggerId).get();
    const taggerName = taggerDoc.exists ? taggerDoc.data().displayName : 'Someone';
    const taggerPhoto = taggerDoc.exists ? taggerDoc.data().profilePicture : null;
    for (const recipientId of videoData.taggedUserIds) {
      await notificationService.notifyMomentTag(recipientId, {
        taggerId,
        taggerName,
        taggerPhoto,
        videoId,
        placeId: videoData.placeId || null,
        placeName: videoData.placeName || null
      }).catch(err => console.error(`⚠️ moment_tag notify failed for ${recipientId}:`, err.message));
    }
  } catch (error) {
    console.error('⚠️ moment_tag notifications failed (non-fatal):', error.message);
  }
}

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
      isNewPlace, // Flag to indicate if place needs to be created
      taggedUserIds // people in this moment (accepted connections only)
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
      // The client flags isNewPlace whenever the place came from search
      // rather than the user's saves — but the user may well have this venue
      // saved already. Reuse it instead of minting a My Moments copy.
      const existingSave = await findExistingUserPlaceForVenue(userId, placeName, placeCoordinates);
      if (existingSave) {
        finalPlaceId = existingSave.id;
        finalPlaceName = existingSave.name;
        console.log(`📍 Reusing existing save "${finalPlaceName}" (${finalPlaceId}) for moment instead of creating a My Moments copy`);
      } else {
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
    }
    
    // Tags: validated against accepted connections; a private ("only me")
    // moment carries no tags — tagging someone into content they can't view
    // would only confuse (and the feed row never exists for private moments).
    const resolvedTags = visibility === 'private'
      ? { taggedUserIds: [], taggedUsers: [] }
      : await resolveTaggedConnections(userId, taggedUserIds);

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
      taggedUserIds: resolvedTags.taggedUserIds,
      taggedUsers: resolvedTags.taggedUsers,
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
    
    // First update with processing status
    await videoRef.update({
      videoUrl,
      previewUrl,
      thumbnailUrl,
      originalSize,
      compressionRatio,
      uploadStatus: 'processing',
      uploadProgress: 90,
      updatedAt: new Date().toISOString()
    });
    
    // Verify video files are accessible with retry logic
    let isVideoReady = false;
    const maxRetries = 3;
    
    for (let i = 0; i < maxRetries && !isVideoReady; i++) {
      if (i > 0) {
        // Wait before retrying (exponential backoff: 1s, 2s, 4s)
        const delay = 1000 * Math.pow(2, i - 1);
        console.log(`📹 Retry ${i}/${maxRetries - 1}: Waiting ${delay}ms before verification...`);
        await new Promise(resolve => setTimeout(resolve, delay));
      }
      
      isVideoReady = await verifyVideoProcessing(videoUrl, previewUrl, thumbnailUrl);
      
      if (!isVideoReady && i < maxRetries - 1) {
        console.log(`📹 Verification failed, will retry (attempt ${i + 1}/${maxRetries})`);
      }
    }
    
    // If verification still fails after retries, mark as ready anyway
    // to avoid blocking uploads (files might be accessible but verification failed)
    if (!isVideoReady) {
      console.log('⚠️ Video verification failed after retries, marking as ready anyway');
      isVideoReady = true;
    }
    
    // Final update to ready status
    await videoRef.update({
      uploadStatus: isVideoReady ? 'ready' : 'error',
      uploadProgress: isVideoReady ? 100 : 0,
      updatedAt: new Date().toISOString(),
      processingCompleted: isVideoReady ? new Date().toISOString() : null
    });

    // Piggy bank: 2 FavCoins per Moment that finishes uploading (per-video
    // dedup; deleting it inside the clearing window reverses the earn).
    if (isVideoReady) {
      require('../../services/piggyBankService').credit({
        userId,
        eventType: 'moment_posted',
        sourceRef: { videoId }
      }).catch(() => {});
    }
    
    // Update user quota
    const quotaRef = db.collection(COLLECTIONS.USER_VIDEO_QUOTAS).doc(userId);
    await quotaRef.update({
      videosUploaded: FieldValue.increment(1),
      totalSize: FieldValue.increment(videoData.fileSize),
      updatedAt: new Date().toISOString()
    });
    
    // Create the feed activity — but never for a private ("only me") moment,
    // which must not broadcast to connections/followers. The stamped
    // momentVisibility/momentOwnerId let the feed gate the row to viewers who
    // are actually entitled to the moment (see getNetworkActivities).
    if (videoData.visibility !== 'private') {
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
          placeId: videoData.placeId,
          momentVisibility: videoData.visibility || 'public',
          momentOwnerId: userId,
          // Photo moments ride the video pipeline; the feed row wording
          // ("shared a photo" vs "uploaded a video") keys off this
          contentType: videoData.contentType || 'video'
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
    }
    
    // Tagged people hear about it now that the moment is actually viewable
    notifyMomentTags(videoData, videoId, userId);

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
    
    // Delete associated activity and its reactions/comments if exists
    if (videoData.activityId) {
      try {
        // Delete activity reactions
        const activityReactionsQuery = db.collection(COLLECTIONS.ACTIVITY_REACTIONS)
          .where('activityId', '==', videoData.activityId);
        const activityReactionsSnapshot = await activityReactionsQuery.get();
        
        const reactionsDeletePromises = activityReactionsSnapshot.docs.map(doc => doc.ref.delete());
        await Promise.all(reactionsDeletePromises);
        
        if (activityReactionsSnapshot.size > 0) {
          console.log(`✅ Deleted ${activityReactionsSnapshot.size} activity reactions for video ${videoId}`);
        }
        
        // Delete activity comments
        const activityCommentsQuery = db.collection(COLLECTIONS.ACTIVITY_COMMENTS)
          .where('activityId', '==', videoData.activityId);
        const activityCommentsSnapshot = await activityCommentsQuery.get();
        
        const commentsDeletePromises = activityCommentsSnapshot.docs.map(doc => doc.ref.delete());
        await Promise.all(commentsDeletePromises);
        
        if (activityCommentsSnapshot.size > 0) {
          console.log(`✅ Deleted ${activityCommentsSnapshot.size} activity comments for video ${videoId}`);
        }
        
        // Delete the activity itself
        await db.collection(COLLECTIONS.ACTIVITIES).doc(videoData.activityId).delete();
        console.log(`✅ Deleted associated activity ${videoData.activityId} for video ${videoId}`);
      } catch (activityError) {
        console.error(`Error deleting associated activity for video ${videoId}:`, activityError);
        // Continue with video deletion even if activity deletion fails
      }
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
      const validVisibility = ['public', 'followers', 'network', 'private'];
      if (!validVisibility.includes(visibility)) {
        return res.status(400).json({
          success: false,
          message: 'Invalid visibility setting'
        });
      }
      // Back-compat guard: a client that doesn't advertise followers support
      // saw this moment's 'followers' value downgraded to 'network' on the wire
      // (see responseNormalizer). If it now echoes 'network' back on an edit,
      // don't clobber the owner's real 'followers' setting — the old client
      // couldn't have intended a change to a value it can't even represent.
      const clientKnowsFollowers = req.headers['x-fc-moments-followers'] === '1';
      const echoingDowngrade = !clientKnowsFollowers
        && visibility === 'network'
        && videoData.visibility === 'followers';
      if (!echoingDowngrade) {
        updates.visibility = visibility;
      }
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

// Add embedded video link
exports.addEmbeddedVideo = async (req, res) => {
  const oembedService = require('../../services/oembedService');
  
  try {
    const userId = req.user.uid;
    const {
      url,
      placeId,
      placeName,
      title,
      description,
      visibility = 'followers',
      tags = [],
      taggedUserIds = []
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
    
    // Create video document based on type
    let videoData;
    
    if (metadata.isDirectVideo) {
      // Handle direct video URLs - treat them like uploaded videos
      videoData = {
        placeId,
        placeName,
        userId,
        title: title || metadata.title,
        description: description || '',
        visibility,
        tags,
        
        // Direct video specific fields
        videoType: 'direct',
        videoUrl: url, // Store the direct URL as videoUrl
        previewUrl: url, // Use same URL for preview
        contentType: 'video',
        
        // No embed fields for direct videos
        embedUrl: null,
        embedPlatform: null,
        embedHtml: null,
        embedMetadata: null,
        
        // Use metadata info
        thumbnailUrl: metadata.thumbnailUrl,
        fileSize: metadata.fileSize,
        
        // Standard fields
        duration: metadata.duration || 0,
        viewCount: 0,
        likeCount: 0,
        commentCount: 0,
        uploadStatus: 'ready',
        
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString(),
        deletedAt: null
      };
    } else {
      // Handle embedded social media videos
      videoData = {
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
        contentType: 'video',
        
        // No direct video fields for embedded
        videoUrl: null,
        previewUrl: null,
        
        // Use thumbnail from platform
        thumbnailUrl: metadata.thumbnailUrl,
        
        // Standard fields
        duration: metadata.duration || 0,
        viewCount: 0,
        likeCount: 0,
        commentCount: 0,
        uploadStatus: 'ready',
        
        createdAt: new Date().toISOString(),
        updatedAt: new Date().toISOString(),
        deletedAt: null
      };
    }
    
    // Tags (accepted connections only; none on private moments)
    const resolvedTags = visibility === 'private'
      ? { taggedUserIds: [], taggedUsers: [] }
      : await resolveTaggedConnections(userId, taggedUserIds);
    videoData.taggedUserIds = resolvedTags.taggedUserIds;
    videoData.taggedUsers = resolvedTags.taggedUsers;

    const videoRef = await db.collection(COLLECTIONS.PLACE_VIDEOS).add(videoData);
    notifyMomentTags(videoData, videoRef.id, userId);
    const videoId = videoRef.id;
    
    // Create activity (positional args — the object form silently failed and
    // embedded videos never appeared in the feed). Skip for private moments so
    // "only me" never broadcasts; stamp visibility/owner for feed gating.
    if (videoData.visibility !== 'private') {
      await createActivity(
        'video_uploaded',
        userId,
        'place_video',
        videoId,
        placeName,
        {
          videoTitle: videoData.title,
          videoThumbnail: videoData.thumbnailUrl || null,
          placeId: placeId,
          momentVisibility: videoData.visibility || 'public',
          momentOwnerId: userId,
          contentType: videoData.contentType || 'video'
        }
      );
    }
    
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
// @desc    Remove MYSELF from a moment's tags ("remove me from this Moment").
//          Only the tagged person can do this; the owner edits via updateVideo.
// @route   DELETE /api/videos/:videoId/tags/me
exports.removeMyMomentTag = async (req, res) => {
  try {
    const userId = req.user.uid;
    const { videoId } = req.params;
    const videoRef = db.collection(COLLECTIONS.PLACE_VIDEOS).doc(videoId);
    const videoDoc = await videoRef.get();
    if (!videoDoc.exists || videoDoc.data().deletedAt) {
      return res.status(404).json({ success: false, message: 'Moment not found' });
    }
    const data = videoDoc.data();
    if (!Array.isArray(data.taggedUserIds) || !data.taggedUserIds.includes(userId)) {
      return res.json({ success: true, data: { removed: false } });
    }
    await videoRef.update({
      taggedUserIds: data.taggedUserIds.filter(id => id !== userId),
      taggedUsers: (data.taggedUsers || []).filter(u => u && u.id !== userId),
      updatedAt: new Date().toISOString()
    });
    console.log(`🏷️ ${userId} removed their tag from moment ${videoId}`);
    res.json({ success: true, data: { removed: true } });
  } catch (error) {
    console.error('Error removing moment tag:', error);
    res.status(500).json({ success: false, message: 'Failed to remove tag' });
  }
};

exports.getVideoMetadata = async (req, res) => {
  const oembedService = require('../../services/oembedService');
  
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

// Check video processing status
exports.checkVideoStatus = async (req, res) => {
  try {
    const { videoId } = req.params;
    const userId = req.user.uid;
    
    const videoRef = db.collection(COLLECTIONS.PLACE_VIDEOS).doc(videoId);
    const videoDoc = await videoRef.get();
    
    if (!videoDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Video not found'
      });
    }
    
    const videoData = videoDoc.data();
    
    // Only owner can check status
    if (videoData.userId !== userId) {
      return res.status(403).json({
        success: false,
        message: 'Unauthorized'
      });
    }
    
    res.json({
      success: true,
      data: {
        videoId,
        uploadStatus: videoData.uploadStatus || 'pending',
        uploadProgress: videoData.uploadProgress || 0,
        processingCompleted: videoData.processingCompleted || null,
        isReady: videoData.uploadStatus === 'ready'
      }
    });
  } catch (error) {
    console.error('Error checking video status:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to check video status',
      error: error.message
    });
  }
};
