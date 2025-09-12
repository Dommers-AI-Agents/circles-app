// backend/routes/privacyContactsRoutes.js
const express = require('express');
const router = express.Router();
const { protect } = require('../middleware/firebaseAuth');
const {
  privacySyncContacts,
  getUserHashedIdentifiers,
  deleteSyncedData
} = require('../controllers/privacyContactsController');

// All routes require authentication
router.use(protect);

// Privacy-preserving contact sync (Apple Guidelines 5.1.1 compliant)
router.post('/privacy-sync', privacySyncContacts);

// Get hashed user identifiers for client-side matching
router.get('/hashed-users', getUserHashedIdentifiers);

// Delete synced contact data (user privacy control)
router.delete('/synced-data', deleteSyncedData);

module.exports = router;