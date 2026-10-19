// The weekly email's HTML (Wes, 2026-10-19: "This weekly email could be
// much better… make it better"). One long, scrollable letter: the week in
// numbers, the actual places friends saved, FavCoins, what's on nearby,
// what's new in the app, three widgets to try, and a tip. Email-safe:
// tables and inline styles only, explicit colors so dark-mode clients
// don't wash it out, every database string escaped.
const { escapeHtml } = require('../../utils/text');

const BASE = 'https://api.favcircles.com';
const APP_STORE = 'https://apps.apple.com/us/app/favcircles/id6746807095';
const NAVY = '#0E2A47';
const ACCENT = '#2F6FED';
const TEXT = '#1d2733';
const MUTED = '#5f6b7a';
const CARD = '#f4f6f9';
const LINE = '#e3e8ef';

const esc = (s) => escapeHtml(String(s == null ? '' : s));
const plural = (n, word) => `${n} ${word}${n === 1 ? '' : 's'}`;

const CATEGORY_WORDS = {
  restaurant: 'Restaurant', cafe: 'Café', bar: 'Bar', retail: 'Shop', entertainment: 'Entertainment',
  outdoor: 'Outdoors', education: 'School', health: 'Health', hotel: 'Hotel', other: 'Place'
};
const categoryWord = (c) => CATEGORY_WORDS[c] || (c ? c.charAt(0).toUpperCase() + c.slice(1) : 'Place');

function weekRange(windowStart, now) {
  const start = windowStart ? new Date(windowStart) : new Date(now.getTime() - 7 * 86400000);
  const fmt = (d, withMonth) => d.toLocaleDateString('en-US', withMonth ? { month: 'short', day: 'numeric' } : { day: 'numeric' });
  const sameMonth = start.getMonth() === now.getMonth();
  return `${fmt(start, true)} – ${fmt(now, !sameMonth)}`;
}

function section(title, inner, { subtitle = null } = {}) {
  return `
  <tr><td style="padding:28px 24px 0 24px;">
    <h2 style="margin:0 0 ${subtitle ? '4px' : '14px'} 0;font-size:19px;line-height:1.3;color:${TEXT};font-weight:700;">${title}</h2>
    ${subtitle ? `<p style="margin:0 0 14px 0;font-size:14px;color:${MUTED};">${subtitle}</p>` : ''}
    ${inner}
  </td></tr>`;
}

function statTiles(tiles) {
  const cell = ({ value, label }) => `
    <td width="50%" style="padding:4px;">
      <div style="background:${CARD};border-radius:12px;padding:14px 16px;">
        <div style="font-size:26px;font-weight:800;color:${NAVY};line-height:1.1;">${esc(value)}</div>
        <div style="font-size:13px;color:${MUTED};margin-top:4px;">${esc(label)}</div>
      </div>
    </td>`;
  const rows = [];
  for (let i = 0; i < tiles.length; i += 2) rows.push(`<tr>${cell(tiles[i])}${tiles[i + 1] ? cell(tiles[i + 1]) : '<td width="50%"></td>'}</tr>`);
  return `<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="table-layout:fixed;">${rows.join('')}</table>`;
}

function thumb(url, emoji) {
  return url
    ? `<img src="${esc(url)}" width="64" height="64" alt="" style="display:block;width:64px;height:64px;border-radius:10px;object-fit:cover;background:${CARD};">`
    : `<div style="width:64px;height:64px;border-radius:10px;background:${CARD};text-align:center;line-height:64px;font-size:28px;">${emoji}</div>`;
}

function listRow({ href, image, emoji, title, lines }) {
  const open = href ? `<a href="${esc(href)}" style="text-decoration:none;color:inherit;">` : '';
  const close = href ? '</a>' : '';
  return `
    <tr><td style="padding:8px 0;border-bottom:1px solid ${LINE};">
      ${open}<table role="presentation" width="100%" cellspacing="0" cellpadding="0"><tr>
        <td width="76" valign="top">${thumb(image, emoji)}</td>
        <td valign="middle" style="word-break:break-word;overflow-wrap:anywhere;">
          <div style="font-size:16px;font-weight:600;color:${TEXT};">${esc(title)}</div>
          ${lines.filter(Boolean).map((l) => `<div style="font-size:13px;color:${MUTED};margin-top:2px;">${l}</div>`).join('')}
        </td>
      </tr></table>${close}
    </td></tr>`;
}

