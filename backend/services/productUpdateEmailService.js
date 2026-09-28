// backend/services/productUpdateEmailService.js
//
// "What's new" emails to every account. One campaign per announcement,
// recorded per user (users/{uid}.productUpdateEmails[campaign]) so a rerun
// after a crash or a partial send never mails anyone twice. Same guard rails
// as the follow-suggestion email: one message at a time with a pause (the
// SMTP host dislikes bursts), one retry per address, a signed one-click
// unsubscribe (kind "productUpdates"), and never the App Review account.
//
// Run from backend/ with the production .env loaded:
//   node services/productUpdateEmailService.js --campaign=2026-09-postcards --dry-run
//   node services/productUpdateEmailService.js --campaign=2026-09-postcards --only=you@example.com
//   node services/productUpdateEmailService.js --campaign=2026-09-postcards --send
const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');
const emailService = require('./emailService');

const PREFERENCE_KEY = 'productUpdates';
const EXCLUDED_EMAILS = new Set(['appreview@favcircles.com', 'review@favcircles.com', 'test@favcircles.com']);
const SEND_GAP_MS = 3000;
const RETRY_DELAY_MS = 8000;
const APP_OPEN_URL = 'https://api.favcircles.com/app/open';
const APP_STORE_URL = 'https://apps.apple.com/us/app/favcircles/id6746807095';
const BRAND_BLUE = '#3478F6';
const POSTCARD_RED = '#E53E3E';
const sleep = (ms) => new Promise((res) => setTimeout(res, ms));

const esc = (s) => String(s == null ? '' : s)
  .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

const firstName = (user) => ((user.firstName || user.displayName || '').trim().split(/\s+/)[0]) || null;

/** Pure: who gets this campaign. */
const selectRecipients = (users, campaign) => {
  const selected = [];
  const skipped = { no_email: 0, internal: 0, deleted: 0, opted_out: 0, already_sent: 0 };
  for (const user of users) {
    if (user.isDeleted || user.deletedAt || user.accountStatus === 'deleted') { skipped.deleted++; continue; }
    const email = (user.email || '').trim();
    if (!email || !email.includes('@')) { skipped.no_email++; continue; }
    const lower = email.toLowerCase();
    // Our own domain is test and review accounts, apart from Wes's inbox
    if (EXCLUDED_EMAILS.has(lower) || (lower.endsWith('@favcircles.com') && lower !== 'wesley@favcircles.com')) { skipped.internal++; continue; }
    if (user.emailPreferences && user.emailPreferences[PREFERENCE_KEY] === false) { skipped.opted_out++; continue; }
    if (user.productUpdateEmails && user.productUpdateEmails[campaign]) { skipped.already_sent++; continue; }
    selected.push({ ...user, email });
  }
  return { selected, skipped };
};

// ---- the campaign content

