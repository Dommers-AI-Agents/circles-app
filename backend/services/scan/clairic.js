// backend/services/scan/clairic.js — Cloudflare's Clairic extraction model
// (Workers AI, preview; $0.10 per million input tokens, nothing for output).
// It fills typed fields from text and up to 4 images and says how sure it
// is about each (confidence, p_null), without writing any text.
//
// Preview: Cloudflare may change or withdraw it. Anything calling this must
// treat `ServiceError(503, 'scan_unavailable')` as "fill it in by hand".
const { ServiceError } = require('../../utils/serviceError');

const MODEL = '@cf/cloudflare/clairic';
const TIMEOUT_MS = 30000;

const isConfigured = () => !!(process.env.CLOUDFLARE_ACCOUNT_ID && process.env.CLOUDFLARE_AI_TOKEN);

/**
 * Runs Clairic. `images` = [{ base64, mediaType }]. Returns
 * { answers, usage }. Throws ServiceError(503) when it can't be reached.
 */
async function extract({ fields, images = [], state = '', referenceDate = null }) {
  if (!isConfigured()) throw new ServiceError(503, 'scan_unavailable', 'Scanning isn’t available right now. You can fill this in by hand.');
  const url = `https://api.cloudflare.com/client/v4/accounts/${process.env.CLOUDFLARE_ACCOUNT_ID}/ai/run/${MODEL}`;
  const body = {
    model: 'clairic',
    state,
    fields,
    images: images.map((img) => ({ content_type: img.mediaType, base64: img.base64 }))
  };
  if (referenceDate) body.reference_date = referenceDate;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
  let res;
  try {
    res = await fetch(url, {
      method: 'POST',
      headers: { Authorization: `Bearer ${process.env.CLOUDFLARE_AI_TOKEN}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
      signal: controller.signal
    });
  } catch (e) {
    throw new ServiceError(503, 'scan_unavailable', 'Scanning isn’t available right now. You can fill this in by hand.');
  } finally {
    clearTimeout(timer);
  }
  const data = await res.json().catch(() => null);
  const result = data && (data.result || data);
  if (!res.ok || !result || !result.answers) {
    console.error('Clairic failed:', res.status, JSON.stringify(data && (data.errors || data)).slice(0, 300));
    throw new ServiceError(503, 'scan_unavailable', 'Scanning isn’t available right now. You can fill this in by hand.');
  }
  return { answers: result.answers, usage: result.usage || {} };
}

/**
 * One answer as { value, unsure }. A value the model thinks is probably not
 * there (p_null over the threshold, already nulled by Clairic) stays null;
 * a value it's unsure of is kept but flagged for the owner to check. Pure.
 */
function read(answer, { minConfidence = 0.7 } = {}) {
  if (!answer || answer.value === null || answer.value === undefined || answer.value === '') return { value: null, unsure: false };
  const confidence = typeof answer.confidence === 'number' ? answer.confidence : 1;
  return { value: answer.value, unsure: confidence < minConfidence };
}

module.exports = { MODEL, isConfigured, extract, read };
