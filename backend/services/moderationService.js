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
const emailService = require('./emailService');

const db = getFirestore();

// Distinct reporters required before content is auto-hidden pending review.
const AUTO_HIDE_THRESHOLD = 2;

const ADMIN_EMAIL = process.env.MODERATION_ALERT_EMAIL || 'wesley@favcircles.com';

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

// Count distinct reporters for a piece of content (report doc ids are
// deduped per reporter, so doc count == reporter count).
async function reporterCount(contentType, contentId) {
  const snap = await db.collection(COLLECTIONS.REPORTS)
    .where('reportedItemType', '==', contentType)
    .where('reportedItemId', '==', contentId)
    .count().get();
  return snap.data().count || 0;
}

// Auto-hide once enough distinct people have reported: the community
// quarantines, the admin adjudicates. Idempotent.
async function applyAutoHideIfNeeded(contentType, contentId) {
  const ref = contentRef(contentType, contentId);
  if (!ref) return { hidden: false, reason: 'type_not_auto_hidable' };
  const count = await reporterCount(contentType, contentId);
  if (count < AUTO_HIDE_THRESHOLD) return { hidden: false, count };
  const doc = await ref.get();
  if (!doc.exists) return { hidden: false, reason: 'content_missing' };
  if (doc.data().moderationStatus === 'removed') return { hidden: true, count }; // already actioned
  await ref.update({
    moderationStatus: 'under_review',
    moderationHiddenAt: new Date().toISOString()
  });
  console.log(`🛡️ auto-hid ${contentType} ${contentId} after ${count} reports`);
  return { hidden: true, count };
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
      '',
      'Action via: POST /api/reports/<reportId>/action {"action": "dismiss" | "remove_content" | "ban_user"}',
      `Report ID: ${report.id}`
    ].filter(Boolean);
    await emailService.transporter.sendMail({
      from: `"FavCircles Moderation" <${process.env.EMAIL_FROM_ADDRESS || 'wesley@favcircles.com'}>`,
      to: ADMIN_EMAIL,
      subject: `🛡️ Content report: ${report.reportedItemType || 'user'} — ${report.reason}${extra.autoHidden ? ' [AUTO-HIDDEN]' : ''}`,
      text: lines.join('\n')
    });
  } catch (e) {
    console.error('🛡️ moderation alert email failed:', e.message);
  }
}

module.exports = {
  AUTO_HIDE_THRESHOLD,
  excludedUserIds,
  isBlockedEitherWay,
  contentRef,
  applyAutoHideIfNeeded,
  notifyAdmin
};
