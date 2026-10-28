// backend/views/orderPage.js — the public ordering page behind
// order.favcircles.com/<slug> (services/orders/webOrderService). Server
// renders the store and its menu so the page reads without JavaScript;
// public/order-page.js adds the cart and checkout. CSP allows no inline
// code, so the menu rides in a JSON data block and the script is a file.
const { escapeHtml: esc } = require('../utils/text');

const APP_STORE_URL = 'https://apps.apple.com/us/app/favcircles/id6746807095';
const API_BASE = 'https://api.favcircles.com';

// JSON inside <script type="application/json">: no '<' at all, so nothing in
// a menu item's name can end the block or start a tag
const jsonBlock = (data) => JSON.stringify(data).replace(/</g, '\\u003c');

const STYLE = `
:root{--brand:#3182CE;--ink:#1A202C;--muted:#4A5568;--line:#E2E8F0;--bg:#F7FAFC;--card:#fff;--danger:#C53030}
*{box-sizing:border-box}html{-webkit-text-size-adjust:100%}
body{margin:0;overflow-x:hidden;font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text",Helvetica,Arial,sans-serif;background:var(--bg);color:var(--ink);font-size:16px;line-height:1.45}
a{color:var(--brand)}button{font:inherit}
.wrap{max-width:720px;margin:0 auto;padding:0 16px 120px}
.cover{height:180px;background:var(--brand) center/cover no-repeat}
.head{padding:18px 0 10px}.head h1{margin:0 0 4px;font-size:28px;line-height:1.15}
.meta{margin:0;color:var(--muted);font-size:15px}.meta a{color:var(--muted)}
.lead{margin:10px 0 0;font-size:15px}.lead b{color:var(--brand)}
.hours{margin:10px 0 0}.hours summary{cursor:pointer;color:var(--muted);font-size:15px;list-style:none}.hours summary::-webkit-details-marker{display:none}
.hours table{border-collapse:collapse;margin-top:8px;font-size:15px}.hours td{padding:2px 14px 2px 0}.hours tr.today td{font-weight:700}
.banner{background:#EBF8FF;border:1px solid #BEE3F8;border-radius:12px;padding:12px 14px;margin:14px 0;font-size:15px;overflow-wrap:anywhere}
.chips{position:sticky;top:0;z-index:5;background:var(--bg);display:flex;gap:8px;overflow-x:auto;padding:10px 0;margin:6px -16px 0;padding-left:16px;padding-right:16px;scrollbar-width:none}.chips::-webkit-scrollbar{display:none}
.chip{flex:0 0 auto;border:1px solid var(--line);background:var(--card);border-radius:999px;padding:8px 14px;font-size:14px;font-weight:600;color:var(--muted);text-decoration:none;white-space:nowrap}.chip.on{background:var(--brand);border-color:var(--brand);color:#fff}
section.menu{margin-top:18px;scroll-margin-top:64px}section.menu h2{font-size:20px;margin:0 0 8px}
.item{display:flex;width:100%;max-width:100%;text-align:left;gap:12px;align-items:flex-start;background:var(--card);border:1px solid var(--line);border-radius:14px;padding:14px;margin-bottom:10px;color:inherit;cursor:pointer;min-height:44px}
.item:disabled{cursor:default}.item .t{display:flex;flex-direction:column;flex:1 1 auto;min-width:0}.item .n{display:block;font-weight:600;font-size:16px;overflow-wrap:anywhere}.item .d{display:block;color:var(--muted);font-size:14px;margin-top:2px;overflow-wrap:anywhere}.item .p{flex:0 0 auto;font-weight:600;white-space:nowrap}
.item .q{display:none;background:var(--brand);color:#fff;border-radius:999px;font-size:13px;font-weight:700;padding:2px 9px;margin-left:6px}.item.inCart .q{display:inline-block}
.tags{display:block;color:var(--muted);font-size:12px;margin-top:4px}
.bar{position:fixed;left:0;right:0;bottom:0;padding:12px 16px calc(12px + env(safe-area-inset-bottom));background:linear-gradient(transparent,var(--bg) 30%)}
.bar button{width:100%;max-width:688px;margin:0 auto;display:flex;justify-content:space-between;align-items:center;background:var(--brand);color:#fff;border:0;border-radius:14px;padding:16px 18px;font-size:17px;font-weight:700;box-shadow:0 10px 30px rgba(49,130,206,.35);cursor:pointer}
.bar[hidden]{display:none}
.dialog{position:fixed;inset:0;z-index:20;background:rgba(26,32,44,.5);display:flex;align-items:flex-end;justify-content:center}.dialog[hidden]{display:none}
.sheet{background:var(--card);width:100%;max-width:720px;border-radius:18px 18px 0 0;padding:18px 16px calc(18px + env(safe-area-inset-bottom));max-height:92vh;overflow:auto}
.sheet h3{margin:0 0 4px;font-size:20px}.sheet .d{color:var(--muted);font-size:15px}
.row{display:flex;justify-content:space-between;align-items:center;gap:12px;padding:12px 0;border-bottom:1px solid var(--line)}
.stepper{display:flex;align-items:center;gap:6px}.stepper button{width:40px;height:40px;border-radius:999px;border:1px solid var(--line);background:var(--card);font-size:20px;cursor:pointer}.stepper output{min-width:28px;text-align:center;font-weight:700}
.field{display:block;margin:12px 0}.field span{display:block;font-size:13px;font-weight:600;color:var(--muted);margin-bottom:4px}
input,textarea,select{width:100%;border:1px solid var(--line);border-radius:10px;padding:11px 12px;font-size:16px;background:var(--card);color:var(--ink)}textarea{min-height:64px;resize:vertical}
.primary{width:100%;background:var(--brand);color:#fff;border:0;border-radius:12px;padding:15px;font-size:17px;font-weight:700;cursor:pointer;margin-top:12px}.primary:disabled{opacity:.6;cursor:default}
.ghost{background:none;border:0;color:var(--brand);font-weight:600;font-size:15px;padding:10px 0;cursor:pointer}.danger{color:var(--danger)}
.total{display:flex;justify-content:space-between;font-weight:700;font-size:17px;padding:12px 0}
.err{color:var(--danger);font-size:14px;margin:8px 0 0}.err:empty{display:none}
.hp{position:absolute;left:-9999px;top:-9999px;height:0;overflow:hidden}
.status{background:var(--card);border:1px solid var(--line);border-radius:16px;padding:18px;margin-top:18px}
.status .big{font-size:22px;font-weight:800;margin:0 0 6px}.status .sub{color:var(--muted);margin:0}
.status ul{list-style:none;padding:0;margin:14px 0 0}.status li{display:flex;justify-content:space-between;padding:6px 0;border-top:1px solid var(--line)}
footer{margin-top:40px;text-align:center;color:var(--muted);font-size:14px}footer a.get{display:inline-block;margin-top:8px;background:var(--brand);color:#fff;padding:10px 18px;border-radius:10px;text-decoration:none;font-weight:700}
@media (prefers-color-scheme:dark){:root{--ink:#F7FAFC;--muted:#A0AEC0;--line:#2D3748;--bg:#111827;--card:#1A202C}.banner{background:#1A365D;border-color:#2C5282}.chips{background:var(--bg)}}
`;

