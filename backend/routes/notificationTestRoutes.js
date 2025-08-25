const express = require('express');
const router = express.Router();
const { protect } = require('../middleware/firebaseAuth');
const engagementNotificationService = require('../services/engagementNotificationService');
const milestoneService = require('../services/milestoneService');
const dailySummaryService = require('../services/dailySummaryService');
const notificationService = require('../services/notificationService');

/**
 * Test routes for notifications - should only be enabled in development
 * All routes require authentication
 */

// Test friend activity alert
router.post('/test/friend-activity', protect, async (req, res) => {
  try {
    const { placeCount = 3, category = 'restaurant' } = req.body;
    
    await engagementNotificationService.sendFriendActivityAlert(
      req.user.uid || req.user.id,
      placeCount,
      category
    );
    
    res.json({
      success: true,
      message: `Sent friend activity alert for ${placeCount} ${category}s`
    });
  } catch (error) {
    console.error('Error testing friend activity:', error);
    res.status(500).json({ 
      success: false, 
      error: error.message 
    });
  }
});

// Test milestone notification
router.post('/test/milestone', protect, async (req, res) => {
  try {
    const { type = 'places' } = req.body;
    
    await engagementNotificationService.checkAndSendMilestone(req.user.uid || req.user.id, type);
    
    res.json({
      success: true,
      message: `Checked and sent ${type} milestone if applicable`
    });
  } catch (error) {
    console.error('Error testing milestone:', error);
    res.status(500).json({ 
      success: false, 
      error: error.message 
    });
  }
});

// Test engagement reminder
router.post('/test/engagement-reminder', protect, async (req, res) => {
  try {
    const { type = 'moments' } = req.body;
    
    await engagementNotificationService.sendEngagementReminder(req.user.uid || req.user.id, type);
    
    res.json({
      success: true,
      message: `Sent ${type} engagement reminder`
    });
  } catch (error) {
    console.error('Error testing engagement reminder:', error);
    res.status(500).json({ 
      success: false, 
      error: error.message 
    });
  }
});

// Test all engagement reminder types
router.post('/test/all-engagement-reminders', protect, async (req, res) => {
  try {
    const types = ['moments', 'checkin', 'places'];
    const results = [];
    
    for (const type of types) {
      await engagementNotificationService.sendEngagementReminder(req.user.uid || req.user.id, type);
      results.push(type);
      // Wait 1 second between notifications
      await new Promise(resolve => setTimeout(resolve, 1000));
    }
    
    res.json({
      success: true,
      message: 'Sent all engagement reminder types',
      types: results
    });
  } catch (error) {
    console.error('Error testing all engagement reminders:', error);
    res.status(500).json({ 
      success: false, 
      error: error.message 
    });
  }
});

// Test weekly summary
router.post('/test/weekly-summary', protect, async (req, res) => {
  try {
    const stats = await engagementNotificationService.gatherWeeklyStats(req.user.uid || req.user.id);
    const user = { id: req.user.uid || req.user.id, displayName: req.user.displayName };
    const notification = engagementNotificationService.buildWeeklySummaryNotification(stats, user);
    
    await notificationService.sendToUser(req.user.uid || req.user.id, notification);
    
    res.json({
      success: true,
      message: 'Sent weekly summary',
      stats
    });
  } catch (error) {
    console.error('Error testing weekly summary:', error);
    res.status(500).json({ 
      success: false, 
      error: error.message 
    });
  }
});

// Test monthly summary
router.post('/test/monthly-summary', protect, async (req, res) => {
  try {
    const stats = await engagementNotificationService.gatherMonthlyStats(req.user.uid || req.user.id);
    
    const lastMonth = new Date();
    lastMonth.setMonth(lastMonth.getMonth() - 1);
    const monthName = lastMonth.toLocaleString('default', { month: 'long' });
    
    const notification = {
      type: 'monthly_summary',
      title: `🎯 Your ${monthName} highlights`,
      body: `${stats.totalPlaces} places discovered, ${stats.totalConnections} connections made!`,
      data: {
        type: 'monthly_summary',
        month: monthName,
        stats: JSON.stringify(stats)
      }
    };
    
    await notificationService.sendToUser(req.user.uid || req.user.id, notification);
    
    res.json({
      success: true,
      message: 'Sent monthly summary',
      stats
    });
  } catch (error) {
    console.error('Error testing monthly summary:', error);
    res.status(500).json({ 
      success: false, 
      error: error.message 
    });
  }
});

