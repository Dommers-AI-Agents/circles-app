// backend/services/storeWebEmails.js
// Email for customers who joined on a store's web page (views/storePage.js,
// Wes 2026-11-26): there is no Android app, so the store's specials and
// events reach them by email, every button goes back to the store's page,
// and every email can stop that store's emails with one tap and no login.
const { escapeHtml: esc } = require('../utils/text');

const BASE_URL = 'https://api.favcircles.com';
const STOP_PREFIX = 'store:';
const INK = '#1B1E24';
const GOLD = '#F6C945';

/**
 * Pure: an account made on a store's web page that has never opened the app
 * or the App Clip. Emails whose links only work in the app are held for
 * these (the weekly letter, people to follow, the map email).
 */
const isWebOnly = (user) => !!user && user.acquisitionSource === 'store_web'
  && !(Array.isArray(user.deviceTokens) && user.deviceTokens.length) && !user.clipInstallConvertedAt;

/** The store's page, opened as the web page on any phone. */
const storePageUrl = (code) => (code
  ? `${BASE_URL}/s/${encodeURIComponent(String(code).toUpperCase())}?web=1`
  : `${BASE_URL}/app/open`);

/** The unsubscribe "kind" that means one store's emails (see emailPreferenceRoutes). */
const stopKind = (globalPlaceId) => `${STOP_PREFIX}${globalPlaceId}`;
const placeFromStopKind = (kind) => {
  const value = String(kind || '');
  if (!value.startsWith(STOP_PREFIX)) return null;
  const id = value.slice(STOP_PREFIX.length);
  return /^[A-Za-z0-9_-]{1,128}$/.test(id) ? id : null;
};

/** "Stop emails from this store": signed like every unsubscribe link, no login. */
const stopUrl = (userId, globalPlaceId) => {
  const { unsubscribeUrl } = require('./followSuggestionEmailService'); // lazy: touches Firestore on load
  return unsubscribeUrl(userId, stopKind(globalPlaceId));
};

/** Turns that store's bell off for this person (they keep the store and their points). */
async function stopStoreEmails(userId, globalPlaceId) {
  const { getFirestore } = require('../config/firebase');
  const { GLOBAL_COLLECTIONS } = require('../models/GlobalPlace');
  const ref = getFirestore().collection(GLOBAL_COLLECTIONS.GLOBAL_PLACES).doc(globalPlaceId);
  const { setAlerts } = require('./placeAlerts');
  await setAlerts(ref, userId, false);
  const doc = await ref.get();
  return { placeName: doc.exists ? doc.data().name || null : null };
}

/**
 * Pure: the first email after joining on the store's page. What they got,
 * what points buy here, and the link that is their way back in.
 */
const buildWelcome = ({ store, awardedPoints = 0, rewards = null, coupon = null, stop = null }) => {
  const name = store.name;
  const headline = awardedPoints > 0 ? `You're in at ${name}. +${awardedPoints} points.` : `You're in at ${name}.`;
  const ladder = rewards && rewards.offers && rewards.offers.length
    ? `<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin-top:16px;">${rewards.offers.map((o) => `<tr>
        <td style="padding:9px 0;border-top:1px solid #E6EAF1;font-size:15px;color:#1A2438;">${esc(o.title)}</td>
        <td align="right" style="padding:9px 0;border-top:1px solid #E6EAF1;font-size:14px;color:#5B6780;white-space:nowrap;">${o.pointsCost} points</td></tr>`).join('')}</table>`
    : '';
  const earn = rewards && rewards.earnRate
    ? `<p style="font-size:15px;line-height:22px;color:#5B6780;margin:10px 0 0;">Scan the code at the register each visit for ${rewards.earnRate} points. You have ${rewards.balance || 0} so far.</p>`
    : `<p style="font-size:15px;line-height:22px;color:#5B6780;margin:10px 0 0;">${esc(name)} is saved to you. Its specials and events will come to this address.</p>`;
  const couponLine = coupon && coupon.title
    ? `<p style="font-size:15px;line-height:22px;margin:14px 0 0;padding:12px 14px;border:1px dashed ${GOLD};border-radius:12px;"><b>Your coupon:</b> ${esc(coupon.title)}<br><span style="color:#5B6780;">Scan the code at the register to use it.</span></p>`
    : '';
  const photo = store.photoUrl
    ? `<tr><td><img src="${esc(store.photoUrl)}" width="520" alt="" style="display:block;width:100%;max-width:520px;height:auto;border:0;"></td></tr>`
    : '';
  const footer = stop
    ? `You're getting this because you joined ${esc(name)} with this email. <a href="${stop}" style="color:#8C97AB;">Stop emails from this store</a>.`
    : `You're getting this because you joined ${esc(name)} with this email.`;
  const html = `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background:#EEF1F6;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#EEF1F6;"><tr><td align="center" style="padding:24px 12px;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;background:#ffffff;border-radius:16px;overflow:hidden;">
    <tr><td style="background:${INK};padding:16px 24px;font-family:-apple-system,Helvetica,Arial,sans-serif;font-size:16px;font-weight:800;color:#ffffff;">FavCircles</td></tr>
    ${photo}
    <tr><td style="padding:26px 24px 28px;font-family:-apple-system,Helvetica,Arial,sans-serif;color:#1A2438;">
      <div style="font-family:Georgia,'Times New Roman',serif;font-size:24px;line-height:30px;font-weight:700;">${esc(headline)}</div>
      ${earn}${couponLine}${ladder}
      <table role="presentation" cellpadding="0" cellspacing="0" style="margin-top:22px;"><tr>
        <td style="background:${GOLD};border-radius:10px;"><a href="${store.pageUrl}" style="display:inline-block;padding:12px 22px;font-size:15px;font-weight:800;color:${INK};text-decoration:none;">Open my points at ${esc(name)}</a></td></tr></table>
      <p style="font-size:13px;line-height:19px;color:#8C97AB;margin:16px 0 0;">Keep this email: the button is your way back to your points on any phone.</p>
    </td></tr>
  </table>
  <div style="max-width:520px;font-family:-apple-system,Helvetica,Arial,sans-serif;font-size:12px;line-height:18px;color:#8C97AB;padding:14px 12px 0;text-align:center;">${footer}</div>
</td></tr></table></body></html>`;
  const text = `${headline}\n\n${rewards && rewards.earnRate ? `Scan the code at the register each visit for ${rewards.earnRate} points.` : `${name} is saved to you.`}`
    + `${coupon && coupon.title ? `\nYour coupon: ${coupon.title}` : ''}\n\nOpen my points: ${store.pageUrl}\n${stop ? `\nStop emails from this store: ${stop}\n` : ''}`;
  return { subject: headline, html, text, unsubscribe: stop };
};

module.exports = { isWebOnly, storePageUrl, stopKind, placeFromStopKind, stopUrl, stopStoreEmails, buildWelcome };
