// backend/views/storePage.js — a store's QR on a phone with no app and no
// App Clip (Wes, 2026-11-26: "account for Android users ... a website to
// sign up for store notifications and rewards since we don't have an android
// app"). The same link the iPhone opens as an App Clip, /s/<code>, opens
// this page everywhere else: email + a 6-digit code, the store is saved,
// the same points are paid, the store's specials and events come by email,
// and the register code gives the visit's points and the counter ticket.
//
// Server-rendered so it reads at once; public/store-page.js does the
// sign-in and the scan against the same API the App Clip uses. CSP allows no
// inline code, so the store's data rides in a JSON block and the script is a
// file (same shape as views/orderPage.js). Preview on any device: ?web=1.
const { escapeHtml: esc } = require('../utils/text');

// JSON inside <script type="application/json">: no '<' at all
const jsonBlock = (data) => JSON.stringify(data).replace(/</g, '\\u003c');

// The store cards' look: charcoal, the store's own photo behind, serif
// headline, gold for what you get. Never a flat page: with no photo the
// backdrop is the brand wash.
const STYLE = `
:root{--ink:#1B1E24;--gold:#F6C945;--blue:#3478F6;--text:#fff;--soft:rgba(255,255,255,.78);--line:rgba(255,255,255,.2);--glass:rgba(255,255,255,.12)}
*{box-sizing:border-box}html{-webkit-text-size-adjust:100%}
body{margin:0;min-height:100vh;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;font-size:16px;line-height:1.45;color:var(--text);background:var(--ink)}
.back{position:fixed;inset:0;z-index:-2;background:linear-gradient(160deg,#274B8F 0%,#1B6E7A 48%,#1B1E24 100%) center/cover no-repeat}
.shade{position:fixed;inset:0;z-index:-1;background:linear-gradient(180deg,rgba(27,30,36,.35) 0%,rgba(27,30,36,.78) 45%,rgba(27,30,36,.94) 100%)}
.wrap{max-width:480px;margin:0 auto;padding:28px 20px calc(36px + env(safe-area-inset-bottom));min-height:100vh;display:flex;flex-direction:column;justify-content:flex-end}
.brand{font-size:13px;font-weight:700;letter-spacing:.08em;text-transform:uppercase;color:var(--soft);margin:0 0 auto;padding-bottom:40px}
h1{font-family:"New York",Georgia,"Times New Roman",serif;font-weight:700;font-size:34px;line-height:1.1;margin:0 0 6px}
h1 .g{color:var(--gold);display:block}
.store{font-size:18px;font-weight:700;margin:14px 0 2px}.addr{margin:0;color:var(--soft);font-size:14px}
.lead{margin:14px 0 0;font-size:16px;color:var(--soft)}
.coupon{margin:14px 0 0;padding:12px 14px;border:1px dashed var(--gold);border-radius:14px;font-weight:700}.coupon span{display:block;font-weight:400;font-size:14px;color:var(--soft)}
.panel{margin-top:20px;background:var(--glass);border:1px solid var(--line);border-radius:18px;padding:16px;-webkit-backdrop-filter:blur(14px);backdrop-filter:blur(14px)}
.panel[hidden]{display:none}
label.f{display:block;font-size:13px;font-weight:600;color:var(--soft);margin:0 0 6px}
input[type=email],input[type=text],input[type=tel]{width:100%;border:1px solid var(--line);border-radius:12px;padding:13px 14px;font-size:17px;background:rgba(255,255,255,.95);color:#1B1E24;margin-bottom:12px}
input.code{letter-spacing:.4em;text-align:center;font-size:24px;font-weight:700}
.check{display:flex;gap:10px;align-items:flex-start;font-size:14px;color:var(--soft);margin:2px 0 4px}.check input{width:20px;height:20px;flex:0 0 auto;margin:0}
button{font:inherit;cursor:pointer}
.primary{width:100%;min-height:50px;border:0;border-radius:14px;background:var(--gold);color:#1B1E24;font-size:17px;font-weight:800;margin-top:10px}
.primary:disabled{opacity:.6;cursor:default}
.ghost{background:none;border:0;color:var(--soft);font-size:14px;font-weight:600;padding:12px 0 0;text-decoration:underline}
.err{color:#FFB4A8;font-size:14px;margin:8px 0 0}.err:empty{display:none}
.fine{font-size:12px;color:var(--soft);margin:12px 0 0}.fine a{color:var(--soft)}
.big{font-family:"New York",Georgia,serif;font-size:28px;font-weight:700;line-height:1.15;margin:0}.big .g{color:var(--gold)}
.sub{margin:8px 0 0;color:var(--soft);font-size:15px}
.bal{display:flex;justify-content:space-between;align-items:baseline;margin-top:14px;padding-top:12px;border-top:1px solid var(--line);font-size:15px}.bal b{font-size:22px;color:var(--gold)}
ul.ladder{list-style:none;margin:10px 0 0;padding:0}ul.ladder li{display:flex;justify-content:space-between;align-items:center;gap:10px;padding:10px 0;border-top:1px solid var(--line);font-size:15px}
ul.ladder .c{color:var(--soft);font-size:13px;display:block}
ul.ladder button{flex:0 0 auto;border:0;border-radius:999px;background:var(--gold);color:#1B1E24;font-weight:800;font-size:14px;padding:9px 16px;min-height:38px}
.ticket{text-align:center}.ticket .code{font-size:46px;font-weight:800;letter-spacing:.18em;color:var(--gold);margin:6px 0 0}
.ticket .left{font-size:15px;color:var(--soft);margin:4px 0 0}
`;

