// Clubs name the owner, members, RSVPs and post authors as they are NOW.
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({ getFirestore: () => mockDb, FieldValue: require('../../__fixtures__/fakeFirestore').FakeFieldValue }));
jest.mock('../notifyQuiet', () => ({ sendInBackground: () => {} }));

const clubs = require('../clubService');
const s = require('../clubs/shared');

const put = (col, id, data) => mockDb.collection(col).doc(id).set(data);
const NOW = new Date('2026-10-28T12:00:00Z');

beforeAll(async () => {
  await put('users', 'wes', { displayName: 'Wes Sgroi', profilePicture: 'https://x/wes.jpg' });
  await put('users', 'ana', { displayName: 'Ana Maria', profilePicture: 'https://x/ana.jpg' });
  await s.clubsCol().doc('club1').set({
    name: 'Run Club', kind: 'run', ownerId: 'wes', ownerName: 'Wesley', organizerIds: ['wes'],
    memberIds: ['wes', 'ana', 'gone'], inviteToken: 'clubtok_abcdefghijk', joinOpen: true, createdAt: '2026-10-01',
    members: { wes: { name: 'Wesley', avatarUrl: null }, ana: { name: 'Ana', avatarUrl: 'https://x/old.jpg' }, gone: { name: 'Ghost', avatarUrl: 'https://x/g.jpg' } },
    timezone: 'America/New_York',
    schedule: [{ id: 'sat', weekday: 6, time: '07:00', title: 'Long run', spot: null, notes: '' }]
  });
  await s.rsvpsCol().doc('club1_m_sat_2026-10-31').set({ clubId: 'club1', key: 'm_sat_2026-10-31',
    going: { ana: { name: 'Ana', avatarUrl: null, at: '2026-10-27' }, gone: { name: 'Ghost', avatarUrl: null, at: '2026-10-28' } }, not: {} });
  await s.postsCol().doc('p1').set({ clubId: 'club1', kind: 'board', authorId: 'ana', authorName: 'Ana', authorAvatar: null, text: 'hi', reactions: {}, createdAt: '2026-10-27' });
  await s.postsCol().doc('p2').set({ clubId: 'club1', kind: 'board', authorId: 'gone', authorName: 'Ghost', authorAvatar: 'https://x/g.jpg', text: 'yo', reactions: {}, createdAt: '2026-10-26' });
});

test('the club page: current owner, members and post authors; deleted accounts keep stored values', async () => {
  const detail = await clubs.getClub('club1', 'wes');
  expect(detail.ownerName).toBe('Wes Sgroi');
  expect(detail.members.find((m) => m.userId === 'ana')).toMatchObject({ name: 'Ana Maria', avatarUrl: 'https://x/ana.jpg' });
  expect(detail.members.find((m) => m.userId === 'gone')).toMatchObject({ name: 'Ghost', avatarUrl: 'https://x/g.jpg' });
  expect(detail.boardPreview.map((p) => [p.authorName, p.authorAvatar])).toEqual([['Ana Maria', 'https://x/ana.jpg'], ['Ghost', 'https://x/g.jpg']]);
});

test('who is going to the next meetup (club list) is current', async () => {
  const [club] = await clubs.listClubs('wes', NOW);
  expect(club.next.key).toBe('m_sat_2026-10-31');
  expect(club.next.going).toEqual([
    { userId: 'ana', name: 'Ana Maria', avatarUrl: 'https://x/ana.jpg' },
    { userId: 'gone', name: 'Ghost', avatarUrl: 'https://x/g.jpg' }
  ]);
});

test('the pure mappers keep stored values without a users map', () => {
  expect(s.toClientPost('p', { authorId: 'ana', authorName: 'Ana' }, { organizerIds: [] }, 'wes').authorName).toBe('Ana');
});

test('join previews name the current owner', async () => {
  expect(await clubs.previewByToken('clubtok_abcdefghijk', 'ana')).toMatchObject({ ownerName: 'Wes Sgroi' });
  expect(await clubs.publicPreview('clubtok_abcdefghijk')).toMatchObject({ ownerName: 'Wes Sgroi' });
});
