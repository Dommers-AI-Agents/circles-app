// Email invites + RSVPs for events (2026-11-02). Pure rules, then the flows
// against the fake database: invite, reply from the page, opt out, the
// daily cap, the resend cooldown, members' replies, the day-before reminder.
const { FakeFirestore, FakeFieldValue } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({ getFirestore: () => mockDb, FieldValue: require('../../__fixtures__/fakeFirestore').FakeFieldValue }));
jest.mock('firebase-admin/firestore', () => ({
  FieldValue: require('../../__fixtures__/fakeFirestore').FakeFieldValue,
  FieldPath: function FieldPath(...segments) { this.segments = segments; }
}));
const mockSent = [];
jest.mock('../emailService', () => ({ sendEmail: jest.fn(async (m) => { mockSent.push(m); return { success: true }; }) }));
const mockPushes = [];
jest.mock('../notifyQuiet', () => ({ sendInBackground: (uid, p) => mockPushes.push({ uid, ...p }) }));
jest.mock('../userLookup', () => ({
  fetchUsersById: async (ids) => new Map(ids.filter(Boolean).map((id) => [String(id), { displayName: id === 'host' ? 'Wes Host' : `User ${id}` }])),
  nameOf: (u) => (u ? u.displayName : null),
  photoOf: () => null
}));

const g = require('../eventGuestService');
const { COLLECTIONS } = require('../../models/FirestoreModels');

const EVENT = 'ev1';
const seed = (extra = {}) => {
  mockDb.collection(COLLECTIONS.EVENTS).doc(EVENT).set({
    name: 'Bday', emoji: '🎂', hostId: 'host', hostName: 'Wes', memberIds: ['host', 'm1'],
    members: { host: { name: 'Wes' }, m1: { name: 'Mo', rsvp: 'maybe', adults: 2, kids: 1 } },
    pendingInviteIds: [], joinOpen: true, inviteToken: 'tokTOKtokTOKtokTOK12',
    startsAt: '2099-05-01T23:00:00.000Z', timezone: 'America/New_York', location: { name: 'Park', address: '' },
    ...extra
  });
  mockDb.collection(COLLECTIONS.USERS).doc('host').set({ displayName: 'Wes Host', email: 'wes@example.com' });
};

beforeEach(() => {
  for (const c of [COLLECTIONS.EVENTS, COLLECTIONS.USERS, 'eventGuests', 'eventEmailQuota']) mockDb.rows(c).clear();
  mockSent.length = 0;
  mockPushes.length = 0;
  seed();
});

const guestRows = () => [...mockDb.rows('eventGuests').values()];

describe('pure rules', () => {
  test('guest lists: addresses cleaned, deduped, the bad ones reported', () => {
    const out = g.parseGuestList(['A@x.com', { email: 'a@x.com' }, { email: 'b@y.org', name: ' Bea ' }, 'nope', '', 'c@d']);
    expect(out.guests).toEqual([{ email: 'a@x.com', name: '' }, { email: 'b@y.org', name: 'Bea' }]);
    expect(out.invalid).toEqual(['nope', 'c@d']);
  });

  test('replies: a choice is required; a no brings nobody; heads are capped', () => {
    expect(() => g.parseReply({ rsvp: 'perhaps' })).toThrow();
    expect(g.parseReply({ rsvp: 'no', adults: 3 })).toMatchObject({ rsvp: 'no', adults: 0, kids: 0 });
    expect(g.parseReply({ rsvp: 'yes', adults: 0, kids: 99 })).toMatchObject({ adults: 1, kids: 20 });
    expect(g.parseReply({ rsvp: 'MAYBE' }).rsvp).toBe('maybe');
  });

  test('what the coordinator is told', () => {
    expect(g.replyLine('Sam', { rsvp: 'yes', adults: 2, kids: 1 })).toBe('Sam is going (+2)');
    expect(g.replyLine('Sam', { rsvp: 'maybe', adults: 1 })).toBe('Sam might come');
    expect(g.replyLine('Sam', { rsvp: 'no' })).toBe("Sam can't make it");
  });

  test('totals: members default to Going, in-app decliners count, linked guests count once', () => {
    const event = {
      memberIds: ['a', 'b'], members: { a: {}, b: { rsvp: 'maybe', adults: 2, kids: 2 } },
      pendingInviteIds: ['c', 'd'], invited: { c: { rsvp: 'no' } }
    };
    const guests = [{ rsvp: 'yes', adults: 2, kids: 0 }, { rsvp: 'pending' }, { rsvp: 'yes', adults: 1, linkedUserId: 'a' }];
    const c = g.countRsvps(event, guests);
    expect(c.yes).toEqual({ replies: 2, people: 3 });
    expect(c.maybe).toEqual({ replies: 1, people: 4 });
    expect(c.no).toEqual({ replies: 1, people: 0 });
    expect(c.pending).toEqual({ replies: 2, people: 2 });
    // Stored guest tallies stand in when the rows weren't read
    expect(g.countRsvps(event, [], g.tallyGuests(guests))).toEqual(c);
  });
});

