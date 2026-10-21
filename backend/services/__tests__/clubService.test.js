const { FakeFirestore, FakeFieldValue } = require('../../__fixtures__/fakeFirestore');

const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({ getFirestore: () => mockDb, FieldValue: require('../../__fixtures__/fakeFirestore').FakeFieldValue }));
const mockPushes = [];
jest.mock('../notifyQuiet', () => ({ sendInBackground: (to, payload) => mockPushes.push({ to, ...payload }) }));
jest.mock('../../utils/networkAccess', () => ({ getConnectedUserIds: async () => new Set(['ana', 'old']) }));

const clubs = require('../clubService');
const shared = require('../clubs/shared');
void FakeFieldValue;

const users = {
  wes: { displayName: 'Wesley Sgroi', appVersion: '1.4.1' },
  ana: { displayName: 'Ana', appVersion: '1.4.1' },
  joe: { displayName: 'Joe', appVersion: '1.4.1' },
  bob: { displayName: 'Bob', blockedUsers: ['wes'] },
  old: { displayName: 'Old Phone', appVersion: '1.4.0' }
};
beforeAll(async () => {
  for (const [id, data] of Object.entries(users)) await mockDb.collection('users').doc(id).set(data);
});
beforeEach(() => { mockPushes.length = 0; });

const code = async (p) => { try { await p; return null; } catch (e) { return e.code; } };

describe('when meetups happen', () => {
  const club = {
    timezone: 'America/New_York',
    homeSpot: { name: 'Freedom Park' },
    schedule: [{ id: 'sat', weekday: 6, time: '07:00', title: 'Long run', spot: null, notes: '' }],
    events: [{ id: 'turkey', title: 'Turkey Trot', startsAt: '2026-11-26T13:00:00.000Z', spot: { name: 'Uptown' } }]
  };
  test('Saturdays 7 AM stay 7 AM across the clocks going back (2026-11-01)', () => {
    const now = new Date('2026-10-28T12:00:00Z'); // a Wednesday
    const occ = shared.upcomingOccurrences(club, now, { weeks: 2 });
    const sats = occ.filter((o) => o.kind === 'meetup');
    expect(sats.map((o) => [o.key, o.startsAt])).toEqual([
      ['m_sat_2026-10-31', '2026-10-31T11:00:00.000Z'], // EDT
      ['m_sat_2026-11-07', '2026-11-07T12:00:00.000Z'] // EST
    ]);
    expect(sats[0].spot).toEqual({ name: 'Freedom Park' }); // falls back to the usual spot
  });
  test('events join the list in time order; past ones (over an hour ago) drop off', () => {
    const occ = shared.upcomingOccurrences(club, new Date('2026-11-20T12:00:00Z'));
    expect(occ.map((o) => o.key).slice(0, 3)).toEqual(['m_sat_2026-11-21', 'e_turkey', 'm_sat_2026-11-28']);
    const during = shared.upcomingOccurrences(club, new Date('2026-11-21T12:30:00Z'));
    expect(during[0].key).toBe('m_sat_2026-11-21'); // started 30 min ago: still on
    const after = shared.upcomingOccurrences(club, new Date('2026-11-21T13:30:00Z'));
    expect(after[0].key).toBe('e_turkey');
  });
  test('lines read naturally', () => {
    expect(shared.scheduleLine([{ weekday: 6, time: '07:00' }, { weekday: 3, time: '18:30' }])).toBe('Wednesdays 6:30 PM · Saturdays 7 AM');
    expect(shared.occurrenceLine('2026-11-26T13:00:00.000Z', 'America/New_York')).toBe('Thu, Nov 26 · 8 AM');
  });
  test('meetups and events are checked', () => {
    expect(() => shared.parseMeetup({ weekday: 7, time: '07:00' })).toThrow('Pick a day of the week');
    expect(() => shared.parseMeetup({ weekday: 1, time: '25:00' })).toThrow('Pick a time');
    expect(shared.parseMeetup({ weekday: 6, time: '07:00' }, 'run').title).toBe('Saturday run');
    const now = new Date('2026-10-21T12:00:00Z');
    expect(() => shared.parseEvent({ title: 'x', startsAt: '2026-10-01T00:00:00Z' }, now)).toThrow('already passed');
    expect(() => shared.parseEvent({ startsAt: '2026-11-01T00:00:00Z' }, now)).toThrow('Give the event a name');
  });
});

