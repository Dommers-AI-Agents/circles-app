// backend/routes/sharePageRoutes.js
//
// The public pages behind shared links: connect invites, circle/place/user
// previews, widget/tab/quote/event/club/run/workout links, postcard and store
// pages. With the app installed iOS opens these as Universal Links and never
// renders them; everyone else gets a preview and the way to the app. Moved out
// of server.js verbatim (2026-10-29), mounted at the same point in the stack.
const express = require('express');
const path = require('path');
const { APP_STORE_URL } = require('../config/rewardConfig');

const router = express.Router();

// Connection invite link. With the Circles app installed, iOS opens this URL
// directly as a Universal Link (AASA paths include /connect/*) and
// auto-connects the two users — this handler is never hit. Without the app,
// the page tries the custom scheme (covers in-app browsers) then falls back
// to the App Store.
router.get('/connect/:userId', async (req, res) => {
  const userId = String(req.params.userId).replace(/[^a-zA-Z0-9_-]/g, '');
  // Carry the referral code and the signed invite token into the app link —
  // the token is what makes opening the link connect in one tap (security
  // audit 2026-10-01); both used to be dropped here
  const qs = new URLSearchParams();
  for (const key of ['code', 't']) {
    const v = typeof req.query[key] === 'string' ? req.query[key].replace(/[^a-zA-Z0-9._-]/g, '').slice(0, 600) : '';
    if (v) qs.set(key, v);
  }
  const appQuery = qs.toString() ? `?${qs.toString()}` : '';
  const appStoreUrl = APP_STORE_URL;

  // Personalize the page and its link preview (OpenGraph) with the inviter's
  // name. Best-effort: any failure falls back to a generic invite.
  let inviterName = null;
  try {
    const { getFirestore } = require('../config/firebase');
    const userDoc = await getFirestore().collection('users').doc(userId).get();
    if (userDoc.exists) {
      inviterName = (userDoc.data().displayName || '').trim() || null;
    }
  } catch (e) {
    console.warn('Connect page: could not load inviter name:', e.message);
  }

  // Escape for safe embedding in HTML
  const safeName = inviterName
    ? inviterName.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;')
    : null;
  const ogTitle = safeName ? `Connect with ${safeName} on Circles` : 'Join me on Circles';
  const heading = safeName ? `${safeName} invited you to Circles` : 'Opening Circles…';

  res.send(`<!DOCTYPE html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>${ogTitle}</title>
<meta property="og:title" content="${ogTitle}">
<meta property="og:description" content="Share and discover favorite places together on Circles.">
<meta property="og:site_name" content="Circles">
<meta property="og:type" content="website">
<meta property="og:url" content="https://api.favcircles.com/connect/${userId}">
</head>
<body style="font-family:-apple-system,Helvetica,Arial,sans-serif;display:flex;justify-content:center;align-items:center;min-height:100vh;margin:0;background:#3182CE;color:#fff;text-align:center">
<div><h1>${heading}</h1><p>If nothing happens, get the app and join ${safeName ? 'them' : 'me'}:</p>
<a href="${appStoreUrl}" style="background:#fff;color:#3182CE;padding:12px 28px;border-radius:8px;text-decoration:none;font-weight:600;display:inline-block">Download FavCircles</a></div>
<script>
  window.location = 'circles://connect/${userId}${appQuery}';
  setTimeout(function(){ if (!document.hidden) window.location = '${appStoreUrl}'; }, 1500);
</script>
</body></html>`);
});

// Public circle share page. With the app installed, iOS opens this as a
// Universal Link (AASA /circle/*). Without it, circle-share.js renders the
// circle preview from /api/circles/:id/public with an App Store fallback.
router.get('/circle/:circleId', (req, res) => {
  res.sendFile(path.join(__dirname, '..', 'public', 'circle-share.html'));
});

