// backend/services/storeWelcomeEmailService.js
// The first email for someone who joined from a store's QR code (Wes,
// 2026-10-31): welcome to FavCircles, the store they just joined at (its
// photo, and the points they earned and its rewards only when the store's
// rewards are live), what the app does, a few people to follow so their map
// fills up, and Get the app. It replaces the generic welcome email for these
// accounts, and the store's scan is what sends it, so it knows the points.
// Once per account (storeWelcomeEmailAt).
const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');
const { escapeHtml: esc } = require('../utils/text');
const rewardConfig = require('../config/rewardConfig');

const BASE_URL = 'https://api.favcircles.com';
const INK = '#1B1E24';
const GOLD = '#F6C945';
const PEOPLE = 4;
const HIDDEN_TIERS = new Set(['innerCircle', 'private']);

const db = () => getFirestore();

/** True when this account's first email is the store welcome (a store code, not the generic one) */
const isStoreSignup = (user) => !!(user && user.acquisitionSource === 'app_clip'
  && user.acquisitionVenueId && user.acquisitionGeneric !== true);

/**
 * The generic welcome email, unless this account gets the store welcome
 * instead. Every generic-welcome call site goes through here.
 */
async function sendGenericWelcome(userId, email, displayName) {
  if (!email) return;
  try {
    const doc = userId ? await db().collection(COLLECTIONS.USERS).doc(userId).get() : null;
    if (doc && doc.exists && isStoreSignup(doc.data())) return;
  } catch (error) {
    console.warn('⚠️ Welcome email: user lookup failed, sending the generic one:', error.message);
  }
  await require('./emailService').sendWelcomeEmail(email, displayName);
}

/**
 * Up to PEOPLE people to follow: those who saved this store (visibly), then
 * people who save the most places near it. Never the new user, test/hidden
 * accounts, or nameless ones. Each with a one-line reason.
 */
async function peopleFor(user, venue) {
  const { isHiddenAccount } = require('./hiddenAccounts');
  const reasons = new Map();
  if (venue.globalPlaceId) {
    const saves = await db().collection(COLLECTIONS.PLACES)
      .where('globalPlaceId', '==', venue.globalPlaceId)
      .select('addedBy', 'privacy', 'deletedAt').limit(60).get();
    for (const doc of saves.docs) {
      const p = doc.data();
      if (!p.addedBy || p.deletedAt || HIDDEN_TIERS.has(p.privacy) || reasons.has(p.addedBy)) continue;
      reasons.set(p.addedBy, `Saved ${venue.venueName}`);
    }
  }
  const loc = venue.location || {};
  const latitude = Number(loc.lat ?? loc.latitude);
  const longitude = Number(loc.lng ?? loc.longitude);
  if (reasons.size < PEOPLE * 3 && Number.isFinite(latitude) && Number.isFinite(longitude)) {
    const counts = await require('./localPeople').localSaverCounts({ latitude, longitude });
    for (const [id, n] of [...counts.entries()].sort((a, b) => b[1] - a[1]).slice(0, PEOPLE * 4)) {
      if (!reasons.has(id)) reasons.set(id, `Saves ${n} ${n === 1 ? 'place' : 'places'} near ${venue.venueName}`);
    }
  }
  reasons.delete(user.id);
  const ids = [...reasons.keys()].slice(0, PEOPLE * 4);
  if (!ids.length) return [];
  const docs = await db().getAll(...ids.map((id) => db().collection(COLLECTIONS.USERS).doc(id)));
  const people = [];
  for (const doc of docs) {
    if (!doc.exists) continue;
    const u = { id: doc.id, ...doc.data() };
    const name = String(u.displayName || '').trim();
    if (isHiddenAccount(u) || !name || name.includes('@') || u.deletedAt) continue;
    people.push({ userId: u.id, displayName: name, profilePicture: u.profilePicture || null, reason: reasons.get(u.id) });
    if (people.length === PEOPLE) break;
  }
  return people;
}

