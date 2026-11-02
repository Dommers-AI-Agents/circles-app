// services/nextStepService.js
//
// Phase 4 of "never a dead end" (Wes, 2026-11-02): the server picks which
// next steps a person sees first, from what they do. The app offers the
// steps that fit each moment; this ranks them (and can add a step that
// matters for this person anywhere, like a reward ready to use).
//
// Signals: how many people they follow, how many places they've saved,
// whether they've posted a moment, a store reward ready to redeem, and the
// steps they keep skipping (shown 4+ times, never tapped → last).

const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');

const STEP_IDS = ['my_rewards', 'find_people', 'add_place', 'post_moment', 'scan_for_points',
  'see_on_map', 'add_more_like_it', 'my_check_ins', 'see_their_map', 'see_moments', 'share_it',
  'preview_store', 'print_codes', 'explore', 'open_chat'];
// Steps the app may add to any moment when they matter for this person
const BOOSTABLE = new Set(['my_rewards', 'find_people', 'add_place', 'post_moment']);
const SKIPPED_AFTER = 4;

/**
 * Pure: the order and the boosts from a person's signals and step history.
 * @returns {{ order: string[], boost: string[], avoid: string[] }}
 */
function rank({ followingCount = 0, placesCount = 0, hasMoment = false, rewardReady = false, stats = {} } = {}) {
  const score = Object.fromEntries(STEP_IDS.map((id, i) => [id, -i / 100])); // stable base order
  const boost = [];
  if (rewardReady) { score.my_rewards += 10; boost.push('my_rewards'); }
  if (followingCount < 5) { score.find_people += 6; boost.push('find_people'); }
  if (placesCount < 10) { score.add_place += 5; boost.push('add_place'); }
  if (!hasMoment) { score.post_moment += 3; }
  const avoid = STEP_IDS.filter((id) => {
    const s = stats[id] || {};
    return (s.shown || 0) >= SKIPPED_AFTER && !(s.tapped > 0);
  });
  for (const id of avoid) score[id] -= 20;
  const order = [...STEP_IDS].sort((a, b) => score[b] - score[a]);
  return { order, boost: boost.filter((id) => !avoid.includes(id) && BOOSTABLE.has(id)), avoid };
}

/** A person's signals, read cheaply (counts, a single-doc lookups) */
async function signals(uid, { db = getFirestore() } = {}) {
  const userRef = db.collection(COLLECTIONS.USERS).doc(uid);
  const [userDoc, places, moment, statsDoc] = await Promise.all([
    userRef.get(),
    db.collection(COLLECTIONS.PLACES).where('addedBy', '==', uid).where('deletedAt', '==', null).count().get()
      .then((s) => s.data().count).catch(() => 0),
    db.collection(COLLECTIONS.PLACE_VIDEOS).where('userId', '==', uid).limit(1).get()
      .then((s) => !s.empty).catch(() => false),
    userRef.collection('private').doc('nextSteps').get().catch(() => null)
  ]);
  const user = userDoc.exists ? userDoc.data() : {};
  let rewardReady = false;
  try {
    const { venueBalances } = await require('./rewardService').getBalance(uid, { withEvents: false });
    rewardReady = (venueBalances || []).some((b) =>
      (b.offers || []).some((o) => o.pointsCost > 0 && o.pointsCost <= (b.points || 0)));
  } catch { /* rewards are a bonus signal */ }
  return {
    followingCount: user.followingCount || (user.following || []).length || 0,
    placesCount: places,
    hasMoment: moment,
    rewardReady,
    stats: (statsDoc && statsDoc.exists && statsDoc.data().steps) || {}
  };
}

/** Shown and tapped counts per step (one doc per person) */
async function record(uid, events, { db = getFirestore() } = {}) {
  const { FieldValue } = require('firebase-admin/firestore');
  const update = {};
  for (const e of (events || []).slice(0, 50)) {
    const step = String(e.step || '');
    const kind = e.kind === 'tapped' ? 'tapped' : 'shown';
    if (!STEP_IDS.includes(step)) continue;
    update[`steps.${step}.${kind}`] = FieldValue.increment(1);
  }
  if (Object.keys(update).length === 0) return 0;
  update.updatedAt = new Date().toISOString();
  const ref = db.collection(COLLECTIONS.USERS).doc(uid).collection('private').doc('nextSteps');
  await ref.set({}, { merge: true });
  await ref.update(update);
  return Object.keys(update).length - 1;
}

module.exports = { rank, signals, record, STEP_IDS, SKIPPED_AFTER };
