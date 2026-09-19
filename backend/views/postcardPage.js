// backend/views/postcardPage.js
//
// The public postcard page (favcircles.com/postcard/<token>): the card, the
// note, and the pitch underneath. Was inline HTML in server.js.
const { escapeHtml: esc } = require('../utils/text');

const APP_STORE_URL = 'https://apps.apple.com/us/app/favcircles/id6746807095';

function renderNotFound() {
  return `<!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>Postcard not found</title></head>
<body style="font-family:-apple-system,Helvetica,Arial,sans-serif;text-align:center;padding:48px 24px;color:#1a202c"><h1>This postcard isn't here</h1><p>The link may be incomplete.</p>
<p><a href="https://favcircles.com" style="color:#3182CE">Create your own digital postcards with FavCircles</a></p></body></html>`;
}

function renderPostcard(share) {
  const appStoreUrl = APP_STORE_URL;
  // Raw text here; every insertion below escapes once. (The inline version
  // escaped the place name twice, so "Watson's" showed as Watson&#39;s.)
  const fromRaw = share.senderName || 'A FavCircles member';
  const whereRaw = share.placeName ? share.placeName + (share.placeCity ? `, ${share.placeCity}` : '') : null;
  const title = whereRaw ? `A postcard from ${whereRaw}` : `A postcard from ${fromRaw}`;
  const from = esc(fromRaw);
  const where = whereRaw ? esc(whereRaw) : null;
  const sent = share.createdAt ? new Date(share.createdAt).toLocaleDateString('en-US', { month: 'long', day: 'numeric', year: 'numeric' }) : '';
  return `<!DOCTYPE html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(title)}</title>
<meta property="og:title" content="${esc(title)}">
<meta property="og:description" content="${share.message ? esc(share.message.slice(0, 160)) : `${from} sent you a digital postcard on FavCircles.`}">
<meta property="og:site_name" content="FavCircles">
<meta property="og:type" content="website">
<meta property="og:image" content="${esc(share.imageUrl)}">
<meta property="og:url" content="https://favcircles.com/postcard/${esc(share.token)}">
<meta name="twitter:card" content="summary_large_image">
<style>
  #lightbox{position:fixed;inset:0;background:rgba(0,0,0,.94);display:none;flex-direction:column;align-items:center;justify-content:center;z-index:10;padding:16px}
  #lightbox.open{display:flex}
  #lightbox img{max-width:100%;max-height:78vh;border-radius:10px;box-shadow:0 12px 40px rgba(0,0,0,.6)}
  .lb-actions{display:flex;gap:12px;margin-top:18px;flex-wrap:wrap;justify-content:center}
  .lb-btn{background:#4FD1C5;color:#0f1b2d;padding:12px 22px;border-radius:10px;text-decoration:none;font-weight:700;border:0;font-size:15px;cursor:pointer}
  .lb-btn.ghost{background:rgba(255,255,255,.12);color:#fff}
  .lb-hint{margin-top:12px;font-size:13px;opacity:.7;text-align:center}
</style>
</head>
<body style="margin:0;background:#0f1b2d;color:#fff;font-family:-apple-system,Helvetica,Arial,sans-serif">
<main style="max-width:640px;margin:0 auto;padding:32px 20px 48px;text-align:center">
  <p style="margin:0 0 12px;opacity:.7;font-size:14px;letter-spacing:.04em;text-transform:uppercase">${where ? `Greetings from ${where}` : 'A digital postcard'}</p>
  <img id="card" src="/postcard/${esc(share.token)}/image" alt="${esc(title)}" style="width:100%;max-width:600px;border-radius:14px;box-shadow:0 12px 40px rgba(0,0,0,.45);display:block;margin:0 auto;cursor:zoom-in">
  <p style="margin:10px 0 0;font-size:13px;opacity:.6">Tap the postcard to view it full size or save it</p>
  ${share.message ? `<p style="font-size:20px;line-height:1.5;margin:28px 0 8px;white-space:pre-wrap">${esc(share.message)}</p>` : ''}
  <p style="margin:8px 0 0;opacity:.75">— ${from}${sent ? ` · ${esc(sent)}` : ''}</p>
  <section style="margin-top:44px;padding:24px;border-radius:14px;background:rgba(255,255,255,.06)">
    <p style="margin:0 0 6px;font-size:22px;font-weight:700">Create your own digital postcards with FavCircles.</p>
    <p style="margin:0 0 18px;opacity:.8">Snap a photo from wherever you are, pick a card, and send it to friends — plus the places you love, all in one app.</p>
    <a href="${appStoreUrl}" style="background:#4FD1C5;color:#0f1b2d;padding:14px 30px;border-radius:10px;text-decoration:none;font-weight:700;display:inline-block">Get it here</a>
    <p style="margin:16px 0 0;font-size:13px;opacity:.6"><a href="https://favcircles.com" style="color:#fff">favcircles.com</a></p>
  </section>
</main>
<div id="lightbox" role="dialog" aria-label="Postcard">
  <img src="/postcard/${esc(share.token)}/image" alt="${esc(title)}">
  <div class="lb-actions">
    <a class="lb-btn" href="/postcard/${esc(share.token)}/download" download="postcard.jpg">Save postcard</a>
    <button class="lb-btn ghost" type="button" id="lb-close">Close</button>
  </div>
  <p class="lb-hint" id="lb-hint">On iPhone: press and hold the postcard, then choose “Save to Photos”.</p>
</div>
<script>
  (function () {
    var lb = document.getElementById('lightbox');
    var open = function () { lb.classList.add('open'); document.body.style.overflow = 'hidden'; };
    var close = function () { lb.classList.remove('open'); document.body.style.overflow = ''; };
    document.getElementById('card').addEventListener('click', open);
    document.getElementById('lb-close').addEventListener('click', close);
    lb.addEventListener('click', function (e) { if (e.target === lb) close(); });
    document.addEventListener('keydown', function (e) { if (e.key === 'Escape') close(); });
    if (!/iPhone|iPad/.test(navigator.userAgent)) document.getElementById('lb-hint').textContent = 'Save downloads the full-size postcard.';
  })();
</script>
</body></html>`;
}

module.exports = { renderNotFound, renderPostcard, APP_STORE_URL };