const CAMPAIGNS = {
  '2026-09-postcards': {
    subject: 'Send a postcard from anywhere, now in FavCircles',
    preheader: 'Share it free as a link, or we print and mail a real one for $3.99.',
    build: ({ greeting }) => {
      const featureRow = (title, body) => `
        <tr><td style="padding:10px 0;border-top:1px solid #EEF1F5;">
          <div style="font-size:15px;font-weight:700;color:#1a202c;">${title}</div>
          <div style="font-size:14px;line-height:1.5;color:#4a5568;margin-top:2px;">${body}</div>
        </td></tr>`;
      const html = `
        <p style="font-size:16px;margin:0 0 16px;">${greeting}</p>
        <h1 style="font-size:24px;line-height:1.25;margin:0 0 8px;color:#1a202c;">Send a postcard from where you are</h1>
        <p style="font-size:15px;line-height:1.6;margin:0 0 16px;color:#4a5568;">
          Pick a photo from your trip, add a note, and choose how it goes out:
        </p>
        <table role="presentation" cellpadding="0" cellspacing="0" width="100%" style="margin:0 0 20px;">
          <tr>
            <td style="padding:14px 16px;background:#F4F8FE;border-radius:12px;">
              <div style="font-size:16px;font-weight:700;color:${BRAND_BLUE};">Digital · free</div>
              <div style="font-size:14px;line-height:1.5;color:#4a5568;margin-top:4px;">Share it as a link or by email. It opens in any browser, so the people you send it to don't need the app.</div>
            </td>
          </tr>
          <tr><td style="height:10px;"></td></tr>
          <tr>
            <td style="padding:14px 16px;background:#FEF3F2;border-radius:12px;">
              <div style="font-size:16px;font-weight:700;color:${POSTCARD_RED};">Printed and mailed · $3.99</div>
              <div style="font-size:14px;line-height:1.5;color:#4a5568;margin-top:4px;">We print a real 4×6 postcard and mail it anywhere in the US. Pay with Apple Pay; you can cancel within an hour of sending.</div>
            </td>
          </tr>
        </table>
        <p style="margin:0 0 8px;">
          <a href="${APP_OPEN_URL}" style="display:inline-block;background:${BRAND_BLUE};color:#fff;text-decoration:none;font-weight:700;font-size:16px;padding:12px 22px;border-radius:10px;">Send a postcard</a>
        </p>
        <p style="font-size:13px;color:#718096;margin:0 0 28px;">In the app: Home → Widgets → Postcard. You can also send one from any Moment.</p>
        <h2 style="font-size:17px;margin:0 0 4px;color:#1a202c;">Also new</h2>
        <table role="presentation" cellpadding="0" cellspacing="0" width="100%">
          ${featureRow('Fridge Mail', "Queue up your kids' drawings and we mail one as a real postcard to the grandparents every week.")}
          ${featureRow('Widgets', 'A new tab on Home with little tools: water and habits, workouts, sleep sounds, quotes, and How Are You? check-ins for Mom or Dad.')}
          ${featureRow('Inner Circle', 'Share places, moments and check-ins with only the people you choose.')}
        </table>
        <p style="font-size:14px;line-height:1.6;color:#4a5568;margin:24px 0 0;">
          Update FavCircles from the <a href="${APP_STORE_URL}" style="color:${BRAND_BLUE};">App Store</a> to get all of it.
        </p>`;
      const text = [
        greeting,
        '',
        'Send a postcard from where you are',
        'Pick a photo from your trip, add a note, and choose how it goes out:',
        '- Digital, free: share it as a link or by email. It opens in any browser, so the people you send it to don\'t need the app.',
        '- Printed and mailed, $3.99: we print a real 4x6 postcard and mail it anywhere in the US. Pay with Apple Pay; you can cancel within an hour of sending.',
        '',
        `Send a postcard: ${APP_OPEN_URL}`,
        'In the app: Home > Widgets > Postcard. You can also send one from any Moment.',
        '',
        'Also new',
        "- Fridge Mail: queue up your kids' drawings and we mail one as a real postcard to the grandparents every week.",
        '- Widgets: a new tab on Home with little tools: water and habits, workouts, sleep sounds, quotes, and How Are You? check-ins for Mom or Dad.',
        '- Inner Circle: share places, moments and check-ins with only the people you choose.',
        '',
        `Update FavCircles from the App Store to get all of it: ${APP_STORE_URL}`
      ].join('\n');
      return { html, text };
    }
  }
};

const mailingAddress = () => (process.env.COMPANY_MAILING_ADDRESS || '').trim();

const buildEmail = ({ user, campaign }) => {
  const spec = CAMPAIGNS[campaign];
  if (!spec) throw new Error(`Unknown campaign ${campaign}`);
  const name = firstName(user);
  const greeting = name ? `Hi ${esc(name)},` : 'Hi there,';
  const { html: body, text: bodyText } = spec.build({ greeting });
  // Lazy: that module touches Firestore on load, before a CLI run has initialised it.
  const { unsubscribeUrl } = require('./followSuggestionEmailService');
  const unsub = unsubscribeUrl(user.id, PREFERENCE_KEY);
  const address = mailingAddress();
  const html = `<!doctype html><html><body style="margin:0;padding:0;background:#F7F9FC;">
<div style="display:none;max-height:0;overflow:hidden;">${esc(spec.preheader)}</div>
<table role="presentation" cellpadding="0" cellspacing="0" width="100%" style="background:#F7F9FC;">
  <tr><td align="center" style="padding:24px 12px;">
    <table role="presentation" cellpadding="0" cellspacing="0" width="100%" style="max-width:560px;background:#ffffff;border-radius:16px;">
      <tr><td style="padding:28px 28px 24px;font-family:-apple-system,Helvetica,Arial,sans-serif;color:#1a202c;">
        <div style="font-size:14px;font-weight:700;color:${BRAND_BLUE};margin-bottom:18px;">FavCircles</div>
        ${body}
      </td></tr>
    </table>
    <div style="max-width:560px;font-family:-apple-system,Helvetica,Arial,sans-serif;font-size:12px;line-height:1.6;color:#8896AB;padding:16px 12px 0;">
      You're getting this because you have a FavCircles account.
      <a href="${unsub}" style="color:#8896AB;">Unsubscribe from product updates</a>.
      ${address ? `<br>FavCircles · ${esc(address)}` : ''}
    </div>
  </td></tr>
</table></body></html>`;
  const text = `${bodyText}\n\n--\nYou're getting this because you have a FavCircles account.\nUnsubscribe from product updates: ${unsub}${address ? `\nFavCircles · ${address}` : ''}\n`;
  return { subject: spec.subject, html, text, unsubscribe: unsub };
};

