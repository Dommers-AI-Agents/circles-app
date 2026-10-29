// backend/services/activity/createActivity.js
//
// THE activity-row writer (type, actor, target + the metadata the feed and
// its privacy gates read). Moved out of controllers/activityController.js so
// controllers and services stop importing a controller for it (2026-10-29).
const { admin, getFirestore } = require('../../config/firebase');
const { COLLECTIONS } = require('../../models/FirestoreModels');

const db = getFirestore();

const createActivity = async (type, actorId, targetType, targetId, targetName, metadata = {}) => {
  try {
    // Creating activity
    
    // Ensure the actorId is a string
    const actorIdStr = String(actorId);
    
    const activityData = {
      type,
      actorId: actorIdStr,
      targetType,
      targetId,
      targetName,
      circleId: metadata.circleId || null,
      circleName: metadata.circleName || null,
      metadata: {
        comment: metadata.comment || null,
        commentId: metadata.commentId || null,
        placePhoto: metadata.placePhoto || null,
        placeAddress: metadata.placeAddress || null,
        placeId: metadata.placeId || null,
        // Canonical venue id — REQUIRED for global_place_liked (photo likes):
        // their targetId is the photo id, so without this the iOS feed row has
        // no place to navigate to (the "tap does nothing" bug, 2026-08-22)
        globalPlaceId: metadata.globalPlaceId || null,
        message: metadata.message || null,
        endTime: metadata.endTime || null,
        // Video/photo moment activities carry their thumbnail here — the feed
        // renders it when placePhoto is absent
        videoTitle: metadata.videoTitle || null,
        videoThumbnail: metadata.videoThumbnail || null,
        videoDuration: metadata.videoDuration || null,
        // Moment privacy gating: the feed only shows a video_uploaded/
        // video_liked row to viewers entitled to the moment, judged by their
        // relationship to momentOwnerId.
        momentVisibility: metadata.momentVisibility || null,
        momentOwnerId: metadata.momentOwnerId || null,
        // Check-in and place audience stamps the read gates key on. These
        // were passed by the writers but dropped here, so an Inner Circle
        // check-in reached every connection (2026-09-23).
        checkInAudience: metadata.checkInAudience || null,
        audienceListId: metadata.audienceListId || null,
        placePrivacy: metadata.placePrivacy || null,
        placeAudienceListId: metadata.placeAudienceListId || null,
        latitude: metadata.latitude ?? null,
        longitude: metadata.longitude ?? null,
        placeCategory: metadata.placeCategory || null,
        contentType: metadata.contentType || null,
        // The owner's Activity tab: rows nobody else sees (private check-ins,
        // postcards, Fridge Mail) and the details it shows for them.
        ownerOnly: metadata.ownerOnly === true,
        isPrivate: metadata.isPrivate === true,
        rating: Number.isFinite(metadata.rating) ? metadata.rating : null,
        companions: Array.isArray(metadata.companions) ? metadata.companions.slice(0, 6) : [],
        recipientName: metadata.recipientName || null,
        imageUrl: metadata.imageUrl || null,
        placeName: metadata.placeName || null,
        childName: metadata.childName || null,
        mailStatus: metadata.mailStatus || null,
        // Shared workouts: the post the row opens, its audience (the read
        // gate keys on it) and the "6 exercises · 42 min" line
        workoutPostId: metadata.workoutPostId || null,
        workoutAudience: metadata.workoutAudience || null,
        workoutDetail: metadata.workoutDetail || null,
        // Posted runs (FavRun): the run the row opens, its audience and
        // the "3.10 mi · 26:40 · 8:36/mi" line
        runId: metadata.runId || null,
        runAudience: metadata.runAudience || null,
        runDetail: metadata.runDetail || null
      },
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      viewers: [], // Track who has seen this activity
      reactionCount: 0,
      commentCount: 0
    };
    
    // Activity data prepared
    
    try {
      const activityRef = await db.collection(COLLECTIONS.ACTIVITIES).add(activityData);
      return activityRef.id;
    } catch (firestoreError) {
      console.error('❌ Firestore error creating activity:', firestoreError.code);
      throw firestoreError;
    }
  } catch (error) {
    console.error('❌ Error creating activity:', error);
    console.error('❌ Error details:', error.message);
    console.error('❌ Error stack:', error.stack);
    // Don't throw - we don't want activity tracking to break the main flow
  }
};

module.exports = { createActivity };
