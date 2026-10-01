// backend/services/adminAnalytics/index.js
//
// The admin dashboard's data. Reads whole collections (with select(), so only
// the fields we count) and keeps them in memory for 10 minutes; at today's
// size that is a few thousand small docs. The math lives in metrics.js.
//
// Privacy: message text, comment text and private check-in details never
// leave this module; people's activity rows marked ownerOnly are dropped.
// Opening one person's detail is written to adminAuditLog.
const { getFirestore } = require('../../config/firebase');
const m = require('./metrics');

const CACHE_MS = 10 * 60 * 1000;
let cache = null; // { at, data }
const db = () => getFirestore();

const all = async (name, fields) => {
  const snap = await db().collection(name).select(...fields).get();
  return snap.docs.map((d) => ({ id: d.id, ...d.data() }));
};

const load = async ({ fresh = false } = {}) => {
  if (!fresh && cache && Date.now() - cache.at < CACHE_MS) return cache.data;
  const [users, places, circles, checkIns, messages, connections, activities, postcards, fridgePlans,
    coins, partnerClicks, rewardEvents, venues, suppressions, fallbackLog] = await Promise.all([
    all('users', ['email', 'displayName', 'profilePicture', 'createdAt', 'lastActive', 'lastAppOpenAt', 'lastLogin',
      'onboardingCompleted', 'isPremium', 'subscriptionStatus', 'subscriptionTier', 'ownerSubscriptionStatus',
      'deviceTokens', 'pushStatus', 'emailPreferences', 'productUpdateEmails', 'followers', 'following', 'isSuperUser',
      'isDeleted', 'deletedAt']),
    all('places', ['addedBy', 'createdAt', 'deletedAt']),
    all('circles', ['owner', 'createdAt']),
    all('checkIns', ['userId', 'createdAt', 'startTime']),
    all('messages', ['senderId', 'createdAt']),
    all('connections', ['userId', 'connectedUserId', 'status', 'createdAt', 'acceptedAt']),
    all('activities', ['actorId', 'type', 'timestamp']),
    all('postcardOrders', ['userId', 'amountCents', 'status', 'createdAt', 'refundedAt', 'complimentary', 'prepaid', 'kind']),
    all('fridgeMailPlans', ['status', 'subscription', 'cardsRemaining', 'createdAt']),
    all('piggyLedger', ['coins', 'status', 'createdAt']),
    all('partnerClicks', ['provider', 'matched', 'at']),
    all('rewardEvents', ['type', 'points', 'venueName', 'createdAt']),
    all('stickerVenues', ['venueName', 'ownerUserId']),
    all('emailSuppressions', ['reason', 'suppressedAt']),
    all('emailFallbackLog', ['type', 'action', 'at'])
  ]);
  const live = users.filter((u) => !u.isDeleted && !u.deletedAt);
  const data = {
    users: live, places: places.filter((p) => !p.deletedAt), circles, checkIns, messages, connections, activities,
    postcards, fridgePlans, coins, partnerClicks, rewardEvents, venues, suppressions, fallbackLog, loadedAt: new Date().toISOString()
  };
  cache = { at: Date.now(), data };
  return data;
};

const countBy = (items, keyOf) => {
  const map = new Map();
  for (const i of items) { const k = keyOf(i); if (k) map.set(k, (map.get(k) || 0) + 1); }
  return map;
};

/** userId → { places, circles, connections } */
const perUserCounts = (d) => {
  const places = countBy(d.places, (p) => p.addedBy);
  const circles = countBy(d.circles, (c) => c.owner);
  const conns = new Map();
  for (const c of d.connections) {
    if (c.status !== 'accepted') continue;
    // Two docs can exist for one pair (one each way); count people, not docs
    for (const [me, other] of [[c.userId, c.connectedUserId], [c.connectedUserId, c.userId]]) {
      if (!me || !other) continue;
      if (!conns.has(me)) conns.set(me, new Set());
      conns.get(me).add(other);
    }
  }
  const out = new Map();
  for (const u of d.users) {
    out.set(u.id, { places: places.get(u.id) || 0, circles: circles.get(u.id) || 0, connections: (conns.get(u.id) || new Set()).size });
  }
  return out;
};

