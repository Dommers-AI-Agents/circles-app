// backend/controllers/tasks/scheduledTasksController.js
//
// The Cloud Scheduler endpoints that used to be inline in routes/taskRoutes.js.
// Each one is the same try/log/run/respond shape via `scheduledTask`; the
// response bodies are exactly what the inline versions sent.
const { scheduledTask } = require('../../middleware/scheduledTask');
const dailySummaryService = require('../../services/dailySummaryService');
const scheduledNotifications = require('../../services/scheduledNotifications');
const engagementNotificationService = require('../../services/engagementNotificationService');
const tipsService = require('../../services/tipsService');
const milestoneService = require('../../services/milestoneService');
const suggestionEngine = require('../../services/suggestionEngine');
const followSuggestionEmail = require('../../services/followSuggestionEmailService');
const { runCategorySweep } = require('../../services/categorySweep');
const { sendVenueReports } = require('../../services/venueReportsTask');

const flag = (req, key) => req.query[key] === 'true' || (req.body && req.body[key] === true);

exports.dailySummary = scheduledTask({
  name: 'daily summary', log: '📊 Daily summary triggered via API', failure: 'Failed to send daily summaries',
  run: async () => { await dailySummaryService.sendDailySummaries(); return { message: 'Daily summaries sent successfully' }; }
});

exports.morningDiscovery = scheduledTask({
  name: 'morning discovery', log: '☕ Morning discovery prompts triggered via API', failure: 'Failed to send morning discovery prompts',
  run: async () => { await scheduledNotifications.sendDiscoveryPrompts('morning'); return { message: 'Morning discovery prompts sent successfully' }; }
});

exports.lunchDiscovery = scheduledTask({
  name: 'lunch discovery', log: '🍽️ Lunch discovery prompts triggered via API', failure: 'Failed to send lunch discovery prompts',
  run: async () => { await scheduledNotifications.sendDiscoveryPrompts('lunch'); return { message: 'Lunch discovery prompts sent successfully' }; }
});

exports.weekendRecommendations = scheduledTask({
  name: 'weekend recommendations', log: '🎉 Weekend recommendations triggered via API', failure: 'Failed to send weekend recommendations',
  run: async () => { await scheduledNotifications.sendWeekendRecommendations(); return { message: 'Weekend recommendations sent successfully' }; }
});

// Weekly: nudges users inactive 7-14 days
exports.reengagement = scheduledTask({
  name: 'reengagement', log: '📱 Reengagement notifications triggered via API', failure: 'Failed to send reengagement notifications',
  run: async () => ({ message: 'Reengagement notifications sent successfully', result: await scheduledNotifications.sendReengagementNotifications() })
});

// "Did you know…" tips, hourly tick; the service gates by local weekday + hour.
// Test hooks: ?dryRun=true; ?userId=<id>&force=true
exports.tips = scheduledTask({
  name: 'tips',
  log: (req) => ['💡 Tips triggered via API', { dryRun: flag(req, 'dryRun'), userId: req.query.userId || (req.body && req.body.userId) || null, force: flag(req, 'force') }],
  failure: 'Failed to send tips',
  run: async (req) => ({
    result: await tipsService.sendTips({ dryRun: flag(req, 'dryRun'), userId: req.query.userId || (req.body && req.body.userId) || null, force: flag(req, 'force') })
  })
});

exports.engagementReminders = scheduledTask({
  name: 'engagement reminders', log: '📱 Engagement reminders triggered via API', failure: 'Failed to send engagement reminders',
  run: async () => { await engagementNotificationService.sendEngagementReminders(); return { message: 'Engagement reminders sent successfully' }; }
});

exports.weeklySummary = scheduledTask({
  name: 'weekly summary', log: '📊 Weekly summary triggered via API', failure: 'Failed to send weekly summaries',
  run: async () => { await engagementNotificationService.sendWeeklySummaries(); return { message: 'Weekly summaries sent successfully' }; }
});

exports.monthlySummary = scheduledTask({
  name: 'monthly summary', log: '📅 Monthly summary triggered via API', failure: 'Failed to send monthly summaries',
  run: async () => { await engagementNotificationService.sendMonthlySummaries(); return { message: 'Monthly summaries sent successfully' }; }
});

exports.networkGrowth = scheduledTask({
  name: 'network growth', log: '📈 Network growth check triggered via API', failure: 'Failed to check network growth',
  run: async () => { await milestoneService.checkWeeklyNetworkGrowth(); return { message: 'Network growth check completed successfully' }; }
});