// Public place share page. Universal Link target (AASA /place/*) — with the
// app installed iOS opens the place directly (carrying ?ref= attribution).
// Without it, this page shows a preview and falls back to the App Store.
router.get('/place/:placeId', async (req, res) => {
  const placeId = String(req.params.placeId).replace(/[^a-zA-Z0-9_-]/g, '');
  const ref = String(req.query.ref || '').replace(/[^a-zA-Z0-9._-]/g, '');
  const appStoreUrl = APP_STORE_URL;

  // Personalize the page + link preview with the place's details. Best-effort:
  // failures fall back to a generic page.
  let name = null;
  let address = null;
  let photoUrl = null;
  // Only a place an anonymous viewer could see is described (security audit
  // 2026-10-01 — see services/placeSharePreview.js). Everything else gets the
  // generic page; the deep link still opens the app, where the viewer's own
  // access decides.
  try {
    const { getFirestore } = require('../config/firebase');
    const { publicPlacePreview } = require('../services/placeSharePreview');
    const preview = await publicPlacePreview(getFirestore(), placeId);
    if (preview) ({ name, address, photoUrl } = preview);
  } catch (e) {
    console.warn('Place share page: could not load place:', e.message);
  }

  const esc = (s) => String(s)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const ogTitle = name ? `${esc(name)} on Circles` : 'A favorite place on Circles';
  const heading = name ? esc(name) : 'Opening Circles…';
  const deepLink = `circles://place/${placeId}${ref ? `?ref=${ref}` : ''}`;

  res.send(`<!DOCTYPE html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>${ogTitle}</title>
<meta property="og:title" content="${ogTitle}">
<meta property="og:description" content="${address ? esc(address) + ' · ' : ''}Saved and recommended on Circles — favorite places from people you trust.">
<meta property="og:site_name" content="Circles">
<meta property="og:type" content="website">
${photoUrl ? `<meta property="og:image" content="${esc(photoUrl)}">` : ''}
<meta property="og:url" content="https://api.favcircles.com/place/${placeId}">
</head>
<body style="font-family:-apple-system,Helvetica,Arial,sans-serif;display:flex;justify-content:center;align-items:center;min-height:100vh;margin:0;background:#3182CE;color:#fff;text-align:center;padding:24px">
<div>${photoUrl ? `<img src="${esc(photoUrl)}" alt="" style="width:96px;height:96px;border-radius:16px;object-fit:cover;margin-bottom:16px">` : ''}
<h1 style="margin:0 0 4px">${heading}</h1>
${address ? `<p style="margin:0 0 16px;opacity:.85">${esc(address)}</p>` : ''}
<p>See it — and who recommends it — in the Circles app:</p>
<a href="${appStoreUrl}" style="background:#fff;color:#3182CE;padding:12px 28px;border-radius:8px;text-decoration:none;font-weight:600;display:inline-block">Download Circles</a></div>
<script>
  window.location = '${deepLink}';
  setTimeout(function(){ if (!document.hidden) window.location = '${appStoreUrl}'; }, 1500);
</script>
</body></html>`);
});
// Public postcard pages (image proxy, QR, share page) — routes/postcardPublicRoutes.js
router.use(require('./postcardPublicRoutes'));
// Store ordering pages, order.favcircles.com/<slug> — routes/orderWebRoutes.js
router.use('/order', require('./orderWebRoutes'));

// instead of a 404 JSON blob.
router.get(['/app/open', '/app/daily-summary', '/daily-summary', '/app/import'], (req, res) => {
  res.redirect('https://favcircles.com');
});

// Weekly map-digest email target (AASA /app/*): installed devices open the
// app's map directly; browsers land on the marketing site.
router.get('/app/map', (req, res) => {
  res.redirect('https://favcircles.com');
});