describe('invites and replies', () => {
  test('the coordinator invites by email: one row and one email per new address', async () => {
    const out = await g.inviteByEmail(EVENT, 'host', { guests: ['sam@x.com', { email: 'Bea@y.org', name: 'Bea' }, 'wes@example.com', 'bad'], message: 'Come!' });
    expect(out).toMatchObject({ invited: 2, sent: 2, invalid: ['bad'] });
    expect(guestRows().map((r) => r.email).sort()).toEqual(['bea@y.org', 'sam@x.com']);
    expect(mockSent[0].fromName).toBe('Wes Host via FavCircles');
    expect(mockSent[0].headers['List-Unsubscribe']).toMatch(/\/rsvp\/[A-Za-z0-9_-]+\/stop>$/);
    expect(mockSent[0].html).toContain('Come!');
    expect(mockSent[0].userTriggered).toBe(true);
    // Again: already on the list
    const again = await g.inviteByEmail(EVENT, 'host', { guests: ['sam@x.com'] });
    expect(again).toMatchObject({ invited: 0, alreadyInvited: 1 });
  });

  test('only the coordinator invites', async () => {
    await expect(g.inviteByEmail(EVENT, 'm1', { guests: ['a@b.com'] })).rejects.toMatchObject({ code: 'not_host' });
  });

  test('the daily cap stops a flood', async () => {
    mockDb.collection('eventEmailQuota').doc(g.quotaKey('host')).set({ count: g.DAILY_EMAIL_CAP - 1 });
    await expect(g.inviteByEmail(EVENT, 'host', { guests: ['a@b.com', 'c@d.com'] })).rejects.toMatchObject({ code: 'email_cap' });
    expect(guestRows()).toHaveLength(0);
  });

  test('a guest replies from the page; the coordinator hears; totals follow', async () => {
    await g.inviteByEmail(EVENT, 'host', { guests: [{ email: 'sam@x.com', name: 'Sam Smith' }] });
    const { token } = guestRows()[0];
    const page = await g.guestPage(token);
    expect(page.guest.rsvp).toBe('pending');
    expect(page.coming.map((c) => c.name)).toEqual(['Wes', 'User']); // members by first name
    await g.replyAsGuest(token, { rsvp: 'yes', adults: 2, kids: 1, note: 'Can\'t wait' });
    expect(guestRows()[0]).toMatchObject({ rsvp: 'yes', adults: 2, kids: 1, note: "Can't wait" });
    expect(mockPushes.find((p) => p.type === 'event_rsvp')).toMatchObject({ uid: 'host', title: '🎂 Sam Smith is going (+2)' });
    const ev = mockDb.rows(COLLECTIONS.EVENTS).get(EVENT);
    expect(ev.guestRsvpCounts.yes).toEqual({ replies: 1, people: 3 });
    // Same reply again: no second push
    mockPushes.length = 0;
    await g.replyAsGuest(token, { rsvp: 'yes', adults: 2, kids: 1 });
    expect(mockPushes).toHaveLength(0);
  });

  test('guests never see addresses; the coordinator does', async () => {
    await g.inviteByEmail(EVENT, 'host', { guests: [{ email: 'sam@x.com', name: 'Sam Smith' }] });
    const hostView = await g.listGuests(EVENT, 'host');
    expect(hostView.guests.find((p) => p.kind === 'email').email).toBe('sam@x.com');
    expect(hostView.emailsLeftToday).toBe(g.DAILY_EMAIL_CAP - 1);
    const memberView = await g.listGuests(EVENT, 'm1');
    const emailRow = memberView.guests.find((p) => p.kind === 'email');
    expect(emailRow.email).toBeUndefined();
    expect(emailRow.name).toBe('Sam');
    expect(memberView.emailsLeftToday).toBeUndefined();
  });

  test('opting out stops messages; resends wait 12 hours', async () => {
    await g.inviteByEmail(EVENT, 'host', { guests: ['sam@x.com', 'bea@y.org'] });
    const [sam, bea] = [...mockDb.rows('eventGuests').entries()];
    await expect(g.resendInvite(EVENT, 'host', sam[0])).rejects.toMatchObject({ code: 'too_soon' });
    await g.optOut(bea[1].token);
    mockSent.length = 0;
    const out = await g.messageGuests(EVENT, 'host', { text: 'Parking is behind the building' });
    expect(out.emailed).toBe(1);
    expect(mockSent.map((m) => m.to)).toEqual(['sam@x.com']);
    expect(mockPushes.some((p) => p.uid === 'm1' && p.type === 'event_message')).toBe(true);
  });

  test('a member changes their reply; the coordinator hears', async () => {
    const out = await g.replyAsMember(EVENT, 'm1', { rsvp: 'no' });
    expect(out.rsvp).toBe('no');
    expect(mockDb.rows(COLLECTIONS.EVENTS).get(EVENT).members.m1).toMatchObject({ rsvp: 'no', adults: 0 });
    expect(mockPushes[0]).toMatchObject({ uid: 'host', type: 'event_rsvp', title: "🎂 Mo can't make it" });
  });

  test('a guest who joins in the app is counted once, with their emailed reply', async () => {
    await g.inviteByEmail(EVENT, 'host', { guests: ['sam@x.com'] });
    await g.replyAsGuest(guestRows()[0].token, { rsvp: 'maybe', adults: 1, kids: 2 });
    const ev = mockDb.rows(COLLECTIONS.EVENTS).get(EVENT);
    mockDb.collection(COLLECTIONS.EVENTS).doc(EVENT).set({ ...ev, memberIds: [...ev.memberIds, 'sam'], members: { ...ev.members, sam: { rsvp: 'yes' } } });
    await g.linkJoinedMember(EVENT, 'sam', 'SAM@x.com');
    const counts = await g.refreshCounts(EVENT);
    expect(mockDb.rows(COLLECTIONS.EVENTS).get(EVENT).members.sam).toMatchObject({ rsvp: 'maybe', kids: 2 });
    expect(counts.maybe.replies).toBe(2); // Mo and Sam, Sam once
  });
});

