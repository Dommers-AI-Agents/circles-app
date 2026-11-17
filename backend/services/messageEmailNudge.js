// backend/services/messageEmailNudge.js
//
// Unread messages come by email, the way Snapchat does it (Wes, 2026-11-17:
// "so users with notification settings not on will know"). A message still
// unread an hour after it arrived gets one email naming the sender, with the
// sender's photo and an "Open chat" button; still unread a day later, one
// reminder; then nothing until the next new message. This is for everyone
// with an unread message, pushes on or off.
//
// - One queue row per (recipient, conversation): messageEmailQueue/{uid}__{cid}.
//   A new message creates it if missing; reading the chat deletes it.
// - Every 15 minutes (tasks/message-emails) due rows are checked against the
//   conversation's unreadCounts; whatever is still unread for a person goes
//   out as ONE email, at most one an hour, never 10 pm–8 am their time.
// - Message text never goes in the email, only who sent it.
// - The email's own unsubscribe (kind "messageEmails") turns this off; hidden
//   test accounts never get it.
const { getFirestore } = require('../config/firebase');
const { localClock, localDateKey } = require('../utils/localClock');
const { isHiddenAccount } = require('./hiddenAccounts');
const emailService = require('./emailService');

const QUEUE = 'messageEmailQueue';
const STATE = 'messageEmailState';
const PREFERENCE_KEY = 'messageEmails';
const MINUTE = 60 * 1000;
const HOUR = 60 * MINUTE;
const FIRST_AFTER = HOUR;          // unread this long → first email
const REMINDER_AFTER = 24 * HOUR;  // still unread this long after → one reminder
const MIN_GAP = HOUR;              // at most one message email an hour per person
const DAILY_CAP = 4;
const QUIET_FROM = 22;             // local hours with no email
const QUIET_UNTIL = 8;
const BASE = 'https://api.favcircles.com';
const BRAND_BLUE = '#3478F6';
const NAVY = '#0F1E3A';
const AVATAR_COLORS = ['#5C82B5', '#6B9987', '#B8826B', '#8C78AD', '#C79959', '#7094A8', '#B37385', '#7A8C66'];

const db = () => getFirestore();
const queueId = (recipientId, conversationId) => `${recipientId}__${conversationId}`;

const esc = (s) => String(s == null ? '' : s)
  .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const clip = (s, n) => {
  const t = String(s || '').trim();
  return t.length > n ? `${t.slice(0, n - 1)}…` : t;
};
const firstName = (name) => clip(String(name || '').trim().split(/\s+/)[0] || 'Someone', 30);

// ---- queue

/** A new message for recipientId in conversationId. Keeps the earliest unread time. Never throws. */
const queue = (recipientId, conversationId, now = new Date()) => {
  if (!recipientId || !conversationId) return Promise.resolve();
  const ref = db().collection(QUEUE).doc(queueId(recipientId, conversationId));
  return db().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (snap.exists) return; // already waiting (first email or the reminder)
    tx.set(ref, {
      recipientId, conversationId, stage: 0,
      firstUnreadAt: now.toISOString(),
      dueAt: new Date(now.getTime() + FIRST_AFTER).toISOString()
    });
  }).catch((e) => console.warn(`📨 Message email queue failed for ${recipientId}: ${e.message}`));
};

/** The person read the chat: nothing to email about. Never throws. */
const cleared = (recipientId, conversationId) => {
  if (!recipientId || !conversationId) return Promise.resolve();
  return db().collection(QUEUE).doc(queueId(recipientId, conversationId)).delete()
    .catch(() => {});
};

// ---- pure decisions

/**
 * Pure: may this person get a message email now?
 * Returns { ok: true } or { ok: false, reason, keep } — keep = leave the rows
 * for a later run (quiet hours, spacing), otherwise drop them.
 */