const head = ({ title, description, url, image, noindex, extraMeta = '' }) => `<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>${esc(title)}</title>
<meta name="description" content="${esc(description)}">
${noindex ? '<meta name="robots" content="noindex">' : ''}
<link rel="canonical" href="${esc(url)}">
<meta property="og:title" content="${esc(title)}"><meta property="og:description" content="${esc(description)}">
<meta property="og:type" content="website"><meta property="og:url" content="${esc(url)}"><meta property="og:site_name" content="FavCircles">
${image ? `<meta property="og:image" content="${esc(image)}">` : ''}
<meta name="theme-color" content="#3182CE">
<link rel="apple-touch-icon" href="https://favcircles.com/app-icon.png">
${extraMeta}
<style>${STYLE}</style>
</head>`;

const footer = (p) => `<footer>Powered by <b>FavCircles</b> · save ${esc(p.name)} to your map and earn rewards there<br>
<a class="get" href="${p.globalPlaceId ? `${API_BASE}/place/${esc(p.globalPlaceId)}` : APP_STORE_URL}">Get the app</a></footer>`;

const hoursHtml = (hours) => {
  if (!hours) return '';
  const today = new Date().getDay();
  return `<details class="hours"><summary>Hours ▾</summary><table>${hours.map((h) =>
    `<tr${h.day === today ? ' class="today"' : ''}><td>${esc(h.label)}</td><td>${esc(h.text)}</td></tr>`).join('')}</table></details>`;
};

