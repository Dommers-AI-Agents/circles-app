#!/usr/bin/env node
// Builds favcircles.com/widgets.html from website/widgets/widgets.json.
// usage: node website/tools/build-widgets-page.js
// Also writes ios/Circles-iOS-UIKit/Resources/WidgetAbout.json (the app's
// per-widget "i" sheet), so commit that alongside widgets.json.
// Also checks the list against the widget package's registry (when the
// favcircles-widgets clone is at ~/favcircles-widgets) so a new widget can't
// ship without a line on the website.
const fs = require('fs');
const path = require('path');
const os = require('os');

const root = path.resolve(__dirname, '..');
// The menu and footer every page shares (site-chrome.js)
const { menuHTML, footerHTML, ACTIVE_STYLE } = require('./site-chrome');
const data = JSON.parse(fs.readFileSync(path.join(root, 'widgets/widgets.json'), 'utf8'));
const out = path.join(root, 'favcircles.com/widgets.html');
// Each widget's search page (favcircles.com/widgets/<slug>.html), Wes
// 2026-11-06: people searching for "pandora alarm" or "water reminder"
// should find FavCircles. Slugs are addresses: never rename one.
const seo = JSON.parse(fs.readFileSync(path.join(root, 'widgets/widget-seo.json'), 'utf8'));
const APP_STORE = 'https://apps.apple.com/us/app/favcircles/id6746807095';
const SITE = 'https://favcircles.com';
// A widget on one of the App Store custom product pages links to that page
const productPage = Object.fromEntries(Object.entries(seo._productPages || {})
  .filter(([ppid]) => !ppid.startsWith('_'))
  .flatMap(([ppid, p]) => p.widgets.map((id) => [id, ppid])));
const appStoreFor = (id) => (productPage[id] ? `${APP_STORE}?ppid=${productPage[id]}` : APP_STORE);
const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

// Every widget in the package must be on the page
const ids = data.groups.flatMap((g) => g.widgets.map((w) => w.id));
const registry = path.join(os.homedir(), 'favcircles-widgets/Sources/FavWidgets');
if (fs.existsSync(registry)) {
  const swift = fs.readdirSync(path.join(registry, 'Widgets'), { recursive: true })
    .filter((f) => String(f).endsWith('Widget.swift'))
    .map((f) => fs.readFileSync(path.join(registry, 'Widgets', String(f)), 'utf8'));
  const pkgIds = swift.map((s) => (s.match(/id:\s*"([a-z0-9_-]+)"/) || [])[1]).filter(Boolean);
  const missing = pkgIds.filter((id) => !ids.includes(id));
  if (missing.length) {
    console.error(`⚠️  In the app but not on the website: ${missing.join(', ')} — add them to website/widgets/widgets.json`);
    process.exitCode = 1;
  }
}

const noSeo = ids.filter((id) => !seo[id] || !seo[id].slug);
if (noSeo.length) {
  console.error(`⚠️  No search page copy for: ${noSeo.join(', ')} — add them to website/widgets/widget-seo.json`);
  process.exit(1);
}
const pageURL = (id) => `/widgets/${seo[id].slug}.html`;

// The app's "i" on each widget page reads the same words (one source)
const appCopy = path.resolve(root, '../ios/Circles-iOS-UIKit/Resources/WidgetAbout.json');
const about = {};
for (const g of data.groups) for (const w of g.widgets) about[w.id] = { name: w.name, tagline: w.tagline, features: w.features };
fs.writeFileSync(appCopy, JSON.stringify(about, null, 1) + '\n');

// So does the server's shared-widget landing page (/app/widget/:id) and the
// weekly email: backend/config/widgetCatalog.generated.json, commit it too
// (Wes, 2026-10-31: one source — the server list had drifted, 4 widgets short)
const serverCopy = path.resolve(root, '../backend/config/widgetCatalog.generated.json');
const catalog = {};
for (const g of data.groups) for (const w of g.widgets) catalog[w.id] = { title: w.name, blurb: w.tagline, emoji: w.emoji, page: SITE + pageURL(w.id) };
fs.writeFileSync(serverCopy, JSON.stringify(catalog, null, 1) + '\n');