// Nightly: recompute Discover suggestions and repair user counters. ?dryRun=true reports only.
exports.buildSuggestions = scheduledTask({
  name: 'build-suggestions', log: '✨ Suggestion rebuild triggered via API', failure: 'Failed to rebuild suggestions',
  run: async (req) => {
    const dryRun = req.query.dryRun === 'true';
    const result = await suggestionEngine.buildAllSuggestions({ dryRun });
    console.log('✅ Suggestion rebuild finished:', result);
    return { message: dryRun ? 'Suggestion rebuild dry run completed' : 'Suggestions rebuilt successfully', ...result };
  }
});

exports.followSuggestions = scheduledTask({
  name: 'follow-suggestions', log: '👋 Follow-suggestion email run triggered via API', failure: 'Failed to send follow-suggestion emails',
  run: async (req) => {
    const dryRun = req.query.dryRun === 'true';
    const { recipients, ...summary } = await followSuggestionEmail.run({ dryRun });
    return {
      message: dryRun ? 'Follow-suggestion email dry run completed' : 'Follow-suggestion emails sent',
      ...summary,
      recipients: recipients.map(({ sampleHtml, ...r }) => r)
    };
  }
});

exports.sweepCategories = scheduledTask({
  name: 'sweep-categories', log: '🧹 Category sweep triggered via API', failure: 'Failed to sweep categories',
  run: async (req) => {
    const dryRun = req.query.dryRun === 'true';
    const maxPlaces = req.query.maxPlaces ? parseInt(req.query.maxPlaces, 10) : undefined;
    const report = await runCategorySweep({ dryRun, maxPlaces });
    if (!report.enabled && !dryRun) {
      console.log('   ↳ LLM tier is off; nothing sent');
    } else {
      console.log(
        `✅ Category sweep: sent ${report.sent}, resolved ${report.resolved}, ` +
        `unresolved ${report.unresolved}, failed ${report.failed}, $${report.costUSD.toFixed(4)}` +
        (report.capped ? ` (CAPPED — ${report.skippedByCap} deferred to next run)` : '')
      );
    }
    return { message: dryRun ? 'Category sweep dry run completed' : 'Category sweep completed', ...report };
  }
});

exports.topContributors = scheduledTask({
  name: 'top contributors', log: '🏆 Top contributors check triggered via API', failure: 'Failed to check top contributors',
  run: async () => { await milestoneService.checkTopContributors(); return { message: 'Top contributors check completed successfully' }; }
});

exports.specialEvent = scheduledTask({
  name: 'special event',
  log: (req) => `🎉 Special event (${req.params.eventType}) triggered via API`,
  failure: 'Failed to send special event notifications',
  run: async (req) => {
    await engagementNotificationService.sendSpecialEventNotification(req.params.eventType);
    return { message: `Special event notifications (${req.params.eventType}) sent successfully` };
  }
});

exports.sendVenueReports = scheduledTask({
  name: 'venue reports', log: '🏪 Venue sticker reports triggered via API', failure: 'Failed to send venue reports',
  run: async () => {
    const { monthKey, sent, skipped, failures } = await sendVenueReports();
    return { message: `Venue reports for ${monthKey}: ${sent} sent, ${skipped} skipped (no email), ${failures.length} failed`, failures };
  }
});

exports.piggyBankClearing = scheduledTask({
  name: 'piggy bank clearing', log: '🐷 Piggy bank clearing triggered via API', failure: 'Failed to run piggy bank clearing',
  run: async () => require('../../services/piggyBankService').runClearing()
});

// Every 5 minutes: send claim_pending on-chain, confirm claim_sent, quarantine the ambiguous.
exports.piggyBankSettlement = scheduledTask({
  name: 'piggy bank settlement', log: '🐷 Piggy bank settlement triggered via API', failure: 'Failed to run piggy bank settlement',
  run: async () => require('../../services/piggyBankService').runSettlement()
});

// Manual resolution for quarantined claims — the admin escape hatch, not the
// common shape, so it keeps its own handler.
exports.piggyBankResolveClaim = async (req, res) => {
  try {
    const { claimId, resolution, txId } = req.body || {};
    if (!claimId || !resolution) {
      return res.status(400).json({ success: false, error: 'claimId and resolution are required' });
    }
    const piggyBankService = require('../../services/piggyBankService');
    const result = await piggyBankService.resolveClaim({ claimId, resolution, txId });
    res.status(result.ok ? 200 : 400).json({ success: result.ok, ...result });
  } catch (error) {
    console.error('❌ Error resolving claim:', error);
    res.status(500).json({ success: false, error: 'Failed to resolve claim', details: error.message });
  }
};
