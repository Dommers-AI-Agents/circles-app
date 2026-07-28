// backend/routes/browseRoutes.js
// Location browse lens over a user's saved places (State -> City -> venues).
const express = require('express');
const { getBrowseLocations, getBrowseCityPlaces } = require('../controllers/browseController');
const { protect } = require('../middleware/firebaseAuth');

const router = express.Router();
router.use(protect);

// State -> City tree with pin counts
router.get('/locations', getBrowseLocations);
// Every venue in a city, across all the user's circles (source-circle chips)
router.get('/cities/:cityKey/places', getBrowseCityPlaces);

module.exports = router;
