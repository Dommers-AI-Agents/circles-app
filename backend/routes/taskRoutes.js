// backend/routes/taskRoutes.js
const express = require('express');
const { verifyScheduler } = require('../middleware/verifyScheduler');
const postcardMail = require('../controllers/widgets/postcardMailController');
const fridgeMail = require('../controllers/widgets/fridgeMailController');
const care = require('../controllers/widgets/careCheckinController');
const quotes = require('../controllers/widgets/quotesController');
const tasks = require('../controllers/tasks/scheduledTasksController');
const orphanUploads = require('../controllers/tasks/orphanUploadsController');
const momentExpiryTask = require('../controllers/tasks/momentExpiryController');
const ordersSweepTask = require('../controllers/tasks/ordersSweepController');
const emailHealthTask = require('../controllers/tasks/emailHealthController');
const farmersMarketsTask = require('../controllers/tasks/farmersMarketsController');
const localCoverageTask = require('../controllers/tasks/localCoverageController');
const instagramTask = require('../controllers/tasks/instagramController');

const router = express.Router();

// Authenticates every task endpoint below. See middleware/verifyScheduler.js —
// it accepts a Google-signed OIDC token from Cloud Scheduler, or the
// SCHEDULER_SECRET bearer token for manual runs, and nothing else.
//
// This replaced a check that trusted the `X-Cloudscheduler` header and the
// User-Agent string. Both are set by the caller, so anyone could trigger a
// push-notification blast to the whole user base with a single curl.
const verifyCloudScheduler = verifyScheduler;

// Printed postcards. The release job closes cancel windows: it submits each
// due order to the printer and only then captures the money, so a card that
// can't be printed costs the customer nothing. Every 10 minutes, because that
// interval is the slack on the advertised cancel window.
router.post('/postcard-orders-release', verifyCloudScheduler, postcardMail.releaseDue);
// Hourly cleanup: retry captures for cards already at the printer, unstick
// claims from a job that died mid-flight, expire holds nobody completed.
router.post('/postcard-orders-reconcile', verifyCloudScheduler, postcardMail.reconcile);
// Fridge Mail: daily at 15:00 UTC (before Lob's 10 AM Pacific cutoff); each
// plan actually sends only on its own weekday, once per rolling week.
router.post('/fridgemail-send', verifyCloudScheduler, fridgeMail.runWeekly);

// Care check-ins: send due questions, raise silence alerts (every 15 min)
router.post('/care-checkins', verifyCloudScheduler, care.runDue);

// Daily quote — hourly tick, each user delivered at the hour they chose in
// their own timezone. A per-day document id makes a retried run a no-op.
router.post('/daily-quotes', verifyCloudScheduler, quotes.runDue);

// Notification and maintenance jobs. Handlers live in
// controllers/tasks/scheduledTasksController.js, one per line here.
router.post('/daily-summary', verifyCloudScheduler, tasks.dailySummary);
router.post('/morning-discovery', verifyCloudScheduler, tasks.morningDiscovery);
router.post('/lunch-discovery', verifyCloudScheduler, tasks.lunchDiscovery);
router.post('/weekend-recommendations', verifyCloudScheduler, tasks.weekendRecommendations);
router.post('/reengagement', verifyCloudScheduler, tasks.reengagement);
router.post('/tips', verifyCloudScheduler, tasks.tips);
router.post('/starter-pushes', verifyCloudScheduler, tasks.starterPushes);
router.post('/engagement-reminders', verifyCloudScheduler, tasks.engagementReminders);
router.post('/weekly-summary', verifyCloudScheduler, tasks.weeklySummary);
router.post('/monthly-summary', verifyCloudScheduler, tasks.monthlySummary);
router.post('/network-growth', verifyCloudScheduler, tasks.networkGrowth);
router.post('/build-suggestions', verifyCloudScheduler, tasks.buildSuggestions);
router.post('/follow-suggestions', verifyCloudScheduler, tasks.followSuggestions);
router.post('/opentable-directory-sync', verifyCloudScheduler, tasks.opentableDirectorySync);
router.post('/email-fallback-digests', verifyCloudScheduler, tasks.emailFallbackDigests);
router.post('/sweep-categories', verifyCloudScheduler, tasks.sweepCategories);
router.post('/top-contributors', verifyCloudScheduler, tasks.topContributors);
router.post('/special-event/:eventType', verifyCloudScheduler, tasks.specialEvent);
router.post('/send-venue-reports', verifyCloudScheduler, tasks.sendVenueReports);
router.post('/piggy-bank-clearing', verifyCloudScheduler, tasks.piggyBankClearing);
router.post('/piggy-bank-settlement', verifyCloudScheduler, tasks.piggyBankSettlement);
router.post('/piggy-bank-resolve-claim', verifyCloudScheduler, tasks.piggyBankResolveClaim);

// Hourly: moment uploads still unfinished 2 h after initiate are marked
// 'abandoned' and their Storage objects deleted (≤200 per run, resumable).
router.post('/orphan-uploads', verifyCloudScheduler, orphanUploads.sweep);
// Every 15 min: disappearing moments past their 24 hours are deleted for good
router.post('/moments-expire', verifyCloudScheduler, momentExpiryTask.sweep);
// Every 5 min: unanswered order-ahead orders expire, stale ready ones close
router.post('/orders-sweep', verifyCloudScheduler, ordersSweepTask.sweep);
router.post('/email-health', verifyCloudScheduler, emailHealthTask.check);
// Monthly: copy the USDA farmers market directory (Locals tab markets)
router.post('/farmers-markets-sync', verifyCloudScheduler, farmersMarketsTask.sync);
// Weekly: where people opened the Local tab with no library calendar
router.post('/local-coverage-report', verifyCloudScheduler, localCoverageTask.report);
// Daily noon ET: the next approved post on @favcircles (admin dashboard → Instagram)
router.post('/instagram-post', verifyCloudScheduler, instagramTask.post);

// Health check endpoint for scheduled tasks
router.get('/health', (req, res) => {
  res.json({
    success: true,
    message: 'Task routes are healthy',
    endpoints: [
      '/api/tasks/daily-summary',
      '/api/tasks/morning-discovery',
      '/api/tasks/lunch-discovery',
      '/api/tasks/weekend-recommendations',
      '/api/tasks/engagement-reminders',
      '/api/tasks/weekly-summary',
      '/api/tasks/monthly-summary',
      '/api/tasks/network-growth',
      '/api/tasks/top-contributors',
      '/api/tasks/build-suggestions',
      '/api/tasks/special-event/:eventType',
      '/api/tasks/piggy-bank-clearing',
      '/api/tasks/piggy-bank-settlement',
      '/api/tasks/orphan-uploads',
      '/api/tasks/email-health',
      '/api/tasks/instagram-post'
    ]
  });
});

module.exports = router;