const total = ids.length;
const card = (w) => `
          <article class="widget" id="${esc(w.id)}">
            <div class="whead"><span class="emoji">${esc(w.emoji)}</span><div><h3>${esc(w.name)}</h3><p class="tag">${esc(w.tagline)}</p></div></div>
            <ul>${w.features.map((f) => `<li>${esc(f)}</li>`).join('')}</ul>
            <a class="more" href="${pageURL(w.id)}">More about ${esc(w.name)} →</a>
          </article>`;
const groups = data.groups.map((g) => `
        <section class="band">
          <h2>${esc(g.title)}</h2>
          <div class="grid">${g.widgets.map(card).join('')}
          </div>
        </section>`).join('');

const html = `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Widgets - FavCircles</title>
    <meta name="description" content="${total} free mini-apps built into FavCircles: Events, How Are You?, Postcards, Workouts, FavRun, Water, Weather and more.">
    <link rel="canonical" href="https://favcircles.com/widgets.html">
    <link rel="icon" href="/favicon.ico">
    <meta property="og:type" content="website">
    <meta property="og:site_name" content="FavCircles">
    <meta property="og:title" content="FavCircles Widgets — ${total} mini-apps in one app">
    <meta property="og:description" content="Party bus photo albums, check-ins with Mom, real postcards, workouts, runs and more, all inside FavCircles.">
    <meta property="og:url" content="https://favcircles.com/widgets.html">
    <meta property="og:image" content="https://favcircles.com/app-icon.png">
    <meta name="apple-itunes-app" content="app-id=6746807095">
    <script type="application/ld+json">${JSON.stringify({
      '@context': 'https://schema.org', '@type': 'ItemList', name: 'FavCircles widgets',
      itemListElement: data.groups.flatMap((g) => g.widgets).map((w, i) => ({ '@type': 'ListItem', position: i + 1, name: w.name, url: SITE + pageURL(w.id) }))
    })}</script>
    <!-- Generated by website/tools/build-widgets-page.js from website/widgets/widgets.json. Edit those, not this file. -->
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif; line-height: 1.6; color: #333;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); min-height: 100vh; }
        .container { max-width: 1100px; margin: 0 auto; padding: 0 20px; }
        header { background: rgba(255, 255, 255, 0.1); backdrop-filter: blur(10px); transition: background 0.25s ease; padding: 1rem 0; position: fixed; width: 100%; top: 0; z-index: 1000; }
        nav { display: flex; justify-content: space-between; align-items: center; }
        .logo { font-size: 1.8rem; font-weight: bold; color: white; text-decoration: none; }
        .nav-links { display: flex; list-style: none; gap: 1.6rem; }
        .nav-links a { color: white; text-decoration: none; font-weight: 500; transition: opacity 0.3s; }
        .nav-links a:hover { opacity: 0.8; }
        .nav-links a.active { text-decoration: underline; text-underline-offset: 6px; }
        header.scrolled { background: rgba(103, 124, 230, 0.94); }
        main.container { margin-top: 112px; }
        .page-hero { padding: 3rem 0 1.5rem 0; color: white; text-align: center; }
        .page-hero h1 { font-size: 2.7rem; line-height: 1.15; margin-bottom: 1rem; }
        .page-hero p.lead { font-size: 1.2rem; opacity: 0.93; max-width: 760px; margin: 0 auto 1.6rem auto; }
        .cta { display: inline-block; background: white; color: #667eea; padding: 0.9rem 1.8rem; text-decoration: none; border-radius: 50px; font-weight: 700; transition: transform 0.3s, box-shadow 0.3s; }
        .cta:hover { transform: translateY(-2px); box-shadow: 0 10px 25px rgba(0, 0, 0, 0.25); }
        .jump { margin-top: 1.4rem; display: flex; flex-wrap: wrap; gap: 0.5rem; justify-content: center; }
        .jump a { color: white; background: rgba(255,255,255,0.16); padding: 0.3rem 0.8rem; border-radius: 50px; text-decoration: none; font-size: 0.9rem; }
        .band { background: white; border-radius: 20px; box-shadow: 0 10px 30px rgba(0, 0, 0, 0.1); padding: 2.4rem; margin: 2rem 0; }
        .band h2 { color: #667eea; font-size: 1.7rem; margin-bottom: 1.2rem; }
        .grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 1.4rem; }
        .widget { border: 1px solid #eceefa; border-radius: 16px; padding: 1.3rem; scroll-margin-top: 120px; }
        .whead { display: flex; gap: 0.9rem; align-items: center; margin-bottom: 0.7rem; }
        .emoji { font-size: 2.1rem; width: 3.2rem; height: 3.2rem; display: inline-flex; align-items: center; justify-content: center; background: #f1f0fe; border-radius: 14px; flex: 0 0 auto; }
        .widget h3 { color: #4c3b9a; font-size: 1.15rem; }
        .tag { color: #555; font-size: 0.95rem; }
        .widget ul { margin-left: 1.2rem; color: #444; font-size: 0.95rem; }
        .widget li { margin-bottom: 0.35rem; }
        .widget .more { display: inline-block; margin-top: 0.6rem; color: #667eea; font-weight: 600; text-decoration: none; font-size: 0.95rem; }
        .note { color: white; text-align: center; opacity: 0.85; font-size: 0.95rem; margin-top: 0.5rem; }
        footer { background: rgba(0, 0, 0, 0.2); color: white; text-align: center; padding: 2rem 0; margin-top: 4rem; }
        footer a { color: white; text-decoration: underline; }
        @media (max-width: 820px) {
            header { position: static; padding: 0.7rem 0; }
            nav { flex-direction: column; gap: 0.7rem; }
            .nav-links { flex-wrap: wrap; justify-content: center; gap: 0.7rem 0.95rem; font-size: 0.9rem; }
            main.container { margin-top: 0; }
            .page-hero h1 { font-size: 2.1rem; }
            .band { padding: 1.6rem 1.1rem; }
            .grid { grid-template-columns: 1fr; }
        }
    </style>
    ${ACTIVE_STYLE}
</head>
<body>
    <header>
        <nav class="container">
            <a href="/" class="logo">FavCircles</a>
            ${menuHTML('/widgets.html')}
        </nav>
    </header>

    <main class="container">
        <section class="page-hero">
            <h1>${total} handy widgets, built in.</h1>
            <p class="lead">Besides saving and sharing your favorite places, FavCircles comes with a Widgets tab full of free mini-apps for your family, your friends, your health and your day. Turn on the ones you want and drag them into your order.</p>
            <a class="cta" href="https://apps.apple.com/us/app/favcircles/id6746807095" target="_blank" rel="noopener">Get FavCircles, free</a>
            <div class="jump">${data.groups.flatMap((g) => g.widgets).map((w) => `<a href="#${esc(w.id)}">${esc(w.emoji)} ${esc(w.name)}</a>`).join('')}</div>
        </section>
${groups}
        <p class="note">Open FavCircles → Home → Widgets. New widgets and features arrive with app updates. Updated ${esc(data.updated)}.</p>
    </main>

    ${footerHTML()}
    <script>
        (function () {
            var header = document.querySelector('header');
            if (!header) return;
            function onScroll() { header.classList.toggle('scrolled', window.scrollY > 10); }
            window.addEventListener('scroll', onScroll, { passive: true });
            onScroll();
        })();
    </script>
</body>
</html>
`;
fs.writeFileSync(out, html);
console.log(`Wrote ${path.relative(process.cwd(), out)} (${total} widgets)`);

