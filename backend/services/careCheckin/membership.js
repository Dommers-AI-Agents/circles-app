// services/careCheckin/membership.js — methods of CareCheckinService (mixed into its prototype by the facade).
const { COLLECTIONS, CareError, TYPES, RESEND_INVITE_COOLDOWN_MS, buildConnectionMap, normalizeUserId, nowIso } = require('./shared');

// Two ways onto a check-in, two people who say yes:
// - A sibling ASKS to join → the PARENT decides (agreeing to one person seeing
//   how you are is not agreeing to four).
// - The owner INVITES a family member → the INVITED person accepts, the parent
//   is told who joined and can remove anyone, any time (Wes, 2026-09-25).
const isSelfRequest = (watcher) => !watcher.invitedBy || watcher.invitedBy === 'self';

module.exports = {
  // MARK: - Watchers (the rest of the family)

  async requestWatcher({ userId, planId, watcherId = null }) {
    const plan = await this.requirePlan(planId);
    const role = this.constructor.roleOf(plan, userId);
    const candidate = normalizeUserId(watcherId || userId);
    const ownerInvites = !!watcherId && candidate !== userId;

    if (ownerInvites && role !== 'owner') {
      throw new CareError(403, 'not_owner', 'Only the person who set this up can invite someone.');
    }
    if (!candidate || candidate === plan.parentId) {
      throw new CareError(400, 'bad_watcher', 'That person cannot join this check-in.');
    }
    if (candidate === plan.ownerId) throw new CareError(409, 'already_owner', 'They already run this check-in.');
    const already = (plan.watchers || []).find((w) => w.userId === candidate);
    if (already) {
      throw new CareError(409, 'already_watching',
        already.status === 'active' ? 'They are already on this check-in.'
          : isSelfRequest(already) ? `${plan.parentName} hasn't answered that request yet.`
            : 'They have not answered the invitation yet.');
    }

    // Someone asking for themselves must be connected to the PARENT — the
    // parent's answers are the thing being shared. A family member the owner
    // invites may be connected to either of them; the parent hears who joined.
    const parentLinks = await buildConnectionMap(plan.parentId);
    let connected = (parentLinks.get(candidate) || {}).status === 'accepted';
    if (!connected && ownerInvites) {
      const ownerLinks = await buildConnectionMap(plan.ownerId);
      connected = (ownerLinks.get(candidate) || {}).status === 'accepted';
    }
    if (!connected) {
      throw new CareError(403, 'not_connected', ownerInvites
        ? 'They need to be connected with you or with ' + (plan.parentName || 'them') + ' first.'
        : `They need to be connected with ${plan.parentName} first.`);
    }

    const doc = await this.db.collection(COLLECTIONS.USERS).doc(candidate).get();
    if (!doc.exists) throw new CareError(404, 'no_user', 'That person could not be found.');
    const name = doc.data().displayName || 'Someone';

    const watcher = {
      userId: candidate,
      name,
      status: 'invited',
      invitedBy: ownerInvites ? userId : 'self',
      invitedAt: nowIso(),
      inviteCount: 1,
      acceptedAt: null
    };
    const merged = { ...plan, watchers: [...(plan.watchers || []), watcher] };
    await this.plans.doc(planId).update({
      watchers: merged.watchers,
      pendingWatcherIds: this.constructor.pendingWatcherIds(merged),
      updatedAt: nowIso()
    });

    if (ownerInvites) {
      await this.push(candidate, this.constructor.watcherInviteMessage(plan, planId));
    } else {
      this.notify(plan.parentId, {
        type: TYPES.watcherRequest,
        title: `${name} wants to check in on you too`,
        body: `They'd see the same answers as ${plan.ownerName || 'your family'}. Open Circles to say yes or no.`,
        data: { planId, watcherId: candidate }
      });
    }
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

  // Yes or no. A request from a sibling is answered by the PARENT; an
  // invitation from the owner is answered by the person invited.
  async respondToWatcher({ userId, planId, watcherId, accept }) {
    const plan = await this.requirePlan(planId);
    const target = normalizeUserId(watcherId);
    const watcher = (plan.watchers || []).find((w) => w.userId === target);
    if (!watcher) throw new CareError(404, 'no_watcher', 'That request is no longer there.');
    if (watcher.status === 'active') throw new CareError(409, 'already_watching', 'They are already on this check-in.');
    const selfRequest = isSelfRequest(watcher);
    if (selfRequest && plan.parentId !== userId) {
      throw new CareError(403, 'not_parent', 'Only the person being checked in on can answer this.');
    }
    if (!selfRequest && target !== userId) {
      throw new CareError(403, 'not_invited', 'Only the person invited can answer this.');
    }

    const watchers = accept
      ? (plan.watchers || []).map((w) => (w.userId === target ? { ...w, status: 'active', acceptedAt: nowIso() } : w))
      : (plan.watchers || []).filter((w) => w.userId !== target);
    const merged = { ...plan, watchers };
    await this.plans.doc(planId).update({
      watchers,
      watcherIds: this.constructor.activeWatcherIds(merged),
      pendingWatcherIds: this.constructor.pendingWatcherIds(merged),
      updatedAt: nowIso()
    });

    const parentName = plan.parentName || 'them';
    if (selfRequest) {
      this.notify(target, accept ? {
        type: TYPES.watcherAccepted,
        title: `You're on ${parentName}'s check-ins`,
        body: `You'll see their answers, and hear about it when a question goes unanswered.`,
        data: { planId }
      } : {
        type: TYPES.watcherDeclined,
        title: `${parentName} said no for now`,
        body: 'They chose not to add you to their check-ins.',
        data: { planId }
      });
    } else if (accept) {
      this.notify(plan.ownerId, {
        type: TYPES.watcherAccepted,
        title: `${watcher.name} joined ${parentName}'s check-ins`,
        body: `They'll see the answers and hear about it when a question goes unanswered.`,
        data: { planId, watcherId: target }
      });
      this.notify(plan.parentId, {
        type: TYPES.watcherJoined,
        title: `${watcher.name} is now on your check-ins`,
        body: `${plan.ownerName || 'Your family'} invited them. They see your answers. You can remove anyone from the How Are You? widget.`,
        data: { planId, watcherId: target }
      });
    } else {
      this.notify(plan.ownerId, {
        type: TYPES.watcherDeclined,
        title: `${watcher.name} said no for now`,
        body: `They chose not to take part in ${parentName}'s check-ins.`,
        data: { planId, watcherId: target }
      });
    }
    return this.presentPlan(merged, { viewerId: userId });
  },

  // The owner sends an invitation again (a missed push, a phone that was off).
  // Awaited so the owner hears whether the phone got it.
  async resendWatcherInvite({ userId, planId, watcherId, now = new Date() }) {
    const plan = await this.requirePlan(planId);
    if (plan.ownerId !== userId) throw new CareError(403, 'not_owner', 'Only the person who set this up can send the invitation again.');
    const target = normalizeUserId(watcherId);
    const watcher = (plan.watchers || []).find((w) => w.userId === target);
    if (!watcher || isSelfRequest(watcher)) throw new CareError(404, 'no_watcher', 'There is no invitation to send again.');
    if (watcher.status === 'active') throw new CareError(409, 'already_watching', 'They already accepted.');
    const last = Date.parse(watcher.invitedAt || 0) || 0;
    const waitMs = RESEND_INVITE_COOLDOWN_MS - (now.getTime() - last);
    if (waitMs > 0) {
      const minutes = Math.max(1, Math.ceil(waitMs / 60000));
      throw new CareError(429, 'too_soon', `The invitation just went out. Try again in ${minutes} minute${minutes === 1 ? '' : 's'}.`);
    }
    const result = await this.push(target, this.constructor.watcherInviteMessage(plan, planId));
    const watchers = (plan.watchers || []).map((w) => (w.userId === target
      ? { ...w, invitedAt: now.toISOString(), inviteCount: (w.inviteCount || 1) + 1 } : w));
    await this.plans.doc(planId).update({ watchers, updatedAt: nowIso() });
    return {
      plan: this.presentPlan({ ...plan, watchers }, { viewerId: userId }),
      delivered: !!(result && result.success)
    };
  },

  // Leaving, or being removed. A watcher can always take themselves off; the
  // parent and the owner can remove anyone — and the person removed is told.
  async removeWatcher({ userId, planId, watcherId }) {
    const plan = await this.requirePlan(planId);
    const target = normalizeUserId(watcherId);
    const isSelf = target === userId;
    if (!isSelf && plan.parentId !== userId && plan.ownerId !== userId) {
      throw new CareError(403, 'not_allowed', 'Only they, the owner, or the person being checked in on can do that.');
    }
    const watcher = (plan.watchers || []).find((w) => w.userId === target);
    const watchers = (plan.watchers || []).filter((w) => w.userId !== target);
    const merged = { ...plan, watchers };
    await this.plans.doc(planId).update({
      watchers,
      watcherIds: this.constructor.activeWatcherIds(merged),
      pendingWatcherIds: this.constructor.pendingWatcherIds(merged),
      updatedAt: nowIso()
    });
    if (watcher && !isSelf) {
      this.notify(target, {
        type: TYPES.watcherRemoved,
        title: `You're no longer on ${plan.parentName || 'their'}'s check-ins`,
        body: watcher.status === 'active' ? 'You will not see their answers any more.' : 'The invitation was withdrawn.',
        data: { planId }
      });
    }
    return this.presentPlan(merged, { viewerId: userId });
  },
};
