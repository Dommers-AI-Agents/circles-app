// backend/routes/suggestionRoutes.js
const express = require('express');
const router = express.Router();
const { protect } = require('../middleware/firebaseAuth');
const {
  createNewSuggestion,
  getNetworkSuggestions,
  getSuggestionsByUser,
  deleteSuggestion,
  cleanupExpiredSuggestions,
  addComment,
  getComments,
  likeSuggestion,
  unlikeSuggestion
} = require('../controllers/suggestionController');

// Suggestion routes
router.post('/', protect, createNewSuggestion);
router.get('/network', protect, getNetworkSuggestions);
router.get('/user/:userId', protect, getSuggestionsByUser);
router.delete('/:id', protect, deleteSuggestion);
router.post('/cleanup', protect, cleanupExpiredSuggestions); // Should be restricted to admin/system

// Comment routes
router.post('/:id/comments', protect, addComment);
router.get('/:id/comments', protect, getComments);

// Like routes
router.post('/:id/like', protect, likeSuggestion);
router.delete('/:id/like', protect, unlikeSuggestion);

module.exports = router;