const list = (rows) => `<table role="presentation" width="100%" cellspacing="0" cellpadding="0">${rows.join('')}</table>`;

function button(href, label, color = ACCENT) {
  return `<a href="${esc(href)}" style="display:inline-block;background:${color};color:#ffffff;text-decoration:none;padding:12px 26px;border-radius:24px;font-weight:600;font-size:15px;margin:6px 4px;">${esc(label)}</a>`;
}

// ---------- sections ----------

function networkSection(stats, extras) {
  const places = extras.networkPlaces || [];
  if (stats.newPlaces === 0 && places.length === 0) return '';
  const rows = places.map((p) => listRow({
    href: `${BASE}/place/${encodeURIComponent(p.id)}`,
    image: p.photo, emoji: '📍', title: p.name,
    lines: [
      esc([categoryWord(p.category), p.city].filter(Boolean).join(' · ')),
      `Saved by <strong style="color:${TEXT};">${esc(p.savedBy)}</strong>${p.rating != null ? ` · rated ${esc(p.rating)}/10` : ''}`
    ]
  }));
  const more = stats.newPlaces > places.length
    ? `<p style="margin:12px 0 0 0;font-size:14px;color:${MUTED};">+ ${plural(stats.newPlaces - places.length, 'more place')} in the app.</p>` : '';
  const top = (stats.topContributors || []).length
    ? `<p style="margin:12px 0 0 0;font-size:14px;color:${MUTED};">Most active: ${stats.topContributors.slice(0, 3).map((c) => `${esc(c.name)} (${c.count})`).join(', ')}</p>` : '';
  return section(`📍 ${plural(stats.newPlaces, 'new place')} from your network`, `${list(rows)}${more}${top}`);
}

function coinsSection(stats, fmt) {
  const c = stats.favCoins;
  if (!c || !(c.lifetimeCoins > 0 || c.earnedThisWeek > 0)) return '';
  const growth = c.earnedThisWeek > 0
    ? `<p style="margin:0 0 6px 0;color:#2e7d32;font-weight:600;">+${fmt(c.earnedThisWeek)} earned this week (${c.earnEventsThisWeek} reward${c.earnEventsThisWeek === 1 ? '' : 's'})</p>`
    : `<p style="margin:0 0 6px 0;color:${MUTED};">No new FavCoins this week. Add a place, check in, or share a circle to earn more.</p>`;
  const pending = c.pendingCoins > 0 ? ` <span style="color:${MUTED};font-weight:400;">(+${fmt(c.pendingCoins)} clearing)</span>` : '';
  const walletLine = c.hasWallet
    ? `${c.settledOnChain > 0 ? `${fmt(c.settledOnChain)} already sent to your wallet. ` : ''}Claim your balance to your Cactus wallet 🌵 anytime from the Piggy Bank.`
    : 'Create your wallet in the app and you can claim them to the Cactus blockchain 🌵.';
  return section('🌵 Your FavCoins', `
    <div style="background:#f1f8e9;border:1px solid #c5e1a5;border-radius:12px;padding:16px;">
      <p style="margin:0 0 6px 0;color:${TEXT};font-size:18px;font-weight:700;">${fmt(c.confirmedCoins)} available${pending}</p>
      ${growth}
      <p style="margin:0 0 6px 0;color:${MUTED};">Lifetime earned: ${fmt(c.lifetimeCoins)}</p>
      <p style="margin:10px 0 0 0;color:${MUTED};font-size:13px;line-height:1.5;">
        FavCoins are real crypto coins on the Cactus blockchain 🌵 that you earn for sharing the places you love.
        ${walletLine}<br>See them in FavCircles: <strong>Rewards → Piggy Bank</strong>.
      </p>
      <p style="margin:12px 0 0 0;">${button(`${BASE}/app/open?path=create-wallet`, '🌵 See my FavCoins', '#558b2f')}</p>
    </div>`);
}

