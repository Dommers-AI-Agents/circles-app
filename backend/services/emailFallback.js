// backend/services/emailFallback.js
//
// Email for people a push can't reach. iOS hands out a push token even when
// someone taps "Don't Allow" or later turns notifications off, so a token on
// file proves nothing; the app reports the real permission on every launch
// (users.pushStatus, see deviceTokenController.updatePushStatus). When a push
// is about something a person would want to know (a new follower, a comment,
// a tag, a suggestion) and they can't get pushes, it comes by
// email instead.
//
// Not spam, by rule:
// - only the types in EMAIL_TYPES; likes, "X added a place", prompts, tips
//   and summaries never email
// - one email per conversation / place / activity per GAP hours
// - at most DAILY_CAP a day; the rest wait for one evening round-up
// - their in-app notification switches still apply, the one-click
//   unsubscribe (kind "activityEmails") turns all of it off, and bounced
//   addresses are skipped by the suppression list on the transport
//
// Connection requests and acceptances are not here: those already email
// every recipient (Wes, 2026-10-01: keep emailing everyone).
//
// A store's alerts (its new specials, events and announcements, to people
// who turned on its bell) are here since 2026-11-26: a customer who joined
// on the store's web page has no app at all (there is no Android app), so
// email is the only way the store reaches them. Those are the store's own
// emails: already at most one per store per day (services/placeAlerts), so
// they don't use the daily cap or the round-up, their unsubscribe kind is
// "storeNudges", and each one can stop just that store.
const { getFirestore } = require('../config/firebase');
const { localDateKey, localClock } = require('../utils/localClock');
const emailService = require('./emailService');

const STATE = 'emailFallbackState';
const PREFERENCE_KEY = 'activityEmails';
const STORE_PREFERENCE_KEY = 'storeNudges'; // "emails from stores" (emailPreferenceRoutes)
const DAILY_CAP = 3;
const DIGEST_HOUR = 19;          // the evening round-up, user-local
const MAX_PENDING = 25;
const BASE = 'https://api.favcircles.com';
const BRAND_BLUE = '#3478F6';
const NAVY = '#0F1E3A';

const db = () => getFirestore();
const HOUR = 60 * 60 * 1000;

const STORE_KINDS = { offer: 'New reward', event: 'New event', announcement: 'News' };
/** "Sal's Bakery: Half-price wine tonight" (the push's own words, on one line) */
const storeLine = (n) => {
  const data = n.data || {};
  const name = String(data.storeName || '').trim();
  const headline = String(data.headline || '').trim();
  if (name && headline) return `${name}: ${headline}`;
  return [n.title, n.body].filter(Boolean).join(': ') || 'News from a store you follow';
};
const storeDetail = (n) => {
  const data = n.data || {};
  const label = STORE_KINDS[data.kind] || null;
  const message = String(data.message || '').trim();
  if (data.kind === 'offer') return label;
  return message && message !== String(data.headline || '').trim() ? clip(message, 220) : label;
};

const esc = (s) => String(s == null ? '' : s)
  .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

const clip = (s, n) => {
  const t = String(s || '').trim();
  return t.length > n ? `${t.slice(0, n - 1)}…` : t;
};

/**
 * One row per type: how to describe it, what groups repeats, how long a
 * group stays quiet after an email, and where the button goes. `n` is the
 * push payload ({ type, title, body, data }).
 */