const gate = ({ user, state, now = new Date() }) => {
  if (!user) return { ok: false, reason: 'no_user', keep: false };
  if (isHiddenAccount(user)) return { ok: false, reason: 'hidden_account', keep: false };
  const email = String(user.email || '').trim();
  if (!email.includes('@')) return { ok: false, reason: 'no_email', keep: false };
  if (user.emailPreferences && user.emailPreferences[PREFERENCE_KEY] === false) {
    return { ok: false, reason: 'unsubscribed', keep: false };
  }
  const zone = user.notificationPreferences && user.notificationPreferences.timezone;
  const { hour } = localClock(zone, now);
  if (hour >= QUIET_FROM || hour < QUIET_UNTIL) return { ok: false, reason: 'quiet_hours', keep: true };
  const last = state && state.lastSentAt ? Date.parse(state.lastSentAt) : 0;
  if (last && now.getTime() - last < MIN_GAP) return { ok: false, reason: 'recently_emailed', keep: true };
  const day = localDateKey(zone, now);
  if (state && state.day === day && (state.sentToday || 0) >= DAILY_CAP) {
    return { ok: false, reason: 'daily_cap', keep: true };
  }
  return { ok: true };
};

/** Pure: the state to save after sending one email. */
const afterSend = ({ user, state, now = new Date() }) => {
  const zone = user.notificationPreferences && user.notificationPreferences.timezone;
  const day = localDateKey(zone, now);
  const sentToday = state && state.day === day ? (state.sentToday || 0) : 0;
  return { day, sentToday: sentToday + 1, lastSentAt: now.toISOString() };
};

/** Pure: what happens to a queue row once its email went out. */
const nextForRow = (row, now = new Date()) => (row.stage === 0
  ? { action: 'update', data: { stage: 1, dueAt: new Date(now.getTime() + REMINDER_AFTER).toISOString(), emailedAt: now.toISOString() } }
  : { action: 'delete' });

const initials = (name) => {
  const words = String(name || '').trim().split(/\s+/).filter((w) => /^[\p{L}\p{N}]/u.test(w));
  if (words.length >= 2) return (words[0][0] + words[words.length - 1][0]).toUpperCase();
  return words.length ? words[0][0].toUpperCase() : '?';
};
const colorFor = (seed) => {
  let h = 5381;
  for (const ch of String(seed || '?')) h = ((h * 33) + ch.codePointAt(0)) >>> 0;
  return AVATAR_COLORS[h % AVATAR_COLORS.length];
};

/** Pure: the subject line for a set of unread chats. */
const subjectFor = (chats) => {
  const total = chats.reduce((n, c) => n + Math.max(1, c.unread || 1), 0);
  if (chats.length === 1) {
    const c = chats[0];
    const who = c.senderName || 'Someone';
    const where = c.groupName ? ` in ${clip(c.groupName, 40)}` : '';
    if (c.stage === 1) return `${firstName(who)} is waiting on your reply`;
    return total > 1 ? `${who} sent you ${total} messages${where}` : `${who} sent you a message${where}`;
  }
  const names = [...new Set(chats.map((c) => firstName(c.senderName)))];
  const from = names.length === 2 ? `${names[0]} and ${names[1]}`
    : names.length > 2 ? `${names[0]}, ${names[1]} and ${names.length - 2} more` : names[0];
  return `You have ${total} unread messages from ${from}`;
};

const ago = (iso, now) => {
  const mins = Math.max(1, Math.round((now.getTime() - Date.parse(iso)) / MINUTE));
  if (mins < 60) return `${mins} min ago`;
  const hrs = Math.round(mins / 60);
  if (hrs < 24) return `${hrs} hr ago`;
  const days = Math.round(hrs / 24);
  return `${days} day${days === 1 ? '' : 's'} ago`;
};

const avatarCell = (c, size) => (c.senderPhoto
  ? `<img src="${esc(c.senderPhoto)}" width="${size}" height="${size}" alt="" style="display:block;width:${size}px;height:${size}px;border-radius:50%;object-fit:cover;border:0;">`
  : `<table role="presentation" cellpadding="0" cellspacing="0"><tr><td width="${size}" height="${size}" align="center" valign="middle" style="width:${size}px;height:${size}px;border-radius:50%;background:${colorFor(c.senderId || c.senderName)};font-family:-apple-system,Helvetica,Arial,sans-serif;font-size:${Math.round(size * 0.4)}px;font-weight:700;color:#ffffff;">${esc(initials(c.senderName))}</td></tr></table>`);

const chatUrl = (c) => `${BASE}/app/messages/${encodeURIComponent(c.conversationId)}`;

/**
 * Pure: the email for one person's unread chats.
 * chats: [{ conversationId, stage, unread, senderId, senderName, senderPhoto, groupName, firstUnreadAt }]
 */
