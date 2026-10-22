// backend/services/dogPark/records.js
//
// "Import from your vet": photos of the paperwork or the vet's PDF → a draft
// of vaccines, visits, medications and weights for the phone to review.
// Nothing is kept: the images pass straight to the reader, the draft goes
// back to the phone (which keeps records in the private widget document),
// and only a usage line is logged. 10 scans per person per day.
const { getFirestore } = require('../../config/firebase');
const { ServiceError } = require('../../utils/serviceError');
const dailyBudget = require('../dailyBudget');
const images = require('../scan/images');
const reader = require('../scan/vetRecordReader');

async function scan(uid, body = {}, { db = getFirestore() } = {}) {
  const hasPdf = typeof body.pdf === 'string' && body.pdf.length > 0;
  const hasImages = Array.isArray(body.images) && body.images.length > 0;
  if (!hasPdf && !hasImages) throw new ServiceError(400, 'no_records', 'Add photos of the records or the PDF from your vet.');
  if (hasPdf && hasImages) throw new ServiceError(400, 'one_kind', 'Send photos or a PDF, not both.');
  const pdf = hasPdf ? reader.preparePdf(body.pdf) : null;
  const prepared = hasImages ? await images.prepare(body.images) : [];
  const budget = await dailyBudget.consume('vetScan', uid);
  if (!budget.allowed) throw new ServiceError(429, 'scan_limit', `That’s ${budget.limit} record scans today. Try again tomorrow.`);
  const started = Date.now();
  const { draft, usage } = await reader.read({ images: prepared, pdf, dogName: body.dogName || null });
  db.collection('scanUsage').add({
    userId: uid, kind: 'vetRecords', images: prepared.length, pdfPages: pdf ? pdf.pages : 0,
    ...usage, ms: Date.now() - started, at: new Date().toISOString()
  }).catch(() => {});
  return { draft, truncated: !!usage.truncated };
}

module.exports = { scan };