// Public user profile share page. Universal Link target (AASA /user/*) —
// opens the profile in-app when installed, App Store fallback otherwise.
router.get('/user/:userId', async (req, res) => {
  const userId = String(req.params.userId).replace(/[^a-zA-Z0-9._-]/g, '');
  const appStoreUrl = APP_STORE_URL;

  let name = null;
  let photoUrl = null;
  try {
    const { getFirestore } = require('../config/firebase');
    const userDoc = await getFirestore().collection('users').doc(userId).get();
    if (userDoc.exists) {
      name = (userDoc.data().displayName || '').trim() || null;
      photoUrl = userDoc.data().profilePicture || null;
    }
  } catch (e) {
    console.warn('User share page: could not load user:', e.message);
  }

  const esc = (s) => String(s)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const ogTitle = name ? `${esc(name)} on Circles` : 'A profile on Circles';
  const heading = name ? esc(name) : 'Opening Circles…';

  res.send(`<!DOCTYPE html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>${ogTitle}</title>
<meta property="og:title" content="${ogTitle}">
<meta property="og:description" content="Follow their favorite places on Circles — recommendations from people you trust.">
<meta property="og:site_name" content="Circles">
<meta property="og:type" content="profile">
${photoUrl ? `<meta property="og:image" content="${esc(photoUrl)}">` : ''}
<meta property="og:url" content="https://api.favcircles.com/user/${userId}">
</head>
<body style="font-family:-apple-system,Helvetica,Arial,sans-serif;display:flex;justify-content:center;align-items:center;min-height:100vh;margin:0;background:#3182CE;color:#fff;text-align:center;padding:24px">
<div>${photoUrl ? `<img src="${esc(photoUrl)}" alt="" style="width:96px;height:96px;border-radius:48px;object-fit:cover;margin-bottom:16px">` : ''}
<h1 style="margin:0 0 16px">${heading}</h1>
<p>See their circles and favorite places in the app:</p>
<a href="${appStoreUrl}" style="background:#fff;color:#3182CE;padding:12px 28px;border-radius:8px;text-decoration:none;font-weight:600;display:inline-block">Download Circles</a></div>
<script>
  window.location = 'circles://user/${userId}';
  setTimeout(function(){ if (!document.hidden) window.location = '${appStoreUrl}'; }, 1500);
</script>
</body></html>`);
});

// Shared widget link (AASA /app/*). A device with the app installed never
// renders this — the Universal Link opens the widget's page directly. This is
// what everyone else sees, and its job is the App Store, because these links
// are shared precisely with people who don't have FavCircles yet.
router.get('/app/widget/:id', async (req, res) => {
  const id = String(req.params.id).replace(/[^a-zA-Z0-9_-]/g, '').slice(0, 64);
  const appStoreUrl = APP_STORE_URL;
  const { widgetCopy } = require('../config/widgetCatalog');
  const copy = widgetCopy(id);

  const esc = (s) => String(s)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  let title = esc(copy.title);
  let blurb = esc(copy.blurb);
  let image = null;
  // A shared Dog Park post or daily dog (?post= / ?daily=): its photo and
  // words in the link preview, and the app opens straight on it
  const linkQuery = new URLSearchParams();
  if (id === 'dogs') {
    const post = typeof req.query.post === 'string' ? req.query.post.replace(/[^a-zA-Z0-9_-]/g, '').slice(0, 128) : '';
    const daily = typeof req.query.daily === 'string' ? req.query.daily.replace(/[^a-zA-Z0-9_-]/g, '').slice(0, 128) : '';
    if (post) linkQuery.set('post', post);
    if (daily) linkQuery.set('daily', daily);
    if (post || daily) {
      const preview = await require('../services/dogParkService').publicPreview({ post: post || null, daily: daily || null });
      if (preview) {
        title = esc(preview.title);
        blurb = esc(preview.description);
        image = preview.imageUrl ? esc(preview.imageUrl) : null;
      }
    }
  }
  const query = linkQuery.toString() ? `?${linkQuery.toString()}` : '';

  res.send(`<!DOCTYPE html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>${title} on FavCircles</title>
<meta property="og:title" content="${title} on FavCircles">
<meta property="og:description" content="${blurb}">
<meta property="og:site_name" content="FavCircles">
<meta property="og:type" content="website">
${image ? `<meta property="og:image" content="${image}">` : ''}
<meta property="og:url" content="https://api.favcircles.com/app/widget/${id}${esc(query)}">
</head>
<body style="font-family:-apple-system,Helvetica,Arial,sans-serif;display:flex;justify-content:center;align-items:center;min-height:100vh;margin:0;background:#3182CE;color:#fff;text-align:center;padding:24px">
<div>${image ? `<img src="${image}" alt="" style="width:220px;max-width:80vw;border-radius:16px;object-fit:cover;margin-bottom:16px">` : `<div style="font-size:64px;line-height:1;margin-bottom:16px">${copy.emoji}</div>`}
<h1 style="margin:0 0 8px">${title}</h1>
<p style="margin:0 0 24px;opacity:.9">${blurb}</p>
<a href="${appStoreUrl}" style="background:#fff;color:#3182CE;padding:12px 28px;border-radius:8px;text-decoration:none;font-weight:600;display:inline-block">Get FavCircles</a></div>
<script>
  window.location = 'circles://widget/${id}${query}';
  setTimeout(function(){ if (!document.hidden) window.location = '${appStoreUrl}'; }, 1500);
</script>
</body></html>`);
});

