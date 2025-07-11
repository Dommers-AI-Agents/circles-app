// backend/routes/sseRoutes.js
const express = require('express');
const { protect } = require('../middleware/firebaseAuth');
const sseService = require('../services/sseService');

const router = express.Router();

// SSE endpoint for real-time notifications
router.get('/stream', protect, (req, res) => {
  const userId = req.user.uid;
  
  // Add client to SSE service
  sseService.addClient(userId, res);
  
  // Keep connection open
  req.on('close', () => {
    sseService.removeClient(userId, res);
  });
});

// Endpoint to check SSE service status
router.get('/status', protect, (req, res) => {
  res.json({
    success: true,
    connectedUsers: sseService.getConnectedUsersCount(),
    isUserConnected: sseService.isUserConnected(req.user.uid)
  });
});

module.exports = router;