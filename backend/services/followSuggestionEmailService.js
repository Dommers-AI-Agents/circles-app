// backend/services/followSuggestionEmailService.js
//
// "People you may know" email for accounts that are still following almost
// nobody. A FavCircles map is only as good as the people on it, and the
// people who never get past two follows are the ones who churn. Once a week
// (and on demand) this picks those users and mails them the top ranked
// suggestions from the same engine Discover uses — with the engine's own
// reason for each ("Also saved Café Mogador + 5 more", "Saves coffee & bars
// in Belmar", "Followed by Dani + 3 others you follow"), so the email says
// why, not just who.
//
// Guard rails: only accounts younger than MAX_ACCOUNT_AGE_DAYS (they are the
// "new people"), only usable addresses (no Apple private relay), never twice
// within a week, never after the one-click unsubscribe, and never when the
// engine has nobody worth suggesting.
const crypto = require('crypto');
const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');
const suggestionEngine = require('./suggestionEngine');
const emailService = require('./emailService');

const FOLLOW_THRESHOLD = 3;          // "following less than three people"
const SUGGESTIONS_PER_EMAIL = 5;
const MIN_DAYS_BETWEEN_EMAILS = 6;   // weekly job + a little slack
const DEFAULT_MAX_ACCOUNT_AGE_DAYS = 60;
const PREFERENCE_KEY = 'followSuggestions';
const APP_REVIEW_EMAIL = 'appreview@favcircles.com';
const SEND_GAP_MS = 3000;            // between messages — the SMTP host dislikes bursts
const RETRY_DELAY_MS = 8000;         // one retry per address after a failure
const sleep = (ms) => new Promise((res) => setTimeout(res, ms));
const BASE_URL = 'https://api.favcircles.com';
const BRAND_BLUE = '#3478F6';

const maxAccountAgeDays = () => {
  const n = parseInt(process.env.FOLLOW_SUGGESTION_MAX_ACCOUNT_AGE_DAYS || '', 10);
  return Number.isFinite(n) && n > 0 ? n : DEFAULT_MAX_ACCOUNT_AGE_DAYS;
};

const toDate = (value) => {
  if (!value) return null;
  if (value instanceof Date) return value;
  if (typeof value.toDate === 'function') return value.toDate();
  const d = new Date(value);
  return Number.isNaN(d.getTime()) ? null : d;
};

const daysBetween = (a, b) => Math.abs(a.getTime() - b.getTime()) / 86400000;

/**
 * Pure: which users get the email this run. `users` are plain user docs with
 * their id. Returns { selected, skipped } where skipped counts each reason.
 */
const selectCandidates = (users, { now = new Date(), maxAgeDays = maxAccountAgeDays() } = {}) => {
  const selected = [];
  const skipped = { following_enough: 0, no_usable_email: 0, internal: 0, too_old: 0, opted_out: 0, sent_recently: 0 };
  for (const user of users) {
    const followingCount = Array.isArray(user.following) ? user.following.length : (user.followingCount || 0);
    if (followingCount >= FOLLOW_THRESHOLD) { skipped.following_enough++; continue; }
    const email = (user.email || '').trim();
    if (!email || email.endsWith('@privaterelay.appleid.com')) { skipped.no_usable_email++; continue; }
    // The App Review demo account gets no growth email (Wes, 2026-09-16)
    if (email.toLowerCase() === APP_REVIEW_EMAIL) { skipped.internal++; continue; }
    const createdAt = toDate(user.createdAt);
    if (!createdAt || daysBetween(now, createdAt) > maxAgeDays) { skipped.too_old++; continue; }
    if (user.emailPreferences && user.emailPreferences[PREFERENCE_KEY] === false) { skipped.opted_out++; continue; }
    const lastSentAt = toDate(user.followSuggestionEmail && user.followSuggestionEmail.lastSentAt);
    if (lastSentAt && daysBetween(now, lastSentAt) < MIN_DAYS_BETWEEN_EMAILS) { skipped.sent_recently++; continue; }
    selected.push({ ...user, email, followingCount });
  }
  return { selected, skipped };
};

// ---- one-click unsubscribe (signed, no login needed from an email client)

const unsubscribeSecret = () => process.env.JWT_SECRET || process.env.UNSUBSCRIBE_SECRET || '';

const unsubscribeToken = (userId, kind = PREFERENCE_KEY) =>
  crypto.createHmac('sha256', unsubscribeSecret()).update(`${userId}:${kind}`).digest('hex');

