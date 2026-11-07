// The follow-up email after a store visit (Wes, 2026-11-07): the store's own
// App Clip card as a picture right in the email, the link to try it, what's
// free and what Business adds, and a request for a demo. Sent by our server
// from wesley@favcircles.com, so its links stay clean (the Gmail connector
// turned every link into a google.com redirect with a "Redirect Notice").
const { cardPreviewJPEG } = require('./appClipExperienceService');
const rewardService = require('./rewardService');
const QRCode = require('qrcode');
const { escapeHtml: esc } = require('../utils/text');

const SITE = 'https://favcircles.com';
const OWNERS_PAGE = `${SITE}/store-owners.html`;
const SIGNATURE = {
  name: 'Wesley Sgroi',
  title: 'Founder and Developer, FavCircles LLC',
  phone: '480-349-2935',
  office: 'Office: Charlotte, South End',
  email: 'Wesley@FavCircles.com'
};

const FREE = [
  ['Your store page', 'keep your details, hours and photos right.'],
  ['Your buttons', 'Menu, Order, Reserve, Catering and Book links customers tap straight from your page.'],
  ['Window code and NFC sticker', 'customers scan or tap to save you and share you with friends.'],
  ['Your numbers at a glance', 'how many people scanned, saved and visited.'],
  ['Customer feedback and your team', 'read what people tell you, and add managers to help run your page.']
];
const BUSINESS = [
  ['Points at the register', 'customers earn points every visit, and you choose the rewards.'],
  ['Offers and announcements', 'to everyone who saved you.'],
  ['Your menu and photo gallery', 'and order ahead with pay at pickup.'],
  ['Your customers', 'who saved you and who comes back, with full stats.']
];

/** The store's card on the website: favcircles.com/store-cards/<slug>-<windowCode>.jpg */
function cardSlug(venue) {
  const slug = String(venue.venueName || 'store').toLowerCase().replace(/&/g, ' and ')
    .normalize('NFKD').replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 60) || 'store';
  return `${slug}-${venue.windowCode}.jpg`;
}

/**
 * { subject, html, text, attachments } for one store. `ownerName` is the
 * first name to greet ("Hi there" without one); `cardJpeg` is the card
 * picture (rendered when not given), embedded inline as cid:storecard.
 */
async function buildStoreFollowup(venue, { ownerName = null, cardJpeg = null } = {}) {
  if (!venue?.windowCode) throw new Error('This store has no window code');
  const store = String(venue.venueName || 'your store').trim();
  const tryLink = rewardService.stickerUrl(venue.windowCode);
  const cardUrl = `${SITE}/store-cards/${cardSlug(venue)}`;
  const jpeg = cardJpeg || await cardPreviewJPEG(venue, 'window');
  // Scanned with an iPhone's camera, it opens the card itself (2026-11-07)
  const qrPng = await QRCode.toBuffer(tryLink, { width: 480, margin: 2, errorCorrectionLevel: 'M' });
  const hi = ownerName ? `Hi ${String(ownerName).trim()},` : 'Hi there,';
  const subject = `${store} on FavCircles: here's your store's card`;

  const list = (rows) => rows.map(([b, rest]) => `<li style="margin:0 0 6px"><b>${esc(b)}:</b> ${esc(rest)}</li>`).join('');
  const p = 'margin:0 0 16px';
  const html = `<div style="font-family:-apple-system,Helvetica,Arial,sans-serif;font-size:16px;line-height:1.5;color:#1a1a1a;max-width:560px">
<p style="${p}">${esc(hi)}</p>
<p style="${p}">Thanks for taking a few minutes with me at ${esc(store)}. As promised, here is what your customers see when they scan your FavCircles code or tap your NFC sticker:</p>
<p style="${p}"><a href="${cardUrl}"><img src="cid:storecard" width="440" alt="${esc(store)}'s FavCircles card" style="display:block;width:100%;max-width:440px;height:auto;border:0;border-radius:18px"></a></p>
<p style="${p}">It's your own store card, with your photo and your name, not a generic app download. One tap on Open saves ${esc(store)} to their favorites, and they can share it with friends right away. There's nothing to download first.</p>
<p style="margin:0 0 8px">Want to try it yourself? Scan this with your iPhone camera:</p>
<p style="margin:0 0 8px"><img src="cid:storeqr" width="160" height="160" alt="QR code for ${esc(store)}'s FavCircles card" style="display:block;width:160px;height:160px;border:0"></p>
<p style="${p}">Or open this link on an iPhone: <a href="${tryLink}">${esc(tryLink.replace(/^https:\/\//, ''))}</a></p>
<p style="margin:0 0 6px"><b>FREE FOR EVERY STORE</b></p>
<ul style="margin:0 0 16px;padding-left:20px">${list(FREE)}</ul>
<p style="margin:0 0 6px"><b>FavCircles BUSINESS</b> (free for 3 months, then $49.99 a month)</p>
<ul style="margin:0 0 16px;padding-left:20px">${list(BUSINESS)}</ul>
<p style="${p}">There's no hardware and nothing to install at the register. You can see more at <a href="${OWNERS_PAGE}">favcircles.com/store-owners</a>.</p>
<p style="${p}"><b>Could I come by for about 20 minutes to show you a live demo on your own store page?</b> Just let me know a day and time that works.</p>
<p style="${p}">Thank you!<br>Wes</p>
<p style="margin:24px 0 0;font-size:14px;color:#555">--<br>${esc(SIGNATURE.name)}<br>${esc(SIGNATURE.title)}<br>${esc(SIGNATURE.phone)}<br>${esc(SIGNATURE.office)}<br><a href="mailto:${SIGNATURE.email}">${esc(SIGNATURE.email)}</a></p>
</div>`;

  const bullets = (rows) => rows.map(([b, rest]) => `- ${b}: ${rest}`).join('\n');
  const text = `${hi}

Thanks for taking a few minutes with me at ${store}. As promised, here is what your customers see when they scan your FavCircles code or tap your NFC sticker:
${cardUrl}

It's your own store card, with your photo and your name, not a generic app download. One tap on Open saves ${store} to their favorites, and they can share it with friends right away. There's nothing to download first.

Want to try it yourself? Scan the QR code in this email with your iPhone camera, or open this link on an iPhone: ${tryLink}

FREE FOR EVERY STORE
${bullets(FREE)}

FavCircles BUSINESS (free for 3 months, then $49.99 a month)
${bullets(BUSINESS)}

There's no hardware and nothing to install at the register. You can see more at ${OWNERS_PAGE}

Could I come by for about 20 minutes to show you a live demo on your own store page? Just let me know a day and time that works.

Thank you!
Wes

--
${SIGNATURE.name}
${SIGNATURE.title}
${SIGNATURE.phone}
${SIGNATURE.office}
${SIGNATURE.email}`;

  return {
    subject, html, text, cardUrl, tryLink,
    attachments: [
      { filename: cardSlug(venue), content: jpeg, contentType: 'image/jpeg', cid: 'storecard' },
      { filename: `${cardSlug(venue).replace(/\.jpg$/, '')}-qr.png`, content: qrPng, contentType: 'image/png', cid: 'storeqr' }
    ]
  };
}

module.exports = { buildStoreFollowup, cardSlug };