// One page per widget, written for what people search ("Pandora alarm clock
// for iPhone"), and each says FavCircles is first an app for saving and
// sharing places (Wes, 2026-11-06: "in addition to its core purpose")
const pagesDir = path.join(root, 'favcircles.com/widgets');
fs.mkdirSync(pagesDir, { recursive: true });
const jsonLD = (o) => `<script type="application/ld+json">${JSON.stringify(o).replace(/</g, '\\u003c')}</script>`;
const pageStyle = html.match(/<style>[\s\S]*?<\/style>/)[0].replace('</style>', `
        .page-hero .emoji { font-size: 3.2rem; width: 5rem; height: 5rem; background: rgba(255,255,255,0.18); border-radius: 22px; margin-bottom: 1rem; }
        .crumbs { color: white; opacity: 0.85; font-size: 0.9rem; margin-bottom: 1.2rem; }
        .crumbs a { color: white; }
        .band p { color: #444; margin-bottom: 0.8rem; }
        .band p a { color: #667eea; font-weight: 600; }
        .band ul.features { margin-left: 1.2rem; color: #444; }
        .band ul.features li { margin-bottom: 0.45rem; }
        .faq h3 { color: #4c3b9a; font-size: 1.05rem; margin: 1rem 0 0.25rem; }
        .faq p { margin: 0; }
        .related { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 1rem; }
        .related a { display: flex; gap: 0.7rem; align-items: center; border: 1px solid #eceefa; border-radius: 14px; padding: 0.8rem; text-decoration: none; color: #4c3b9a; font-weight: 600; }
        .related .emoji { font-size: 1.6rem; width: 2.6rem; height: 2.6rem; }
    </style>`);