/**
 * Sends (or dry-runs) one campaign. `onlyTo` limits it to one address, for a
 * test copy; a test copy is not recorded, so the real send still reaches it.
 */
const run = async ({ campaign, dryRun = true, onlyTo = null, log = console.log } = {}) => {
  if (!CAMPAIGNS[campaign]) throw new Error(`Unknown campaign ${campaign}`);
  if (!dryRun && !onlyTo && !mailingAddress()) {
    throw new Error('Set COMPANY_MAILING_ADDRESS first: a commercial email needs a postal address (CAN-SPAM).');
  }
  const snap = await db().collection(COLLECTIONS.USERS).get();
  const users = snap.docs.map((d) => ({ id: d.id, ...d.data() }));
  let { selected, skipped } = selectRecipients(users, campaign);
  if (onlyTo) {
    const target = onlyTo.toLowerCase();
    const match = users.find((u) => (u.email || '').toLowerCase() === target);
    selected = [{ ...(match || { id: 'test-recipient', firstName: 'Wes' }), email: onlyTo }];
  }
  const results = { campaign, dryRun, recipients: selected.length, sent: 0, failed: 0, skipped };
  log(`📣 ${campaign}: ${selected.length} recipients${dryRun ? ' (dry run)' : ''}; skipped ${JSON.stringify(skipped)}`);
  if (dryRun) {
    results.emails = selected.map((u) => u.email);
    return results;
  }
  for (const user of selected) {
    const email = buildEmail({ user, campaign });
    let delivered = false;
    for (let attempt = 1; attempt <= 2 && !delivered; attempt++) {
      try {
        await emailService.sendEmail({
          to: user.email, subject: email.subject, html: email.html, text: email.text,
          headers: {
            'List-Unsubscribe': `<${email.unsubscribe}>`,
            'List-Unsubscribe-Post': 'List-Unsubscribe=One-Click'
          }
        });
        delivered = true;
      } catch (e) {
        log(`📣 attempt ${attempt} failed for ${user.email}: ${e.message}`);
        if (attempt === 1) await sleep(RETRY_DELAY_MS);
      }
    }
    if (delivered) {
      results.sent++;
      log(`📣 sent to ${user.email}`);
      if (!onlyTo) {
        await db().collection(COLLECTIONS.USERS).doc(user.id)
          .set({ productUpdateEmails: { [campaign]: new Date().toISOString() } }, { merge: true });
      }
    } else {
      results.failed++;
    }
    await sleep(SEND_GAP_MS);
  }
  log(`📣 ${campaign} done: ${results.sent} sent, ${results.failed} failed`);
  return results;
};

const db = () => getFirestore();

module.exports = { PREFERENCE_KEY, CAMPAIGNS, selectRecipients, buildEmail, run };

if (require.main === module) {
  const arg = (name) => {
    const hit = process.argv.find((a) => a === `--${name}` || a.startsWith(`--${name}=`));
    if (!hit) return null;
    return hit.includes('=') ? hit.split('=').slice(1).join('=') : true;
  };
  const campaign = arg('campaign');
  const onlyTo = arg('only');
  const dryRun = !arg('send') && !onlyTo;
  require('../config/firebase').initializeFirebase();
  run({ campaign, dryRun, onlyTo: typeof onlyTo === 'string' ? onlyTo : null })
    .then((r) => { console.log(JSON.stringify(r, null, 2)); process.exit(0); })
    .catch((e) => { console.error(e.message); process.exit(1); });
}
