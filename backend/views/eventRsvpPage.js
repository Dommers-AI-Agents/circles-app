// backend/views/eventRsvpPage.js
//
// A guest's reply page (/rsvp/<token>), reached from their invite email.
// No account: the token in the link is theirs. Shows when/where/what, who's
// coming (first names only), and a form: Going / Maybe / Can't go, adults,
// kids, a note. The form POSTs; opening the page never records anything
// (mail scanners open links). `?r=yes` only preselects the choice.
const { escapeHtml: esc } = require('../utils/text');
const { whenLine, whereLine } = require('../services/eventDetails');

const ACCENT = '#7b2ff7';

const shell = (title, body) => `<!DOCTYPE html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>${esc(title)}</title>
<style>
  body{margin:0;font-family:-apple-system,Helvetica,Arial,sans-serif;background:#f4f2fb;color:#1b1e24}
  main{max-width:560px;margin:0 auto;padding:18px 14px 40px}
  .hero{background:linear-gradient(135deg,#ff3d81,${ACCENT});border-radius:18px;padding:26px 20px;text-align:center;color:#fff}
  .card{background:#fff;border-radius:16px;padding:18px;margin-top:14px}
  .choices{display:flex;gap:8px}
  .choices label{flex:1;text-align:center;border:2px solid #e6e1f5;border-radius:12px;padding:12px 4px;font-weight:700;cursor:pointer}
  .choices input{position:absolute;opacity:0}
  .choices input:checked + span{color:${ACCENT}}
  .choices label:has(input:checked){border-color:${ACCENT};background:#f6f3ff}
  .row{display:flex;gap:10px;margin-top:12px}
  .row label{flex:1;font-size:14px;color:#555}
  input[type=number],input[type=text],textarea{width:100%;box-sizing:border-box;margin-top:4px;padding:10px;border:1px solid #ddd;border-radius:10px;font-size:16px;font-family:inherit}
  button{width:100%;margin-top:16px;padding:15px;border:0;border-radius:12px;background:${ACCENT};color:#fff;font-size:17px;font-weight:800}
  a{color:${ACCENT}}
  .muted{color:#777;font-size:13px}
  .pill{display:inline-block;margin:3px;padding:5px 10px;border-radius:999px;background:#f1edfd;font-size:14px}
</style></head><body><main>${body}</main></body></html>`;

const facts = (page) => {
  const { event } = page;
  const when = whenLine(event);
  const where = whereLine(event);
  return `
  ${when ? `<p style="margin:0 0 8px;font-size:16px">📅 ${esc(when)}${page.calendarUrl ? ` · <a href="${esc(page.calendarUrl)}">Add to calendar</a>` : ''}${page.googleCalendarUrl ? ` · <a href="${esc(page.googleCalendarUrl)}">Google</a>` : ''}</p>` : ''}
  ${where ? `<p style="margin:0 0 8px;font-size:16px">📍 ${esc(where)}${page.mapsUrl ? ` · <a href="${esc(page.mapsUrl)}">Directions</a>` : ''}</p>` : ''}
  ${event.details ? `<p style="margin:10px 0 0;font-size:15px;color:#444;white-space:pre-wrap">${esc(event.details)}</p>` : ''}`;
};

const comingList = (page) => {
  const going = page.coming.filter((c) => c.rsvp === 'yes');
  const maybe = page.coming.filter((c) => c.rsvp === 'maybe');
  if (!going.length && !maybe.length) return '';
  const pills = (list) => list.slice(0, 40).map((c) => `<span class="pill">${esc(c.name)}</span>`).join('');
  return `<div class="card">
    ${going.length ? `<p style="margin:0 0 6px;font-weight:700">Going · ${page.counts.yes.people}</p>${pills(going)}` : ''}
    ${maybe.length ? `<p style="margin:12px 0 6px;font-weight:700">Maybe · ${page.counts.maybe.people}</p>${pills(maybe)}` : ''}
  </div>`;
};

const appCard = (page) => (page.appUrl
  ? `<div class="card" style="text-align:center"><p style="margin:0 0 8px">📸 Everyone there shares one photo album in FavCircles.</p><a href="${esc(page.appUrl)}" style="font-weight:800">Join the album</a></div>`
  : '');

