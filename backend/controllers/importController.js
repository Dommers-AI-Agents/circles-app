// Import controller: bring saved places in from other platforms
// (Mapstr, Google Takeout, Swarm). Premium-gated.

const jwt = require('jsonwebtoken');
const importService = require('../services/importService');
const subscriptionLimitService = require('../services/subscriptionLimitService');
const swarmService = require('../services/swarmService');
const { resolveGoogleList, GoogleListError } = require('../services/googleListResolver');
const { getFirestore } = require('../config/firebase');

const db = getFirestore();
const IMPORT_TOKENS_COLLECTION = 'importTokens';
// Deep link back into the iOS app after the OAuth dance
const SWARM_APP_REDIRECT = 'circles://import/swarm';

// @desc    Resolve, categorize and dedup an import payload (read-only preview)
// @route   POST /api/import/prepare
// @access  Private (Premium)
exports.prepareImport = async (req, res) => {
  try {
    const importCheck = await subscriptionLimitService.canImport(req.user.uid);
    if (!importCheck.canImport) {
      return res.status(403).json({
        success: false,
        message: importCheck.error,
        upgradeRequired: true
      });
    }

    const result = await importService.prepareImport(req.user.uid, req.body);
    if (result.error) {
      return res.status(400).json({ success: false, message: result.error });
    }

    res.json({ success: true, preview: result.preview });
  } catch (error) {
    console.error('❌ Import prepare error:', error);
    res.status(500).json({ success: false, message: 'Failed to prepare import' });
  }
};

// @desc    Expand a shared Google Maps LIST link into its places, so the
//          share extension / app can import the whole list as one circle.
// @route   POST /api/import/resolve-google-list   body: { url }
// @access  Private
// @returns { success, list: { id, name, description, author, url, totalCount,
//            truncated, places: [{ name, address, lat, lng, notes,
//            sourceExternalId, sourceUrl }] } }
//          404 NOT_A_LIST when the link is a single place (caller falls back
//          to the normal single-place flow); 422 for private/missing lists.
const GOOGLE_LIST_STATUS = {
  INVALID_URL: 400,
  NOT_GOOGLE_MAPS: 400,
  INVALID_LIST_ID: 400,
  NOT_A_LIST: 404,
  LIST_NOT_FOUND: 422,
  UPSTREAM: 502
};

exports.resolveGoogleListLink = async (req, res) => {
  const url = typeof req.body?.url === 'string' ? req.body.url.trim() : '';
  if (!url || url.length > 2048) {
    return res.status(400).json({ success: false, code: 'INVALID_URL', message: 'A Google Maps list link is required' });
  }
  try {
    const list = await resolveGoogleList(url);
    console.log(`📋 Google list resolved for ${req.user.uid}: "${list.name}" (${list.places.length}/${list.totalCount})`);
    res.json({ success: true, list });
  } catch (error) {
    if (error instanceof GoogleListError) {
      return res.status(GOOGLE_LIST_STATUS[error.code] || 400)
        .json({ success: false, code: error.code, message: error.message });
    }
    console.error('❌ Google list resolve error:', error);
    res.status(502).json({ success: false, code: 'UPSTREAM', message: 'Could not read that list right now' });
  }
};

// @desc    Create circles + places from a reviewed import payload
// @route   POST /api/import/execute
// @access  Private (Premium)
exports.executeImport = async (req, res) => {
  try {
    const importCheck = await subscriptionLimitService.canImport(req.user.uid);
    if (!importCheck.canImport) {
      return res.status(403).json({
        success: false,
        message: importCheck.error,
        upgradeRequired: true
      });
    }

    const result = await importService.executeImport(req.user.uid, req.body);
    if (result.error) {
      return res.status(result.upgradeRequired ? 403 : 400)
        .json({ success: false, message: result.error, upgradeRequired: !!result.upgradeRequired });
    }

    const totals = result.results.reduce((acc, r) => {
      acc.created += r.created;
      acc.skippedDuplicates += r.skippedDuplicates;
      acc.failed += r.failed.length;
      return acc;
    }, { created: 0, skippedDuplicates: 0, failed: 0 });

    console.log(`📥 Import executed for user ${req.user.uid}:`, totals);
    res.json({ success: true, results: result.results, totals });
  } catch (error) {
    console.error('❌ Import execute error:', error);
    res.status(500).json({ success: false, message: 'Failed to execute import' });
  }
};