const verifyUnsubscribeToken = (userId, kind, token) => {
  if (!userId || !kind || !token || !unsubscribeSecret()) return false;
  const expected = Buffer.from(unsubscribeToken(userId, kind));
  const given = Buffer.from(String(token));
  return expected.length === given.length && crypto.timingSafeEqual(expected, given);
};

const unsubscribeUrl = (userId, kind = PREFERENCE_KEY) =>
  `${BASE_URL}/api/email/unsubscribe?uid=${encodeURIComponent(userId)}&kind=${encodeURIComponent(kind)}&sig=${unsubscribeToken(userId, kind)}`;

// ---- the email

const esc = (s) => String(s == null ? '' : s)
  .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

const firstName = (user) => ((user.firstName || user.displayName || '').trim().split(/\s+/)[0]) || null;

const subjectFor = (suggestions) =>
  suggestions.length === 1
    ? 'Someone near you is on FavCircles'
    : `${suggestions.length} people near you on FavCircles`;

const buildEmail = ({ user, suggestions }) => {
  const name = firstName(user);
  const greeting = name ? `Hi ${esc(name)},` : 'Hi there,';
  const following = user.followingCount || 0;
  const followingLine = following === 0
    ? "You're not following anyone yet"
    : `You're following ${following} ${following === 1 ? 'person' : 'people'} so far`;
  const unsub = unsubscribeUrl(user.id);

  const rows = suggestions.map((s) => {
    const profileUrl = `${BASE_URL}/user/${encodeURIComponent(s.userId)}`;
    const avatar = s.profilePicture
      ? `<img src="${esc(s.profilePicture)}" width="48" height="48" alt="" style="width:48px;height:48px;border-radius:24px;object-fit:cover;display:block;">`
      : `<div style="width:48px;height:48px;border-radius:24px;background:#E6EEFB;color:${BRAND_BLUE};font-weight:700;font-size:20px;line-height:48px;text-align:center;">${esc((s.displayName || '?').trim().charAt(0).toUpperCase())}</div>`;
    const places = s.placesCount ? ` · ${s.placesCount} ${s.placesCount === 1 ? 'place' : 'places'}` : '';
    return `
      <tr>
        <td style="padding:12px 0;border-top:1px solid #EEF1F5;vertical-align:middle;width:48px;">${avatar}</td>
        <td style="padding:12px 12px;border-top:1px solid #EEF1F5;vertical-align:middle;">
          <div style="font-size:16px;font-weight:600;color:#1a202c;">${esc(s.displayName)}</div>
          <div style="font-size:13px;color:#4a5568;margin-top:2px;">${esc(s.reason)}${esc(places)}</div>
        </td>
        <td style="padding:12px 0;border-top:1px solid #EEF1F5;vertical-align:middle;text-align:right;white-space:nowrap;">
          <a href="${profileUrl}" style="display:inline-block;background:${BRAND_BLUE};color:#fff;text-decoration:none;font-weight:600;font-size:13px;padding:8px 14px;border-radius:8px;">View profile</a>
        </td>
      </tr>`;
  }).join('');

  const html = `
    <div style="font-family: -apple-system, Helvetica, Arial, sans-serif; max-width: 560px; margin: 0 auto; padding: 24px; color: #1a202c;">
      <h1 style="font-size: 22px; margin: 0 0 12px;">People you may know</h1>
      <p style="font-size: 15px; line-height: 1.6; margin: 0 0 6px;">${greeting}</p>
      <p style="font-size: 15px; line-height: 1.6; margin: 0 0 16px;">
        ${followingLine}. FavCircles gets better with every person you follow —
        their favorite places show up on your map, and yours on theirs.
        Here's who we think you may know, and why:
      </p>
      <table role="presentation" cellpadding="0" cellspacing="0" style="width:100%;border-collapse:collapse;border-bottom:1px solid #EEF1F5;">
        ${rows}
      </table>
      <div style="text-align:center;margin:22px 0 6px;">
        <a href="${BASE_URL}/app/open?path=network" style="display:inline-block;background:${BRAND_BLUE};color:#ffffff;text-decoration:none;font-weight:600;font-size:15px;padding:12px 26px;border-radius:9px;">Find more people</a>
      </div>
      <p style="font-size: 15px; line-height: 1.6;">— Wesley &amp; the FavCircles team</p>
      <div style="padding:16px 0 0;color:#999;font-size:12px;text-align:center;">
        <p style="margin:0;">You're getting this because you joined FavCircles recently and aren't following many people yet.</p>
        <p style="margin:6px 0 0;"><a href="${unsub}" style="color:#999;">Don't send me these</a></p>
      </div>
    </div>`;

  const text = [
    'People you may know',
    '',
    greeting.replace(/&amp;/g, '&'),
    '',
    `${followingLine}. FavCircles gets better with every person you follow — their favorite places show up on your map, and yours on theirs. Here's who we think you may know, and why:`,
    '',
    ...suggestions.map((s) => `• ${s.displayName} — ${s.reason}\n  ${BASE_URL}/user/${encodeURIComponent(s.userId)}`),
    '',
    `Find more people: ${BASE_URL}/app/open?path=network`,
    '',
    '— Wesley & the FavCircles team',
    '',
    `Don't want these emails? ${unsub}`
  ].join('\n');

  return { subject: subjectFor(suggestions), html, text };
};

