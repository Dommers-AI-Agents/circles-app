// backend/routes/emailTestRoutes.js
const express = require('express');
const router = express.Router();
const { protect } = require('../middleware/firebaseAuth');
const emailService = require('../services/emailService');

// Test email configuration
router.get('/test-config', protect, async (req, res) => {
  try {
    const isConfigured = await emailService.testEmailConfiguration();
    
    res.json({
      success: true,
      configured: isConfigured,
      service: process.env.EMAIL_SERVICE || 'Not configured',
      fromAddress: emailService.fromAddress,
      fromName: emailService.fromName
    });
  } catch (error) {
    console.error('Email config test error:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to test email configuration',
      error: error.message
    });
  }
});

// Send test email
router.post('/test-send', protect, async (req, res) => {
  try {
    const { toEmail } = req.body;
    const userEmail = toEmail || req.user.email;
    const userName = req.user.displayName || req.user.email;
    
    const result = await emailService.sendTestEmail(userEmail, userName);
    
    res.json({
      success: true,
      message: 'Test email sent successfully',
      to: userEmail,
      messageId: result.messageId
    });
  } catch (error) {
    console.error('Test email send error:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to send test email',
      error: error.message
    });
  }
});

// Test connection request email
router.post('/test-connection-request', protect, async (req, res) => {
  try {
    const { toEmail } = req.body;
    const userEmail = toEmail || req.user.email;
    const userName = req.user.displayName || 'Test User';
    const userId = req.user.id;
    
    await emailService.sendConnectionRequestEmail(userEmail, userName, userId);
    
    res.json({
      success: true,
      message: 'Test connection request email sent',
      to: userEmail
    });
  } catch (error) {
    console.error('Test connection request email error:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to send test connection request email',
      error: error.message
    });
  }
});

// Test connection accepted email
router.post('/test-connection-accepted', protect, async (req, res) => {
  try {
    const { toEmail } = req.body;
    const userEmail = toEmail || req.user.email;
    const acceptedByName = req.user.displayName || 'Test User';
    
    await emailService.sendConnectionAcceptedEmail(userEmail, acceptedByName);
    
    res.json({
      success: true,
      message: 'Test connection accepted email sent',
      to: userEmail
    });
  } catch (error) {
    console.error('Test connection accepted email error:', error);
    res.status(500).json({
      success: false,
      message: 'Failed to send test connection accepted email',
      error: error.message
    });
  }
});

module.exports = router;