// Maricopa County Library District (events.mcldaz.org). Its RSS feed has
// each event's date and time; its list page says which branch. Joined by
// event id; events we can't place are left out.
const { SERVICE_PROGRAM, NOT_AN_OUTING, matchBranch, libraryEvent, stripHtml } = require('./libraryCommon');

const HEADERS = { 'User-Agent': 'Mozilla/5.0 (compatible; FavCircles/1.0; +https://favcircles.com)' };
const MONTHS = { jan: 1, feb: 2, mar: 3, apr: 4, may: 5, jun: 6, jul: 7, aug: 8, sep: 9, oct: 10, nov: 11, dec: 12 };

const decode = (text) => String(text || '')
  .replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#0?39;/g, "'").replace(/&amp;/g, '&');

/** "Thu, 15 Oct 2026, 9:30am - 10:30am" → { date, time }; null for spans over a day. */
function parseWhen(text) {
  const m = /(\d{1,2}) ([A-Za-z]{3}) (\d{4}), (\d{1,2}):(\d{2})(am|pm)\s*-\s*(.*)$/.exec(String(text || '').trim());
  if (!m) return null;
  // "… - Sat, 31 Oct 2026, 5:00pm": a month-long take-home kit, not an outing
  if (/\d{4}/.test(m[7])) return null;
  const month = MONTHS[m[2].toLowerCase()];
  if (!month) return null;
  let hour = parseInt(m[4], 10) % 12;
  if (m[6] === 'pm') hour += 12;
  const pad = (n) => String(n).padStart(2, '0');
  return { date: `${m[3]}-${pad(month)}-${pad(parseInt(m[1], 10))}`, time: `${pad(hour)}:${m[5]}:00` };
}

/** RSS items → { id: { title, link, when, description } } */
function parseRss(xml) {
  const items = {};
  for (const [, body] of String(xml || '').matchAll(/<item>([\s\S]*?)<\/item>/g)) {
    const link = (/<link>(.*?)<\/link>/.exec(body) || [])[1] || '';
    const id = (/[?&]id=(\d+)/.exec(link) || [])[1];
    if (!id) continue;
    const description = decode((/<description>([\s\S]*?)<\/description>/.exec(body) || [])[1]);
    const when = stripHtml((/Date\/Time:<\/strong>(.*?)<\/p>/.exec(description) || [])[1]);
    items[id] = {
      title: decode((/<title>([\s\S]*?)<\/title>/.exec(body) || [])[1]),
      link: decode(link),
      when,
      description: description.replace(/<p><strong>Date\/Time:[\s\S]*?<\/p>/, '')
    };
  }
  return items;
}

/** List page rows → { id: third-cell text } (the branch, in the tables that list one). */
function parseBranches(html) {
  const out = {};
  const rowRe = /<tr>\s*<td><a href="event\?id=(\d+)">[\s\S]*?<\/a><\/td>\s*<td>[\s\S]*?<\/td>\s*<td>([\s\S]*?)<\/td>/g;
  // An event shows in several tables (upcoming, by branch, by category):
  // keep every third cell, so whichever names the branch is there
  for (const [, id, cell] of String(html || '').matchAll(rowRe)) out[id] = [out[id], stripHtml(cell)].filter(Boolean).join(' | ');
  return out;
}

function joinMcld(xml, html, feed, { fromDay, toDay }) {
  const rss = parseRss(xml);
  const places = parseBranches(html);
  return Object.entries(rss).map(([id, item]) => {
    if (!item.title || SERVICE_PROGRAM.test(item.title) || NOT_AN_OUTING.test(item.title) || /^online\b/i.test(item.title)) return null;
    const when = parseWhen(item.when);
    if (!when || when.date < fromDay || when.date > toDay) return null;
    const branch = matchBranch(places[id], feed.branches);
    if (!branch) return null;
    return libraryEvent({
      feed, id, name: item.title, description: item.description, date: when.date, time: when.time, branch,
      url: item.link || `https://${feed.host}/event?id=${id}`
    });
  }).filter(Boolean);
}

async function fetchText(url) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 8000);
  try {
    const res = await fetch(url, { headers: HEADERS, signal: controller.signal });
    if (!res.ok) {
      console.warn(`[localEvents] ${url} answered ${res.status}`);
      return null;
    }
    return await res.text();
  } finally {
    clearTimeout(timer);
  }
}

async function loadMcld(feed, window) {
  const [xml, html] = await Promise.all([fetchText(`https://${feed.host}/rss`), fetchText(`https://${feed.host}/`)]);
  if (!xml || !html) return null;
  return joinMcld(xml, html, feed, window);
}

module.exports = { loadMcld, joinMcld, parseWhen, parseRss, parseBranches };
