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
const { forEachPage } = require('../utils/firestorePaging');

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

const NAVY = '#0F1E3A';
const INK = '#1A2438';
const MUTED = '#5B6780';
const LINE = '#E6EAF1';
const IMG = 'https://favcircles.com/img/email';
const FONT = "-apple-system,BlinkMacSystemFont,'Segoe UI',Helvetica,Arial,sans-serif";

// A row in "Also new": a tinted round badge with an emoji, then the words.
const featureRow = (emoji, tint, title, body) => `
  <tr>
    <td width="52" valign="top" style="padding:14px 0 14px 0;">
      <div style="width:40px;height:40px;border-radius:20px;background:${tint};text-align:center;font-size:20px;line-height:40px;">${emoji}</div>
    </td>
    <td valign="top" style="padding:14px 0;border-bottom:1px solid ${LINE};">
      <div style="font-family:${FONT};font-size:16px;font-weight:700;color:${INK};">${title}</div>
      <div style="font-family:${FONT};font-size:14px;line-height:21px;color:${MUTED};padding-top:3px;">${body}</div>
    </td>
  </tr>`;

// One of the two "how it goes out" cards. Stacks on phones via .col.
const optionCard = ({ label, price, color, tint, body }) => `
  <td class="col" width="50%" valign="top" style="padding:0 6px 12px;">
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:${tint};border-radius:14px;">
      <tr><td style="padding:18px 18px 20px;">
        <div style="font-family:${FONT};font-size:12px;font-weight:700;letter-spacing:1.2px;text-transform:uppercase;color:${color};">${label}</div>
        <div style="font-family:${FONT};font-size:30px;font-weight:800;color:${INK};padding:6px 0 6px;">${price}</div>
        <div style="font-family:${FONT};font-size:14px;line-height:21px;color:${MUTED};">${body}</div>
      </td></tr>
    </table>
  </td>`;

// ---- "your map": each person's own saved places, drawn on a map

const MAP_URL = 'https://api.favcircles.com/app/map';
const MAP_CLUSTER_KM = 30;   // "around home": the densest 30 km of their places

/** Renders pins on OpenStreetMap tiles (free, same as the weekly map digest). */
const renderPlacesMap = async (places, { distanceKm }) => {
  const StaticMaps = require('staticmaps');
  const map = new StaticMaps({
    width: 1200,
    height: 640,
    paddingX: 110,
    paddingY: 110,
    tileUrl: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    tileRequestHeader: { 'User-Agent': 'FavCircles-product-update/1.0 (wesley@favcircles.com)' }
  });
  const lats = places.map((p) => p.lat);
  const lngs = places.map((p) => p.lng);
  const spanKm = distanceKm({ lat: Math.min(...lats), lng: Math.min(...lngs) },
    { lat: Math.max(...lats), lng: Math.max(...lngs) });
  const radiusMeters = Math.max(45, Math.min(700, (Math.max(spanKm, 1) * 1000) / 48));
  for (const p of places) {
    map.addCircle({ coord: [p.lng, p.lat], radius: radiusMeters, fill: '#E53E3ECC', color: '#FFFFFF', width: 4 });
  }
  if (spanKm < 0.4) {
    // One place, or a few on one block: auto-fit would zoom to the pavement
    const center = [lngs.reduce((a, b) => a + b, 0) / lngs.length, lats.reduce((a, b) => a + b, 0) / lats.length];
    await map.render(center, 15);
  } else {
    await map.render();
  }
  return map.image.buffer('image/png');
};

/**
 * What the "your map" section needs for one person: how many places they
 * have saved, and a hosted picture of the densest cluster (usually home).
 * No places: { count: 0 }, and the section becomes "start your map".
 */
const mapBlockFor = async (user) => {
  const mapDigest = require('./mapDigestService');
  const places = await mapDigest.mappedPlaces(user.id);
  if (!places.length) return { count: 0 };
  let best = [];
  for (const center of places) {
    const cluster = places.filter((p) => mapDigest.distanceKm(center, p) <= MAP_CLUSTER_KM);
    if (cluster.length > best.length) best = cluster;
  }
  const votes = new Map();
  for (const p of best) {
    const city = mapDigest.cityFromAddress(p.address);
    if (city) votes.set(city, (votes.get(city) || 0) + 1);
  }
  const top = [...votes.entries()].sort((a, b) => b[1] - a[1])[0];
  const city = top && top[1] >= Math.ceil(best.length / 2) ? top[0] : null;
  let imageUrl = null;
  try {
    const buffer = await renderPlacesMap(best, mapDigest);
    const { uploadImage } = require('./storage');
    imageUrl = await uploadImage(buffer.toString('base64'), 'product-update-map.png');
  } catch (e) {
    // Tiles or storage hiccup: keep the count and the nudge, drop the picture
    console.warn(`📣 map image for ${user.id} failed: ${e.message}`);
  }
  return { count: places.length, shown: best.length, city, imageUrl };
};