const EMAIL_TYPES = {
  // new_message is not here: every unread message, pushes on or off, is
  // emailed by services/messageEmailNudge (Wes, 2026-11-17).
  new_follower: {
    gapHours: 0,
    key: (n) => `follow:${(n.data && n.data.fromUserId) || 'any'}`,
    line: (n) => clip(n.body || n.title || 'You have a new follower', 120),
    detail: () => null,
    url: (n) => (n.data && n.data.fromUserId ? `${BASE}/user/${encodeURIComponent(n.data.fromUserId)}` : `${BASE}/app/open`),
    button: 'See their places'
  },
  place_comment: {
    gapHours: 1,
    key: (n) => `placec:${(n.data && n.data.placeId) || 'any'}`,
    line: (n) => clip(n.title || 'New comment on your place', 120),
    detail: (n) => (n.body ? `“${clip(n.body, 140)}”` : null),
    url: (n) => (n.data && n.data.placeId ? `${BASE}/place/${encodeURIComponent(n.data.placeId)}` : `${BASE}/app/open`),
    button: 'See the comment'
  },
  activity_comment: {
    gapHours: 1,
    key: (n) => `actc:${(n.data && n.data.activityId) || 'any'}`,
    line: (n) => clip(n.body || 'Someone commented on your activity', 120),
    detail: () => null,
    url: () => `${BASE}/app/open`,
    button: 'See the comment'
  },
  moment_tag: {
    appOnly: true,
    gapHours: 0,
    key: (n) => `tag:${(n.data && n.data.videoId) || 'any'}`,
    line: (n) => clip(n.body || 'You were tagged in a Moment', 120),
    detail: () => null,
    url: (n) => (n.data && n.data.videoId ? `${BASE}/video/${encodeURIComponent(n.data.videoId)}` : `${BASE}/app/open`),
    button: 'Watch it'
  },
  new_suggestion: {
    gapHours: 1,
    key: (n) => `sugg:${(n.data && n.data.suggestionId) || 'any'}`,
    line: (n) => clip(n.body || 'Someone suggested a place for you', 140),
    detail: () => null,
    url: () => `${BASE}/app/open`,
    button: 'Take a look'
  },
  // A store's new special, event or announcement (services/placeAlerts).
  // Someone with the app (notifications off) lands on the store in the app;
  // someone who joined on the store's web page has no app, so their button
  // opens that page, where their points are.
  store_alert: {
    gapHours: 0,
    store: true,
    preference: STORE_PREFERENCE_KEY,
    key: (n) => `store:${(n.data && n.data.placeId) || 'any'}`,
    line: (n) => clip(storeLine(n), 140),
    detail: (n) => storeDetail(n),
    url: (n, user) => {
      const web = require('./storeWebEmails');
      if (web.isWebOnly(user) && n.data && n.data.storeCode) return web.storePageUrl(n.data.storeCode);
      return n.data && n.data.placeId ? `${BASE}/place/${encodeURIComponent(n.data.placeId)}` : `${BASE}/app/open`;
    },
    button: (n, user) => (require('./storeWebEmails').isWebOnly(user) ? 'Open my points there' : 'See it')
  }
};

const preferenceFor = (spec) => (spec && spec.preference) || PREFERENCE_KEY;

// Statuses the app reports that mean a push will actually show
const REACHABLE = new Set(['authorized', 'provisional', 'ephemeral']);

/**
 * Pure: can a push reach this person? No token = no. A reported status of
 * denied / notDetermined = no. A token with no report yet (an older build)
 * is treated as reachable, which is how it has always behaved.
 */
const pushReachable = (user) => {
  const tokens = Array.isArray(user.deviceTokens) ? user.deviceTokens : [];
  if (tokens.length === 0) return false;
  const status = user.pushStatus && user.pushStatus.status;
  if (!status) return true;
  return REACHABLE.has(status);
};

/**
 * Pure: what to do with one notification for one person, given their saved
 * state. Returns { action: 'send' | 'queue' | 'skip', reason, next } where
 * `next` is the state to save.
 */
