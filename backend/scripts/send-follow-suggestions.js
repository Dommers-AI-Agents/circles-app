// Send the "People you may know" email to new accounts following fewer than
// three people. Same code path as the weekly Cloud Scheduler job
// (/api/tasks/follow-suggestions); this is the on-demand / first-run form.
//
// Usage:
//   DRY_RUN=true node scripts/send-follow-suggestions.js        # who would get it + a preview file
//   node scripts/send-follow-suggestions.js                     # live send
//   USER_ID=<uid> node scripts/send-follow-suggestions.js       # one user only
//   LIMIT=25 node scripts/send-follow-suggestions.js            # cap this run
//   FOLLOW_SUGGESTION_MAX_ACCOUNT_AGE_DAYS=120 …                # widen "new"
const path = require('path');
const fs = require('fs');
require('dotenv').config({ path: path.join(__dirname, '..', '.env') });
const { initializeFirebase } = require('../config/firebase');
initializeFirebase();
const service = require('../services/followSuggestionEmailService');

const DRY_RUN = process.env.DRY_RUN === 'true';
const ONLY_USER = process.env.USER_ID || null;
const LIMIT = parseInt(process.env.LIMIT || '500', 10);

(async () => {
  console.log(`👋 Follow suggestions (${DRY_RUN ? 'DRY RUN' : 'LIVE'})${ONLY_USER ? ' for ' + ONLY_USER : ''}`);
  const result = await service.run({ dryRun: DRY_RUN, limit: LIMIT, onlyUserId: ONLY_USER });
  console.log(`📊 candidates=${result.candidates} sent=${result.sent} skipped=${JSON.stringify(result.skipped)}`);
  for (const r of result.recipients) {
    console.log(`  ${r.email} (following ${r.followingCount}) — ${r.subject}`);
    for (const s of r.suggestions) console.log(`      • ${s.displayName}: ${s.reason}`);
  }
  const sample = result.recipients.find((r) => r.sampleHtml);
  if (sample) {
    const out = path.join(__dirname, '..', '.follow-suggestions-preview.html');
    fs.writeFileSync(out, sample.sampleHtml);
    console.log(`📝 preview written to ${out}`);
  }
  process.exit(0);
})().catch((e) => { console.error(e); process.exit(1); });