const WASH = 'linear-gradient(160deg,#274B8F 0%,#1B6E7A 48%,#1B1E24 100%)';

/**
 * The store's photo as a CSS url(): https only, already-encoded URLs left as
 * they are (a storage path's %2F must stay %2F), and nothing that could end
 * the url('…') or the style attribute.
 */
const cssUrl = (url) => {
  const value = String(url || '').trim();
  if (!/^https:\/\//i.test(value)) return null;
  return value.replace(/[\s'"()\\<>]/g, (c) => `%${c.charCodeAt(0).toString(16).toUpperCase().padStart(2, '0')}`);
};

const hookFor = (p) => {
  if (p.kind === 'register') {
    return p.loyaltyLive
      ? { top: 'Thanks for stopping in.', gold: `Get your ${p.scanPoints} points.` }
      : { top: 'Thanks for stopping in.', gold: 'Keep this store close.' };
  }
  return p.loyaltyLive && p.scanPoints > 0
    ? { top: 'Love it here?', gold: `Save us. Get ${p.scanPoints} points.` }
    : { top: 'Love it here?', gold: 'Save us.' };
};

const leadFor = (p) => {
  if (!p.loyaltyLive) return 'Sign in with your email and this store stays with you, with its specials and events sent to you.';
  const first = p.offers[0];
  const toward = first ? ` Points here go toward ${esc(first.title)} (${first.pointsCost} points).` : '';
  return `Sign in with your email. No app and no password.${toward}`;
};

/**
 * `p` is services/storePagePreview's data. Everything from the store is
 * escaped; the script reads the same data from the JSON block.
 */
function renderStorePage(p) {
  const hook = hookFor(p);
  const cover = cssUrl(p.coverUrl);
  // The wash stays underneath, so a photo that fails to load is never a flat page
  const back = cover ? ` style="background-image:url('${esc(cover)}'),${WASH}"` : '';
  const coupon = p.coupon
    ? `<p class="coupon">Your coupon: ${esc(p.coupon.title)}<span>Sign in and it's saved to you, so it's never left at home.</span></p>`
    : '';
  const data = {
    code: p.code, tag: p.tag, kind: p.kind, venueId: p.venueId, globalPlaceId: p.globalPlaceId,
    name: p.name, loyaltyLive: p.loyaltyLive, scanPoints: p.scanPoints, earnRate: p.earnRate,
    couponId: p.coupon ? p.coupon.couponId : null
  };
  return `<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="robots" content="noindex"><meta name="theme-color" content="#1B1E24">
<title>${esc(p.name)} on FavCircles</title>
<style>${STYLE}</style></head>
<body>
<div class="back"${back}></div><div class="shade"></div>
<main class="wrap">
  <p class="brand">FavCircles</p>
  <h1>${esc(hook.top)}<span class="g">${esc(hook.gold)}</span></h1>
  <p class="store">${esc(p.name)}</p>
  ${p.address ? `<p class="addr">${esc(p.address)}</p>` : ''}
  ${coupon}

  <section class="panel" id="step-email">
    <p class="lead" style="margin:0 0 14px">${leadFor(p)}</p>
    <form id="email-form" novalidate>
      <label class="f" for="email">Your email</label>
      <input type="email" id="email" name="email" autocomplete="email" inputmode="email" placeholder="you@example.com" required>
      ${p.globalPlaceId ? `<label class="check"><input type="checkbox" id="alerts" checked><span>Email me ${esc(p.name)}'s specials and events. Stop any time from a link in each email.</span></label>` : ''}
      <button class="primary" type="submit" id="email-go">Continue</button>
      <p class="err" id="email-err" role="alert"></p>
    </form>
    <p class="fine">By continuing you agree to the FavCircles <a href="https://favcircles.com/terms.html">terms</a> and <a href="https://favcircles.com/privacy.html">privacy policy</a>.</p>
    <noscript><p class="err">This page needs JavaScript turned on to sign you in.</p></noscript>
  </section>

  <section class="panel" id="step-code" hidden>
    <form id="code-form" novalidate>
      <label class="f" for="code">The 6-digit code we emailed to <b id="code-to"></b></label>
      <input class="code" type="text" id="code" name="code" inputmode="numeric" autocomplete="one-time-code" maxlength="6" placeholder="000000" required>
      <div id="name-row" hidden>
        <label class="f" for="name">Your name</label>
        <input type="text" id="name" name="name" autocomplete="name" maxlength="60" placeholder="First and last name">
      </div>
      <button class="primary" type="submit" id="code-go">Sign in</button>
      <p class="err" id="code-err" role="alert"></p>
    </form>
    <button class="ghost" type="button" id="code-back">Use a different email</button>
  </section>

  <section class="panel" id="step-earn" hidden>
    <p class="big" id="earn-title">Welcome back.</p>
    <p class="sub" id="earn-sub"></p>
    <button class="primary" type="button" id="earn-go">Get today's points</button>
    <p class="err" id="earn-err" role="alert"></p>
  </section>

  <section class="panel" id="step-done" hidden>
    <p class="big" id="done-title"></p>
    <p class="sub" id="done-sub"></p>
    <p class="coupon" id="done-coupon" hidden></p>
    <div class="bal" id="done-bal" hidden><span>Your points here</span><b id="done-points">0</b></div>
    <ul class="ladder" id="done-ladder"></ul>
    <p class="err" id="done-err" role="alert"></p>
    <button class="ghost" type="button" id="sign-out">Not you? Sign out</button>
  </section>

  <section class="panel" id="step-share" hidden>
    <p class="big">One thing first.</p>
    <p class="sub" id="share-sub"></p>
    <button class="primary" type="button" id="share-go">Share and get my reward</button>
    <button class="ghost" type="button" id="share-no">Not now</button>
    <p class="err" id="share-err" role="alert"></p>
  </section>

  <section class="panel ticket" id="step-ticket" hidden>
    <p class="sub" style="margin:0">Show this at the counter</p>
    <p class="big" id="ticket-title"></p>
    <p class="code" id="ticket-code"></p>
    <p class="left" id="ticket-left"></p>
    <button class="primary" type="button" id="ticket-given">Staff: tap when given</button>
    <button class="ghost" type="button" id="ticket-back">Back to my points</button>
    <p class="err" id="ticket-err" role="alert"></p>
  </section>
</main>
<script type="application/json" id="store-data">${jsonBlock(data)}</script>
<script src="/public/store-page.js" defer></script>
</body></html>`;
}

module.exports = { renderStorePage, hookFor, cssUrl };