// Test special event notification
router.post('/test/special-event', protect, async (req, res) => {
  try {
    const { eventType = 'christmas' } = req.body;
    
    const events = {
      'christmas': {
        title: '🎄 Share your holiday favorites!',
        body: 'What are your go-to spots for the holiday season?'
      },
      'valentines': {
        title: '❤️ Valentine\'s Day ideas',
        body: 'Romantic restaurants from your network'
      },
      'summer': {
        title: '☀️ Summer is here!',
        body: 'Beach spots and outdoor dining from your circle'
      },
      'thanksgiving': {
        title: '🦃 Thanksgiving gathering spots',
        body: 'Where is your network celebrating?'
      },
      'newyear': {
        title: '🎊 New Year, new places!',
        body: 'Start the year with new discoveries'
      }
    };
    
    const event = events[eventType];
    if (!event) {
      return res.status(400).json({
        success: false,
        error: 'Invalid event type'
      });
    }
    
    const notification = {
      type: 'special_event',
      title: event.title,
      body: event.body,
      data: {
        type: 'special_event',
        eventType
      }
    };
    
    await notificationService.sendToUser(req.user.uid || req.user.id, notification);
    
    res.json({
      success: true,
      message: `Sent ${eventType} special event notification`
    });
  } catch (error) {
    console.error('Error testing special event:', error);
    res.status(500).json({ 
      success: false, 
      error: error.message 
    });
  }
});

// Test network growth notification
router.post('/test/network-growth', protect, async (req, res) => {
  try {
    const { count = 5 } = req.body;
    
    await engagementNotificationService.sendNetworkGrowthAlert(req.user.uid || req.user.id, count);
    
    res.json({
      success: true,
      message: `Sent network growth alert for ${count} new connections`
    });
  } catch (error) {
    console.error('Error testing network growth:', error);
    res.status(500).json({ 
      success: false, 
      error: error.message 
    });
  }
});

// Get user stats
router.get('/test/user-stats', protect, async (req, res) => {
  try {
    const stats = await milestoneService.getUserStats(req.user.uid || req.user.id);
    
    res.json({
      success: true,
      stats
    });
  } catch (error) {
    console.error('Error getting user stats:', error);
    res.status(500).json({ 
      success: false, 
      error: error.message 
    });
  }
});

// Test daily summary (existing functionality)
router.post('/test/daily-summary', protect, async (req, res) => {
  try {
    const user = {
      id: req.user.uid || req.user.id,
      email: req.user.email,
      displayName: req.user.displayName,
      notificationPreferences: { dailySummary: true }
    };
    
    await dailySummaryService.generateAndSendSummary(user);
    
    res.json({
      success: true,
      message: 'Sent daily summary notification'
    });
  } catch (error) {
    console.error('Error testing daily summary:', error);
    res.status(500).json({ 
      success: false, 
      error: error.message 
    });
  }
});

// Test notification suite - sends one of each type
router.post('/test/notification-suite', protect, async (req, res) => {
  try {
    const results = [];
    const userId = req.user.uid || req.user.id;
    
    // 1. Friend activity
    await engagementNotificationService.sendFriendActivityAlert(userId, 3, 'restaurant');
    results.push('friend_activity');
    await new Promise(resolve => setTimeout(resolve, 1000));
    
    // 2. Milestone
    await engagementNotificationService.checkAndSendMilestone(userId, 'places');
    results.push('milestone');
    await new Promise(resolve => setTimeout(resolve, 1000));
    
    // 3. Engagement reminder (moments)
    await engagementNotificationService.sendEngagementReminder(userId, 'moments');
    results.push('engagement_reminder_moments');
    await new Promise(resolve => setTimeout(resolve, 1000));
    
    // 4. Weekly summary
    const weeklyStats = await engagementNotificationService.gatherWeeklyStats(userId);
    const user = { id: userId, displayName: req.user.displayName };
    const weeklyNotification = engagementNotificationService.buildWeeklySummaryNotification(weeklyStats, user);
    await notificationService.sendToUser(userId, weeklyNotification);
    results.push('weekly_summary');
    await new Promise(resolve => setTimeout(resolve, 1000));
    
    // 5. Special event
    const specialEventNotification = {
      type: 'special_event',
      title: '🎉 Special event test',
      body: 'Testing special event notifications',
      data: { type: 'special_event', eventType: 'test' }
    };
    await notificationService.sendToUser(userId, specialEventNotification);
    results.push('special_event');
    await new Promise(resolve => setTimeout(resolve, 1000));
    
    // 6. Network growth
    await engagementNotificationService.sendNetworkGrowthAlert(userId, 3);
    results.push('network_growth');
    
    res.json({
      success: true,
      message: 'Sent notification test suite',
      notifications: results
    });
  } catch (error) {
    console.error('Error testing notification suite:', error);
    res.status(500).json({ 
      success: false, 
      error: error.message 
    });
  }
});

module.exports = router;