const decide = ({ notification, user, state, now = new Date() }) => {
  const spec = EMAIL_TYPES[notification.type];
  if (!spec) return { action: 'skip', reason: 'type_not_emailed' };
  if (pushReachable(user)) return { action: 'skip', reason: 'push_reachable' };
  const email = String(user.email || '').trim();
  if (!email.includes('@')) return { action: 'skip', reason: 'no_email' };
  // Nobody should hear from a test or closed account (services/hiddenAccounts).
  // A store's email skips Apple's relay addresses, as store nudges do.
  if (require('./hiddenAccounts').isHiddenAccount(user)) return { action: 'skip', reason: 'hidden_account' };
  if (spec.store && /@privaterelay\.appleid\.com$/i.test(email)) return { action: 'skip', reason: 'relay_address' };
  // Joined on the web and has no app: everything here opens in the web app
  // (routes/webAppRoutes sends the links there) except a Moment, which only
  // the iOS app plays
  if (spec.appOnly && require('./storeWebEmails').isWebOnly(user)) return { action: 'skip', reason: 'web_only' };
  if (user.emailPreferences && user.emailPreferences[preferenceFor(spec)] === false) return { action: 'skip', reason: 'unsubscribed' };

  const zone = user.notificationPreferences && user.notificationPreferences.timezone;
  const day = localDateKey(zone, now);
  const base = state && state.day === day ? state : { ...(state || {}), day, sentToday: 0 };
  const lastByKey = { ...(base.lastByKey || {}) };
  const key = spec.key(notification);
  const last = lastByKey[key] ? Date.parse(lastByKey[key]) : 0;
  if (spec.gapHours > 0 && last && now.getTime() - last < spec.gapHours * HOUR) {
    return { action: 'skip', reason: 'recently_emailed_about_this' };
  }
  lastByKey[key] = now.toISOString();
  const item = {
    type: notification.type,
    line: spec.line(notification),
    detail: spec.detail(notification),
    url: spec.url(notification, user),
    at: now.toISOString()
  };
  const buttonLabel = typeof spec.button === 'function' ? spec.button(notification, user) : spec.button;
  // A store's email: the store is already held to one a day, so it neither
  // waits for the round-up nor uses up the day's other emails
  if (spec.store) {
    const placeId = (notification.data && notification.data.placeId) || null;
    const storeName = (notification.data && notification.data.storeName) || null;
    return { action: 'send', item: { ...item, store: { placeId, name: storeName } }, button: buttonLabel, next: { ...base, lastByKey } };
  }
  if ((base.sentToday || 0) < DAILY_CAP) {
    return { action: 'send', item, button: buttonLabel, next: { ...base, lastByKey, sentToday: (base.sentToday || 0) + 1 } };
  }
  const pending = [...(base.pending || []), item].slice(-MAX_PENDING);
  return { action: 'queue', item, next: { ...base, lastByKey, pending } };
};

// ---- the email

const unsubscribeUrl = (userId) => {
  const { unsubscribeUrl: make } = require('./followSuggestionEmailService'); // lazy: touches Firestore on load
  return make(userId, PREFERENCE_KEY);
};

const phoneFooter = (unsub) => `You're getting this because notifications are off for FavCircles on your phone.<br>
    Turn them on in Settings › FavCircles › Notifications, or <a href="${unsub}" style="color:#8C97AB;">stop these emails</a>.`;

const shell = ({ preheader, inner, unsub, footer }) => `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background:#EEF1F6;">
<div style="display:none;max-height:0;overflow:hidden;opacity:0;">${esc(preheader)}</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#EEF1F6;"><tr><td align="center" style="padding:24px 12px;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;background:#ffffff;border-radius:16px;overflow:hidden;">
    <tr><td style="background:${NAVY};padding:16px 24px;">
      <table role="presentation" cellpadding="0" cellspacing="0"><tr>
        <td style="padding-right:10px;"><img src="https://favcircles.com/app-icon.png" width="26" height="26" alt="" style="display:block;border-radius:6px;border:0;"></td>
        <td style="font-family:-apple-system,Helvetica,Arial,sans-serif;font-size:16px;font-weight:800;color:#ffffff;">FavCircles</td>
      </tr></table>
    </td></tr>
    <tr><td style="padding:26px 24px 28px;font-family:-apple-system,Helvetica,Arial,sans-serif;color:#1A2438;">${inner}</td></tr>
  </table>
  <div style="max-width:520px;font-family:-apple-system,Helvetica,Arial,sans-serif;font-size:12px;line-height:18px;color:#8C97AB;padding:14px 12px 0;text-align:center;">
    ${footer || phoneFooter(unsub)}
  </div>
</td></tr></table></body></html>`;

