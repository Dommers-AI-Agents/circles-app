// backend/services/moderationService.js
//
// Content governance for user-generated content (App Review guideline 1.2):
// report → auto-hide at a reporter threshold → admin adjudication, plus the
// block model that removes a user's content from someone's app entirely.
//
// Block state is denormalized onto both user docs (blockedUsers on the
// blocker, blockedBy on the blocked) so every hot read path can filter from
// data it already holds — the BLOCKS collection stays the audit trail.

const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');

const db = getFirestore();

// Distinct TRUSTED reporters required before content is auto-hidden pending
// review. Any account's report still alerts the admin; only trusted ones
// count toward the automatic hide (see isTrustedReporter).
const AUTO_HIDE_THRESHOLD = 2;

// Security audit 2026-10-01: two throwaway accounts made in a minute could
// hide anyone's moment or comment. A reporter counts toward auto-hide only
// once their account is a week old and not banned.
const TRUSTED_REPORTER_MIN_AGE_MS = 7 * 24 * 60 * 60 * 1000;
// Reads at most this many reports per item when counting — far past the
// threshold; the admin sees every report regardless.
const MAX_REPORTS_SCANNED = 200;

const toMillis = (value) => {
  if (!value) return null;
  if (typeof value.toMillis === 'function') return value.toMillis();
  if (value instanceof Date) return value.getTime();
  if (typeof value === 'object' && Number.isFinite(value._seconds)) return value._seconds * 1000;
  const ms = Date.parse(value);
  return Number.isFinite(ms) ? ms : null;
};

/**
 * Pure: may this reporter's report count toward auto-hide?
 * `userSnap` is a user DocumentSnapshot. Age comes from the doc's `createdAt`,
 * falling back to Firestore's own createTime; a legacy account with neither
 * is treated as trusted (an attacker can't mint one of those today).
 */
function isTrustedReporter(userSnap, now = Date.now()) {
  if (!userSnap || !userSnap.exists) return false;
  const data = userSnap.data() || {};
  if (data.banned === true) return false;
  const created = toMillis(data.createdAt) ?? toMillis(userSnap.createTime);
  if (created === null) return true;
  return now - created >= TRUSTED_REPORTER_MIN_AGE_MS;
}


// The union of "people I blocked" and "people who blocked me" — content in
// either direction is invisible. Works straight off a loaded user doc
// (req.user carries the full doc via the auth middleware).
function excludedUserIds(userData) {
  return new Set([
    ...(userData?.blockedUsers || []),
    ...(userData?.blockedBy || [])
  ]);
}

function isBlockedEitherWay(userData, otherUserId) {
  return excludedUserIds(userData).has(otherUserId);
}

// Where a given content type's moderationStatus lives.
function contentRef(contentType, contentId) {
  switch (contentType) {
    case 'moment':
    case 'video':
      return db.collection(COLLECTIONS.PLACE_VIDEOS).doc(contentId);
    case 'comment':
      return db.collection(COLLECTIONS.PLACE_COMMENTS).doc(contentId);
    case 'video_comment':
      return db.collection('videoComments').doc(contentId);
    default:
      return null; // place/photo/profile reports are admin-adjudicated only
  }
}

// Count distinct reporters for a piece of content, and how many of them are
// trusted (report doc ids are deduped per reporter, so doc count == reporter
// count). Equality filters only — no composite index needed.
async function reporterCounts(contentType, contentId, now = Date.now()) {
  const snap = await db.collection(COLLECTIONS.REPORTS)
    .where('reportedItemType', '==', contentType)
    .where('reportedItemId', '==', contentId)
    .limit(MAX_REPORTS_SCANNED)
    .get();
  const reporterIds = [...new Set(snap.docs.map(d => d.data().reporterId).filter(Boolean))];
  if (reporterIds.length === 0) return { count: snap.size, trustedCount: 0 };
  const userSnaps = await db.getAll(...reporterIds.map(id => db.collection(COLLECTIONS.USERS).doc(String(id))));
  const trustedCount = userSnaps.filter(u => isTrustedReporter(u, now)).length;
  return { count: snap.size, trustedCount };
}

// Auto-hide once enough distinct trusted people have reported: the community
// quarantines, the admin adjudicates. Idempotent.
async function applyAutoHideIfNeeded(contentType, contentId) {
  const ref = contentRef(contentType, contentId);
  if (!ref) return { hidden: false, reason: 'type_not_auto_hidable' };
  const { count, trustedCount } = await reporterCounts(contentType, contentId);
  if (trustedCount < AUTO_HIDE_THRESHOLD) return { hidden: false, count, trustedCount };
  const doc = await ref.get();
  if (!doc.exists) return { hidden: false, reason: 'content_missing', count, trustedCount };
  if (doc.data().moderationStatus === 'removed') return { hidden: true, count, trustedCount }; // already actioned
  await ref.update({
    moderationStatus: 'under_review',
    moderationHiddenAt: new Date().toISOString()
  });
  console.log(`🛡️ auto-hid ${contentType} ${contentId} after ${trustedCount} trusted of ${count} reports`);
  return { hidden: true, count, trustedCount };
}

// Every report emails the admin — this is the "timely response" pipeline.
// Fire-and-forget; a mail failure must never fail the report.
async function notifyAdmin(report, extra = {}) {
  try {
    const lines = [
      `Type: ${report.type} (${report.reportedItemType || 'user'})`,
      `Target: ${report.reportedItemId || report.reportedUserId}`,
      `Reason: ${report.reason}`,
      report.details ? `Details: ${report.details}` : null,
      `Reporter: ${report.reporterId}`,
      extra.autoHidden ? `⚠️ AUTO-HIDDEN (${extra.reporterCount} reporters)` : `Reporter count: ${extra.reporterCount || 1}`,
      extra.trustedCount !== undefined
        ? `Trusted reporters (account ≥7 days, not banned): ${extra.trustedCount} — auto-hide needs ${AUTO_HIDE_THRESHOLD}`
        : null,
      '',
      'Action via: POST /api/reports/<reportId>/action {"action": "dismiss" | "remove_content" | "ban_user"}',
      `Report ID: ${report.id}`
    ].filter(Boolean);
    // Through the one admin channel (email with retries + push to the admin
    // account); every report alerts — no de-duplication (security audit 2026-10-01)
    await require('./adminAlerts').alertAdmin({
      key: `report_${report.id}`,
      minIntervalMs: 0,
      title: `🛡️ Report: ${report.reportedItemType || 'user'} — ${report.reason}${extra.autoHidden ? ' [AUTO-HIDDEN]' : ''}`,
      body: lines.join('\n')
    });
  } catch (e) {
    console.error('🛡️ moderation alert email failed:', e.message);
  }
}

module.exports = {
  AUTO_HIDE_THRESHOLD,
  TRUSTED_REPORTER_MIN_AGE_MS,
  isTrustedReporter,
  excludedUserIds,
  isBlockedEitherWay,
  contentRef,
  applyAutoHideIfNeeded,
  notifyAdmin
};
