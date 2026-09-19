// services/careCheckin/membership.js — methods of CareCheckinService (mixed into its prototype by the facade).
const { COLLECTIONS, CareError, TYPES, buildConnectionMap, normalizeUserId, nowIso } = require('./shared');

module.exports = {
  // MARK: - Watchers (the other siblings)

  // A sibling asks to join, or the owner invites one. Either way the PARENT
  // decides: they already had to accept the first child, and agreeing to one
  // person seeing how you are is not agreeing to four.
  async requestWatcher({ userId, planId, watcherId = null }) {
    const plan = await this.requirePlan(planId);
    const role = this.constructor.roleOf(plan, userId);
    const candidate = normalizeUserId(watcherId || userId);

    if (watcherId && role !== 'owner') {
      throw new CareError(403, 'not_owner', 'Only the person who set this up can invite someone.');
    }
    if (!candidate || candidate === plan.parentId) {
      throw new CareError(400, 'bad_watcher', 'That person cannot join this check-in.');
    }
    if (candidate === plan.ownerId) throw new CareError(409, 'already_owner', 'They already run this check-in.');
    const already = (plan.watchers || []).find((w) => w.userId === candidate);
    if (already) {
      throw new CareError(409, 'already_watching',
        already.status === 'active' ? 'They are already on this check-in.' : `${plan.parentName} hasn't answered that request yet.`);
    }

    // A watcher must be connected to the PARENT, not merely to the sibling who
    // invited them — the parent's answers are the thing being shared.
    const connections = await buildConnectionMap(plan.parentId);
    const link = connections.get(candidate);
    if (!link || link.status !== 'accepted') {
      throw new CareError(403, 'not_connected', `They need to be connected with ${plan.parentName} first.`);
    }

    const doc = await this.db.collection(COLLECTIONS.USERS).doc(candidate).get();
    if (!doc.exists) throw new CareError(404, 'no_user', 'That person could not be found.');
    const name = doc.data().displayName || 'Someone';

    const watcher = {
      userId: candidate,
      name,
      status: 'invited',
      invitedBy: userId === candidate ? 'self' : userId,
      invitedAt: nowIso(),
      acceptedAt: null
    };
    await this.plans.doc(planId).update({
      watchers: [...(plan.watchers || []), watcher],
      updatedAt: nowIso()
    });

    this.notify(plan.parentId, {
      type: TYPES.watcherRequest,
      title: `${name} wants to check in on you too`,
      body: `They'd see the same answers as ${plan.ownerName || 'your family'}. Open Circles to say yes or no.`,
      data: { planId, watcherId: candidate }
    });
    const merged = { ...plan, watchers: [...(plan.watchers || []), watcher] };
    return this.presentPlan(merged, { viewerId: userId });
  },

  // Join by naming the PARENT rather than the plan. A sibling who tries to set
  // up their own check-in only knows who they meant to watch, not the id of the
  // arrangement someone else already made — so this resolves it for them.
  async requestWatcherForParent({ userId, parentId }) {
    const parent = normalizeUserId(parentId);
    const plan = parent ? await this.livePlanForParent(parent) : null;
    if (!plan) throw new CareError(404, 'no_plan', 'Nobody is checking in on them yet — set one up instead.');
    return this.requestWatcher({ userId, planId: plan.id });
  },

  // The parent says yes or no. Only the parent — the owner cannot wave a
  // sibling through on their behalf.
  async respondToWatcher({ userId, planId, watcherId, accept }) {
    const plan = await this.requirePlan(planId);
    if (plan.parentId !== userId) {
      throw new CareError(403, 'not_parent', 'Only the person being checked in on can answer this.');
    }
    const target = normalizeUserId(watcherId);
    const watcher = (plan.watchers || []).find((w) => w.userId === target);
    if (!watcher) throw new CareError(404, 'no_watcher', 'That request is no longer there.');

    const watchers = accept
      ? (plan.watchers || []).map((w) => (w.userId === target ? { ...w, status: 'active', acceptedAt: nowIso() } : w))
      : (plan.watchers || []).filter((w) => w.userId !== target);
    const merged = { ...plan, watchers };
    await this.plans.doc(planId).update({
      watchers,
      watcherIds: this.constructor.activeWatcherIds(merged),
      updatedAt: nowIso()
    });

    this.notify(target, accept ? {
      type: TYPES.watcherAccepted,
      title: `You're on ${plan.parentName}'s check-ins`,
      body: `You'll see their answers, and hear about it when a question goes unanswered.`,
      data: { planId }
    } : {
      type: TYPES.watcherDeclined,
      title: `${plan.parentName} said no for now`,
      body: 'They chose not to add you to their check-ins.',
      data: { planId }
    });
    return this.presentPlan(merged, { viewerId: userId });
  },

  // Leaving, or being removed. A watcher can always take themselves off; the
  // parent and the owner can remove anyone.
  async removeWatcher({ userId, planId, watcherId }) {
    const plan = await this.requirePlan(planId);
    const target = normalizeUserId(watcherId);
    const isSelf = target === userId;
    if (!isSelf && plan.parentId !== userId && plan.ownerId !== userId) {
      throw new CareError(403, 'not_allowed', 'Only they, the owner, or the person being checked in on can do that.');
    }
    const watchers = (plan.watchers || []).filter((w) => w.userId !== target);
    const merged = { ...plan, watchers };
    await this.plans.doc(planId).update({
      watchers,
      watcherIds: this.constructor.activeWatcherIds(merged),
      updatedAt: nowIso()
    });
    return this.presentPlan(merged, { viewerId: userId });
  },
};