const button = (label, url) => `<table role="presentation" cellpadding="0" cellspacing="0" style="margin-top:20px;"><tr>
  <td style="background:${BRAND_BLUE};border-radius:10px;"><a href="${url}" style="display:inline-block;padding:12px 22px;font-size:15px;font-weight:700;color:#ffffff;text-decoration:none;">${esc(label)}</a></td></tr></table>`;

/**
 * Pure: a store's alert as an email. Its links stop that one store, or
 * every store's emails; neither needs a login.
 */
const buildStore = ({ userId, item, buttonLabel }) => {
  const web = require('./storeWebEmails');
  const { unsubscribeUrl: make } = require('./followSuggestionEmailService');
  const allStores = make(userId, STORE_PREFERENCE_KEY);
  const stop = item.store.placeId ? web.stopUrl(userId, item.store.placeId) : allStores;
  const name = item.store.name || 'this store';
  const inner = `<div style="font-size:19px;line-height:26px;font-weight:700;">${esc(item.line)}</div>
    ${item.detail ? `<div style="font-size:15px;line-height:22px;color:#5B6780;margin-top:8px;">${esc(item.detail)}</div>` : ''}
    ${button(buttonLabel || 'See it', item.url)}`;
  const footer = `You're getting this because you asked for emails from ${esc(name)}.<br>
    <a href="${stop}" style="color:#8C97AB;">Stop emails from this store</a> · <a href="${allStores}" style="color:#8C97AB;">Stop emails from all stores</a>`;
  return {
    subject: item.line,
    html: shell({ preheader: item.detail || `From ${name}`, inner, unsub: stop, footer }),
    text: `${item.line}${item.detail ? `\n${item.detail}` : ''}\n\n${item.url}\n\nStop emails from this store: ${stop}\nStop emails from all stores: ${allStores}\n`,
    unsubscribe: stop
  };
};

/** Pure: one notification as an email. */
const buildSingle = ({ userId, item, buttonLabel }) => {
  if (item.store) return buildStore({ userId, item, buttonLabel });
  const unsub = unsubscribeUrl(userId);
  const inner = `<div style="font-size:19px;line-height:26px;font-weight:700;">${esc(item.line)}</div>
    ${item.detail ? `<div style="font-size:15px;line-height:22px;color:#5B6780;margin-top:8px;">${esc(item.detail)}</div>` : ''}
    ${button(buttonLabel || 'Open FavCircles', item.url)}`;
  return {
    subject: item.line,
    html: shell({ preheader: item.detail || 'Open FavCircles to see it.', inner, unsub }),
    text: `${item.line}${item.detail ? `\n${item.detail}` : ''}\n\n${item.url}\n\nNotifications are off for FavCircles on your phone. Stop these emails: ${unsub}\n`,
    unsubscribe: unsub
  };
};

/** Pure: the evening round-up of what didn't fit in the day's emails. */
const buildDigest = ({ userId, items }) => {
  const unsub = unsubscribeUrl(userId);
  const n = items.length;
  const rows = items.map((i) => `<tr><td style="padding:10px 0;border-top:1px solid #E6EAF1;">
      <a href="${i.url}" style="font-size:15px;line-height:21px;color:#1A2438;text-decoration:none;font-weight:600;">${esc(i.line)}</a>
      ${i.detail ? `<div style="font-size:13px;color:#5B6780;margin-top:2px;">${esc(i.detail)}</div>` : ''}
    </td></tr>`).join('');
  const inner = `<div style="font-size:19px;line-height:26px;font-weight:700;">${n} more ${n === 1 ? 'thing' : 'things'} on FavCircles today</div>
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin-top:12px;">${rows}</table>
    ${button('Open FavCircles', `${BASE}/app/open`)}`;
  return {
    subject: `${n} more ${n === 1 ? 'update' : 'updates'} from FavCircles today`,
    html: shell({ preheader: items[0] ? items[0].line : '', inner, unsub }),
    text: `${items.map((i) => `- ${i.line}`).join('\n')}\n\n${BASE}/app/open\n\nStop these emails: ${unsub}\n`,
    unsubscribe: unsub
  };
};