// Menu prices are free text ("9", "4.50", "$12", "MP"): a bare number gets a
// dollar sign on the page; anything else prints as the owner typed it
const priceText = (price) => (/^\s*\d+(?:\.\d{1,2})?\s*$/.test(String(price || '')) ? `$${String(price).trim()}` : (price || ''));

const itemHtml = (item, canOrder) => `<button class="item" type="button" data-item-id="${esc(item.id)}"${canOrder ? '' : ' disabled'}>
<span class="t"><span class="n">${esc(item.name)}<span class="q" data-qty></span></span>${item.description ? `<span class="d">${esc(item.description)}</span>` : ''}${item.tags && item.tags.length ? `<span class="tags">${esc(item.tags.join(' · '))}</span>` : ''}</span>
<span class="p">${esc(priceText(item.price))}</span></button>`;

/**
 * The store page. `base` is '' on the ordering host and '/order' on the
 * API host, so links work on both.
 */
function renderOrderPage(p, { base = '', canonicalUrl, noindex = false } = {}) {
  const canOrder = !!(p.ordering && p.ordering.enabled);
  const title = canOrder ? `Order from ${p.name}` : `${p.name} · ${p.offeringsLabel}`;
  const description = canOrder
    ? `Order ahead from ${p.name} and pay at pickup.${p.address ? ` ${p.address}.` : ''}`
    : `${p.name}'s ${p.offeringsLabel.toLowerCase()}, hours and address.`;
  const mapsHref = p.address ? `https://maps.apple.com/?q=${encodeURIComponent(p.address)}` : null;
  const sections = p.menu.sections;
  return `${head({ title, description, url: canonicalUrl, image: p.coverPhotoUrl, noindex })}
<body>
${p.coverPhotoUrl ? `<div class="cover" style="background-image:url('${esc(p.coverPhotoUrl)}')" role="img" aria-label="${esc(p.name)}"></div>` : ''}
<div class="wrap">
<header class="head">
<h1>${esc(p.name)}</h1>
${p.address ? `<p class="meta"><a href="${esc(mapsHref)}" target="_blank" rel="noopener">${esc(p.address)}</a></p>` : ''}
${p.phone ? `<p class="meta"><a href="tel:${esc(p.phone.replace(/[^+\d]/g, ''))}">${esc(p.phone)}</a></p>` : ''}
${hoursHtml(p.hours)}
${canOrder ? `<p class="lead">Order ahead · <b>pay at pickup</b> · usually ready in ${p.ordering.leadMinutes} min${p.ordering.note ? `<br><span class="meta">${esc(p.ordering.note)}</span>` : ''}</p>`
  : `<div class="banner">Online ordering isn't on here right now. Save ${esc(p.name)} in the FavCircles app to keep it on your map${p.globalPlaceId ? ` — <a href="${API_BASE}/place/${esc(p.globalPlaceId)}">open it in the app</a>` : ''}.</div>`}
</header>
${sections.length > 1 ? `<nav class="chips" aria-label="${esc(p.offeringsLabel)} sections">${sections.map((s, i) => `<a class="chip${i === 0 ? ' on' : ''}" href="#s-${esc(s.id)}">${esc(s.name)}</a>`).join('')}</nav>` : ''}
<main id="menu">
${sections.map((s) => `<section class="menu" id="s-${esc(s.id)}"><h2>${esc(s.name)}</h2>${s.items.map((i) => itemHtml(i, canOrder)).join('')}</section>`).join('')}
</main>
${footer(p)}
</div>
${canOrder ? `
<div class="bar" id="bar" hidden><button type="button" id="viewOrder"><span>View order · <span id="barCount">0</span> items</span><span id="barTotal"></span></button></div>
<div class="dialog" id="itemDialog" hidden role="dialog" aria-modal="true" aria-labelledby="itemName"><div class="sheet">
<h3 id="itemName"></h3><p class="d" id="itemDesc"></p>
<div class="row"><span id="itemPrice"></span><div class="stepper"><button type="button" id="qtyMinus" aria-label="Fewer">−</button><output id="qty">1</output><button type="button" id="qtyPlus" aria-label="More">+</button></div></div>
<label class="field"><span>Anything to note? (optional)</span><input id="itemNote" maxlength="200" placeholder="No onions, extra sauce…"></label>
<button type="button" class="primary" id="itemAdd">Add to order</button>
<div style="text-align:center"><button type="button" class="ghost danger" id="itemRemove" hidden>Remove from order</button> <button type="button" class="ghost" id="itemClose">Close</button></div>
</div></div>
<div class="dialog" id="cartDialog" hidden role="dialog" aria-modal="true" aria-labelledby="cartTitle"><div class="sheet">
<h3 id="cartTitle">Your order</h3>
<div id="cartLines"></div>
<div class="total"><span>Estimate</span><span id="cartTotal"></span></div>
<p class="d">You pay at the counter when you pick up. Nothing is charged here.</p>
<form id="checkout" novalidate>
<label class="field"><span>Your name</span><input name="name" autocomplete="name" required maxlength="60"></label>
<label class="field"><span>Phone (the store may call about your order)</span><input name="phone" type="tel" autocomplete="tel" inputmode="tel" required></label>
<label class="field"><span>Email for updates (optional)</span><input name="email" type="email" autocomplete="email" maxlength="120"></label>
<label class="field"><span>Pickup</span><select name="pickup" id="pickup"><option value="asap">As soon as it's ready (about ${p.ordering.leadMinutes} min)</option></select></label>
<label class="field"><span>Note for the store (optional)</span><textarea name="note" maxlength="300"></textarea></label>
<div class="hp" aria-hidden="true"><label>Website<input name="website" tabindex="-1" autocomplete="off"></label></div>
<p class="err" id="checkoutError" role="alert"></p>
<button type="submit" class="primary" id="placeBtn">Place order</button>
<div style="text-align:center"><button type="button" class="ghost" id="cartClose">Keep browsing</button></div>
</form>
</div></div>
<script type="application/json" id="menu-data">${jsonBlock({ slug: p.slug, base, leadMinutes: p.ordering.leadMinutes, sections })}</script>
<script src="/public/order-page.js" defer></script>` : ''}
</body></html>`;
}

/** The status page shell; public/order-status.js fills it from the order's token. */
function renderOrderStatusPage({ base = '', orderId }) {
  return `${head({ title: 'Your order', description: 'Where your order stands.', url: `${base}/o/${esc(orderId)}`, noindex: true })}
<body><div class="wrap">
<header class="head"><h1 id="storeName">Your order</h1><p class="meta" id="storeMeta"></p></header>
<div class="status" id="status" aria-live="polite"><p class="big">Loading…</p></div>
<p style="text-align:center"><button type="button" class="ghost danger" id="cancelBtn" hidden>Cancel this order</button></p>
<p style="text-align:center"><a id="again" href="${esc(base)}/" hidden>Order again</a></p>
<p class="err" id="statusError" role="alert"></p>
<footer>Powered by <b>FavCircles</b> · <a class="get" href="${APP_STORE_URL}">Get the app</a></footer>
</div>
<script type="application/json" id="status-data">${jsonBlock({ base, orderId })}</script>
<script src="/public/order-status.js" defer></script>
</body></html>`;
}

function renderNotFound({ base = '' } = {}) {
  return `${head({ title: 'Not taking online orders yet', description: 'This store isn’t on FavCircles online ordering yet.', url: `${base}/`, noindex: true })}
<body><div class="wrap"><header class="head"><h1>Not taking online orders yet</h1>
<p class="meta">This store isn’t set up for FavCircles online ordering, or the address has changed.</p>
<p class="lead">Run a store? <a href="https://favcircles.com/store-owners.html">Online ordering is part of FavCircles Business</a>.</p></header>
<footer>Powered by <b>FavCircles</b> · <a class="get" href="${APP_STORE_URL}">Get the app</a></footer></div></body></html>`;
}

module.exports = { renderOrderPage, renderOrderStatusPage, renderNotFound, priceText };