const range = (query, now = new Date()) => {
  const days = query.days === 'all' ? 3650 : Math.min(3650, Math.max(1, parseInt(query.days || '30', 10) || 30));
  return { from: new Date(now.getTime() - (days - 1) * m.DAY), to: now, days };
};

const overview = async (query = {}) => {
  const d = await load({ fresh: query.fresh === 'true' });
  const { from, to, days } = range(query);
  const chartFrom = days > 180 ? new Date(to.getTime() - 179 * m.DAY) : from;
  const counts = perUserCounts(d);
  const activityByUser = new Map();
  const note = (id, v) => { const dt = m.toDate(v); if (!id || !dt) return; if (!activityByUser.has(id)) activityByUser.set(id, []); activityByUser.get(id).push(dt); };
  d.activities.forEach((a) => note(a.actorId, a.timestamp));
  d.places.forEach((p) => note(p.addedBy, p.createdAt));
  d.messages.forEach((x) => note(x.senderId, x.createdAt));
  d.checkIns.forEach((c) => note(c.userId, c.createdAt || c.startTime));
  d.users.forEach((u) => { note(u.id, m.lastSeen(u)); note(u.id, u.createdAt); });
  const within = (items, dateOf) => items.filter((i) => { const t = m.toDate(dateOf(i)); return t && t >= from && t <= to; }).length;
  return {
    range: { from: from.toISOString(), to: to.toISOString(), days },
    loadedAt: d.loadedAt,
    totals: {
      users: d.users.length,
      newUsers: within(d.users, (u) => u.createdAt),
      ...m.activeCounts(d.users),
      places: d.places.length,
      newPlaces: within(d.places, (p) => p.createdAt),
      checkIns: within(d.checkIns, (c) => c.createdAt || c.startTime),
      messages: within(d.messages, (x) => x.createdAt),
      newConnections: within(d.connections.filter((c) => c.status === 'accepted'), (c) => c.acceptedAt || c.createdAt),
      circles: d.circles.length
    },
    series: {
      signups: m.perDay(d.users, (u) => u.createdAt, chartFrom, to),
      places: m.perDay(d.places, (p) => p.createdAt, chartFrom, to),
      checkIns: m.perDay(d.checkIns, (c) => c.createdAt || c.startTime, chartFrom, to),
      messages: m.perDay(d.messages, (x) => x.createdAt, chartFrom, to),
      active: m.perDay([...activityByUser].flatMap(([, dates]) => [...new Set(dates.map(m.dayKey))].map((day) => ({ day: `${day}T12:00:00Z` }))), (x) => x.day, chartFrom, to)
    },
    funnel: m.funnel(d.users, counts, from, to),
    retention: m.retention(d.users, activityByUser, to)
  };
};

const userRow = (u, counts, suppressed) => {
  const c = counts.get(u.id) || {};
  const prefs = u.emailPreferences || {};
  return {
    id: u.id,
    name: u.displayName || '',
    email: u.email || '',
    photo: u.profilePicture || null,
    createdAt: m.toDate(u.createdAt) ? m.toDate(u.createdAt).toISOString() : null,
    lastSeen: m.lastSeen(u) ? m.lastSeen(u).toISOString() : null,
    places: c.places || 0,
    circles: c.circles || 0,
    connections: c.connections || 0,
    followers: Array.isArray(u.followers) ? u.followers.length : 0,
    following: Array.isArray(u.following) ? u.following.length : 0,
    push: m.pushState(u),
    emailStatus: suppressed.has(String(u.email || '').toLowerCase()) ? 'bounced'
      : Object.keys(prefs).filter((k) => prefs[k] === false).length ? `unsubscribed: ${Object.keys(prefs).filter((k) => prefs[k] === false).join(', ')}` : 'ok',
    plan: u.ownerSubscriptionStatus === 'active' ? 'Business' : (u.isPremium || ['active', 'trial'].includes(u.subscriptionStatus) ? 'Premium' : 'Free'),
    admin: u.isSuperUser === true,
    onboarded: u.onboardingCompleted === true
  };
};