/** The reply form. `preselect`: the choice from the email button (?r=). */
function renderRsvpPage(token, page, { preselect = null, saved = null, error = null } = {}) {
  const { event, guest } = page;
  const choice = preselect || (guest.rsvp !== 'pending' ? guest.rsvp : null);
  const radio = (value, label) => `<label><input type="radio" name="rsvp" value="${value}"${choice === value ? ' checked' : ''} required><span>${label}</span></label>`;
  const ended = !!event.endedAt;
  const thanks = saved
    ? `<div class="card" style="background:#eefaf1;border:1px solid #bfe8cb"><b>${saved.rsvp === 'yes' ? '🎉 You\'re going!' : saved.rsvp === 'maybe' ? '🤔 Got it: maybe.' : '😢 Sorry you can\'t make it.'}</b> ${esc(page.hostName)} will see your reply. You can change it here any time.</div>`
    : '';
  const form = ended
    ? '<div class="card"><b>This event has ended.</b></div>'
    : `<form class="card" method="post" action="/rsvp/${esc(token)}">
      <p style="margin:0 0 10px;font-weight:800;font-size:18px">Can you make it?</p>
      <div class="choices">${radio('yes', '🎉 Going')}${radio('maybe', '🤔 Maybe')}${radio('no', '😢 Can\'t go')}</div>
      <div class="row">
        <label>Adults<input type="number" name="adults" min="1" max="20" value="${Math.max(1, guest.adults || 1)}"></label>
        <label>Kids<input type="number" name="kids" min="0" max="20" value="${guest.kids || 0}"></label>
      </div>
      <label style="display:block;margin-top:12px;font-size:14px;color:#555">Your name<input type="text" name="name" maxlength="60" value="${esc(guest.name)}"></label>
      <label style="display:block;margin-top:12px;font-size:14px;color:#555">A note for ${esc(page.hostName)} (optional)<textarea name="note" rows="3" maxlength="300">${esc(guest.note)}</textarea></label>
      ${error ? `<p style="color:#c0392b;margin:10px 0 0">${esc(error)}</p>` : ''}
      <button type="submit">Send my reply</button>
    </form>`;
  const body = `
  <div class="hero">
    <div style="font-size:60px;line-height:1">${esc(event.emoji || '🎉')}</div>
    <h1 style="margin:10px 0 4px;font-size:28px">${esc(event.name)}</h1>
    <p style="margin:0;opacity:.92">Hosted by ${esc(page.hostName)}</p>
  </div>
  ${thanks}
  <div class="card">${facts(page) || '<p style="margin:0">Details coming soon.</p>'}</div>
  ${form}
  ${comingList(page)}
  ${appCard(page)}
  <p class="muted" style="text-align:center;margin-top:18px">${guest.optedOut ? 'You won\'t get more emails about this event.' : `<a href="/rsvp/${esc(token)}/stop" style="color:#777">Stop emails about ${esc(event.name)}</a>`} · Sent with <a href="https://favcircles.com" style="color:#777">FavCircles</a></p>`;
  return shell(`${event.emoji || '🎉'} ${event.name}`, body);
}

function renderRsvpNotFound() {
  return shell('Invite not found', '<div class="card" style="text-align:center"><h1>This invite isn\'t valid</h1><p>Ask whoever sent it for a new invite.</p></div>');
}

/** The stop-emails page: a confirm button (POST), or the done message. */
function renderStopPage(token, { name, done }) {
  if (done) {
    return shell('Unsubscribed', `<div class="card" style="text-align:center"><h1>Done</h1><p>You won't get more emails about ${esc(name)}.</p></div>`);
  }
  return shell('Stop emails', `<form class="card" method="post" action="/rsvp/${esc(token)}/stop" style="text-align:center">
    <h1 style="font-size:22px">Stop emails about ${esc(name)}?</h1>
    <p class="muted">You can still open your reply page from the invite.</p>
    <button type="submit">Stop these emails</button></form>`);
}

module.exports = { renderRsvpPage, renderRsvpNotFound, renderStopPage };