const send = async (to, email, kind) => emailService.sendEmail({
  to, subject: email.subject, html: email.html, text: email.text, ...(kind ? { kind } : {}),
  headers: { 'List-Unsubscribe': `<${email.unsubscribe}>`, 'List-Unsubscribe-Post': 'List-Unsubscribe=One-Click' }
});

/**
 * Called from notificationService.sendToUser with the user doc it already
 * read. Never throws and never delays the push path.
 */
const maybeEmail = (userId, user, notification) => {
  if (!EMAIL_TYPES[notification.type] || pushReachable(user)) return;
  (async () => {
    const ref = db().collection(STATE).doc(userId);
    let outcome = null;
    await db().runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      outcome = decide({ notification, user, state: snap.exists ? snap.data() : null });
      if (outcome.next) tx.set(ref, outcome.next);
    });
    if (outcome.action !== 'skip') {
      // Counts for the admin dashboard (no addresses, no content)
      db().collection('emailFallbackLog').add({ type: notification.type, action: outcome.action, at: new Date().toISOString() })
        .catch(() => {});
    }
    if (outcome.action === 'send') {
      await send(user.email, buildSingle({ userId, item: outcome.item, buttonLabel: outcome.button }),
        outcome.item.store ? 'store_alert' : null);
      console.log(`📨 Email fallback sent to ${userId} (${notification.type})`);
    } else {
      console.log(`📨 Email fallback ${outcome.action} for ${userId} (${notification.type}): ${outcome.reason || 'queued for the evening'}`);
    }
  })().catch((e) => console.warn(`📨 Email fallback failed for ${userId}: ${e.message}`));
};

/**
 * Scheduled hourly: everyone with queued items whose local hour is the
 * digest hour gets one round-up, then the queue is cleared.
 */
const runDigests = async ({ now = new Date(), log = console.log } = {}) => {
  const snap = await db().collection(STATE).get();
  const summary = { checked: 0, sent: 0, waiting: 0, skipped: 0 };
  for (const doc of snap.docs) {
    const state = doc.data();
    if (!state.pending || state.pending.length === 0) continue;
    summary.checked++;
    const userSnap = await db().collection('users').doc(doc.id).get();
    const user = userSnap.exists ? userSnap.data() : null;
    if (!user || !user.email || (user.emailPreferences && user.emailPreferences[PREFERENCE_KEY] === false)) {
      await doc.ref.update({ pending: [] });
      summary.skipped++;
      continue;
    }
    const zone = user.notificationPreferences && user.notificationPreferences.timezone;
    if (localClock(zone, now).hour !== DIGEST_HOUR) { summary.waiting++; continue; }
    try {
      await send(user.email, buildDigest({ userId: doc.id, items: state.pending }));
      await doc.ref.update({ pending: [], lastDigestAt: now.toISOString() });
      summary.sent++;
    } catch (e) {
      log(`📨 Digest for ${doc.id} failed: ${e.message}`);
    }
  }
  log(`📨 Email fallback digests: ${JSON.stringify(summary)}`);
  return summary;
};

module.exports = {
  EMAIL_TYPES, PREFERENCE_KEY, STORE_PREFERENCE_KEY, DAILY_CAP, pushReachable, decide, buildSingle, buildStore, buildDigest, maybeEmail, runDigests
};