// Shared home tab link (AASA /app/*): the header's Share button on the Locals
// and Widgets tabs. With the app installed the Universal Link opens that tab
// directly; everyone else gets the tab's pitch and the App Store.
router.get('/app/tab/:slug', (req, res) => {
  const slug = String(req.params.slug).replace(/[^a-zA-Z0-9_-]/g, '').slice(0, 32).toLowerCase();
  const appStoreUrl = APP_STORE_URL;
  const { tabCopy } = require('../config/homeTabCatalog');
  const copy = tabCopy(slug);

  const esc = (s) => String(s)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const title = esc(copy.title);
  const blurb = esc(copy.blurb);

  res.send(`<!DOCTYPE html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>${title} on FavCircles</title>
<meta property="og:title" content="${title} on FavCircles">
<meta property="og:description" content="${blurb}">
<meta property="og:site_name" content="FavCircles">
<meta property="og:type" content="website">
<meta property="og:url" content="https://api.favcircles.com/app/tab/${slug}">
</head>
<body style="font-family:-apple-system,Helvetica,Arial,sans-serif;display:flex;justify-content:center;align-items:center;min-height:100vh;margin:0;background:#3182CE;color:#fff;text-align:center;padding:24px">
<div><div style="font-size:64px;line-height:1;margin-bottom:16px">${copy.emoji}</div>
<h1 style="margin:0 0 8px">${title}</h1>
<p style="margin:0 0 24px;opacity:.9">${blurb}</p>
<a href="${appStoreUrl}" style="background:#fff;color:#3182CE;padding:12px 28px;border-radius:8px;text-decoration:none;font-weight:600;display:inline-block">Get FavCircles</a></div>
<script>
  window.location = 'circles://tab/${slug}';
  setTimeout(function(){ if (!document.hidden) window.location = '${appStoreUrl}'; }, 1500);
</script>
</body></html>`);
});

