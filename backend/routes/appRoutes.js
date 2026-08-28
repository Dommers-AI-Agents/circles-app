const express = require('express');
const router = express.Router();

// App version configuration
const APP_VERSION = {
    version: "1.0.0",           // Current app version
    buildNumber: "1",           // Current build number
    minimumVersion: "1.0.0",    // Minimum supported version
    releaseNotes: "• Search for places using an interactive map\n• Add places to your circles with ease\n• Improved user interface\n• Bug fixes and performance improvements",
    isRequired: false,          // Force update if true
    releaseDate: new Date().toISOString()
};

// Get current app version info
router.get('/version', (req, res) => {
    try {
        // You can also fetch this from a database or config file
        res.json({
            success: true,
            data: APP_VERSION
        });
    } catch (error) {
        console.error('Error fetching version info:', error);
        res.status(500).json({
            success: false,
            error: 'Failed to fetch version information'
        });
    }
});

// Partner action catalog for the place detail screen (server-driven deep-link
// groups: Delivery / Reserve / Ride). Read-only, global, category-keyed —
// iOS fetches once per session and caches. See services/partnerActionsService.
router.get('/partner-actions', async (req, res) => {
    try {
        const catalog = await require('../services/partnerActionsService').getCatalog();
        res.set('Cache-Control', 'public, max-age=300');
        res.json({ success: true, data: catalog });
    } catch (error) {
        console.error('Error fetching partner actions:', error);
        // Fails closed: an empty catalog just hides the row on the client
        res.json({ success: true, data: { updatedAt: null, groups: [] } });
    }
});

// Update version info (admin endpoint - add authentication)
router.post('/version', async (req, res) => {
    try {
        // TODO: Add admin authentication here
        
        const { version, buildNumber, releaseNotes, isRequired, minimumVersion } = req.body;
        
        // Update the version info (in production, save to database)
        if (version) APP_VERSION.version = version;
        if (buildNumber) APP_VERSION.buildNumber = buildNumber;
        if (releaseNotes) APP_VERSION.releaseNotes = releaseNotes;
        if (typeof isRequired === 'boolean') APP_VERSION.isRequired = isRequired;
        if (minimumVersion) APP_VERSION.minimumVersion = minimumVersion;
        APP_VERSION.releaseDate = new Date().toISOString();
        
        res.json({
            success: true,
            data: APP_VERSION
        });
    } catch (error) {
        console.error('Error updating version info:', error);
        res.status(500).json({
            success: false,
            error: 'Failed to update version information'
        });
    }
});

module.exports = router;