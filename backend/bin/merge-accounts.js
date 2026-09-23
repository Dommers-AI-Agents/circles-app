#!/usr/bin/env node
// The one way to merge two accounts from a terminal. Versioned, unlike the
// one-off scripts in backend/scripts/ (gitignored) that each reimplemented
// the merge by hand and drifted from the tested service.
//
//   node bin/merge-accounts.js <primaryId> <secondaryId>            # dry run: prints the plan
//   node bin/merge-accounts.js <primaryId> <secondaryId> --confirm  # applies it
//
// Primary = the account that survives. The service may swap them (older
// account wins); the output says so. Every applied merge writes an
// accountMerges/{mergeId} record with who ran it.
require('dotenv').config();
const os = require('os');
const { initializeFirebase } = require('../config/firebase');
initializeFirebase();
const { mergeAccounts } = require('../services/accountMergeService');

const [primaryId, secondaryId, ...flags] = process.argv.slice(2);
const confirm = flags.includes('--confirm');
const byFlag = flags.find((f) => f.startsWith('--by='));
const mergedBy = byFlag ? byFlag.slice(5) : `cli:${os.userInfo().username}`;

if (!primaryId || !secondaryId) {
  console.error('usage: node bin/merge-accounts.js <primaryId> <secondaryId> [--confirm] [--by=<uid>]');
  process.exit(2);
}

(async () => {
  const result = await mergeAccounts({ primaryId, secondaryId, dryRun: !confirm, mergedBy, via: 'cli' });
  console.log(confirm ? '✅ MERGED' : '🔍 DRY RUN — nothing written');
  console.log(`survivor: ${result.primaryId}${result.swapped ? ' (swapped — the older account survives)' : ''}`);
  console.log(`folded:   ${result.secondaryId}`);
  console.log('counts:  ', JSON.stringify(result.counts));
  console.log(`operations: ${result.operations}`);
  if (result.mergeId) console.log(`audit:    accountMerges/${result.mergeId}`);
  if (!confirm) console.log('\nRe-run with --confirm to apply.');
  process.exit(0);
})().catch((e) => {
  console.error('❌', e.code || '', e.message);
  process.exit(1);
});
