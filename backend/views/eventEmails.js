// backend/views/eventEmails.js
//
// The emails an event's guests get (services/eventGuestService): the
// invite, "the details changed", a message from the coordinator, and the
// day-before reminder. Every one carries the guest's own Going / Maybe /
// Can't go buttons. They open the reply page with that choice picked; the
// reply is only recorded when the guest presses Send there, because mail
// scanners open links on their own. Plain text twin for every message.
const { escapeHtml: esc } = require('../utils/text');
const { whenLine, whereLine } = require('../services/eventDetails');

const ACCENT = '#7b2ff7';
const PINK = '#ff3d81';

const button = (href, label, bg, fg = '#fff') =>
  `<a href="${esc(href)}" style="display:inline-block;margin:4px;padding:12px 18px;border-radius:10px;background:${bg};color:${fg};font-weight:700;text-decoration:none;font-size:15px">${esc(label)}</a>`;

const subjectFor = (kind, { event, hostName }) => {
  const title = `${event.emoji || '🎉'} ${event.name}`;
  if (kind === 'invite') return `${hostName} invited you to ${title}`;
  if (kind === 'update') return `Update: ${title}`;
  if (kind === 'message') return `${hostName}: a message about ${title}`;
  return `Tomorrow: ${title}`;
};

const leadFor = (kind, { hostName, guest }) => {
  const hi = guest.name ? `Hi ${guest.name.split(/\s+/)[0]}, ` : '';
  if (kind === 'invite') return `${hi}${hostName} invited you. Can you make it?`;
  if (kind === 'update') return `${hi}${hostName} changed the details. Here's the latest.`;
  if (kind === 'message') return `${hostName} sent a message to the guests:`;
  return `${hi}it's tomorrow. See you there!`;
};

const replyPrompt = (rsvp) => {
  if (rsvp === 'yes') return 'You said you\'re going. Changed your mind?';
  if (rsvp === 'maybe') return 'You said maybe. Know yet?';
  if (rsvp === 'no') return 'You said you can\'t make it. Can you now?';
  return 'Will you be there?';
};

/**
 * { subject, html, text } for one guest. `links`: yes/maybe/no/page/stop/
 * calendar/app/maps URLs (app and maps may be null).
 */
function renderEventEmail(kind, { event, guest, hostName, message = '', links }) {
  const subject = subjectFor(kind, { event, hostName });
  const when = whenLine(event);
  const where = whereLine(event);
  const lead = leadFor(kind, { hostName, guest });
  const rsvp = guest.rsvp || 'pending';

  const facts = [
    when ? `<tr><td style="padding:4px 10px 4px 0;font-size:20px;vertical-align:top">📅</td><td style="padding:4px 0;font-size:16px;color:#1b1e24">${esc(when)}${links.calendar ? `<br><a href="${esc(links.calendar)}" style="color:${ACCENT};font-size:14px;font-weight:600">Add to calendar</a>` : ''}</td></tr>` : '',
    where ? `<tr><td style="padding:4px 10px 4px 0;font-size:20px;vertical-align:top">📍</td><td style="padding:4px 0;font-size:16px;color:#1b1e24">${esc(where)}${links.maps ? `<br><a href="${esc(links.maps)}" style="color:${ACCENT};font-size:14px;font-weight:600">Directions</a>` : ''}</td></tr>` : ''
  ].join('');

  const html = `<!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"></head>
<body style="margin:0;background:#f4f2fb;font-family:-apple-system,Helvetica,Arial,sans-serif">
<div style="max-width:560px;margin:0 auto;padding:20px 12px">
  <div style="background:linear-gradient(135deg,${PINK},${ACCENT});border-radius:18px 18px 0 0;padding:28px 22px;text-align:center;color:#fff">
    <div style="font-size:56px;line-height:1">${esc(event.emoji || '🎉')}</div>
    <h1 style="margin:12px 0 4px;font-size:28px">${esc(event.name)}</h1>
    <p style="margin:0;font-size:15px;opacity:.92">Hosted by ${esc(hostName)}</p>
  </div>
  <div style="background:#fff;border-radius:0 0 18px 18px;padding:22px">
    <p style="margin:0 0 14px;font-size:16px;color:#1b1e24">${esc(lead)}</p>
    ${message ? `<blockquote style="margin:0 0 16px;padding:12px 14px;background:#f6f3ff;border-left:4px solid ${ACCENT};border-radius:8px;font-size:15px;color:#1b1e24;white-space:pre-wrap">${esc(message)}</blockquote>` : ''}
    ${facts ? `<table role="presentation" style="border-collapse:collapse;margin:0 0 14px">${facts}</table>` : ''}
    ${event.details ? `<p style="margin:0 0 16px;font-size:15px;color:#444;white-space:pre-wrap">${esc(event.details)}</p>` : ''}
    <p style="margin:18px 0 6px;font-size:15px;font-weight:700;color:#1b1e24;text-align:center">${esc(replyPrompt(rsvp))}</p>
    <div style="text-align:center">
      ${button(links.yes, '🎉 Going', ACCENT)}${button(links.maybe, '🤔 Maybe', '#eee8ff', ACCENT)}${button(links.no, '😢 Can\'t go', '#f1f1f4', '#555')}
    </div>
    ${links.app ? `<div style="margin-top:22px;padding:14px;border-radius:12px;background:#faf8ff;font-size:14px;color:#444;text-align:center">📸 Everyone there shares one photo album in FavCircles.<br><a href="${esc(links.app)}" style="color:${ACCENT};font-weight:700">Join the album</a></div>` : ''}
  </div>
  <p style="margin:16px 8px 0;font-size:12px;color:#888;text-align:center;line-height:1.5">
    ${esc(hostName)} invited ${esc(guest.email)} with FavCircles.<br>
    <a href="${esc(links.stop)}" style="color:#888">Stop emails about ${esc(event.name)}</a> · <a href="${esc(links.page)}" style="color:#888">Your reply page</a>
  </p>
</div></body></html>`;

  const text = [
    `${event.emoji || '🎉'} ${event.name}`,
    `Hosted by ${hostName}`,
    '',
    lead,
    message ? `\n"${message}"\n` : '',
    when ? `When: ${when}` : '',
    where ? `Where: ${where}` : '',
    event.details ? `\n${event.details}\n` : '',
    replyPrompt(rsvp),
    `Going: ${links.yes}`,
    `Maybe: ${links.maybe}`,
    `Can't go: ${links.no}`,
    links.calendar ? `\nAdd to calendar: ${links.calendar}` : '',
    links.app ? `Join the photo album in FavCircles: ${links.app}` : '',
    '',
    `Stop emails about ${event.name}: ${links.stop}`
  ].filter((line) => line !== '').join('\n');

  return { subject, html, text };
}

module.exports = { renderEventEmail, subjectFor };