const mapSection = (block) => {
  const label = `<div style="font-family:${FONT};font-size:12px;font-weight:700;letter-spacing:1.4px;text-transform:uppercase;color:#8C97AB;border-top:1px solid ${LINE};padding-top:26px;">Your map</div>`;
  const button = (text, href) => `
        <table role="presentation" cellpadding="0" cellspacing="0" style="margin-top:18px;"><tr>
          <td style="border:2px solid ${NAVY};border-radius:12px;">
            <a href="${href}" style="display:inline-block;padding:12px 26px;font-family:${FONT};font-size:15px;font-weight:700;color:${NAVY};text-decoration:none;">${text}</a>
          </td>
        </tr></table>`;
  if (!block) return { html: '', text: [] };   // places couldn't be read: leave the section out
  if (!block.count) {
    const html = `
      <tr><td class="pad" style="padding:34px 36px 4px;">
        ${label}
        <h2 style="margin:10px 0 0;font-family:${FONT};font-size:22px;line-height:28px;font-weight:800;color:${INK};">Start your own map</h2>
        <p style="margin:8px 0 0;font-family:${FONT};font-size:15px;line-height:23px;color:${MUTED};">Save the restaurants, shops and spots you love so you never forget them. Every one lands on your map, ready the next time someone asks where to go.</p>
        ${button('Save your first place', APP_OPEN_URL)}
      </td></tr>`;
    const text = ['YOUR MAP', 'Start your own map: save the restaurants, shops and spots you love so you never forget them. Every one lands on your map.', `Save your first place: ${APP_OPEN_URL}`];
    return { html, text };
  }
  const n = block.count;
  const where = !block.imageUrl ? '' : block.shown < n
    ? `Here are the ${block.shown}${block.city ? ` around ${esc(block.city)}` : ' closest together'}.`
    : (block.city ? `Here they are around ${esc(block.city)}.` : 'Here they are, all on one map.');
  const html = `
      <tr><td class="pad" style="padding:34px 36px 4px;">
        ${label}
        <h2 style="margin:10px 0 0;font-family:${FONT};font-size:22px;line-height:28px;font-weight:800;color:${INK};">You've saved ${n} favorite ${n === 1 ? 'place' : 'places'}</h2>
        <p style="margin:8px 0 14px;font-family:${FONT};font-size:15px;line-height:23px;color:${MUTED};">${where} Keep adding the places you love so you never forget a great one. They're always on your map.</p>
        ${block.imageUrl ? `<a href="${MAP_URL}"><img src="${block.imageUrl}" width="528" alt="Your saved places on a map" style="display:block;width:100%;max-width:528px;height:auto;border:0;border-radius:14px;"></a>
        <div style="font-family:${FONT};font-size:11px;color:#A3ADBF;padding-top:6px;">Map data © OpenStreetMap contributors</div>` : ''}
        ${button('Add a place', APP_OPEN_URL)}
      </td></tr>`;
  const text = ['YOUR MAP', `You've saved ${n} favorite ${n === 1 ? 'place' : 'places'}. Keep adding the places you love so you never forget a great one. They're always on your map.`, `Open your map: ${MAP_URL}`];
  return { html, text };
};