function localsSection(locals) {
  if (!locals) return '';
  const when = (e) => {
    const d = e.date ? new Date(`${e.date}T12:00:00`) : null;
    const day = d && !Number.isNaN(d.getTime()) ? d.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' }) : '';
    let time = '';
    if (e.time) {
      const [h, m] = e.time.split(':').map(Number);
      time = ` · ${h % 12 === 0 ? 12 : h % 12}${m ? `:${String(m).padStart(2, '0')}` : ''} ${h < 12 ? 'AM' : 'PM'}`;
    }
    return esc(day + time);
  };
  const rows = [
    ...locals.events.map((e) => listRow({ href: e.url, image: e.image, emoji: '🎟️', title: e.name, lines: [when(e), esc(e.venue || '')] })),
    ...locals.markets.map((m) => listRow({ href: null, image: m.image, emoji: '🥕', title: m.name, lines: [esc(m.hours || 'Farmers market'), esc(m.address || '')] }))
  ];
  const credit = locals.attribution ? `<p style="margin:10px 0 0 0;font-size:11px;color:${MUTED};">${esc(locals.attribution)}</p>` : '';
  return section('🎟️ Happening near you', `${list(rows)}
    <p style="margin:14px 0 0 0;">${button(`${BASE}/app/tab/locals`, 'See more on the Locals tab')}</p>${credit}`,
  { subtitle: 'Events, specials and farmers markets close by.' });
}

function whatsNewSection(items) {
  if (!items || items.length === 0) return '';
  const rows = items.map((e) => `
    <tr><td style="padding:10px 0;border-bottom:1px solid ${LINE};">
      <div style="font-size:16px;font-weight:600;color:${TEXT};">${e.emoji} ${esc(e.title)}</div>
      <div style="font-size:14px;color:${MUTED};margin-top:4px;line-height:1.5;">${esc(e.body)}</div>
      ${e.needsUpdate
        ? `<div style="margin-top:6px;"><a href="${APP_STORE}" style="font-size:13px;font-weight:600;color:${ACCENT};text-decoration:none;">Update FavCircles to get this →</a></div>`
        : e.link ? `<div style="margin-top:6px;"><a href="${esc(BASE + e.link)}" style="font-size:13px;font-weight:600;color:${ACCENT};text-decoration:none;">Try it →</a></div>` : ''}
    </td></tr>`);
  return section("✨ What's new in FavCircles", list(rows));
}

function widgetsSection(widgets) {
  if (!widgets || widgets.length === 0) return '';
  const rows = widgets.map((w) => listRow({
    href: `${BASE}/app/widget/${encodeURIComponent(w.id)}`, image: null, emoji: w.emoji, title: w.title,
    lines: [esc(w.blurb), `<span style="color:${ACCENT};font-weight:600;">Open ${esc(w.title)} →</span>`]
  }));
  return section('🧩 Widgets to try this week', list(rows),
    { subtitle: 'Little apps inside FavCircles. Find them on the Widgets tab on Home.' });
}

function tipSection(tip) {
  if (!tip) return '';
  return section('💡 Tip of the week', `
    <div style="background:${CARD};border-radius:12px;padding:16px;font-size:15px;color:${TEXT};line-height:1.5;">${tip.emoji} ${esc(tip.text)}</div>`);
}

// ---------- the letter ----------