// Shared quote link (AASA /app/*). With the app installed the Universal Link
// opens the quote reel on this quote. Everyone else sees the quote itself,
// set like the reel, with the way to get more.
//
// og:image is the quote drawn like the app shows it (author, source, topics;
// services/quoteCard.js) — Wes, 2026-10-18: the compact title-only card had
// room for the quote and nothing else.
router.get('/share/quote/:id/card.png', async (req, res) => {
  const id = String(req.params.id).replace(/[^a-zA-Z0-9_-]/g, '').slice(0, 64);
  try {
    const { getFirestore } = require('../config/firebase');
    const doc = id ? await getFirestore().collection('quotes').doc(id).get() : null;
    if (!doc || !doc.exists || doc.data().enabled === false) return res.status(404).end();
    const { CATEGORIES } = require('../services/quotesService');
    const labels = Object.fromEntries(CATEGORIES.map((c) => [c.id, c.label]));
    const png = await require('../services/quoteCard').renderQuoteCard(id, doc.data(), labels);
    res.set('Content-Type', 'image/png');
    res.set('Cache-Control', 'public, max-age=86400');
    res.send(png);
  } catch (e) {
    console.warn('Quote card: could not draw:', e.message);
    res.status(500).end();
  }
});

router.get('/app/quote/:id', async (req, res) => {
  const id = String(req.params.id).replace(/[^a-zA-Z0-9_-]/g, '').slice(0, 64);
  const appStoreUrl = APP_STORE_URL;
  const iconUrl = 'https://favcircles.com/app-icon.png';

  let quote = null;
  try {
    const { getFirestore } = require('../config/firebase');
    const doc = id ? await getFirestore().collection('quotes').doc(id).get() : null;
    if (doc && doc.exists && doc.data().enabled !== false) quote = doc.data();
  } catch (e) {
    console.warn('Quote share page: could not load quote:', e.message);
  }

  const esc = (s) => String(s)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const text = quote && quote.text ? String(quote.text).trim() : null;
  const author = quote && quote.author ? String(quote.author).trim() : null;
  const ogTitle = text ? `“${esc(text.length > 180 ? `${text.slice(0, 177)}…` : text)}”` : 'Quotes on FavCircles';
  const ogDescription = author
    ? `— ${esc(author)} · More quotes on FavCircles`
    : 'A good line a few times a day, on the topics you pick.';
  // The card picture already shows the quote and who said it, so the line
  // under it invites the person it was sent to (Wes, 2026-10-19)
  const cardTitle = 'Sign up to get your own daily quotes';
  const cardUrl = `https://api.favcircles.com/share/quote/${id}/card.png`;

  res.send(`<!DOCTYPE html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>${ogTitle}</title>
<meta property="og:title" content="${quote ? cardTitle : ogTitle}">
${quote ? `<meta property="og:image" content="${cardUrl}">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta property="og:image:alt" content="${ogTitle} ${author ? `— ${esc(author)}` : ''}">` : ''}
<meta property="og:description" content="${ogDescription}">
<meta property="og:site_name" content="FavCircles">
<meta property="og:type" content="article">
<meta property="og:url" content="https://api.favcircles.com/app/quote/${id}">
<link rel="apple-touch-icon" href="${iconUrl}">
<link rel="icon" href="${iconUrl}">
</head>
<body style="font-family:-apple-system,Helvetica,Arial,sans-serif;min-height:100vh;margin:0;background:#000;color:#fff;display:flex;align-items:center;padding:32px;box-sizing:border-box">
<div style="max-width:560px;margin:0 auto">
${text ? `<p style="font-family:'New York',ui-serif,Georgia,serif;font-weight:600;font-size:30px;line-height:1.25;margin:0 0 20px">${esc(text)}</p>` : '<p style="font-family:ui-serif,Georgia,serif;font-size:28px;margin:0 0 20px">Quotes on FavCircles</p>'}
${author ? `<p style="color:#7C6BD6;font-size:18px;font-weight:500;margin:0 0 36px">— ${esc(author)}</p>` : ''}
<p style="color:#8e8e93;font-size:15px;margin:0 0 16px">Swipe through more quotes like this in FavCircles.</p>
<a href="${appStoreUrl}" style="background:#7C6BD6;color:#fff;padding:12px 28px;border-radius:10px;text-decoration:none;font-weight:600;display:inline-block">Get FavCircles</a>
</div>
<script>
  window.location = 'circles://quote/${id}';
  setTimeout(function(){ if (!document.hidden) window.location = '${appStoreUrl}'; }, 1500);
</script>
</body></html>`);
});