/** A row is only worth showing when the person has a real name to show. */
const presentable = (s) => {
  const name = (s.displayName || '').trim();
  return name.length > 0 && !name.includes('@') && name.toLowerCase() !== 'someone';
};

// ---- the run

/**
 * Picks recipients, builds each one's suggestions from a fresh index, sends,
 * and stamps the user so the weekly job never repeats within a week.
 * dryRun: no email, no stamp — returns what would have gone out.
 */
const run = async ({ dryRun = false, limit = 500, onlyUserId = null, log = console.log } = {}) => {
  const [usersSnap, idx] = await Promise.all([
    db().collection(COLLECTIONS.USERS).get(),
    suggestionEngine.buildIndexes()
  ]);
  const users = usersSnap.docs
    .map((doc) => ({ id: doc.id, ...doc.data() }))
    .filter((u) => !onlyUserId || u.id === onlyUserId);
  const { selected, skipped } = selectCandidates(users);
  skipped.no_suggestions = 0;

  const results = { dryRun, candidates: selected.length, sent: 0, skipped, recipients: [] };
  for (const user of selected.slice(0, limit)) {
    const suggestions = suggestionEngine.suggestFor(user.id, idx).filter(presentable).slice(0, SUGGESTIONS_PER_EMAIL);
    if (suggestions.length === 0) { skipped.no_suggestions++; continue; }
    const email = buildEmail({ user, suggestions });
    results.recipients.push({
      userId: user.id,
      email: user.email,
      followingCount: user.followingCount,
      subject: email.subject,
      suggestions: suggestions.map((s) => ({ userId: s.userId, displayName: s.displayName, reason: s.reason })),
      ...(dryRun && results.recipients.length === 0 ? { sampleHtml: email.html } : {})
    });
    if (dryRun) continue;
    // One at a time, with a real pause between messages: the SMTP host
    // rejects bursts, so a batch is a slow orderly queue, never a fan-out.
    let delivered = false;
    for (let attempt = 1; attempt <= 2 && !delivered; attempt++) {
      try {
        await emailService.sendEmail({ to: user.email, subject: email.subject, html: email.html, text: email.text });
        delivered = true;
      } catch (e) {
        console.error(`👋 Follow suggestions attempt ${attempt} failed for ${user.id}:`, e.message);
        if (attempt === 1) await sleep(RETRY_DELAY_MS);
      }
    }
    if (delivered) {
      await db().collection(COLLECTIONS.USERS).doc(user.id).set({
        followSuggestionEmail: { lastSentAt: new Date().toISOString(), count: ((user.followSuggestionEmail || {}).count || 0) + 1 }
      }, { merge: true });
      results.sent++;
      log(`👋 Follow suggestions sent to ${user.email} (${suggestions.length} people)`);
    } else {
      results.failed = (results.failed || 0) + 1;
    }
    await sleep(SEND_GAP_MS);
  }
  log(`👋 Follow suggestions ${dryRun ? 'dry run' : 'complete'}: ${results.sent} sent of ${results.candidates} candidates; skipped ${JSON.stringify(skipped)}`);
  return results;
};

/** Marks a user as opted out of one email kind. */
const unsubscribe = async (userId, kind) => {
  await db().collection(COLLECTIONS.USERS).doc(userId).set({ emailPreferences: { [kind]: false } }, { merge: true });
};

// Lazy so tests can mock the firebase module before it is touched.
const db = () => getFirestore();

module.exports = {
  FOLLOW_THRESHOLD,
  SUGGESTIONS_PER_EMAIL,
  PREFERENCE_KEY,
  selectCandidates,
  presentable,
  buildEmail,
  subjectFor,
  unsubscribeToken,
  verifyUnsubscribeToken,
  unsubscribeUrl,
  unsubscribe,
  run
};
