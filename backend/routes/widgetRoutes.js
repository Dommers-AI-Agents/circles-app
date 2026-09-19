// backend/routes/widgetRoutes.js
// Home Widgets tab: generic per-widget JSON documents (optimistic
// versioning) plus the digital-postcard send. Schemas live in the iOS
// FavWidgets package; the backend never interprets a payload.

const express = require('express');
const { protect } = require('../middleware/firebaseAuth');
const { messageLimiter } = require('../middleware/security');
const widgetData = require('../controllers/widgets/widgetDataController');
const postcard = require('../controllers/widgets/postcardController');
const nextBarRounds = require('../controllers/widgets/nextBarRoundController');
const postcardMail = require('../controllers/widgets/postcardMailController');
const fridgeMail = require('../controllers/widgets/fridgeMailController');
const care = require('../controllers/widgets/careCheckinController');
const quotes = require('../controllers/widgets/quotesController');
const workoutFeed = require('../controllers/widgets/workoutFeedController');

const router = express.Router();
router.use(protect);

router.get('/data', widgetData.listData);
router.get('/data/:widgetId', widgetData.getData);
router.put('/data/:widgetId', widgetData.putData);
router.delete('/data/:widgetId', widgetData.deleteData);

// A postcard is a chat message, so it shares the messaging rate limit
router.post('/postcard/send', messageLimiter, postcard.sendPostcard);
router.post('/postcard/share', messageLimiter, postcard.createShareLink);
router.post('/postcard/email', messageLimiter, postcard.emailPostcard);

// Printed-and-mailed postcards. Print art bypasses /api/upload/image, which
// caps at 1MB and would downsize below print resolution.
router.post('/postcard/mail/upload', messageLimiter, postcardMail.uploadPrintImage);
router.get('/postcard/mail/config', postcardMail.getConfig);
router.post('/postcard/mail/quote', messageLimiter, postcardMail.quote);
router.post('/postcard/mail/orders', messageLimiter, postcardMail.createOrder);
router.get('/postcard/mail/orders', postcardMail.listOrders);
router.get('/postcard/mail/orders/:id', postcardMail.getOrder);
router.post('/postcard/mail/orders/:id/confirm', postcardMail.confirmOrder);
router.post('/postcard/mail/orders/:id/cancel', postcardMail.cancelOrder);

// NOTE: the Stripe and Lob webhooks are NOT here. They arrive without a JWT
// and verify an HMAC over the raw body, so they are mounted in server.js
// above the global express.json() parser.

// Fridge Mail: weekly printed cards to grandparents. Server-owned state; the
// print image is uploaded through /postcard/mail/upload like any postcard.
router.get('/fridgemail/plan', fridgeMail.getPlan);
router.put('/fridgemail/plan', fridgeMail.updatePlan);
router.post('/fridgemail/recipients', messageLimiter, fridgeMail.addRecipient);
router.put('/fridgemail/recipients/:id', messageLimiter, fridgeMail.updateRecipient);
router.delete('/fridgemail/recipients/:id', fridgeMail.removeRecipient);
router.post('/fridgemail/queue', messageLimiter, fridgeMail.enqueue);
router.delete('/fridgemail/queue/:id', fridgeMail.removeQueued);
router.put('/fridgemail/queue/order', fridgeMail.reorderQueue);
router.get('/fridgemail/packs', fridgeMail.listPacks);
router.post('/fridgemail/packs/orders', messageLimiter, fridgeMail.createPackOrder);
router.post('/fridgemail/packs/orders/:id/confirm', fridgeMail.confirmPackOrder);
router.post('/fridgemail/subscription/setup', messageLimiter, fridgeMail.setupSubscription);
router.post('/fridgemail/subscription/start', messageLimiter, fridgeMail.startSubscription);
router.post('/fridgemail/subscription/cancel', fridgeMail.cancelSubscription);
router.post('/fridgemail/subscription/resume', fridgeMail.resumeSubscription);
router.get('/fridgemail/cards', fridgeMail.listCards);

// "How Are You?" check-ins: a child sets up questions, the parent answers
// from the Lock Screen, silence gets reported.
// Daily quote: the topics, the hour, and whether it also goes to email.
router.get('/quotes/settings', quotes.getSettings);
router.put('/quotes/settings', quotes.updateSettings);

router.get('/care/plans', care.listPlans);
router.post('/care/plans', messageLimiter, care.createPlan);
router.put('/care/plans/:id', care.updatePlan);
router.delete('/care/plans/:id', care.endPlan);
router.post('/care/plans/:id/respond', care.respond);
// Watchers: the other siblings. Joining is requested by them or offered by the
// owner, and accepted by the parent — never by the owner on their behalf.
router.post('/care/plans/:id/watchers', messageLimiter, care.requestWatcher);
router.post('/care/join', messageLimiter, care.joinForParent);
router.post('/care/plans/:id/watchers/:watcherId/respond', care.respondToWatcher);
router.delete('/care/plans/:id/watchers/:watcherId', care.removeWatcher);
router.get('/care/asks', care.listAsks);
router.post('/care/asks/:id/answer', care.answer);

// Workouts shared with the Inner Circle (feed = grantors ∩ connections)
router.post('/workouts/share', messageLimiter, workoutFeed.share);
router.get('/workouts/feed', workoutFeed.feed);

// NextBar voting rounds: shared docs (host + tagged connections vote)
router.post('/nextbar/rounds', nextBarRounds.createRound);
router.get('/nextbar/rounds', nextBarRounds.listRounds);
router.get('/nextbar/rounds/:id', nextBarRounds.getRound);
router.post('/nextbar/rounds/:id/vote', nextBarRounds.vote);
router.post('/nextbar/rounds/:id/close', nextBarRounds.closeRound);

module.exports = router;
