// backend/routes/eventRsvpRoutes.js
//
// Public pages for event guests invited by email (services/eventGuestService):
//   GET  /rsvp/:token              the reply page (?r=yes|maybe|no preselects)
//   POST /rsvp/:token              records the reply (form post)
//   GET  /rsvp/:token/event.ics    "Add to calendar"
//   GET  /rsvp/:token/stop         confirm "stop emails about this event"
//   POST /rsvp/:token/stop         does it (also the one-click List-Unsubscribe)
//   GET  /calendar/event/:token.ics  members' "Add to calendar" (invite token)
// Deliberately outside /app/* (the app's Universal Links), so a guest with
// FavCircles installed still gets the page. Only POSTs change anything:
// mail scanners open links. The guest token is the only credential, so
// every route is rate-limited by IP.
const express = require('express');
const rateLimit = require('express-rate-limit');
const guests = require('../services/eventGuestService');
const details = require('../services/eventDetails');
const { renderRsvpPage, renderRsvpNotFound, renderStopPage } = require('../views/eventRsvpPage');

const router = express.Router();

const pageLimiter = rateLimit({ windowMs: 15 * 60 * 1000, max: 120, standardHeaders: true, legacyHeaders: false });
const writeLimiter = rateLimit({ windowMs: 15 * 60 * 1000, max: 30, standardHeaders: true, legacyHeaders: false });
const form = express.urlencoded({ extended: false, limit: '8kb' });

const tokenOf = (req) => String(req.params.token || '').replace(/[^A-Za-z0-9_-]/g, '').slice(0, 48);
const CHOICES = new Set(['yes', 'maybe', 'no']);

const noStore = (res) => {
  res.set('Cache-Control', 'no-store');
  res.set('X-Robots-Tag', 'noindex, nofollow');
  res.set('Referrer-Policy', 'no-referrer');
};

router.get('/rsvp/:token', pageLimiter, async (req, res) => {
  noStore(res);
  const token = tokenOf(req);
  try {
    const page = await guests.guestPage(token);
    const preselect = CHOICES.has(String(req.query.r)) ? String(req.query.r) : null;
    res.send(renderRsvpPage(token, page, { preselect }));
  } catch (error) {
    if (error.status !== 404) console.warn('🎟️ rsvp page:', error.message);
    res.status(404).send(renderRsvpNotFound());
  }
});

router.post('/rsvp/:token', writeLimiter, form, async (req, res) => {
  noStore(res);
  const token = tokenOf(req);
  try {
    const saved = await guests.replyAsGuest(token, req.body || {});
    const page = await guests.guestPage(token);
    res.send(renderRsvpPage(token, page, { saved }));
  } catch (error) {
    if (error.status === 404) return res.status(404).send(renderRsvpNotFound());
    try {
      const page = await guests.guestPage(token);
      return res.status(error.status || 500).send(renderRsvpPage(token, page, { error: error.status ? error.message : 'Something went wrong. Please try again.' }));
    } catch (e) {
      return res.status(404).send(renderRsvpNotFound());
    }
  }
});

router.get('/rsvp/:token/event.ics', pageLimiter, async (req, res) => {
  try {
    const page = await guests.guestPage(tokenOf(req));
    const ics = details.icsFor(page.eventId, page.event, { url: `${req.protocol}://${req.get('host')}/rsvp/${tokenOf(req)}` });
    if (!ics) return res.status(404).send('No date set yet');
    res.set('Content-Type', 'text/calendar; charset=utf-8');
    res.set('Content-Disposition', 'attachment; filename="event.ics"');
    return res.send(ics);
  } catch (error) {
    return res.status(404).send('Not found');
  }
});

router.get('/rsvp/:token/stop', pageLimiter, async (req, res) => {
  noStore(res);
  try {
    const page = await guests.guestPage(tokenOf(req));
    res.send(renderStopPage(tokenOf(req), { name: page.event.name, done: page.guest.optedOut }));
  } catch (error) {
    res.status(404).send(renderRsvpNotFound());
  }
});

router.post('/rsvp/:token/stop', writeLimiter, form, async (req, res) => {
  noStore(res);
  try {
    const { name } = await guests.optOut(tokenOf(req));
    res.send(renderStopPage(tokenOf(req), { name, done: true }));
  } catch (error) {
    res.status(404).send(renderRsvpNotFound());
  }
});

router.get('/calendar/event/:token.ics', pageLimiter, async (req, res) => {
  try {
    const token = tokenOf(req);
    const { eventsCol, TOKEN_RE, LINK_BASE } = require('../services/eventService');
    if (!TOKEN_RE.test(token)) return res.status(404).send('Not found');
    const snap = await eventsCol().where('inviteToken', '==', token).limit(1).get();
    const doc = snap.docs.find((d) => !d.data().deletedAt);
    if (!doc) return res.status(404).send('Not found');
    const ics = details.icsFor(doc.id, doc.data(), { url: `${LINK_BASE}${token}` });
    if (!ics) return res.status(404).send('No date set yet');
    res.set('Content-Type', 'text/calendar; charset=utf-8');
    res.set('Content-Disposition', 'attachment; filename="event.ics"');
    return res.send(ics);
  } catch (error) {
    return res.status(404).send('Not found');
  }
});

module.exports = router;
