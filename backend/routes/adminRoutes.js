// backend/routes/adminRoutes.js
const express = require('express');
const router = express.Router();
const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');
const { safeEqual } = require('../middleware/verifyScheduler');

const db = getFirestore();

// Admin auth. Fails closed: an unset ADMIN_SECRET denies every request rather
// than falling back to a hardcoded default. The previous default
// ('admin-secret-2025') would have opened these endpoints to anyone who guessed
// it the moment the env var went missing.
const adminAuth = (req, res, next) => {
  const adminSecret = process.env.ADMIN_SECRET;
  const authHeader = req.get('Authorization') || '';
  const token = authHeader.startsWith('Bearer ') ? authHeader.slice(7).trim() : null;

  if (!adminSecret) {
    console.error('🚫 [admin] ADMIN_SECRET is not configured — denying admin request');
    return res.status(403).json({ success: false, error: 'Unauthorized' });
  }

  if (token && safeEqual(token, adminSecret)) {
    return next();
  }

  console.warn(`🚫 [admin] Unauthorized admin request to ${req.originalUrl} from ${req.ip}`);
  return res.status(403).json({ success: false, error: 'Unauthorized' });
};

// Reset daily summary timestamps
router.post('/reset-daily-summaries', adminAuth, async (req, res) => {
  try {
    // Get all users with daily summary enabled
    const usersSnapshot = await db.collection(COLLECTIONS.USERS)
      .where('notificationPreferences.dailySummary', '==', true)
      .get();
    
    if (usersSnapshot.empty) {
      return res.json({ 
        success: true, 
        message: 'No users have daily summary enabled',
        count: 0 
      });
    }
    
    // Reset lastDailySummary for each user
    const batch = db.batch();
    let count = 0;
    const userNames = [];
    
    usersSnapshot.forEach(doc => {
      const userData = doc.data();
      userNames.push(userData.displayName || doc.id);
      
      // Set lastDailySummary to yesterday
      const yesterday = new Date();
      yesterday.setDate(yesterday.getDate() - 1);
      
      batch.update(doc.ref, {
        lastDailySummary: yesterday.toISOString()
      });
      count++;
    });
    
    // Commit the batch
    await batch.commit();
    
    res.json({ 
      success: true, 
      message: `Reset daily summary timestamps for ${count} users`,
      count,
      users: userNames
    });
    
  } catch (error) {
    console.error('Error resetting daily summaries:', error);
    res.status(500).json({ 
      success: false, 
      error: 'Failed to reset daily summaries',
      details: error.message 
    });
  }
});

module.exports = router;