const buildEmail = ({ chats, unsubscribe, now = new Date() }) => {
  const subject = subjectFor(chats);
  const single = chats.length === 1;
  const rows = chats.map((c) => {
    const what = c.unread > 1 ? `${c.unread} new messages` : (c.stage === 1 ? 'Still unread' : 'New message');
    const where = c.groupName ? ` in ${esc(clip(c.groupName, 40))}` : '';
    return `<tr><td style="padding:12px 0;${single ? '' : 'border-top:1px solid #E6EAF1;'}">
      <a href="${chatUrl(c)}" style="text-decoration:none;color:#1A2438;">
      <table role="presentation" cellpadding="0" cellspacing="0" width="100%"><tr>
        <td width="${single ? 64 : 48}" valign="middle" style="padding-right:14px;">${avatarCell(c, single ? 64 : 48)}</td>
        <td valign="middle" style="font-family:-apple-system,Helvetica,Arial,sans-serif;">
          <div style="font-size:${single ? 18 : 16}px;line-height:24px;font-weight:700;color:#1A2438;">${esc(clip(c.senderName || 'Someone', 60))}${where}</div>
          <div style="font-size:14px;line-height:20px;color:#5B6780;"><span style="color:${BRAND_BLUE};font-weight:700;">&#9679;</span> ${esc(what)} &middot; ${esc(ago(c.firstUnreadAt, now))}</div>
        </td>
      </tr></table></a>
    </td></tr>`;
  }).join('');
  const target = single ? chatUrl(chats[0]) : `${BASE}/app/messages`;
  const heading = single
    ? (chats[0].stage === 1 ? `${esc(firstName(chats[0].senderName))} is still waiting on your reply`
      : (chats[0].unread > 1 ? 'You have new messages' : 'You have a new message'))
    : `${chats.length} chats are waiting for you`;
  const inner = `<div style="font-size:20px;line-height:27px;font-weight:800;">${heading}</div>
    <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="margin-top:10px;">${rows}</table>
    <table role="presentation" cellpadding="0" cellspacing="0" style="margin-top:18px;"><tr>
      <td style="background:${BRAND_BLUE};border-radius:22px;"><a href="${target}" style="display:inline-block;padding:12px 26px;font-size:15px;font-weight:700;color:#ffffff;text-decoration:none;">${single ? 'Open chat' : 'Open messages'}</a></td></tr></table>`;
  const html = `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background:#EEF1F6;">
<div style="display:none;max-height:0;overflow:hidden;opacity:0;">Open FavCircles to read it.</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#EEF1F6;"><tr><td align="center" style="padding:24px 12px;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;background:#ffffff;border-radius:16px;overflow:hidden;">
    <tr><td style="background:${NAVY};padding:16px 24px;">
      <table role="presentation" cellpadding="0" cellspacing="0"><tr>
        <td style="padding-right:10px;"><img src="https://favcircles.com/app-icon.png" width="26" height="26" alt="" style="display:block;border-radius:6px;border:0;"></td>
        <td style="font-family:-apple-system,Helvetica,Arial,sans-serif;font-size:16px;font-weight:800;color:#ffffff;">FavCircles</td>
      </tr></table>
    </td></tr>
    <tr><td style="padding:24px 24px 28px;font-family:-apple-system,Helvetica,Arial,sans-serif;color:#1A2438;">${inner}</td></tr>
  </table>
  <div style="max-width:520px;font-family:-apple-system,Helvetica,Arial,sans-serif;font-size:12px;line-height:18px;color:#8C97AB;padding:14px 12px 0;text-align:center;">
    You're getting this because you have unread messages on FavCircles.<br>
    <a href="${unsubscribe}" style="color:#8C97AB;">Stop emails about unread messages</a>
  </div>
</td></tr></table></body></html>`;
  const text = `${subject}\n\n${chats.map((c) => `- ${c.senderName || 'Someone'}: ${c.unread > 1 ? `${c.unread} new messages` : 'new message'}`).join('\n')}\n\nOpen it: ${target}\n\nStop emails about unread messages: ${unsubscribe}\n`;
  return { subject, html, text };
};

// ---- the scheduled run

const unsubscribeUrl = (userId) => {
  const { unsubscribeUrl: make } = require('./followSuggestionEmailService'); // lazy: touches Firestore on load
  return make(userId, PREFERENCE_KEY);
};