describe('a club, end to end', () => {
  let club;
  let token;
  test('create: the owner is the first organizer and member', async () => {
    club = await clubs.createClub('wes', { name: 'Charlotte Run Club', kind: 'run', timezone: 'America/New_York', homeSpot: { name: 'Freedom Park', lat: 35.19, lng: -80.84 } });
    expect(club).toMatchObject({ name: 'Charlotte Run Club', emoji: '🏃', myRole: 'owner', memberCount: 1, joinOpen: true });
    token = club.inviteLink.split('/').pop();
    expect(club.inviteLink).toMatch(/\/app\/club\//);
  });
  test('joining by link; organizers hear about it; joining twice is fine', async () => {
    const r = await clubs.joinByToken(token, 'ana');
    expect(r.joined).toBe(true);
    expect(r.club.myRole).toBe('member');
    expect(mockPushes).toEqual([expect.objectContaining({ to: 'wes', type: 'club_joined' })]);
    expect((await clubs.joinByToken(token, 'ana')).joined).toBe(false);
    await clubs.joinByToken(token, 'joe');
  });
  test('blocked people and closed joining are refused', async () => {
    expect(await code(clubs.joinByToken(token, 'bob'))).toBe('blocked');
    await clubs.updateClub(club.id, 'wes', { joinOpen: false });
    expect(await code(clubs.joinByToken(token, 'old'))).toBe('join_closed');
    await clubs.updateClub(club.id, 'wes', { joinOpen: true });
  });
  test('only organizers change the schedule; the owner promotes organizers', async () => {
    expect(await code(clubs.addMeetup(club.id, 'ana', { weekday: 6, time: '07:00' }))).toBe('not_organizer');
    const { club: c1 } = await clubs.addMeetup(club.id, 'wes', { weekday: 6, time: '07:00', title: 'Long run' });
    expect(c1.schedule).toHaveLength(1);
    expect(c1.scheduleLine).toBe('Saturdays 7 AM');
    expect(c1.upcoming.length).toBeGreaterThan(0);
    expect(await code(clubs.setRole(club.id, 'ana', 'joe', 'organizer'))).toBe('not_owner');
    const { club: c2 } = await clubs.setRole(club.id, 'wes', 'ana', 'organizer');
    expect(c2.members.find((m) => m.userId === 'ana').role).toBe('organizer');
  });
  test('RSVP: going, then can\'t make it; unknown dates refused', async () => {
    const detail = await clubs.getClub(club.id, 'joe');
    const key = detail.upcoming[0].key;
    let r = await clubs.rsvp(club.id, 'joe', { key, status: 'going' });
    expect(r.occurrence).toMatchObject({ myRsvp: 'going', going: [expect.objectContaining({ userId: 'joe', name: 'Joe' })] });
    r = await clubs.rsvp(club.id, 'joe', { key, status: 'not' });
    expect(r.occurrence).toMatchObject({ myRsvp: 'not', going: [], notGoingCount: 1 });
    expect(await code(clubs.rsvp(club.id, 'joe', { key: 'm_nope_2020-01-01', status: 'going' }))).toBe('not_found');
  });
  test('a bulletin tells every member except the author and anyone who muted the club', async () => {
    await clubs.setMuted(club.id, 'joe', true);
    expect(await code(clubs.createPost(club.id, 'joe', { kind: 'bulletin', text: 'hi' }))).toBe('not_organizer');
    mockPushes.length = 0;
    await clubs.createPost(club.id, 'wes', { kind: 'bulletin', text: 'Route change Saturday' });
    expect(mockPushes.map((p) => [p.to, p.type])).toEqual([['ana', 'club_bulletin']]);
  });
  test('a board post tells nobody; a reply tells only the post\'s author', async () => {
    await clubs.setMuted(club.id, 'joe', false);
    mockPushes.length = 0;
    const { post } = await clubs.createPost(club.id, 'joe', { kind: 'board', text: 'Anyone up for Tuesday?' });
    expect(mockPushes).toEqual([]);
    await clubs.addReply(club.id, 'ana', post.id, { text: 'Me!' });
    await new Promise((r) => setTimeout(r, 5)); // distinct timestamps
    await clubs.addReply(club.id, 'joe', post.id, { text: 'Great' }); // own post: no push
    expect(mockPushes.map((p) => [p.to, p.type])).toEqual([['joe', 'club_reply']]);
    const { replies } = await clubs.listReplies(club.id, 'wes', post.id);
    expect(replies.map((r) => r.text)).toEqual(['Me!', 'Great']);
    const { posts } = await clubs.listPosts(club.id, 'wes', { kind: 'board' });
    expect(posts[0]).toMatchObject({ replyCount: 2, canDelete: true });
    const reacted = await clubs.react(club.id, 'ana', post.id, { emoji: '🔥' });
    expect(reacted.post.reactions).toEqual([{ emoji: '🔥', count: 1, mine: true }]);
    expect((await clubs.react(club.id, 'ana', post.id, { emoji: '🔥' })).post.reactions).toEqual([]);
    expect(await code(clubs.deletePost(club.id, 'ana', 'nope'))).toBe('not_found');
  });
  test('removal: organizers remove members, not the owner; removed people can\'t rejoin', async () => {
    expect(await code(clubs.removeMember(club.id, 'joe', 'ana'))).toBe('not_organizer');
    expect(await code(clubs.removeMember(club.id, 'ana', 'wes'))).toBe('owner');
    await clubs.removeMember(club.id, 'ana', 'joe');
    expect(await code(clubs.joinByToken(token, 'joe'))).toBe('removed');
    expect(await code(clubs.leaveClub(club.id, 'wes'))).toBe('owner_cannot_leave');
  });
  test('invites: connections only; an old app is asked to update', async () => {
    mockPushes.length = 0;
    const r = await clubs.inviteConnections(club.id, 'wes', ['old', 'stranger']);
    expect(r.invited).toBe(1);
    expect(mockPushes[0]).toMatchObject({ to: 'old', type: 'club_invite', data: expect.objectContaining({ needsUpdate: 'true' }) });
    expect(mockPushes[0].body).toMatch(/Update FavCircles/);
  });
  test('my clubs list carries the next meetup; ending it hides it', async () => {
    const list = await clubs.listClubs('ana');
    expect(list[0]).toMatchObject({ id: club.id, myRole: 'organizer', next: expect.objectContaining({ kind: 'meetup' }) });
    expect(await code(clubs.endClub(club.id, 'ana'))).toBe('not_owner');
    await clubs.endClub(club.id, 'wes');
    expect(await clubs.listClubs('ana')).toEqual([]);
  });
});

describe('who can open clubs', () => {
  test('1.4.1 and newer, on any phone', () => {
    expect(shared.canOpenClubs({ appVersion: '1.4.1' })).toBe(true);
    expect(shared.canOpenClubs({ appVersion: '1.4.0' })).toBe(false);
    expect(shared.canOpenClubs({ appVersion: '1.4.0', deviceTokens: [{ appVersion: '1.5.0' }] })).toBe(true);
    expect(shared.canOpenClubs(null)).toBe(false);
  });
});

describe('the invite page', () => {
  const { renderClubInvite } = require('../../views/clubPage');
  test('says what and when, never who', () => {
    const html = renderClubInvite('tok', { name: 'Run <Club>', emoji: '🏃', ownerName: 'Wes', memberCount: 12, joinOpen: true, scheduleLine: 'Saturdays 7 AM', homeSpotName: 'Freedom Park' });
    expect(html).toContain('Run &lt;Club&gt;');
    expect(html).toContain('Saturdays 7 AM');
    expect(html).toContain('12 members');
    expect(html).toContain('circles://club/tok');
    expect(renderClubInvite('tok', null)).toContain("isn't valid");
  });
});

describe('upcoming list keeps one-off events (2026-10-21)', () => {
  const { upcomingOccurrences } = require('../clubs/shared');
  it('a twice-weekly club never pushes a far-off race off the list', () => {
    const club = {
      timezone: 'America/New_York',
      schedule: [{ id: 'sat', weekday: 6, time: '07:00', title: 'Sat' }, { id: 'wed', weekday: 3, time: '18:30', title: 'Wed' }],
      events: [{ id: 'race', title: 'Turkey Trot', startsAt: '2026-12-20T13:00:00Z' }]
    };
    const list = upcomingOccurrences(club, new Date('2026-10-21T12:00:00Z'));
    expect(list.filter((o) => o.kind === 'meetup')).toHaveLength(12);
    expect(list.map((o) => o.key)).toContain('e_race');
    expect(list[list.length - 1].key).toBe('e_race');
  });
});
