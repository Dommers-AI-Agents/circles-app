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

// The home tour's bubbles (OnboardingManager.TutorialStep raw values plus the
// "Keep going" card) report every showing and every button, so we can see
// where a new person bails (Wes, 2026-11-12: a new user's first night left
// no trace beyond "tutorial not completed"). They live under `tour`, apart
// from the next-step `steps` that rank() reads.
const TOUR_STEP_IDS = ['tour_add_places', 'tour_follow_users', 'tour_view_activity', 'tour_see_widgets',
  'tour_moments', 'tour_locals', 'tour_check_in', 'tour_rewards', 'tour_notifications', 'tour_invite', 'tour_help',
  'tour_my_network', 'tour_messages', 'tour_profile', 'tour_keep_going'];
const TOUR_ACTIONS = ['shown', 'next', 'back', 'skip', 'learn_more', 'video', 'keep_going', 'done'];

/**
 * Pure: the Firestore update for a batch of step events — next-step chips
 * (`steps.<id>.shown|tapped`) and tour bubbles (`tour.<id>.<action>` plus
 * `tourLast`, the one field that says where someone stopped).
 * @returns {{ update: object, count: number }}
 */
function eventUpdate(events, { now = new Date().toISOString(), increment = (n) => n } = {}) {
  const update = {};
  let count = 0;
  let tourLast = null;
  for (const e of (events || []).slice(0, 50)) {
    const step = String(e.step || '');
    const kind = String(e.kind || '');
    if (TOUR_STEP_IDS.includes(step)) {
      if (!TOUR_ACTIONS.includes(kind)) continue;
      update[`tour.${step}.${kind}`] = increment(1);
      tourLast = { step, action: kind, at: now };
      count += 1;
    } else if (STEP_IDS.includes(step)) {
      update[`steps.${step}.${kind === 'tapped' ? 'tapped' : 'shown'}`] = increment(1);
      count += 1;
    }
  }
  if (tourLast) update.tourLast = tourLast;
  return { update, count };
}

/** Shown and tapped counts per step, tour bubble events (one doc per person) */
async function record(uid, events, { db = getFirestore() } = {}) {
  const { FieldValue } = require('firebase-admin/firestore');
  const { update, count } = eventUpdate(events, { increment: (n) => FieldValue.increment(n) });
  if (count === 0) return 0;
  update.updatedAt = new Date().toISOString();
  const ref = db.collection(COLLECTIONS.USERS).doc(uid).collection('private').doc('nextSteps');
  await ref.set({}, { merge: true });
  await ref.update(update);
  return count;
}

module.exports = { rank, signals, record, eventUpdate, STEP_IDS, TOUR_STEP_IDS, TOUR_ACTIONS, SKIPPED_AFTER };