const people = async (query = {}) => {
  const d = await load({ fresh: query.fresh === 'true' });
  const counts = perUserCounts(d);
  const suppressed = new Set(d.suppressions.map((s) => s.id));
  const q = String(query.q || '').trim().toLowerCase();
  let rows = d.users.map((u) => userRow(u, counts, suppressed));
  if (q) rows = rows.filter((r) => r.name.toLowerCase().includes(q) || r.email.toLowerCase().includes(q));
  const sort = String(query.sort || 'lastSeen');
  const val = (r) => (sort === 'createdAt' || sort === 'lastSeen' ? (r[sort] || '') : r[sort]);
  rows.sort((a, b) => (val(a) < val(b) ? 1 : val(a) > val(b) ? -1 : 0));
  return { total: rows.length, rows: rows.slice(0, 1000) };
};

const person = async (id, adminId) => {
  const d = await load();
  const user = d.users.find((u) => u.id === id);
  if (!user) return null;
  const counts = perUserCounts(d);
  const suppressed = new Set(d.suppressions.map((s) => s.id));
  // Recent activity, without anything only the owner should see
  const snap = await db().collection('activities').where('actorId', '==', id).orderBy('timestamp', 'desc').limit(60).get()
    .catch(() => ({ docs: [] }));
  const recent = snap.docs.map((doc) => doc.data())
    .filter((a) => !(a.metadata && a.metadata.ownerOnly))
    .slice(0, 40)
    .map((a) => ({ type: a.type, target: a.targetName || null, at: m.toDate(a.timestamp) ? m.toDate(a.timestamp).toISOString() : null }));
  db().collection('adminAuditLog').add({ adminId, action: 'view_person', targetUserId: id, at: new Date().toISOString() })
    .catch(() => {});
  return {
    ...userRow(user, counts, suppressed),
    messagesSent: d.messages.filter((x) => x.senderId === id).length,
    checkIns: d.checkIns.filter((c) => c.userId === id).length,
    recent
  };
};

const money = async (query = {}) => {
  const d = await load({ fresh: query.fresh === 'true' });
  const { from, to } = range(query);
  const subs = (key) => d.users.reduce((acc, u) => { const s = u[key] || 'none'; acc[s] = (acc[s] || 0) + 1; return acc; }, {});
  const clicks = d.partnerClicks.filter((c) => c.provider === 'opentable');
  return {
    postcards: m.postcardMoney(d.postcards.filter((o) => o.kind !== 'fridgemail')),
    fridgeMail: {
      plans: d.fridgePlans.length,
      activeSubscriptions: d.fridgePlans.filter((p) => p.subscription && p.subscription.status === 'active').length,
      cardsMailed: d.postcards.filter((o) => o.kind === 'fridgemail').length
    },
    subscriptions: { premium: subs('subscriptionStatus'), business: subs('ownerSubscriptionStatus') },
    favCoins: m.coinSummary(d.coins),
    opentable: {
      taps: clicks.length,
      matched: clicks.filter((c) => c.matched).length,
      byDay: m.perDay(clicks, (c) => c.at, from, to)
    },
    storeRewards: {
      stores: d.venues.length,
      visits: d.rewardEvents.filter((e) => e.type === 'venue_visit').length,
      redemptions: d.rewardEvents.filter((e) => e.type === 'redemption').length
    }
  };
};

const messaging = async (query = {}) => {
  const d = await load({ fresh: query.fresh === 'true' });
  const { from, to } = range(query);
  const reach = d.users.reduce((acc, u) => { const s = m.pushState(u); acc[s] = (acc[s] || 0) + 1; return acc; }, {});
  const unsubscribes = {};
  for (const u of d.users) for (const [k, v] of Object.entries(u.emailPreferences || {})) if (v === false) unsubscribes[k] = (unsubscribes[k] || 0) + 1;
  const campaigns = {};
  for (const u of d.users) for (const k of Object.keys(u.productUpdateEmails || {})) campaigns[k] = (campaigns[k] || 0) + 1;
  return {
    push: reach,
    fallback: {
      sent: d.fallbackLog.filter((x) => x.action === 'send').length,
      queued: d.fallbackLog.filter((x) => x.action === 'queue').length,
      byDay: m.perDay(d.fallbackLog.filter((x) => x.action === 'send'), (x) => x.at, from, to)
    },
    suppressions: d.suppressions.map((s) => ({ email: s.id, reason: s.reason || '', at: s.suppressedAt || null })),
    unsubscribes,
    campaigns
  };
};

module.exports = { load, overview, people, person, money, messaging, perUserCounts };
