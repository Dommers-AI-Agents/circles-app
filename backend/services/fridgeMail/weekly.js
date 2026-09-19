// services/fridgeMail/weekly.js — methods of FridgeMailService (mixed into its prototype by the facade).
const { FieldValue, KIND, RESEND_AFTER_MS, buildFridgeBackHtml, dryRun, entitlement, formatLongDate, isDue, isEnabled, lobClient, newId, nowIso } = require('./shared');

module.exports = {
  async runWeekly({ now = new Date(), limit = 200 } = {}) {
    const summary = { plans: 0, sent: 0, skippedNoQueue: 0, skippedNoCredit: 0, failed: 0 };
    if (!isEnabled() || !lobClient.isEnabled()) return { ...summary, disabled: true };
    // `limit` is a page size, not a cap: every active plan is visited. (It
    // used to be a cap applied before the due check, so past 200 plans the
    // rest silently never mailed.) A retried run is safe: lastSentAt gates.
    let cursor = null;
    for (;;) {
      let query = this.plans.where('status', '==', 'active').limit(limit);
      if (cursor) query = query.startAfter(cursor);
      const snap = await query.get();
      for (const doc of snap.docs) {
        const plan = doc.data();
        if (!isDue(plan, now)) continue;
        summary.plans++;
        const outcome = await this.sendForPlan(doc, plan, now);
        summary.sent += outcome.sent;
        if (outcome.reason === 'no_queue') summary.skippedNoQueue++;
        if (outcome.reason === 'no_credit') summary.skippedNoCredit++;
        summary.failed += outcome.failed;
      }
      if (snap.docs.length < limit) break;
      cursor = snap.docs[snap.docs.length - 1];
    }
    return summary;
  },

  async sendForPlan(doc, plan, now) {
    const result = { sent: 0, failed: 0, reason: null };
    const recipients = plan.recipients || [];
    const item = (plan.queue || []).find((q) => !q.sentAt);
    const weekNudgeDue = !plan.lastNudgeAt || now.getTime() - Date.parse(plan.lastNudgeAt) >= RESEND_AFTER_MS;

    if (recipients.length === 0) return { ...result, reason: 'no_recipients' };
    if (!item) {
      if (weekNudgeDue) {
        this.notify(plan.userId, {
          title: 'Fridge Mail needs a drawing',
          body: "Nothing is queued for this week. Add one and it goes out on the next mailing day.",
          data: { reason: 'no_queue' }
        });
        await doc.ref.update({ lastNudgeAt: now.toISOString() });
      }
      return { ...result, reason: 'no_queue' };
    }

    const ent = entitlement(plan);
    if (ent.covered === 0) {
      if (weekNudgeDue) {
        this.notify(plan.userId, {
          title: 'Fridge Mail is out of cards',
          body: `Add a pack or subscribe to keep ${item.childName ? `${item.childName}'s` : 'the'} drawings going to ${recipients.length === 1 ? recipients[0].name : `${recipients.length} people`}.`,
          data: { reason: 'no_credit' }
        });
        await doc.ref.update({ lastNudgeAt: now.toISOString() });
      }
      return { ...result, reason: 'no_credit' };
    }

    // Subscription slots first, then credits. Recipients past the covered
    // count wait for more cards.
    let creditsToSpend = Math.max(0, ent.covered - ent.subscribedSlots);
    const covered = recipients.slice(0, ent.covered);
    const dateText = formatLongDate(now, plan.timezone);
    for (const recipient of covered) {
      const usesCredit = creditsToSpend > 0 && covered.indexOf(recipient) >= ent.subscribedSlots;
      const ok = await this.mailOne({ plan, item, recipient, now, dateText, usesCredit });
      if (ok) {
        result.sent++;
        if (usesCredit) { creditsToSpend--; await doc.ref.update({ cardsRemaining: FieldValue.increment(-1) }); }
      } else {
        result.failed++;
      }
    }
    if (result.sent > 0) {
      const queue = (plan.queue || []).map((q) => (q.id === item.id ? { ...q, sentAt: now.toISOString() } : q));
      await doc.ref.update({ queue, lastSentAt: now.toISOString(), updatedAt: now.toISOString() });
      const to = covered.length === 1 ? covered[0].name : `${covered.length} people`;
      this.notify(plan.userId, {
        title: 'Fridge Mail is on its way',
        body: `${item.childName ? `${item.childName}'s` : 'This week\'s'} card is headed to ${to}. Typically arrives in 4 to 6 business days.`,
        data: { reason: 'sent' }
      });
      if (ent.weeksOfCredits !== null && ent.weeksOfCredits - 1 <= 1 && ent.subscribedSlots < recipients.length) {
        this.notify(plan.userId, {
          title: 'Fridge Mail is almost out of cards',
          body: ent.weeksOfCredits - 1 <= 0 ? 'That was the last prepaid card. Add a pack or subscribe to keep going.' : 'One more week of cards left. Add a pack or subscribe.',
          data: { reason: 'low_credit' }
        });
      }
    }
    return result;
  },

  /** One card to one recipient: a prepaid postcardOrders row, then Lob. */
  async mailOne({ plan, item, recipient, now, dateText, usesCredit }) {
    const rowId = `fm_${newId()}`;
    const ref = this.cards.doc(rowId);
    const row = {
      kind: KIND, prepaid: true, usesCredit: !!usesCredit,
      userId: plan.userId, status: 'submitting',
      amountCents: 0, currency: 'usd', stripePaymentIntentId: null, stripeClientSecret: null,
      recipient: { name: recipient.name, ...recipient.address },
      recipientId: recipient.id, queueItemId: item.id,
      imageUrl: item.imageUrl, message: item.note || '', childName: item.childName || '',
      templateId: KIND, placeName: null, placeCity: null, publicPageToken: null,
      lobPostcardId: null, lobExpectedDeliveryDate: null, lobPreviewUrl: null, lobAttempts: 1,
      authorizedAt: null, cancelableUntil: null, capturedAt: null, error: null,
      createdAt: now.toISOString(), updatedAt: now.toISOString()
    };
    await ref.create(row);
    try {
      let lob;
      if (dryRun()) {
        lob = { id: `dryrun_${rowId}`, expectedDeliveryDate: null, previewUrl: null };
      } else {
        lob = await lobClient.createPostcard({
          idempotencyKey: rowId,
          description: `FavCircles Fridge Mail ${rowId}`,
          to: {
            name: recipient.name,
            address_line1: recipient.address.line1,
            address_line2: recipient.address.line2 || '',
            address_city: recipient.address.city,
            address_state: recipient.address.state,
            address_zip: recipient.address.zip,
            address_country: 'US'
          },
          frontUrl: item.imageUrl,
          backHtml: buildFridgeBackHtml({
            childName: item.childName, ageText: item.ageText, dateText, note: item.note, familyName: plan.familyName
          })
        });
      }
      await ref.update({
        status: 'submitted', lobPostcardId: lob.id, lobExpectedDeliveryDate: lob.expectedDeliveryDate || null,
        lobPreviewUrl: lob.previewUrl || null, updatedAt: nowIso()
      });
      return true;
    } catch (error) {
      console.error(`[fridge-mail] Lob refused ${rowId} for ${plan.userId}: ${error.message}`);
      await ref.update({ status: 'rejected', error: String(error.message || error).slice(0, 300), needsReview: true, updatedAt: nowIso() });
      return false;
    }
  },
};
