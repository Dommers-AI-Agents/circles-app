// backend/controllers/newsController.js
// News tab endpoints: the source catalog (+ the caller's enabled sources)
// and the merged headline feed. Source preferences live on the user doc at
// preferences.enabledNewsSources (written via PUT /api/users/me).

const newsService = require('../services/newsService');

// @desc    News source catalog plus which sources this user has enabled.
//          enabledSourceIds is null when the user has never configured the
//          feature (drives the app's first-run picker) vs [] = explicitly none.
// @route   GET /api/news/sources
// @access  Private
exports.getSources = (req, res) => {
  const stored = req.user.preferences?.enabledNewsSources;
  res.json({
    success: true,
    sources: newsService.getCatalog(),
    enabledSourceIds: Array.isArray(stored) ? stored : null
  });
};

// @desc    Merged, newest-first headlines from the user's enabled sources
//          (or an explicit ?sources=a,b list)
// @route   GET /api/news/feed?sources=cnbc,bbc
// @access  Private
exports.getFeed = async (req, res) => {
  try {
    let sourceIds;
    if (req.query.sources) {
      sourceIds = String(req.query.sources).split(',').map((s) => s.trim()).filter(Boolean);
    } else {
      const stored = req.user.preferences?.enabledNewsSources;
      sourceIds = Array.isArray(stored) ? stored : [];
    }

    if (sourceIds.length === 0) {
      return res.json({ success: true, articles: [], sourcesFailed: [], configured: false });
    }

    const { articles, sourcesFailed } = await newsService.getFeedForSources(sourceIds);
    res.json({ success: true, articles, sourcesFailed, configured: true });
  } catch (error) {
    console.error('❌ News feed failed:', error);
    res.status(500).json({ success: false, message: 'Failed to load news feed' });
  }
};
