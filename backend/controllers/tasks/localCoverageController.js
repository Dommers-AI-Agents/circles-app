// Weekly: email the admin the busiest places where the Local tab had no
// library calendar (services/localEvents/coverageGaps.js).
const { scheduledTask } = require('../../middleware/scheduledTask');
const { topGaps, reportText } = require('../../services/localEvents/coverageGaps');
const { alertAdmin } = require('../../services/adminAlerts');

exports.report = scheduledTask({
  name: 'local-coverage-report',
  log: '📍 Local tab coverage report',
  failure: 'Local coverage report failed',
  run: async () => {
    const rows = await topGaps();
    const body = reportText(rows);
    if (body) {
      await alertAdmin({ key: 'local_coverage_report', title: `Local tab: ${rows.length} places without library events`, body, minIntervalMs: 0, push: false });
    }
    return { places: rows.length };
  }
});