const written = [];
for (const g of data.groups) {
  for (const w of g.widgets) {
    const s = seo[w.id];
    const url = SITE + pageURL(w.id);
    const siblings = g.widgets.filter((o) => o.id !== w.id).slice(0, 3);
    const faq = s.faq || [];
    const ld = [
      { '@context': 'https://schema.org', '@type': 'SoftwareApplication', name: 'FavCircles', alternateName: `${w.name} in FavCircles`,
        operatingSystem: 'iOS', applicationCategory: 'LifestyleApplication', url, installUrl: APP_STORE, downloadUrl: APP_STORE,
        description: s.description, featureList: w.features, offers: { '@type': 'Offer', price: '0', priceCurrency: 'USD' } },
      { '@context': 'https://schema.org', '@type': 'BreadcrumbList', itemListElement: [
        { '@type': 'ListItem', position: 1, name: 'FavCircles', item: SITE + '/' },
        { '@type': 'ListItem', position: 2, name: 'Widgets', item: SITE + '/widgets.html' },
        { '@type': 'ListItem', position: 3, name: w.name, item: url }] }
    ];
    if (faq.length) ld.push({ '@context': 'https://schema.org', '@type': 'FAQPage',
      mainEntity: faq.map(([q, a]) => ({ '@type': 'Question', name: q, acceptedAnswer: { '@type': 'Answer', text: a } })) });
    const page = `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>${esc(s.title)}</title>
    <meta name="description" content="${esc(s.description)}">
    <link rel="canonical" href="${url}">
    <link rel="icon" href="/favicon.ico">
    <meta name="apple-itunes-app" content="app-id=6746807095">
    <meta property="og:type" content="website">
    <meta property="og:site_name" content="FavCircles">
    <meta property="og:title" content="${esc(s.title)}">
    <meta property="og:description" content="${esc(s.description)}">
    <meta property="og:url" content="${url}">
    <meta property="og:image" content="https://favcircles.com/app-icon.png">
    ${ld.map(jsonLD).join('\n    ')}
    <!-- Generated by website/tools/build-widgets-page.js from website/widgets/widgets.json and widget-seo.json. Edit those, not this file. -->
    ${pageStyle}
    ${ACTIVE_STYLE}
</head>
<body>
    <header>
        <nav class="container">
            <a href="/" class="logo">FavCircles</a>
            ${menuHTML('/widgets.html')}
        </nav>
    </header>

    <main class="container">
        <section class="page-hero">
            <p class="crumbs"><a href="/widgets.html">Widgets</a> › ${esc(w.name)}</p>
            <span class="emoji">${esc(w.emoji)}</span>
            <h1>${esc(s.h1)}</h1>
            <p class="lead">${esc(s.intro)}</p>
            <a class="cta" href="${appStoreFor(w.id)}" target="_blank" rel="noopener">Get FavCircles, free on iPhone</a>
        </section>

        <section class="band">
            <h2>What ${esc(w.name)} does</h2>
            <ul class="features">${w.features.map((f) => `<li>${esc(f)}</li>`).join('')}</ul>${(s.goodToKnow || []).length ? `
            <h2 style="margin-top:1.6rem">Good to know</h2>
            <ul class="features">${s.goodToKnow.map((f) => `<li>${esc(f)}</li>`).join('')}</ul>` : ''}
        </section>
${faq.length ? `
        <section class="band faq">
            <h2>Questions</h2>${faq.map(([q, a]) => `
            <h3>${esc(q)}</h3>
            <p>${esc(a)}</p>`).join('')}
        </section>
` : ''}
        <section class="band">
            <h2>Part of FavCircles</h2>
            <p>${esc(w.name)} is one of ${total} widgets in FavCircles, the free app for saving and sharing your favorite places. Keep the restaurants, coffee shops and spots you love in circles, see where your friends go, and earn rewards at local shops. The widgets live in the app's Widgets tab: turn on the ones you want.</p>
            <p><a href="/">What FavCircles is</a> · <a href="/widgets.html">All ${total} widgets</a></p>
        </section>
${siblings.length ? `
        <section class="band">
            <h2>More for ${esc(g.title.toLowerCase())}</h2>
            <div class="related">${siblings.map((o) => `<a href="${pageURL(o.id)}"><span class="emoji">${esc(o.emoji)}</span>${esc(o.name)}</a>`).join('')}</div>
        </section>
` : ''}
        <p class="note">Open FavCircles → Home → Widgets. Updated ${esc(data.updated)}.</p>
    </main>

    ${footerHTML()}
    <script>
        (function () {
            var header = document.querySelector('header');
            if (!header) return;
            function onScroll() { header.classList.toggle('scrolled', window.scrollY > 10); }
            window.addEventListener('scroll', onScroll, { passive: true });
            onScroll();
        })();
    </script>
</body>
</html>
`;
    fs.writeFileSync(path.join(pagesDir, `${s.slug}.html`), page);
    written.push(pageURL(w.id));
  }
}
// A page whose slug changed or was removed would linger: say so (never
// delete it silently; the old address may be indexed)
const stray = fs.readdirSync(pagesDir).filter((f) => !written.includes(`/widgets/${f}`));
if (stray.length) console.warn(`⚠️  Old widget pages not built any more: ${stray.join(', ')}`);
console.log(`Wrote ${written.length} widget pages in favcircles.com/widgets/`);

// sitemap.xml and robots.txt: every public page plus the widget pages
const hidden = new Set(['store-owner-tutorial.html', 'delete-data.html']);
const sitePages = fs.readdirSync(path.join(root, 'favcircles.com'))
  .filter((f) => f.endsWith('.html') && !hidden.has(f))
  .map((f) => (f === 'index.html' ? '/' : `/${f}`));
const urls = [...sitePages.sort(), ...written];
fs.writeFileSync(path.join(root, 'favcircles.com/sitemap.xml'), `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
${urls.map((u) => `  <url><loc>${SITE}${u}</loc>${u.startsWith('/widgets') ? `<lastmod>${data.updated}</lastmod>` : ''}</url>`).join('\n')}
</urlset>
`);
fs.writeFileSync(path.join(root, 'favcircles.com/robots.txt'), `User-agent: *
Allow: /

Sitemap: ${SITE}/sitemap.xml
`);
console.log(`Wrote sitemap.xml (${urls.length} pages) and robots.txt`);
