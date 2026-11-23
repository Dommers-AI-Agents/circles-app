// Weekly: email the admin where the Local tab had no library programs, and
// why (services/localEvents/coverageGaps.js).
const { scheduledTask } = require('../../middleware/scheduledTask');
const { topGaps, buildReport } = require('../../services/localEvents/coverageGaps');
const { alertAdmin } = require('../../services/adminAlerts');

exports.report = scheduledTask({
  name: 'local-coverage-report',
  log: '📍 Local tab coverage report',
  failure: 'Local coverage report failed',
  run: async () => {
    const report = buildReport(await topGaps());
    if (report) {
      await alertAdmin({ key: 'local_coverage_report', title: report.title, body: report.body, minIntervalMs: 0, push: false });
    }
    return { places: report ? report.places : 0 };
  }
});