// Event invite link (Events widget / Party Bus). The app installed: the
// Universal Link opens its join screen. Otherwise this page explains the event
// and the two steps to join. No member names or photos here.
router.get('/app/event/:token', async (req, res) => {
  const token = String(req.params.token).replace(/[^a-zA-Z0-9_-]/g, '').slice(0, 64);
  const { renderEventInvite } = require('../views/eventPage');
  let preview = null;
  try {
    preview = await require('../services/eventService').publicPreview(token);
  } catch (e) {
    if (e.status !== 404) console.warn('Event invite page:', e.message);
  }
  res.status(preview ? 200 : 404).send(renderEventInvite(token, preview));
});

// Club invite link (Clubs widget). The app installed: the Universal Link opens
// the join screen. Otherwise this page says what the club is and when it
// meets. No member names here.
router.get('/app/club/:token', async (req, res) => {
  const token = String(req.params.token).replace(/[^a-zA-Z0-9_-]/g, '').slice(0, 64);
  const { renderClubInvite } = require('../views/clubPage');
  let preview = null;
  try {
    preview = await require('../services/clubService').publicPreview(token);
  } catch (e) {
    if (e.status !== 404) console.warn('Club invite page:', e.message);
  }
  res.status(preview ? 200 : 404).send(renderClubInvite(token, preview));
});

// Watch-a-run link (FavRun). The app installed: the Universal Link opens
// the run in FavRun. Otherwise: who's running and how to get the app — no
// route, no position.
router.get('/app/run/:token', async (req, res) => {
  const token = String(req.params.token).replace(/[^a-zA-Z0-9_-]/g, '').slice(0, 64);
  const { escapeHtml } = require('../utils/text');
  let preview = null;
  try { preview = await require('../services/runShareService').publicPreview(token); } catch (e) { /* unknown link */ }
  const who = preview ? escapeHtml(preview.ownerName) : 'Someone';
  const line = preview && preview.live ? `${who} is out for a run right now` : `${who} shared a run with you`;
  const appStoreUrl = APP_STORE_URL;
  res.status(preview ? 200 : 404).send(`<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex">
<title>Watch the run · FavCircles</title>
<meta property="og:title" content="${line} 🏃"><meta property="og:description" content="Follow along live in FavCircles: the route, the pace, a ping every mile.">
<style>body{margin:0;font-family:-apple-system,Helvetica,Arial,sans-serif;background:#DD6B20;color:#fff;display:flex;min-height:100vh;align-items:center;justify-content:center;text-align:center}
.c{padding:32px;max-width:420px}h1{font-size:28px;margin:12px 0}p{opacity:.9;line-height:1.4}a{display:inline-block;margin-top:18px;background:#fff;color:#DD6B20;font-weight:700;padding:14px 26px;border-radius:999px;text-decoration:none}</style></head>
<body><div class="c"><div style="font-size:56px">🏃</div><h1>${line}</h1>
<p>Get FavCircles to follow along live: the route on a map, the pace, and a ping every mile. Then open this link again.</p>
<a href="${appStoreUrl}">Get FavCircles</a></div></body></html>`);
});