/** Pure: the email. `store` = {name, address, photoUrl, placeUrl}; `rewards` only when live. */
function buildEmail({ user, store, awardedPoints = 0, rewards = null, people = [] }) {
  const first = String(user.displayName || '').trim().split(/\s+/)[0];
  const greeting = first && !first.includes('@') ? `Hi ${first},` : 'Hi there,';
  const appUrl = rewardConfig.APP_STORE_URL;
  const subject = `Welcome to FavCircles — ${store.name} is on your map`;

  const photo = store.photoUrl
    ? `<img src="${esc(store.photoUrl)}" alt="" width="512" style="width:100%;max-width:512px;height:auto;border-radius:14px;display:block;">`
    : '';
  const pointsLine = awardedPoints > 0
    ? `<p style="font-size:17px;font-weight:700;color:${INK};margin:14px 0 2px;">+${awardedPoints} points at ${esc(store.name)}</p>`
    : '';
  const rewardRows = rewards ? rewards.offers.map((o) => `
      <tr><td style="padding:6px 0;font-size:15px;color:${INK};">${esc(o.title)}</td>
          <td style="padding:6px 0;font-size:15px;color:#4a5568;text-align:right;white-space:nowrap;">${o.pointsCost} points</td></tr>`).join('') : '';
  const rewardsBlock = rewards ? `
      <div style="background:#F7F5EE;border-radius:12px;padding:14px 16px;margin:14px 0;">
        <div style="font-size:12px;font-weight:700;letter-spacing:.06em;color:#9A7B12;">KEEP EARNING</div>
        <p style="font-size:15px;line-height:1.5;margin:6px 0 10px;">Every visit earns ${rewards.earnRate} points. Scan the code at the register, right in the app or with your camera.${rewards.balance ? ` You have ${rewards.balance} points here.` : ''}</p>
        ${rewardRows ? `<div style="font-size:12px;font-weight:700;letter-spacing:.06em;color:#9A7B12;">REWARDS AT ${esc(store.name.toUpperCase())}</div>
        <table role="presentation" cellpadding="0" cellspacing="0" style="width:100%;border-collapse:collapse;">${rewardRows}</table>` : ''}
      </div>` : '';
  const peopleRows = people.map((p) => {
    const avatar = p.profilePicture
      ? `<img src="${esc(p.profilePicture)}" width="44" height="44" alt="" style="width:44px;height:44px;border-radius:22px;object-fit:cover;display:block;">`
      : `<div style="width:44px;height:44px;border-radius:22px;background:#EEF1F5;color:${INK};font-weight:700;font-size:18px;line-height:44px;text-align:center;">${esc(p.displayName.charAt(0).toUpperCase())}</div>`;
    return `
      <tr>
        <td style="padding:10px 0;border-top:1px solid #EEF1F5;width:44px;vertical-align:middle;">${avatar}</td>
        <td style="padding:10px 12px;border-top:1px solid #EEF1F5;vertical-align:middle;">
          <div style="font-size:15px;font-weight:600;color:${INK};">${esc(p.displayName)}</div>
          <div style="font-size:13px;color:#4a5568;">${esc(p.reason)}</div>
        </td>
        <td style="padding:10px 0;border-top:1px solid #EEF1F5;text-align:right;vertical-align:middle;white-space:nowrap;">
          <a href="${BASE_URL}/user/${encodeURIComponent(p.userId)}" style="display:inline-block;background:${INK};color:#fff;text-decoration:none;font-weight:600;font-size:13px;padding:8px 14px;border-radius:8px;">Follow</a>
        </td>
      </tr>`;
  }).join('');
  const peopleBlock = people.length ? `
      <h2 style="font-family:Georgia,serif;font-size:20px;margin:26px 0 4px;color:${INK};">Build your map with people nearby</h2>
      <p style="font-size:14px;line-height:1.5;color:#4a5568;margin:0 0 8px;">Follow them and their favorite places show up on your map.</p>
      <table role="presentation" cellpadding="0" cellspacing="0" style="width:100%;border-collapse:collapse;border-bottom:1px solid #EEF1F5;">${peopleRows}</table>` : '';

  const html = `
    <div style="font-family:-apple-system,Helvetica,Arial,sans-serif;max-width:560px;margin:0 auto;padding:24px;color:${INK};">
      <div style="background:${INK};border-radius:16px;padding:22px 22px 18px;">
        <div style="font-family:Georgia,serif;font-weight:700;font-size:28px;line-height:1.15;color:#fff;">Welcome to FavCircles.</div>
        <div style="font-family:Georgia,serif;font-weight:700;font-size:28px;line-height:1.15;color:${GOLD};">You saved ${esc(store.name)}.</div>
        <div style="font-family:Georgia,serif;font-style:italic;font-size:14px;color:${GOLD};margin-top:10px;">It's your road, the road less traveled. Save it.</div>
      </div>
      <p style="font-size:15px;line-height:1.6;margin:18px 0 10px;">${esc(greeting)}</p>
      ${photo}
      <p style="font-size:16px;font-weight:600;margin:12px 0 0;"><a href="${esc(store.placeUrl)}" style="color:${INK};text-decoration:none;">${esc(store.name)}</a></p>
      ${store.address ? `<p style="font-size:13px;color:#4a5568;margin:2px 0 0;">${esc(store.address)}</p>` : ''}
      ${pointsLine}
      ${rewardsBlock}
      <h2 style="font-family:Georgia,serif;font-size:20px;margin:24px 0 6px;color:${INK};">What FavCircles does</h2>
      <ul style="font-size:15px;line-height:1.7;padding-left:20px;margin:0;">
        <li><strong>Save your favorite places</strong> in circles, so you never forget a spot.</li>
        <li><strong>Your own map</strong> of your places and the places of people you follow.</li>
        <li><strong>Rewards</strong> at local stores: collect points and spend them on real things.</li>
        <li><strong>Locals</strong>: specials and events near you.</li>
      </ul>
      ${peopleBlock}
      <div style="text-align:center;margin:26px 0 8px;">
        <a href="${appUrl}" style="display:inline-block;background:${GOLD};color:${INK};text-decoration:none;font-weight:700;font-size:16px;padding:14px 28px;border-radius:12px;">Get the FavCircles app</a>
      </div>
      <p style="font-size:13px;color:#4a5568;text-align:center;margin:6px 0 18px;">Sign in with the same email and ${esc(store.name)} is already on your map.</p>
      <p style="font-size:15px;line-height:1.6;">— Wesley &amp; the FavCircles team</p>
      <p style="font-size:12px;color:#a0aec0;line-height:1.5;">You're getting this because you joined FavCircles at ${esc(store.name)}. Didn't sign up? You can ignore this email.</p>
    </div>`;

  const text = [
    'Welcome to FavCircles.', `You saved ${store.name}.`, '', greeting, '',
    store.name, store.address || '',
    awardedPoints > 0 ? `+${awardedPoints} points at ${store.name}` : '',
    rewards ? `Every visit earns ${rewards.earnRate} points. Scan the code at the register.` : '',
    ...(rewards ? rewards.offers.map((o) => `- ${o.title}: ${o.pointsCost} points`) : []),
    '', 'What FavCircles does:',
    '- Save your favorite places in circles, so you never forget a spot.',
    '- Your own map of your places and the places of people you follow.',
    '- Rewards at local stores: collect points and spend them on real things.',
    '- Locals: specials and events near you.',
    ...(people.length ? ['', 'People to follow:', ...people.map((p) => `- ${p.displayName} (${p.reason}): ${BASE_URL}/user/${encodeURIComponent(p.userId)}`)] : []),
    '', `Get the FavCircles app: ${appUrl}`, '', '— Wesley & the FavCircles team'
  ].filter((line, i, all) => line !== '' || all[i - 1] !== '').join('\n');

  return { subject, html, text };
}

