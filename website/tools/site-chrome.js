// favcircles.com's menu and footer, in ONE place (Wes, 2026-11-02: the FAQ
// page's menu was missing items — every page carried its own hand-copied
// list and they drifted). build-site-chrome.js writes these into every page;
// build-widgets-page.js uses them for the page it generates.

const MENU = [
  ['/', 'Home'],
  ['/widgets.html', 'Widgets'],
  ['/watch.html', 'Watch'],
  ['/faq.html', 'FAQ'],
  ['/store-owners.html', 'Store&nbsp;Owners'],
  ['/rewards.html', 'Store&nbsp;Rewards'],
  ['/cactus.html', 'Cactus&nbsp;Blockchain'],
  ['/support.html', 'Support']
];

const FOOTER_ROWS = [
  [['/widgets.html', 'Widgets'], ['/watch.html', 'Watch'], ['/faq.html', 'FAQ'], ['/store-owners.html', 'Store Owners'],
    ['/rewards.html', 'Store Rewards'], ['/cactus.html', 'Cactus Blockchain'], ['/connect-claude.html', 'Connect to Claude']],
  [['/switch-from-google-maps.html', 'Switch from Google Maps'], ['/switch-from-mapstr.html', 'Switch from Mapstr'],
    ['/switch-from-swarm.html', 'Switch from Swarm']],
  [['/support.html', 'Support'], ['/privacy.html', 'Privacy Policy'], ['/terms.html', 'Terms of Service'],
    ['/delete-data.html', 'Delete Your Data']]
];

/// `<ul class="nav-links">…</ul>` with the current page marked
function menuHTML(current) {
  const items = MENU.map(([href, label]) => {
    const here = href === current;
    return `                <li><a href="${href}"${here ? ' class="active" aria-current="page"' : ''}>${label}</a></li>`;
  });
  return `<ul class="nav-links">\n${items.join('\n')}\n            </ul>`;
}

function footerHTML() {
  const rows = FOOTER_ROWS.map((row) => `            <p>${row.map(([href, label]) => `<a href="${href}">${label}</a>`).join(' |\n               ')}</p>`);
  return `<footer>
        <div class="container">
            <p>&copy; ${new Date().getFullYear()} FavCircles. All rights reserved.</p>
${rows.join('\n')}
        </div>
    </footer>`;
}

/// One style rule every page needs for the marked menu item
const ACTIVE_STYLE = '<style data-site-chrome>.nav-links a.active{text-decoration:underline;text-underline-offset:6px}</style>';

module.exports = { MENU, FOOTER_ROWS, menuHTML, footerHTML, ACTIVE_STYLE };