// Texted workout link (AASA /app/*). With the app installed the Universal
// Link opens the workout in the Workouts widget (view it, copy it, try the
// widget). Everyone else sees the workout here and the way to get the app.
// No og:image: the sender's share sheet hands Messages the card image itself.
router.get('/app/workout/:token', async (req, res) => {
  const token = String(req.params.token).replace(/[^a-zA-Z0-9_-]/g, '').slice(0, 64);
  const appStoreUrl = APP_STORE_URL;
  const iconUrl = 'https://favcircles.com/app-icon.png';
  let post = null;
  let author = null;
  try {
    const doc = await require('../services/workoutFeedService').postByLink(token);
    if (doc) {
      post = doc.data();
      const user = await require('../config/firebase').getFirestore().collection('users').doc(String(post.userId)).get();
      author = user.exists ? (user.data().displayName || null) : null;
    }
  } catch (e) {
    console.warn('Workout share page: could not load workout:', e.message);
  }
  const esc = (v) => String(v)
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const s = post ? post.summary || {} : null;
  const first = author ? String(author).split(' ')[0] : null;
  const minutes = s ? Math.max(1, Math.round((s.durationSeconds || 0) / 60)) : 0;
  const exercises = s && Array.isArray(s.exercises) ? s.exercises : [];
  const cardio = s && Array.isArray(s.cardio) ? s.cardio : [];
  const stats = s ? [`${minutes} min`, exercises.length ? `${exercises.length} exercise${exercises.length === 1 ? '' : 's'}` : null,
    s.completedSets ? `${s.completedSets} sets` : null].filter(Boolean).join(' · ') : '';
  const day = s && s.startedAt ? new Date(s.startedAt).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric', timeZone: 'UTC' }) : '';
  const ogTitle = s ? `${first ? `${esc(first)}'s workout: ` : ''}${esc(s.name || 'Workout')}` : 'Workouts on FavCircles';
  const ogDescription = s ? `${esc(stats)} · Log yours with FavCircles` : 'Log workouts, copy routines from friends.';
  const rows = [...exercises.map((e) => [e.name, `${e.bestSet || ''}${e.isPR ? ' 🏆' : ''}`]), ...cardio.map((c) => [c.name, c.detail || ''])]
    .map(([n, d]) => `<div style="display:flex;justify-content:space-between;gap:12px;padding:9px 0;border-top:1px solid rgba(255,255,255,.12)"><span>${esc(n)}</span><span style="color:#cfd8ff">${esc(d)}</span></div>`).join('');
  res.send(`<!DOCTYPE html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>${ogTitle}</title>
<meta property="og:title" content="${ogTitle}">
<meta property="og:description" content="${ogDescription}">
<meta property="og:site_name" content="FavCircles">
<meta property="og:type" content="article">
<meta property="og:url" content="https://api.favcircles.com/app/workout/${token}">
<link rel="apple-touch-icon" href="${iconUrl}">
<link rel="icon" href="${iconUrl}">
</head>
<body style="font-family:-apple-system,Helvetica,Arial,sans-serif;margin:0;background:#0b1020;color:#fff;padding:28px 20px;box-sizing:border-box">
<div style="max-width:520px;margin:0 auto">
${s ? `<div style="background:linear-gradient(135deg,#2f6fd6,#4b4fc9);border-radius:20px;padding:22px 20px">
<div style="font-size:26px;font-weight:700">${esc(s.name || 'Workout')}</div>
<div style="color:#dbe4ff;font-size:14px;margin:4px 0 14px">${first ? `${esc(first)} · ` : ''}${esc(day)}</div>
<div style="font-size:15px;font-weight:600;margin-bottom:10px">${esc(stats)}</div>
${rows}
</div>` : '<p style="font-size:22px">This workout isn\'t available anymore.</p>'}
<p style="color:#9aa3b8;font-size:15px;margin:22px 0 14px">Track your own workouts, copy this one as a routine, and see what your friends are lifting — in FavCircles.</p>
<a href="circles://workout/${token}" style="background:#fff;color:#0b1020;padding:12px 22px;border-radius:10px;text-decoration:none;font-weight:600;display:inline-block;margin:0 8px 10px 0">Open in FavCircles</a>
<a href="${appStoreUrl}" style="background:#2f6fd6;color:#fff;padding:12px 22px;border-radius:10px;text-decoration:none;font-weight:600;display:inline-block">Get FavCircles</a>
</div>
</body></html>`);
});

module.exports = router;
