// Onboarding funnel milestones, stamped once per user on the user doc:
//
//   funnel.firstConnectionAt   first accepted connection (either side)
//   funnel.firstPlaceAt        first place the user added themselves
//   funnel.firstReactionAt     first reaction on someone's activity
//
// createdAt is the funnel's start. Read via scripts/report-onboarding-funnel.js
// — signup → connected → contributing → engaging, with day-cohorts. Stamps are
// best-effort and never throw into their calling request.

const { getFirestore } = require('../config/firebase');
const db = getFirestore();

async function stampFunnelMilestone(userId, field) {
  try {
    if (!userId || !field) return;
    const ref = db.collection('users').doc(String(userId));
    const doc = await ref.get();
    if (!doc.exists) return;
    const funnel = doc.data().funnel || {};
    if (funnel[field]) return; // first time only
    await ref.update({ [`funnel.${field}`]: new Date().toISOString() });
  } catch (error) {
    console.warn(`funnel stamp ${field} failed for ${userId}:`, error.message);
  }
}

module.exports = { stampFunnelMilestone };
