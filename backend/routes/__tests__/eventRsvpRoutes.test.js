// Guests' reply pages: opening a link (what mail scanners do) records
// nothing; only the form's POST does. Calendar files and stop links work.
const express = require('express');

const mockPage = {
  eventId: 'ev1',
  event: { name: 'Bday', emoji: '🎂', startsAt: '2099-05-01T23:00:00.000Z', timezone: 'America/New_York', inviteToken: 'x' },
  hostName: 'Wes',
  guest: { name: 'Sam', rsvp: 'pending', adults: 1, kids: 0, note: '', optedOut: false },
  coming: [{ name: 'Mo', rsvp: 'yes' }],
  counts: { yes: { replies: 1, people: 1 }, maybe: { replies: 0, people: 0 }, no: { replies: 0, people: 0 }, pending: { replies: 1, people: 1 } },
  appUrl: null, calendarUrl: '/rsvp/t/event.ics', googleCalendarUrl: null, mapsUrl: null
};
jest.mock('../../services/eventGuestService', () => ({
  guestPage: jest.fn(async (token) => { if (token !== 'goodTOKENgoodTOKENgood') { const e = new Error('nope'); e.status = 404; throw e; } return mockPage; }),
  replyAsGuest: jest.fn(async (token, body) => ({ rsvp: body.rsvp, adults: 1, kids: 0 })),
  optOut: jest.fn(async () => ({ name: 'Bday' })),
  rsvpUrl: (token) => `https://api.favcircles.com/rsvp/${token}`
}));
const guests = require('../../services/eventGuestService');

let server;
let base;
beforeAll(async () => {
  const app = express();
  app.use(require('../eventRsvpRoutes'));
  await new Promise((resolve) => { server = app.listen(0, resolve); });
  base = `http://127.0.0.1:${server.address().port}`;
});
afterAll(() => new Promise((resolve) => server.close(resolve)));
beforeEach(() => jest.clearAllMocks());

const TOKEN = 'goodTOKENgoodTOKENgood';

test('opening an email button preselects the choice and records nothing', async () => {
  const res = await fetch(`${base}/rsvp/${TOKEN}?r=yes`);
  const html = await res.text();
  expect(res.status).toBe(200);
  expect(html).toContain('value="yes" checked');
  expect(html).toContain('May 1 · 7:00 PM');
  expect(guests.replyAsGuest).not.toHaveBeenCalled();
  expect(res.headers.get('cache-control')).toBe('no-store');
});

test('the form post records the reply', async () => {
  const res = await fetch(`${base}/rsvp/${TOKEN}`, {
    method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: 'rsvp=maybe&adults=2&kids=1&note=hi'
  });
  expect(res.status).toBe(200);
  expect(guests.replyAsGuest).toHaveBeenCalledWith(TOKEN, expect.objectContaining({ rsvp: 'maybe', adults: '2' }));
  expect(await res.text()).toContain('Got it: maybe');
});

test('an unknown link is a 404 page', async () => {
  const res = await fetch(`${base}/rsvp/badbadbadbadbadbadbad1`);
  expect(res.status).toBe(404);
});

test('the calendar file', async () => {
  const res = await fetch(`${base}/rsvp/${TOKEN}/event.ics`);
  expect(res.status).toBe(200);
  expect(res.headers.get('content-type')).toContain('text/calendar');
  expect(await res.text()).toContain('DTSTART:20990501T230000Z');
});

test('stop: the page asks, the post (also one-click unsubscribe) does it', async () => {
  const page = await fetch(`${base}/rsvp/${TOKEN}/stop`);
  expect(await page.text()).toContain('Stop these emails');
  expect(guests.optOut).not.toHaveBeenCalled();
  const res = await fetch(`${base}/rsvp/${TOKEN}/stop`, {
    method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: 'List-Unsubscribe=One-Click'
  });
  expect(res.status).toBe(200);
  expect(guests.optOut).toHaveBeenCalledWith(TOKEN);
});