const pickPhoto = (u) => (u && (u.photoUrl || u.profileImageUrl || u.avatarUrl || u.photoURL)) || null;

/** Scheduled every 15 minutes: send whatever is due. */
const runDue = async ({ now = new Date(), log = console.log } = {}) => {
  const summary = { due: 0, people: 0, sent: 0, dropped: 0, waiting: 0 };
  const snap = await db().collection(QUEUE).where('dueAt', '<=', now.toISOString()).limit(500).get();
  summary.due = snap.size;
  const byRecipient = new Map();
  snap.docs.forEach((d) => {
    const row = { id: d.id, ref: d.ref, ...d.data() };
    if (!byRecipient.has(row.recipientId)) byRecipient.set(row.recipientId, []);
    byRecipient.get(row.recipientId).push(row);
  });

  for (const [recipientId, rows] of byRecipient) {
    summary.people += 1;
    try {
      const [userDoc, stateDoc] = await Promise.all([
        db().collection('users').doc(recipientId).get(),
        db().collection(STATE).doc(recipientId).get()
      ]);
      const user = userDoc.exists ? userDoc.data() : null;
      const state = stateDoc.exists ? stateDoc.data() : null;
      const g = gate({ user, state, now });
      if (!g.ok) {
        if (g.keep) { summary.waiting += rows.length; continue; }
        await Promise.all(rows.map((r) => r.ref.delete()));
        summary.dropped += rows.length;
        continue;
      }

      const chats = [];
      for (const row of rows) {
        const convDoc = await db().collection('conversations').doc(row.conversationId).get();
        const conv = convDoc.exists ? convDoc.data() : null;
        const unread = conv && conv.unreadCounts ? Number(conv.unreadCounts[recipientId] || 0) : 0;
        if (!conv || !(conv.participants || []).includes(recipientId) || unread <= 0) {
          await row.ref.delete();
          summary.dropped += 1;
          continue;
        }
        const senderId = conv.lastMessageSenderId && conv.lastMessageSenderId !== recipientId
          ? conv.lastMessageSenderId
          : (conv.participants || []).find((p) => p !== recipientId);
        const senderDoc = senderId ? await db().collection('users').doc(senderId).get() : null;
        const sender = senderDoc && senderDoc.exists ? senderDoc.data() : null;
        const isGroup = (conv.participants || []).length > 2 || conv.type === 'group' || conv.isGroup === true;
        chats.push({
          row,
          conversationId: row.conversationId,
          stage: row.stage || 0,
          unread,
          senderId,
          senderName: (sender && sender.displayName) || conv.lastMessageSenderName || 'Someone',
          senderPhoto: pickPhoto(sender),
          groupName: isGroup ? (conv.name || conv.groupName || null) : null,
          firstUnreadAt: row.firstUnreadAt || now.toISOString()
        });
      }
      if (chats.length === 0) continue;

      const unsubscribe = unsubscribeUrl(recipientId);
      const email = buildEmail({ chats, unsubscribe, now });
      await emailService.sendEmail({
        to: user.email, subject: email.subject, html: email.html, text: email.text,
        headers: { 'List-Unsubscribe': `<${unsubscribe}>`, 'List-Unsubscribe-Post': 'List-Unsubscribe=One-Click' }
      });
      await db().collection(STATE).doc(recipientId).set(afterSend({ user, state, now }));
      await Promise.all(chats.map(({ row }) => {
        const next = nextForRow(row, now);
        return next.action === 'delete' ? row.ref.delete() : row.ref.update(next.data);
      }));
      db().collection('emailFallbackLog').add({ type: 'unread_message', action: 'send', at: now.toISOString() }).catch(() => {});
      summary.sent += 1;
      log(`📨 Unread-message email to ${recipientId}: ${chats.length} chat(s)`);
    } catch (e) {
      console.warn(`📨 Unread-message email failed for ${recipientId}: ${e.message}`);
    }
  }
  return summary;
};

module.exports = {
  queue, cleared, runDue,
  // pure, for tests
  gate, afterSend, nextForRow, subjectFor, buildEmail, initials,
  PREFERENCE_KEY, FIRST_AFTER, REMINDER_AFTER, DAILY_CAP
};
