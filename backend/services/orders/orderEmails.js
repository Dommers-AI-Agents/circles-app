// backend/services/orders/orderEmails.js — what a web guest hears by email.
// They have no app to push to (services/orders/webOrderService), so the
// order's steps (accepted, ready, declined, not answered) and the receipt
// at placement go to the email they gave, each carrying the status link.
const { escapeHtml } = require('../../utils/text');

const TEXT_STYLE = 'font-family:-apple-system,Helvetica,Arial,sans-serif;max-width:520px;color:#1A202C';
const BUTTON_STYLE = 'background:#3182CE;color:#fff;padding:12px 22px;border-radius:10px;text-decoration:none;font-weight:700;display:inline-block';

const linesHtml = (o) => o.lines.map((l) =>
  `<tr><td style="padding:4px 12px 4px 0">${l.qty}×</td><td style="padding:4px 12px 4px 0"><b>${escapeHtml(l.name)}</b>${l.note ? `<br><i>${escapeHtml(l.note)}</i>` : ''}</td><td style="padding:4px 0;text-align:right">${escapeHtml(l.price || '')}</td></tr>`
).join('');
const linesText = (o) => o.lines.map((l) => `${l.qty}x ${l.name}${l.note ? ` (${l.note})` : ''} ${l.price || ''}`.trim()).join('\n');
const estimateText = (o) => (o.estimate
  ? `About $${Number(o.estimate).toFixed(2)}${o.estimateIsPartial ? ' (plus items priced at the counter)' : ''}, paid at pickup.`
  : 'Paid at pickup.');

const wrap = (heading, intro, o, statusUrl, extra = '') => ({
  html: `<div style="${TEXT_STYLE}">
<h2 style="margin:0 0 6px">${escapeHtml(heading)}</h2>
<p style="margin:0 0 14px;color:#4A5568">${escapeHtml(intro)}</p>
<table style="border-collapse:collapse;font-size:15px">${linesHtml(o)}</table>
<p style="margin:14px 0">${escapeHtml(estimateText(o))}</p>
${extra}
<p style="margin:18px 0"><a href="${escapeHtml(statusUrl)}" style="${BUTTON_STYLE}">See your order</a></p>
<p style="margin:0;color:#718096;font-size:13px">Ordered through FavCircles · ${escapeHtml(o.venueName)}</p>
</div>`,
  text: `${heading}\n${intro}\n\n${linesText(o)}\n${estimateText(o)}\n\nSee your order: ${statusUrl}`
});

/** The receipt right after placing. */
function guestPlacedEmail(o, statusUrl) {
  const when = o.pickup && !o.pickup.asap && o.pickup.at ? 'at the time you picked' : 'as soon as it’s ready';
  const body = wrap(`Order sent to ${o.venueName}`, `We’ll email you when they accept it. Pickup ${when}; pay at the counter.`, o, statusUrl);
  return { subject: `Your order at ${o.venueName}`, ...body };
}

/**
 * One step: `notice` is the push copy orderService already wrote for the
 * step (title + body), reused so the two channels say the same thing.
 */
function guestStepEmail(o, action, notice, statusUrl) {
  const extra = action === 'decline' && o.declineReason
    ? `<p style="margin:0 0 14px"><b>From the store:</b> ${escapeHtml(o.declineReason)}</p>` : '';
  const body = wrap(notice.title, notice.body, o, statusUrl, extra);
  return { subject: notice.title, ...body };
}

async function send(to, mail) {
  const emailService = require('../emailService');
  return emailService.sendEmail({ to, subject: mail.subject, html: mail.html, text: mail.text });
}

async function sendGuestPlaced(orderId, o, statusUrl) {
  if (!o.customer || !o.customer.email) return null;
  return send(o.customer.email, guestPlacedEmail(o, statusUrl));
}

async function sendGuestStep(orderId, o, action, notice) {
  if (!o.customer || !o.customer.email || !notice) return null;
  const { statusUrl } = require('./webOrderService');
  return send(o.customer.email, guestStepEmail(o, action, notice, statusUrl(orderId)));
}

module.exports = { guestPlacedEmail, guestStepEmail, sendGuestPlaced, sendGuestStep };
