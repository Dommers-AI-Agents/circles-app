// backend/routes/taskRoutes.js
const express = require('express');
const dailySummaryService = require('../services/dailySummaryService');
const scheduledNotifications = require('../services/scheduledNotifications');

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

// Health check endpoint for scheduled tasks
router.get('/health', (req, res) => {
  res.json({ 
    success: true, 
    message: 'Task routes are healthy',
    endpoints: [
      '/api/tasks/daily-summary',
      '/api/tasks/morning-discovery', 
      '/api/tasks/lunch-discovery',
      '/api/tasks/weekend-recommendations'
    ]
  });
});

module.exports = router;