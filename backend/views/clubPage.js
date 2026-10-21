// backend/views/clubPage.js
//
// The public page behind a club's invite link (api.favcircles.com/app/club/<token>,
// claimed by the AASA's /app/*). With FavCircles installed the link opens the
// Clubs widget's join screen and this page is never seen; everyone else lands
// here: what the club is, when it meets, and how to join. Member names never
// appear here — members only.
const { escapeHtml: esc } = require('../utils/text');

const APP_STORE_URL = 'https://apps.apple.com/us/app/favcircles/id6746807095';

function renderClubInvite(token, preview) {
  const t = esc(token);
  if (!preview) {
    return `<!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Invite not found</title></head>
<body style="font-family:-apple-system,Helvetica,Arial,sans-serif;text-align:center;padding:48px 24px;background:#0E2A47;color:#fff"><h1>This club link isn't valid</h1><p>Ask whoever sent it for a fresh link.</p></body></html>`;
  }
  const emoji = preview.emoji || '🤝';
  const title = `${emoji} ${preview.name}`;
  const count = preview.memberCount || 1;
  const facts = [preview.scheduleLine, `${count} member${count === 1 ? '' : 's'}`].filter(Boolean).join(' · ');
  const where = preview.homeSpotName ? `Usually meets at ${preview.homeSpotName}` : '';
  return `<!DOCTYPE html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(title)}</title>
<meta property="og:title" content="${esc(title)}">
<meta property="og:description" content="${esc(`${facts} · Join on FavCircles`)}">
<meta property="og:site_name" content="FavCircles">
<meta property="og:type" content="website">
<meta property="og:url" content="https://api.favcircles.com/app/club/${t}">
<meta name="apple-itunes-app" content="app-id=6746807095, app-argument=https://api.favcircles.com/app/club/${t}">
<link rel="apple-touch-icon" href="https://favcircles.com/app-icon.png">
</head>
<body style="margin:0;font-family:-apple-system,Helvetica,Arial,sans-serif;background:linear-gradient(160deg,#2F6FED,#0E2A47 70%);min-height:100vh;color:#fff">
<main style="max-width:520px;margin:0 auto;padding:40px 22px 48px;text-align:center">
  <div style="font-size:84px;line-height:1">${esc(emoji)}</div>
  <h1 style="font-size:34px;margin:14px 0 6px">${esc(preview.name)}</h1>
  <p style="margin:0 0 4px;font-size:17px;opacity:.92">${esc(preview.ownerName || 'A friend')} runs this club</p>
  <p style="margin:0 0 ${where ? '4px' : '26px'};font-size:15px;opacity:.8">${esc(facts)}${preview.joinOpen ? '' : ' · not taking new members'}</p>
  ${where ? `<p style="margin:0 0 26px;font-size:15px;opacity:.8">${esc(where)}</p>` : ''}
  ${preview.description ? `<p style="margin:0 0 22px;font-size:16px;line-height:1.5;opacity:.95">${esc(preview.description)}</p>` : ''}
  <section style="background:rgba(255,255,255,.12);border-radius:18px;padding:20px;text-align:left;font-size:16px;line-height:1.5">
    <p style="margin:0 0 10px"><b>1.</b> Get the FavCircles app (free).</p>
    <p style="margin:0 0 10px"><b>2.</b> Come back to this message and tap the link again to join ${esc(preview.name)}.</p>
    <p style="margin:0">See the weekly meetups and say you're going, get the organizers' updates, and chat on the club board.</p>
  </section>
  <p style="margin:24px 0 10px"><a href="${APP_STORE_URL}" style="background:#fff;color:#0E2A47;padding:15px 30px;border-radius:12px;text-decoration:none;font-weight:800;display:inline-block">Get FavCircles</a></p>
  <p style="margin:0"><a href="circles://club/${t}" style="color:#fff;opacity:.9;font-weight:600">Already have it? Open the invite</a></p>
</main>
</body></html>`;
}

module.exports = { renderClubInvite };
