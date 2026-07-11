// backend/routes/taskRoutes.js
const express = require('express');
const dailySummaryService = require('../services/dailySummaryService');
const scheduledNotifications = require('../services/scheduledNotifications');
const engagementNotificationService = require('../services/engagementNotificationService');
const milestoneService = require('../services/milestoneService');

const router = express.Router();

// Middleware to verify the request is from Cloud Scheduler
const verifyCloudScheduler = (req, res, next) => {
  // Cloud Scheduler adds these headers
  const userAgent = req.get('User-Agent');
  const cloudSchedulerToken = req.get('X-Cloudscheduler');
  
  // Also accept requests with a secret token for testing
  const authHeader = req.get('Authorization');
  const schedulerSecret = process.env.SCHEDULER_SECRET;
  
  if (
    (userAgent && userAgent.includes('Google-Cloud-Scheduler')) ||
    cloudSchedulerToken === 'true' ||
    (schedulerSecret && authHeader === `Bearer ${schedulerSecret}`)
  ) {
    next();
  } else {
    res.status(403).json({ 
      success: false, 
      error: 'Forbidden - This endpoint is only accessible by Cloud Scheduler' 
    });
  }
};

// Daily summary endpoint
router.post('/daily-summary', verifyCloudScheduler, async (req, res) => {
  try {
    console.log('📊 Daily summary triggered via API');
    
    // Run the daily summary service
    await dailySummaryService.sendDailySummaries();
    
    res.json({ 
      success: true, 
      message: 'Daily summaries sent successfully',
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    console.error('❌ Error in daily summary endpoint:', error);
    res.status(500).json({ 
      success: false, 
      error: 'Failed to send daily summaries',
      details: error.message
    });
  }
});

// Morning discovery prompts endpoint
router.post('/morning-discovery', verifyCloudScheduler, async (req, res) => {
  try {
    console.log('☕ Morning discovery prompts triggered via API');
    
    await scheduledNotifications.sendDiscoveryPrompts('morning');
    
    res.json({ 
      success: true, 
      message: 'Morning discovery prompts sent successfully',
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    console.error('❌ Error in morning discovery endpoint:', error);
    res.status(500).json({ 
      success: false, 
      error: 'Failed to send morning discovery prompts',
      details: error.message
    });
  }
});

// Lunch discovery prompts endpoint
router.post('/lunch-discovery', verifyCloudScheduler, async (req, res) => {
  try {
    console.log('🍽️ Lunch discovery prompts triggered via API');
    
    await scheduledNotifications.sendDiscoveryPrompts('lunch');
    
    res.json({ 
      success: true, 
      message: 'Lunch discovery prompts sent successfully',
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    console.error('❌ Error in lunch discovery endpoint:', error);
    res.status(500).json({ 
      success: false, 
      error: 'Failed to send lunch discovery prompts',
      details: error.message
    });
  }
});

// Weekend recommendations endpoint
router.post('/weekend-recommendations', verifyCloudScheduler, async (req, res) => {
  try {
    console.log('🎉 Weekend recommendations triggered via API');
    
    await scheduledNotifications.sendWeekendRecommendations();
    
    res.json({ 
      success: true, 
      message: 'Weekend recommendations sent successfully',
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    console.error('❌ Error in weekend recommendations endpoint:', error);
    res.status(500).json({ 
      success: false, 
      error: 'Failed to send weekend recommendations',
      details: error.message
    });
  }
});

// Engagement reminders endpoint (3 PM daily)
// Reengagement/winback endpoint (weekly) — nudges users inactive 7-14 days
router.post('/reengagement', verifyCloudScheduler, async (req, res) => {
  try {
    console.log('📱 Reengagement notifications triggered via API');

    const result = await scheduledNotifications.sendReengagementNotifications();

    res.json({
      success: true,
      message: 'Reengagement notifications sent successfully',
      result: result,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    console.error('❌ Error in reengagement endpoint:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to send reengagement notifications',
      details: error.message
    });
  }
});

router.post('/engagement-reminders', verifyCloudScheduler, async (req, res) => {
  try {
    console.log('📱 Engagement reminders triggered via API');
    
    await engagementNotificationService.sendEngagementReminders();
    
    res.json({ 
      success: true, 
      message: 'Engagement reminders sent successfully',
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    console.error('❌ Error in engagement reminders endpoint:', error);
    res.status(500).json({ 
      success: false, 
      error: 'Failed to send engagement reminders',
      details: error.message
    });
  }
});

// Weekly summary endpoint (Mondays at 9 AM)
router.post('/weekly-summary', verifyCloudScheduler, async (req, res) => {
  try {
    console.log('📊 Weekly summary triggered via API');
    
    await engagementNotificationService.sendWeeklySummaries();
    
    res.json({ 
      success: true, 
      message: 'Weekly summaries sent successfully',
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    console.error('❌ Error in weekly summary endpoint:', error);
    res.status(500).json({ 
      success: false, 
      error: 'Failed to send weekly summaries',
      details: error.message
    });
  }
});

// Monthly summary endpoint (1st of month at 10 AM)
router.post('/monthly-summary', verifyCloudScheduler, async (req, res) => {
  try {
    console.log('📅 Monthly summary triggered via API');
    
    await engagementNotificationService.sendMonthlySummaries();
    
    res.json({ 
      success: true, 
      message: 'Monthly summaries sent successfully',
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    console.error('❌ Error in monthly summary endpoint:', error);
    res.status(500).json({ 
      success: false, 
      error: 'Failed to send monthly summaries',
      details: error.message
    });
  }
});

// Network growth check endpoint (Sundays at 8 PM)
router.post('/network-growth', verifyCloudScheduler, async (req, res) => {
  try {
    console.log('📈 Network growth check triggered via API');
    
    await milestoneService.checkWeeklyNetworkGrowth();
    
    res.json({ 
      success: true, 
      message: 'Network growth check completed successfully',
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    console.error('❌ Error in network growth endpoint:', error);
    res.status(500).json({ 
      success: false, 
      error: 'Failed to check network growth',
      details: error.message
    });
  }
});

// Top contributors endpoint (last day of month at 6 PM)
router.post('/top-contributors', verifyCloudScheduler, async (req, res) => {
  try {
    console.log('🏆 Top contributors check triggered via API');
    
    await milestoneService.checkTopContributors();
    
    res.json({ 
      success: true, 
      message: 'Top contributors check completed successfully',
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    console.error('❌ Error in top contributors endpoint:', error);
    res.status(500).json({ 
      success: false, 
      error: 'Failed to check top contributors',
      details: error.message
    });
  }
});

// Special event endpoints
router.post('/special-event/:eventType', verifyCloudScheduler, async (req, res) => {
  try {
    const { eventType } = req.params;
    console.log(`🎉 Special event (${eventType}) triggered via API`);
    
    await engagementNotificationService.sendSpecialEventNotification(eventType);
    
    res.json({ 
      success: true, 
      message: `Special event notifications (${eventType}) sent successfully`,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    console.error(`❌ Error in special event endpoint (${req.params.eventType}):`, error);
    res.status(500).json({ 
      success: false, 
      error: 'Failed to send special event notifications',
      details: error.message
    });
  }
});

// Monthly sticker-program report emails to venues (run on the 1st of each month)
router.post('/send-venue-reports', verifyCloudScheduler, async (req, res) => {
  try {
    console.log('🏪 Venue sticker reports triggered via API');
    const { getFirestore } = require('../config/firebase');
    const { STICKER_COLLECTIONS } = require('../models/StickerModels');
    const emailService = require('../services/emailService');
    const db = getFirestore();

    // Report on the previous calendar month
    const now = new Date();
    const prevMonth = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth() - 1, 1));
    const monthKey = prevMonth.toISOString().slice(0, 7);

    const snapshot = await db.collection(STICKER_COLLECTIONS.STICKER_VENUES)
      .where('active', '==', true)
      .get();

    let sent = 0;
    let skipped = 0;
    const failures = [];

    for (const doc of snapshot.docs) {
      const venue = { venueId: doc.id, ...doc.data() };
      if (!venue.contactEmail) {
        skipped++;
        continue;
      }
      try {
        const stats = (venue.statsMonthly && venue.statsMonthly[monthKey]) || {};
        await emailService.sendVenueReportEmail(venue, monthKey, stats);
        await doc.ref.update({ lastReportSentAt: new Date().toISOString() });
        sent++;
      } catch (error) {
        console.error(`❌ Venue report failed for ${venue.venueName}:`, error.message);
        failures.push(venue.venueName);
      }
    }

    res.json({
      success: true,
      message: `Venue reports for ${monthKey}: ${sent} sent, ${skipped} skipped (no email), ${failures.length} failed`,
      failures,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    console.error('❌ Error in venue reports endpoint:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to send venue reports',
      details: error.message
    });
  }
});

// Health check endpoint for scheduled tasks
router.get('/health', (req, res) => {
  res.json({ 
    success: true, 
    message: 'Task routes are healthy',
    endpoints: [
      '/api/tasks/daily-summary',
      '/api/tasks/morning-discovery', 
      '/api/tasks/lunch-discovery',
      '/api/tasks/weekend-recommendations',
      '/api/tasks/engagement-reminders',
      '/api/tasks/weekly-summary',
      '/api/tasks/monthly-summary',
      '/api/tasks/network-growth',
      '/api/tasks/top-contributors',
      '/api/tasks/special-event/:eventType'
    ]
  });
});

module.exports = router;