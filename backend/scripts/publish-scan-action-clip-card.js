#!/usr/bin/env node
// Publishes the App Clip card for Scan Action QRs (https://api.favcircles.com/q,
// which Apple matches for every /q/<code>). Run AFTER the App Clip build that
// opens /q links is live on the App Store, together with SCAN_ACTION_APP_LINKS=1
// on the backend (the AASA's /q/* path). Idempotent; DRY_RUN=true shows the
// words and whether the card exists without touching App Store Connect.
//
//   DRY_RUN=true node scripts/publish-scan-action-clip-card.js
//   node scripts/publish-scan-action-clip-card.js
require('dotenv').config();
// The service pulls in modules that open Firestore when they load
require('../config/firebase').initializeFirebase();
const { publishScanActionExperience } = require('../services/appClipExperienceService');

publishScanActionExperience({ dryRun: process.env.DRY_RUN === 'true' })
  .then((result) => { console.log(JSON.stringify(result, null, 2)); process.exit(0); })
  .catch((error) => { console.error('❌', error.message); process.exit(1); });
