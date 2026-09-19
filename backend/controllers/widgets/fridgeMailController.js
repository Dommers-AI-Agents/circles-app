// backend/controllers/widgets/fridgeMailController.js
// Fridge Mail routes. Every handler builds its service arguments explicitly
// from the authenticated user plus named body fields — never a body spread.
const fridge = require('../../services/fridgeMailService');

const { sendServiceError } = require('../../utils/serviceError');
const fail = (res, error) => sendServiceError(res, error, {
  log: '[fridge-mail] request failed', fallbackCode: 'fridge_failed', fallbackMessage: 'Something went wrong with Fridge Mail.'
});

exports.getPlan = async (req, res) => {
  try { res.json({ success: true, plan: await fridge.getPlan(req.user.uid) }); } catch (e) { fail(res, e); }
};

exports.updatePlan = async (req, res) => {
  const { weekday, timezone, familyName, status } = req.body || {};
  try { res.json({ success: true, plan: await fridge.setPlan({ userId: req.user.uid, weekday, timezone, familyName, status }) }); }
  catch (e) { fail(res, e); }
};

exports.addRecipient = async (req, res) => {
  const { name, relation, address } = req.body || {};
  try { res.status(201).json({ success: true, plan: await fridge.addRecipient({ userId: req.user.uid, name, relation, address }) }); }
  catch (e) { fail(res, e); }
};

exports.updateRecipient = async (req, res) => {
  const { name, relation, address } = req.body || {};
  try { res.json({ success: true, plan: await fridge.updateRecipient({ userId: req.user.uid, recipientId: req.params.id, name, relation, address }) }); }
  catch (e) { fail(res, e); }
};

exports.removeRecipient = async (req, res) => {
  try { res.json({ success: true, plan: await fridge.removeRecipient({ userId: req.user.uid, recipientId: req.params.id }) }); }
  catch (e) { fail(res, e); }
};

exports.enqueue = async (req, res) => {
  const { imageUrl, childName, ageText, note } = req.body || {};
  try { res.status(201).json({ success: true, plan: await fridge.enqueue({ userId: req.user.uid, imageUrl, childName, ageText, note }) }); }
  catch (e) { fail(res, e); }
};

exports.removeQueued = async (req, res) => {
  try { res.json({ success: true, plan: await fridge.removeQueued({ userId: req.user.uid, itemId: req.params.id }) }); }
  catch (e) { fail(res, e); }
};

exports.reorderQueue = async (req, res) => {
  const ids = Array.isArray(req.body && req.body.ids) ? req.body.ids.map(String) : [];
  try { res.json({ success: true, plan: await fridge.reorderQueue({ userId: req.user.uid, ids }) }); }
  catch (e) { fail(res, e); }
};

exports.listPacks = (req, res) => {
  res.json({ success: true, packs: fridge.packs(), subscriptionPriceCents: fridge.SUBSCRIPTION_PRICE_CENTS, currency: 'usd' });
};

exports.createPackOrder = async (req, res) => {
  const { orderId, packId } = req.body || {};
  try { res.status(201).json({ success: true, ...(await fridge.createPackOrder({ userId: req.user.uid, orderId, packId })) }); }
  catch (e) { fail(res, e); }
};

exports.confirmPackOrder = async (req, res) => {
  try { res.json({ success: true, plan: await fridge.confirmPackOrder({ userId: req.user.uid, orderId: req.params.id }) }); }
  catch (e) { fail(res, e); }
};

exports.setupSubscription = async (req, res) => {
  try {
    const result = await fridge.setupSubscription({ userId: req.user.uid, email: req.user.email, name: req.user.displayName });
    res.status(201).json({ success: true, ...result });
  } catch (e) { fail(res, e); }
};

exports.startSubscription = async (req, res) => {
  const { setupIntentId } = req.body || {};
  try { res.json({ success: true, plan: await fridge.startSubscription({ userId: req.user.uid, setupIntentId: String(setupIntentId || '') }) }); }
  catch (e) { fail(res, e); }
};

exports.cancelSubscription = async (req, res) => {
  try { res.json({ success: true, plan: await fridge.cancelSubscription({ userId: req.user.uid }) }); } catch (e) { fail(res, e); }
};

exports.resumeSubscription = async (req, res) => {
  try { res.json({ success: true, plan: await fridge.resumeSubscription({ userId: req.user.uid }) }); } catch (e) { fail(res, e); }
};

exports.listCards = async (req, res) => {
  try { res.json({ success: true, cards: await fridge.listCards(req.user.uid) }); } catch (e) { fail(res, e); }
};

// @route POST /api/tasks/fridgemail-send (Cloud Scheduler, daily 15:00 UTC)
exports.runWeekly = async (req, res) => {
  try {
    const summary = await fridge.runWeekly();
    console.log('[fridge-mail] weekly run:', summary);
    res.json({ success: true, ...summary });
  } catch (error) {
    console.error('[fridge-mail] weekly run failed:', error);
    res.status(500).json({ success: false, error: error.message });
  }
};
