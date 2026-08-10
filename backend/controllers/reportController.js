const { admin, getFirestore } = require('../config/firebase');
const { COLLECTIONS, serializeDoc } = require('../models/FirestoreModels');

const db = getFirestore();

// @desc    Report a user
// @route   POST /api/reports/user
// @access  Private
const reportUser = async (req, res) => {
  try {
    const reporterId = req.user.firebaseDocId || req.user.uid;
    const { reportedUserId, reason, details } = req.body;

    if (!reportedUserId || !reason) {
      return res.status(400).json({
        success: false,
        message: 'Reported user ID and reason are required'
      });
    }

    // Check if user exists
    const userDoc = await db.collection(COLLECTIONS.USERS).doc(reportedUserId).get();
    if (!userDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'User not found'
      });
    }

    // Create report document (deduped per reporter+target)
    const report = {
      type: 'user',
      reporterId,
      reportedItemId: reportedUserId,
      reportedItemType: 'user',
      reportedUserId,
      reason,
      details: details || '',
      status: 'pending', // pending, reviewed, resolved, dismissed
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    };

    const dedupId = `user_${reportedUserId}_${reporterId}`.replace(/[/.]/g, '_');
    const reportRef = db.collection(COLLECTIONS.REPORTS).doc(dedupId);
    try {
      await reportRef.create(report);
    } catch (createError) {
      if (createError.code === 6 || /already exists/i.test(createError.message || '')) {
        return res.status(200).json({
          success: true,
          message: 'You already reported this user — our team is on it.'
        });
      }
      throw createError;
    }

    require('../services/moderationService').notifyAdmin({ id: dedupId, ...report });

    res.status(201).json({
      success: true,
      message: 'Report submitted. Thank you for keeping FavCircles safe.'
    });
  } catch (error) {
    console.error('Error reporting user:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to submit report',
      error: error.message
    });
  }
};

// @desc    Report content (place, comment, circle, etc.)
// @route   POST /api/reports/content
// @access  Private
const reportContent = async (req, res) => {
  try {
    const reporterId = req.user.firebaseDocId || req.user.uid;
    const { contentId, contentType, reason, details } = req.body;

    if (!contentId || !contentType || !reason) {
      return res.status(400).json({
        success: false,
        message: 'Content ID, type, and reason are required'
      });
    }

    // Validate content type
    const validContentTypes = ['place', 'circle', 'comment', 'video_comment', 'message', 'moment', 'video', 'activity', 'place_photo', 'venue_image'];
    if (!validContentTypes.includes(contentType)) {
      return res.status(400).json({
        success: false,
        message: 'Invalid content type'
      });
    }

    // Create report document — doc id deduped per reporter+content, so the
    // same person can't inflate the auto-hide threshold by re-reporting.
    const report = {
      type: 'content',
      reporterId,
      reportedItemId: contentId,
      reportedItemType: contentType,
      reportedUserId: req.body.contentOwnerId || null,
      reason,
      details: details || '',
      status: 'pending',
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    };

    const dedupId = `${contentType}_${contentId}_${reporterId}`.replace(/[/.]/g, '_');
    const reportRef = db.collection(COLLECTIONS.REPORTS).doc(dedupId);
    try {
      await reportRef.create(report);
    } catch (createError) {
      if (createError.code === 6 || /already exists/i.test(createError.message || '')) {
        return res.status(200).json({
          success: true,
          message: 'You already reported this — our team is on it.'
        });
      }
      throw createError;
    }

    // Community quarantine: enough distinct reporters auto-hides the content
    // pending admin review; every report emails the admin. Both best-effort —
    // the report itself is already safely recorded.
    const moderationService = require('../services/moderationService');
    let autoHide = { hidden: false };
    try {
      autoHide = await moderationService.applyAutoHideIfNeeded(contentType, contentId);
    } catch (hideError) {
      console.error('🛡️ auto-hide check failed:', hideError.message);
    }
    moderationService.notifyAdmin({ id: dedupId, ...report }, {
      autoHidden: autoHide.hidden,
      reporterCount: autoHide.count
    });

    res.status(201).json({
      success: true,
      message: 'Report submitted. Thank you for keeping FavCircles safe.',
      autoHidden: autoHide.hidden === true
    });
  } catch (error) {
    console.error('Error reporting content:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to submit report',
      error: error.message
    });
  }
};

// @desc    Get reports (admin only)
// @route   GET /api/reports
// @access  Private/Admin
const getReports = async (req, res) => {
  try {
    const { status = 'pending', type, limit = 50 } = req.query;

    // Super-users see the full moderation queue; everyone else only their own
    const reporterId = req.user.firebaseDocId || req.user.uid;

    let query = req.user.isSuperUser === true
      ? db.collection(COLLECTIONS.REPORTS)
      : db.collection(COLLECTIONS.REPORTS).where('reporterId', '==', reporterId);

    if (status) {
      query = query.where('status', '==', status);
    }

    if (type) {
      query = query.where('type', '==', type);
    }

    query = query.orderBy('createdAt', 'desc').limit(parseInt(limit));

    const snapshot = await query.get();
    const reports = snapshot.docs.map(doc => serializeDoc(doc));

    res.status(200).json({
      success: true,
      reports
    });
  } catch (error) {
    console.error('Error fetching reports:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to fetch reports',
      error: error.message
    });
  }
};

