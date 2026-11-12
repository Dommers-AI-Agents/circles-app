// backend/services/emailEngagementReport.js
//
// The admin dashboard's "Email engagement" card: for each kind of email we
// sent in the window, how many went out (emailStats/{day}.kinds), how many
// people clicked (distinct recipients, from emailEvents) and how many
// clicks; opens too, marked as weak. Plus the latest clicks, named. The
// math is pure (summarize); dashboard() does the reads.

const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');

const DAY = 86400000;
const dayKey = (d) => d.toISOString().slice(0, 10);

/** Pure. events: emailEvents rows; sendsByKind: { kind: sent }. */
function summarize(events, sendsByKind = {}, { now = new Date(), days = 30 } = {}) {
  const from = new Date(now.getTime() - (days - 1) * DAY);
  const kinds = {};
  const at = (k) => kinds[k] || (kinds[k] = { kind: k, sent: 0, clicks: 0, clickers: new Set(), opens: 0, openers: new Set() });
  for (const [k, sent] of Object.entries(sendsByKind)) at(k).sent = sent || 0;
  for (const e of events || []) {
    const row = at(e.kind || 'email');
    const who = e.uid || e.email || '?';
    if (e.event === 'click') { row.clicks += 1; row.clickers.add(who); } else if (e.event === 'open') { row.opens += 1; row.openers.add(who); }
  }
  const rows = Object.values(kinds).map((r) => ({
    kind: r.kind, sent: r.sent, clicks: r.clicks, clickers: r.clickers.size, opens: r.opens, openers: r.openers.size,
    clickRate: r.sent > 0 ? Math.min(1, r.clickers.size / r.sent) : null
  })).sort((a, b) => b.sent - a.sent || b.clicks - a.clicks || a.kind.localeCompare(b.kind));

  const byDay = [];
  for (let i = days - 1; i >= 0; i--) {
    const day = dayKey(new Date(now.getTime() - i * DAY));
    byDay.push({ day, clicks: 0, opens: 0 });
  }
  const index = new Map(byDay.map((r) => [r.day, r]));
  for (const e of events || []) {
    const r = index.get(String(e.at || '').slice(0, 10));
    if (!r) continue;
    if (e.event === 'click') r.clicks += 1; else if (e.event === 'open') r.opens += 1;
  }

  const totals = rows.reduce((acc, r) => ({ sent: acc.sent + r.sent, clicks: acc.clicks + r.clicks, opens: acc.opens + r.opens }), { sent: 0, clicks: 0, opens: 0 });
  const clickers = new Set((events || []).filter((e) => e.event === 'click').map((e) => e.uid || e.email)).size;
  const recentClicks = (events || []).filter((e) => e.event === 'click')
    .sort((a, b) => (a.at < b.at ? 1 : -1)).slice(0, 40)
    .map((e) => ({ at: e.at, email: e.email, uid: e.uid || null, kind: e.kind, url: e.url, userAgent: e.userAgent || '' }));
  return { days, from: dayKey(from), totals: { ...totals, clickers }, kinds: rows, byDay, recentClicks };
}

async function dashboard({ days = 30 } = {}, deps = {}) {
  const db = deps.db || getFirestore();
  const now = deps.now ? deps.now() : new Date();
  const fromIso = new Date(now.getTime() - (days - 1) * DAY).toISOString().slice(0, 10) + 'T00:00:00.000Z';
  const keys = [];
  for (let i = days - 1; i >= 0; i--) keys.push(dayKey(new Date(now.getTime() - i * DAY)));
  const [eventsSnap, statSnaps] = await Promise.all([
    db.collection('emailEvents').where('at', '>=', fromIso).get(),
    Promise.all(keys.map((k) => db.collection('emailStats').doc(k).get()))
  ]);
  const sendsByKind = {};
  for (const s of statSnaps) {
    const kinds = (s.exists && s.data().kinds) || {};
    for (const [k, v] of Object.entries(kinds)) sendsByKind[k] = (sendsByKind[k] || 0) + ((v && v.sent) || 0);
  }
  const events = eventsSnap.docs.map((d) => d.data());
  const report = summarize(events, sendsByKind, { now, days });
  // Names for the recent clicks (one read per distinct person, few)
  const uids = [...new Set(report.recentClicks.map((c) => c.uid).filter(Boolean))];
  const names = new Map();
  if (uids.length) {
    const docs = await db.getAll(...uids.map((id) => db.collection(COLLECTIONS.USERS).doc(id)), { fieldMask: ['displayName'] });
    for (const d of docs) if (d.exists) names.set(d.id, d.data().displayName || null);
  }
  report.recentClicks = report.recentClicks.map((c) => ({ ...c, name: c.uid ? names.get(c.uid) || null : null }));
  return report;
}

module.exports = { summarize, dashboard };
