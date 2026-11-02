#!/usr/bin/env node
// Writes the shared menu and footer (site-chrome.js) into every page of
// favcircles.com. Run after changing the menu or adding a page, then upload
// the changed pages over SFTP. Pages without a menu (store-owner-tutorial)
// are left alone. Exits non-zero if a page's menu can't be found.
const fs = require('fs');
const path = require('path');
const { menuHTML, footerHTML, ACTIVE_STYLE } = require('./site-chrome');

const site = path.join(__dirname, '..', 'favcircles.com');
let changed = 0;
for (const name of fs.readdirSync(site).filter((f) => f.endsWith('.html'))) {
  const file = path.join(site, name);
  const before = fs.readFileSync(file, 'utf8');
  if (!before.includes('class="nav-links"')) continue;
  const current = name === 'index.html' ? '/' : `/${name}`;
  let html = before.replace(/<ul class="nav-links">[\s\S]*?<\/ul>/, menuHTML(current));
  html = html.replace(/<footer>[\s\S]*?<\/footer>/, footerHTML());
  if (!html.includes('data-site-chrome')) html = html.replace('</head>', `    ${ACTIVE_STYLE}\n</head>`);
  if (html !== before) {
    fs.writeFileSync(file, html);
    changed += 1;
    console.log('updated', name);
  }
}
console.log(`${changed} page(s) changed`);