// @desc    Update report status (admin only)
// @route   PUT /api/reports/:id
// @access  Private/Admin
const updateReportStatus = async (req, res) => {
  try {
    // TODO: Add admin check
    const { id } = req.params;
    const { status, resolution } = req.body;

    if (!status) {
      return res.status(400).json({
        success: false,
        message: 'Status is required'
      });
    }

    const validStatuses = ['pending', 'reviewed', 'resolved', 'dismissed'];
    if (!validStatuses.includes(status)) {
      return res.status(400).json({
        success: false,
        message: 'Invalid status'
      });
    }

    const reportRef = db.collection(COLLECTIONS.REPORTS).doc(id);
    const reportDoc = await reportRef.get();

    if (!reportDoc.exists) {
      return res.status(404).json({
        success: false,
        message: 'Report not found'
      });
    }

    const updateData = {
      status,
      updatedAt: new Date().toISOString()
    };

    if (resolution) {
      updateData.resolution = resolution;
      updateData.resolvedAt = new Date().toISOString();
    }

    await reportRef.update(updateData);
    const updatedReport = serializeDoc(await reportRef.get());

    res.status(200).json({
      success: true,
      message: 'Report updated successfully',
      report: updatedReport
    });
  } catch (error) {
    console.error('Error updating report:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to update report',
      error: error.message
    });
  }
};

// @desc    Adjudicate a report (super-user only): dismiss it, remove the
//          content, or ban the offending user. One call, decisive outcome.
// @route   POST /api/reports/:id/action
// @access  Private/SuperUser
const actionReport = async (req, res) => {
  try {
    if (req.user.isSuperUser !== true) {
      return res.status(403).json({ success: false, message: 'Super-user only' });
    }
    const { id } = req.params;
    const { action } = req.body; // dismiss | remove_content | ban_user

    const reportRef = db.collection(COLLECTIONS.REPORTS).doc(id);
    const reportDoc = await reportRef.get();
    if (!reportDoc.exists) {
      return res.status(404).json({ success: false, message: 'Report not found' });
    }
    const report = reportDoc.data();
    const moderationService = require('../services/moderationService');
    const stamp = new Date().toISOString();

    if (action === 'dismiss') {
      // Content was fine: clear any auto-hide so it reappears.
      const ref = moderationService.contentRef(report.reportedItemType, report.reportedItemId);
      if (ref) {
        const doc = await ref.get();
        if (doc.exists && doc.data().moderationStatus === 'under_review') {
          await ref.update({ moderationStatus: null, moderationHiddenAt: null });
        }
      }
      await reportRef.update({ status: 'dismissed', resolvedAt: stamp, resolvedBy: req.user.uid, updatedAt: stamp });
      return res.json({ success: true, action: 'dismissed' });
    }

    if (action === 'remove_content') {
      const ref = moderationService.contentRef(report.reportedItemType, report.reportedItemId);
      if (!ref) {
        return res.status(400).json({ success: false, message: `Content type ${report.reportedItemType} must be removed manually` });
      }
      await ref.update({ moderationStatus: 'removed', moderationRemovedAt: stamp });
      await reportRef.update({ status: 'resolved', resolution: 'content_removed', resolvedAt: stamp, resolvedBy: req.user.uid, updatedAt: stamp });
      return res.json({ success: true, action: 'content_removed' });
    }

    if (action === 'ban_user') {
      const targetUserId = report.reportedUserId || (report.reportedItemType === 'user' ? report.reportedItemId : null);
      if (!targetUserId) {
        return res.status(400).json({ success: false, message: 'No target user on this report — pass contentOwnerId when reporting' });
      }
      await db.collection(COLLECTIONS.USERS).doc(targetUserId).update({
        banned: true, bannedAt: stamp, bannedBy: req.user.uid, bannedForReport: id
      });
      // Also remove the reported content itself, if we can
      const ref = moderationService.contentRef(report.reportedItemType, report.reportedItemId);
      if (ref) {
        const doc = await ref.get();
        if (doc.exists) await ref.update({ moderationStatus: 'removed', moderationRemovedAt: stamp });
      }
      await reportRef.update({ status: 'resolved', resolution: 'user_banned', resolvedAt: stamp, resolvedBy: req.user.uid, updatedAt: stamp });
      return res.json({ success: true, action: 'user_banned', bannedUserId: targetUserId });
    }

    return res.status(400).json({ success: false, message: 'action must be dismiss, remove_content, or ban_user' });
  } catch (error) {
    console.error('Error actioning report:', error);
    res.status(500).json({ success: false, message: 'Failed to action report', error: error.message });
  }
};

module.exports = {
  reportUser,
  reportContent,
  getReports,
  updateReportStatus,
  actionReport
};