function renderWeeklyEmail({ user, stats, extras = {}, fmtCoins, now = new Date() }) {
  const own = extras.own || { saved: 0, checkIns: 0 };
  const reactions = (stats.placeLikes || 0) + (stats.placeComments || 0);
  const name = String(user.displayName || '').trim().split(/\s+/)[0] || 'there';

  const extrasLines = [];
  if (stats.newConnections > 0) extrasLines.push(`👥 ${plural(stats.newConnections, 'new connection')}`);
  if (stats.unreadMessages > 0) extrasLines.push(`💬 ${plural(stats.unreadMessages, 'unread message')}`);
  if (stats.placeComments > 0 || stats.placeLikes > 0) {
    const bits = [];
    if (stats.placeLikes > 0) bits.push(plural(stats.placeLikes, 'like'));
    if (stats.placeComments > 0) bits.push(plural(stats.placeComments, 'comment'));
    extrasLines.push(`❤️ ${bits.join(' and ')} on your places`);
  }

  const glance = section('Your week', `${statTiles([
    { value: own.saved, label: own.saved === 1 ? 'place you saved' : 'places you saved' },
    { value: own.checkIns, label: own.checkIns === 1 ? 'check-in' : 'check-ins' },
    { value: stats.newPlaces || 0, label: 'new from friends' },
    { value: reactions, label: 'likes & comments' }
  ])}${extrasLines.length ? `<p style="margin:12px 0 0 0;font-size:14px;color:${TEXT};line-height:1.7;">${extrasLines.join('<br>')}</p>` : ''}`);

  return `<!DOCTYPE html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
<meta name="color-scheme" content="light only"><meta name="supported-color-schemes" content="light only">
<title>Your FavCircles week</title></head>
<body style="margin:0;padding:0;background:#eef1f5;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#eef1f5;"><tr><td align="center" style="padding:20px 10px;">
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:600px;width:100%;table-layout:fixed;background:#ffffff;border-radius:16px;overflow:hidden;word-wrap:break-word;">
  <tr><td style="background:${NAVY};padding:28px 24px;text-align:center;">
    <div style="font-size:26px;font-weight:800;color:#ffffff;letter-spacing:0.3px;">FavCircles</div>
    <div style="font-size:15px;color:#c9d6ea;margin-top:6px;">Your Weekly Summary · ${esc(weekRange(stats.windowStart, now))}</div>
  </td></tr>
  <tr><td style="padding:26px 24px 0 24px;">
    <h1 style="margin:0 0 8px 0;font-size:22px;color:${TEXT};">Hi ${esc(name)} 👋</h1>
    <p style="margin:0;font-size:15px;color:${MUTED};line-height:1.6;">Here's your week on FavCircles: what your friends found, what's on near you, and what's new in the app. Scroll as far as you like.</p>
  </td></tr>
  ${glance}
  ${networkSection(stats, extras)}
  ${coinsSection(stats, fmtCoins)}
  ${localsSection(extras.locals)}
  ${whatsNewSection(extras.whatsNew)}
  ${widgetsSection(extras.widgets)}
  ${tipSection(extras.tip)}
  <tr><td style="padding:30px 24px 8px 24px;text-align:center;">
    ${button(`${BASE}/app/daily-summary`, 'Open FavCircles', NAVY)}
  </td></tr>
  <tr><td style="padding:20px 24px 28px 24px;text-align:center;border-top:1px solid ${LINE};">
    <p style="margin:0;font-size:12px;color:${MUTED};line-height:1.6;">
      You're receiving this because you have the weekly summary turned on.<br>
      <a href="${BASE}/app/open?path=settings/notifications" style="color:${ACCENT};">Manage notification preferences</a>
    </p>
  </td></tr>
</table>
</td></tr></table>
</body></html>`;
}

/** "5 new places from your network · +61.5 FavCoins" — the subject says what's inside. */
function subjectFor(stats, fmtCoins) {
  const bits = [];
  if (stats.newPlaces > 0) bits.push(`${plural(stats.newPlaces, 'new place')} from friends`);
  if (stats.favCoins && stats.favCoins.earnedThisWeek > 0) bits.push(`+${fmtCoins(stats.favCoins.earnedThisWeek)}`);
  return bits.length ? `Your FavCircles week: ${bits.join(' · ')}` : 'Your FavCircles week';
}

module.exports = { renderWeeklyEmail, subjectFor, weekRange };