const CAMPAIGNS = {
  '2026-09-postcards': {
    subject: 'Send a postcard from anywhere, now in FavCircles',
    preheader: 'Share it free as a link, or we print and mail a real one for $3.99.',
    build: ({ greeting, map }) => {
      const html = `
      <tr><td style="padding:0;">
        <a href="${APP_OPEN_URL}"><img src="${IMG}/postcards-hero.jpg" width="600" alt="A FavCircles postcard, front and back" style="display:block;width:100%;max-width:600px;height:auto;border:0;"></a>
      </td></tr>
      <tr><td class="pad" style="padding:32px 36px 8px;">
        <div style="font-family:${FONT};font-size:15px;color:${MUTED};padding-bottom:10px;">${greeting}</div>
        <h1 style="margin:0;font-family:${FONT};font-size:30px;line-height:36px;font-weight:800;color:${INK};letter-spacing:-0.3px;">Send a postcard from where you are</h1>
        <p style="margin:12px 0 0;font-family:${FONT};font-size:16px;line-height:25px;color:${MUTED};">Pick a photo from your trip, write a note, and choose how it goes out.</p>
      </td></tr>
      <tr><td class="pad" style="padding:20px 30px 4px;">
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr>
          ${optionCard({ label: 'Digital', price: 'Free', color: BRAND_BLUE, tint: '#EEF4FE', body: "Share it as a link or by email. It opens in any browser, so they don't need the app." })}
          ${optionCard({ label: 'Printed &amp; mailed', price: '$3.99', color: POSTCARD_RED, tint: '#FDF0EF', body: 'A real 4×6 card, mailed anywhere in the US. Apple Pay, and an hour to change your mind.' })}
        </tr></table>
      </td></tr>
      <tr><td align="center" style="padding:14px 36px 6px;">
        <table role="presentation" cellpadding="0" cellspacing="0"><tr>
          <td style="background:${NAVY};border-radius:12px;">
            <a href="${APP_OPEN_URL}" style="display:inline-block;padding:15px 34px;font-family:${FONT};font-size:16px;font-weight:700;color:#ffffff;text-decoration:none;">Send a postcard</a>
          </td>
        </tr></table>
        <div style="font-family:${FONT};font-size:13px;color:#8C97AB;padding-top:12px;">In the app: Home → Widgets → Postcard, or from any Moment.</div>
      </td></tr>
      <tr><td class="pad" style="padding:34px 36px 8px;">
        <div style="font-family:${FONT};font-size:12px;font-weight:700;letter-spacing:1.4px;text-transform:uppercase;color:#8C97AB;border-top:1px solid ${LINE};padding-top:26px;">Also new</div>
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin-top:6px;">
          ${featureRow('🖍️', '#FFF4E0', 'Fridge Mail', "Queue up your kids' drawings. We mail one to the grandparents every week as a real postcard.")}
          ${featureRow('🧩', '#EEF4FE', 'Widgets', 'A new Home tab of little tools: water, habits, workouts, sleep sounds, quotes, and How Are You? check-ins for Mom or Dad.')}
          ${featureRow('🔒', '#EEF8F1', 'Inner Circle', 'Share places, moments and check-ins with only the people you pick.')}
        </table>
      </td></tr>
      ${map.html}
      <tr><td class="pad" style="padding:22px 36px 34px;">
        <p style="margin:0;font-family:${FONT};font-size:14px;line-height:22px;color:${MUTED};">Get the latest version from the <a href="${APP_STORE_URL}" style="color:${BRAND_BLUE};text-decoration:none;font-weight:600;">App Store</a> to try all of it.</p>
      </td></tr>`;
      const text = [
        greeting,
        '',
        'Send a postcard from where you are',
        'Pick a photo from your trip, write a note, and choose how it goes out:',
        "- Digital, free: share it as a link or by email. It opens in any browser, so they don't need the app.",
        '- Printed and mailed, $3.99: a real 4x6 card, mailed anywhere in the US. Apple Pay, and an hour to change your mind.',
        '',
        `Send a postcard: ${APP_OPEN_URL}`,
        'In the app: Home > Widgets > Postcard, or from any Moment.',
        '',
        'ALSO NEW',
        "- Fridge Mail: queue up your kids' drawings. We mail one to the grandparents every week as a real postcard.",
        '- Widgets: a new Home tab of little tools: water, habits, workouts, sleep sounds, quotes, and How Are You? check-ins for Mom or Dad.',
        '- Inner Circle: share places, moments and check-ins with only the people you pick.',
        '',
        ...map.text,
        '',
        `Get the latest version from the App Store: ${APP_STORE_URL}`
      ].join('\n');
      return { html, text };
    }
  }
};

// Postal address for the footer: CAN-SPAM requires one on a commercial email.
const COMPANY_MAILING_ADDRESS = 'PO Box 1540, Charlotte, NC 28203';
const mailingAddress = () => (process.env.COMPANY_MAILING_ADDRESS || COMPANY_MAILING_ADDRESS).trim();