/**
 * After a store-code scan: sends the store welcome if this is the store the
 * account joined at and it hasn't had one. Fire-and-forget from the scan.
 */
async function maybeSendAfterScan(userId, venue, { awardedPoints = 0, balance = 0 } = {}) {
  try {
    if (!venue || venue.genericJoin) return { sent: false, reason: 'generic' };
    const userRef = db().collection(COLLECTIONS.USERS).doc(userId);
    const snap = await userRef.get();
    if (!snap.exists) return { sent: false, reason: 'no_user' };
    const user = { id: snap.id, ...snap.data() };
    if (!isStoreSignup(user) || user.acquisitionVenueId !== venue.venueId) return { sent: false, reason: 'not_this_store' };
    if (user.storeWelcomeEmailAt) return { sent: false, reason: 'already_sent' };
    if (!user.email || /@privaterelay\.appleid\.com$/i.test(user.email)) return { sent: false, reason: 'no_email' };

    // Once per account, even when two scans race
    const claimed = await db().runTransaction(async (tx) => {
      const fresh = await tx.get(userRef);
      if (!fresh.exists || fresh.data().storeWelcomeEmailAt) return false;
      tx.update(userRef, { storeWelcomeEmailAt: new Date().toISOString() });
      return true;
    });
    if (!claimed) return { sent: false, reason: 'already_sent' };

    const { registerScanEarns } = require('./ownerSubscriptionService');
    const { activeOffers } = require('./venueHelpers');
    const rewardProgress = require('./rewardProgress');
    const rewardService = require('./rewardService');
    const [photoUrl, earns, people] = await Promise.all([
      require('./placePhotoService').venueCoverUrl(venue).catch(() => null),
      registerScanEarns(venue).then((r) => r.earns).catch(() => false),
      peopleFor(user, venue).catch((e) => { console.warn('⚠️ Store welcome: people lookup failed:', e.message); return []; })
    ]);
    const rewards = earns ? {
      earnRate: rewardService.effectiveEarnRate(venue),
      offers: rewardProgress.rewardLadder(activeOffers(venue)).slice(0, 4),
      balance
    } : null;
    const store = {
      name: venue.venueName,
      address: venue.placeAddress || null,
      photoUrl,
      placeUrl: venue.globalPlaceId ? `${BASE_URL}/place/${encodeURIComponent(venue.globalPlaceId)}` : BASE_URL
    };
    const email = buildEmail({ user, store, awardedPoints, rewards, people });
    await require('./emailService').sendEmail({ to: user.email, subject: email.subject, html: email.html, text: email.text });
    console.log(`🏪 Store welcome email sent for ${venue.venueName} (${people.length} people)`);
    return { sent: true };
  } catch (error) {
    console.error('⚠️ Store welcome email failed:', error.message);
    return { sent: false, reason: 'error' };
  }
}

module.exports = { isStoreSignup, sendGenericWelcome, peopleFor, buildEmail, maybeSendAfterScan };