describe('the day-before reminder', () => {
  test('goes once, to Going/Maybe guests and members who are coming', async () => {
    await g.inviteByEmail(EVENT, 'host', { guests: ['yes@x.com', 'no@x.com', 'quiet@x.com'] });
    const rows = [...mockDb.rows('eventGuests').values()];
    await g.replyAsGuest(rows[0].token, { rsvp: 'yes' });
    await g.replyAsGuest(rows[1].token, { rsvp: 'no' });
    await g.replyAsGuest(rows[2].token, { rsvp: 'maybe' });
    await g.optOut(rows[2].token);
    const ev = mockDb.rows(COLLECTIONS.EVENTS).get(EVENT);
    mockDb.collection(COLLECTIONS.EVENTS).doc(EVENT).set({ ...ev, reminderAt: '2099-04-30T23:00:00.000Z' });
    mockSent.length = 0;
    mockPushes.length = 0;
    const now = new Date('2099-04-30T23:30:00.000Z');
    expect(await g.sendDueReminders(now)).toEqual({ reminded: 1, emailed: 1 });
    expect(mockSent.map((m) => m.to)).toEqual(['yes@x.com']);
    expect(mockSent[0].subject).toBe('Tomorrow: 🎂 Bday');
    expect(mockPushes.map((p) => p.uid).sort()).toEqual(['host', 'm1']);
    expect(await g.sendDueReminders(now)).toEqual({ reminded: 0, emailed: 0 });
  });

  test('never after the start, never for an ended event', async () => {
    const ev = mockDb.rows(COLLECTIONS.EVENTS).get(EVENT);
    mockDb.collection(COLLECTIONS.EVENTS).doc(EVENT).set({ ...ev, reminderAt: '2099-04-30T23:00:00.000Z' });
    expect(await g.sendDueReminders(new Date('2099-05-02T00:00:00.000Z'))).toEqual({ reminded: 0, emailed: 0 });
    mockDb.collection(COLLECTIONS.EVENTS).doc(EVENT).set({ ...ev, reminderAt: '2099-04-30T23:00:00.000Z', endedAt: '2099-04-01' });
    expect(await g.sendDueReminders(new Date('2099-04-30T23:30:00.000Z'))).toEqual({ reminded: 0, emailed: 0 });
  });
});