const buildEmail = ({ user, campaign, mapBlock = null }) => {
  const spec = CAMPAIGNS[campaign];
  if (!spec) throw new Error(`Unknown campaign ${campaign}`);
  const name = firstName(user);
  const greeting = name ? `Hi ${esc(name)},` : 'Hi there,';
  const { html: body, text: bodyText } = spec.build({ greeting, map: mapSection(mapBlock) });
  // Lazy: that module touches Firestore on load, before a CLI run has initialised it.
  const { unsubscribeUrl } = require('./followSuggestionEmailService');
  const unsub = unsubscribeUrl(user.id, PREFERENCE_KEY);
  const address = mailingAddress();
  const html = `<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="color-scheme" content="light"><meta name="supported-color-schemes" content="light">
<title>${esc(spec.subject)}</title>
<style>
  @media (max-width:620px){
    .outer{padding:0 !important;}
    .shell{width:100% !important;border-radius:0 !important;}
    .pad{padding-left:22px !important;padding-right:22px !important;}
    .col{display:block !important;width:100% !important;box-sizing:border-box;}
    h1{font-size:26px !important;line-height:32px !important;}
  }
</style></head>
<body style="margin:0;padding:0;background:#EEF1F6;">
<div style="display:none;max-height:0;overflow:hidden;opacity:0;">${esc(spec.preheader)}&#8199;&#65279;&#847;&#8199;&#65279;&#847;&#8199;&#65279;&#847;</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#EEF1F6;">
  <tr><td align="center" class="outer" style="padding:28px 12px;">
    <table role="presentation" class="shell" width="600" cellpadding="0" cellspacing="0" style="width:100%;max-width:600px;background:#ffffff;border-radius:18px;overflow:hidden;">
      <tr><td style="background:${NAVY};padding:18px 28px;">
        <table role="presentation" cellpadding="0" cellspacing="0"><tr>
          <td style="padding-right:10px;"><img src="https://favcircles.com/app-icon.png" width="30" height="30" alt="" style="display:block;border-radius:7px;border:0;"></td>
          <td style="font-family:${FONT};font-size:18px;font-weight:800;color:#ffffff;letter-spacing:-0.2px;">FavCircles</td>
        </tr></table>
      </td></tr>
      ${body}
    </table>
    <table role="presentation" width="600" class="shell" cellpadding="0" cellspacing="0" style="width:100%;max-width:600px;">
      <tr><td class="pad" style="padding:20px 36px 8px;font-family:${FONT};font-size:12px;line-height:19px;color:#8C97AB;text-align:center;">
        You're getting this because you have a FavCircles account.<br>
        <a href="${unsub}" style="color:#8C97AB;text-decoration:underline;">Unsubscribe from product updates</a>
        ${address ? `<br>FavCircles · ${esc(address)}` : ''}
      </td></tr>
    </table>
  </td></tr>
</table>
</body></html>`;
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
  const results = { campaign, dryRun, recipients: 0, sent: 0, failed: 0, skipped: selectRecipients([], campaign).skipped };
  if (dryRun) results.emails = [];

  // A test copy looks up just that address — no need to read every account.
  if (onlyTo) {
    const match = await findUserByEmail(onlyTo);
    const selected = [{ ...(match || { id: 'test-recipient', firstName: 'Wes' }), email: onlyTo }];
    results.recipients = 1;
    log(`📣 ${campaign}: test copy to ${onlyTo}${dryRun ? ' (dry run)' : ''}`);
    if (dryRun) results.emails.push(onlyTo);
    else await sendTo(selected, { campaign, onlyTo, results, log });
    log(`📣 ${campaign} done: ${results.sent} sent, ${results.failed} failed`);
    return results;
  }

  // Viral-growth review 2026-10-01: stream accounts a page at a time and mail
  // each page's recipients before reading the next, instead of loading every
  // user doc first. The per-user stamp still makes a rerun resume safely.
  log(`📣 ${campaign}: walking accounts${dryRun ? ' (dry run)' : ''}`);
  await forEachPage(db().collection(COLLECTIONS.USERS), async (docs) => {
    const { selected, skipped } = selectRecipients(docs.map((d) => ({ id: d.id, ...d.data() })), campaign);
    for (const [reason, n] of Object.entries(skipped)) results.skipped[reason] += n;
    results.recipients += selected.length;
    if (dryRun) results.emails.push(...selected.map((u) => u.email));
    else await sendTo(selected, { campaign, onlyTo, results, log });
  });
  log(`📣 ${campaign}: ${results.recipients} recipients${dryRun ? ' (dry run)' : ''}; skipped ${JSON.stringify(results.skipped)}`);
  if (dryRun) return results;
  log(`📣 ${campaign} done: ${results.sent} sent, ${results.failed} failed`);
  return results;
};

/** Case-insensitive lookup of one account by address (equality probes, no scan). */
const findUserByEmail = async (address) => {
  const variants = [...new Set([address, address.toLowerCase()])];
  for (const email of variants) {
    const snap = await db().collection(COLLECTIONS.USERS).where('email', '==', email).limit(1).get();
    if (!snap.empty) return { id: snap.docs[0].id, ...snap.docs[0].data() };
  }
  return null;
};

/** Sends to each user in turn, with the retry, pause and per-user stamp. */
const sendTo = async (selected, { campaign, onlyTo, results, log }) => {
  for (const user of selected) {
    let mapBlock = null;
    try {
      mapBlock = await mapBlockFor(user);
    } catch (e) {
      log(`📣 map for ${user.email} failed, sending without it: ${e.message}`);
    }
    const email = buildEmail({ user, campaign, mapBlock });
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
};

const db = () => getFirestore();

module.exports = { PREFERENCE_KEY, CAMPAIGNS, selectRecipients, buildEmail, mapBlockFor, mapSection, run };

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
