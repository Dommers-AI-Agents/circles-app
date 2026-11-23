// backend/services/scan/medScan.js — the Medications widget's "Scan a label"
// (Wes, 2026-11-23): label photos → draft reminders (medReader). A personal
// scan, not a store's: it consumes only the per-person 'aiScan' budget (25 a
// day across every paid scan). Nothing is saved and the photos aren't kept;
// scanUsage gets token counts only, never what the label said.
const { getFirestore } = require('../../config/firebase');
const { ServiceError } = require('../../utils/serviceError');
const dailyBudget = require('../dailyBudget');
const images = require('./images');
const medReader = require('./medReader');

async function scan({ images: raw, userId, db = getFirestore(), reader = medReader }) {
  const prepared = await images.prepare(raw);
  const personal = await dailyBudget.consume('aiScan', userId);
  if (!personal.allowed) throw new ServiceError(429, 'scan_limit', `That’s ${personal.limit} scans for you today. Try again tomorrow.`);
  const started = Date.now();
  const { draft, usage } = await reader.read(prepared);
  db.collection('scanUsage').add({
    userId, kind: 'medLabel', images: prepared.length, ...usage, medications: draft.medications.length,
    ms: Date.now() - started, at: new Date().toISOString()
  }).catch(() => {});
  return { kind: 'medLabel', draft, truncated: !!usage.truncated };
}

module.exports = { scan };