// @desc    Get the Foursquare OAuth authorization URL for Swarm import
// @route   GET /api/import/swarm/auth-url
// @access  Private (Premium)
exports.getSwarmAuthUrl = async (req, res) => {
  try {
    if (!swarmService.isConfigured()) {
      return res.status(503).json({ success: false, message: 'Swarm import is not configured' });
    }

    const importCheck = await subscriptionLimitService.canImport(req.user.uid);
    if (!importCheck.canImport) {
      return res.status(403).json({
        success: false,
        message: importCheck.error,
        upgradeRequired: true
      });
    }

    // Short-lived state token ties the browser callback back to this user
    const state = jwt.sign(
      { uid: req.user.uid, purpose: 'swarm_import' },
      process.env.JWT_SECRET,
      { expiresIn: '15m' }
    );

    res.json({ success: true, url: swarmService.authorizationUrl(state) });
  } catch (error) {
    console.error('❌ Swarm auth-url error:', error);
    res.status(500).json({ success: false, message: 'Failed to start Swarm authorization' });
  }
};

// @desc    OAuth callback hit by Foursquare's redirect; stores the access
//          token and bounces back into the app via deep link
// @route   GET /api/import/swarm/callback
// @access  Public (validated via signed state param)
exports.swarmCallback = async (req, res) => {
  const { code, state, error } = req.query;
  try {
    if (error || !code || !state) {
      return res.redirect(`${SWARM_APP_REDIRECT}?status=denied`);
    }

    let decoded;
    try {
      decoded = jwt.verify(state, process.env.JWT_SECRET);
    } catch (jwtError) {
      console.error('❌ Swarm callback: invalid state token');
      return res.redirect(`${SWARM_APP_REDIRECT}?status=error`);
    }
    if (decoded.purpose !== 'swarm_import' || !decoded.uid) {
      return res.redirect(`${SWARM_APP_REDIRECT}?status=error`);
    }

    const accessToken = await swarmService.exchangeCodeForToken(code);

    // Stored only for the duration of the import; deleted after fetch
    await db.collection(IMPORT_TOKENS_COLLECTION).doc(decoded.uid).set({
      provider: 'swarm',
      accessToken,
      createdAt: new Date().toISOString()
    });

    res.redirect(`${SWARM_APP_REDIRECT}?status=ok`);
  } catch (callbackError) {
    console.error('❌ Swarm callback error:', callbackError.message);
    res.redirect(`${SWARM_APP_REDIRECT}?status=error`);
  }
};

// @desc    Fetch the connected Swarm account's lists (and optionally
//          check-ins) as a normalized import payload
// @route   POST /api/import/swarm/fetch
// @access  Private (Premium)
exports.fetchSwarmData = async (req, res) => {
  try {
    const importCheck = await subscriptionLimitService.canImport(req.user.uid);
    if (!importCheck.canImport) {
      return res.status(403).json({
        success: false,
        message: importCheck.error,
        upgradeRequired: true
      });
    }

    const tokenDoc = await db.collection(IMPORT_TOKENS_COLLECTION).doc(req.user.uid).get();
    const tokenData = tokenDoc.exists ? tokenDoc.data() : null;
    if (!tokenData || tokenData.provider !== 'swarm') {
      return res.status(400).json({
        success: false,
        message: 'Swarm account not connected. Authorize first.'
      });
    }
    // Tokens older than 24h are treated as stale
    if (new Date(tokenData.createdAt).getTime() < Date.now() - 24 * 60 * 60 * 1000) {
      await tokenDoc.ref.delete();
      return res.status(400).json({
        success: false,
        message: 'Swarm connection expired. Authorize again.'
      });
    }

    const includeCheckins = req.body && req.body.includeCheckins === true;
    const payload = await swarmService.fetchNormalizedPayload(tokenData.accessToken, { includeCheckins });

    // One-shot token: remove it now that the data has been fetched
    await tokenDoc.ref.delete();

    res.json({ success: true, payload });
  } catch (error) {
    console.error('❌ Swarm fetch error:', error.message);
    res.status(500).json({ success: false, message: 'Failed to fetch data from Swarm' });
  }
};
