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

    // Create report document
    const report = {
      type: 'user',
      reporterId,
      reportedItemId: reportedUserId,
      reportedItemType: 'user',
      reason,
      details: details || '',
      status: 'pending', // pending, reviewed, resolved, dismissed
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    };

    const reportRef = await db.collection(COLLECTIONS.REPORTS).add(report);
    const createdReport = serializeDoc(await reportRef.get());

    res.status(201).json({
      success: true,
      message: 'Report submitted successfully',
      report: createdReport
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
    const validContentTypes = ['place', 'circle', 'comment', 'message', 'moment', 'activity'];
    if (!validContentTypes.includes(contentType)) {
      return res.status(400).json({
        success: false,
        message: 'Invalid content type'
      });
    }

    // Create report document
    const report = {
      type: 'content',
      reporterId,
      reportedItemId: contentId,
      reportedItemType: contentType,
      reason,
      details: details || '',
      status: 'pending',
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString()
    };

    const reportRef = await db.collection(COLLECTIONS.REPORTS).add(report);
    const createdReport = serializeDoc(await reportRef.get());

    res.status(201).json({
      success: true,
      message: 'Report submitted successfully',
      report: createdReport
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

    // TODO: Add admin check here
    // For now, only allow fetching your own reports
    const reporterId = req.user.firebaseDocId || req.user.uid;
    
    let query = db.collection(COLLECTIONS.REPORTS)
      .where('reporterId', '==', reporterId);

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

module.exports = {
  reportUser,
  reportContent,
  getReports,
  updateReportStatus
};