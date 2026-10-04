// backend/views/eventPage.js
//
// The public page behind an event's invite link (api.favcircles.com/app/event/<token>,
// claimed by the AASA's /app/*). With FavCircles installed the link opens the
// app's join screen directly and this page is never seen; everyone else lands
// here: what the event is, who's running it, and the two steps to join.
// Member names and photos are never shown here — members only.
const { escapeHtml: esc } = require('../utils/text');

const APP_STORE_URL = 'https://apps.apple.com/us/app/favcircles/id6746807095';

function renderEventInvite(token, preview) {
  const t = esc(token);
  if (!preview) {
    return `<!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Invite not found</title></head>
<body style="font-family:-apple-system,Helvetica,Arial,sans-serif;text-align:center;padding:48px 24px;background:#120c2b;color:#fff"><h1>This invite isn't valid</h1><p>Ask whoever sent it for a fresh link.</p></body></html>`;
  }
  const name = esc(preview.name);
  const emoji = esc(preview.emoji || '🚌');
  const host = esc(preview.hostName || 'A friend');
  const count = preview.memberCount || 1;
  const title = `${preview.emoji || '🚌'} Join ${preview.name} on FavCircles`;
  return `<!DOCTYPE html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(title)}</title>
<meta property="og:title" content="${esc(title)}">
<meta property="og:description" content="${host} invited you. Share photos and places with everyone who's there.">
<meta property="og:site_name" content="FavCircles">
<meta property="og:type" content="website">
<meta property="og:url" content="https://api.favcircles.com/app/event/${t}">
<meta name="apple-itunes-app" content="app-id=6746807095, app-argument=https://api.favcircles.com/app/event/${t}">
<link rel="apple-touch-icon" href="https://favcircles.com/app-icon.png">
</head>
<body style="margin:0;font-family:-apple-system,Helvetica,Arial,sans-serif;background:linear-gradient(160deg,#ff3d81,#7b2ff7 55%,#120c2b);min-height:100vh;color:#fff">
<main style="max-width:520px;margin:0 auto;padding:40px 22px 48px;text-align:center">
  <div style="font-size:84px;line-height:1">${emoji}</div>
  <h1 style="font-size:34px;margin:14px 0 6px">${name}</h1>
  <p style="margin:0 0 4px;font-size:17px;opacity:.92">${host} invited you</p>
  <p style="margin:0 0 26px;font-size:15px;opacity:.75">${count} ${count === 1 ? 'person is' : 'people are'} in${preview.joinOpen ? '' : ' · joining is closed'}</p>
  <section style="background:rgba(255,255,255,.12);border-radius:18px;padding:20px;text-align:left;font-size:16px;line-height:1.5">
    <p style="margin:0 0 10px"><b>1.</b> Get the FavCircles app (free).</p>
    <p style="margin:0 0 10px"><b>2.</b> Come back to this message and tap the link again. You'll join ${name} and get a FavCoin 🌵.</p>
    <p style="margin:0">Share photos with everyone who's there, save the places you go, and download the whole night's pictures.</p>
  </section>
  <p style="margin:24px 0 10px"><a href="${APP_STORE_URL}" style="background:#fff;color:#7b2ff7;padding:15px 30px;border-radius:12px;text-decoration:none;font-weight:800;display:inline-block">Get FavCircles</a></p>
  <p style="margin:0"><a href="circles://event/${t}" style="color:#fff;opacity:.9;font-weight:600">Already have it? Open the invite</a></p>
</main>
</body></html>`;
}

module.exports = { renderEventInvite };
