// Events name people as they are NOW: host, members, invitees, roll call,
// photo uploaders, place taggers, wall authors, song adders and the recap.
// The name stored on the event is only the fallback for a deleted account.
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({ getFirestore: () => mockDb, FieldValue: require('../../__fixtures__/fakeFirestore').FakeFieldValue }));
jest.mock('../notifyQuiet', () => ({ sendInBackground: () => {} }));
jest.mock('../innerCircleService', () => ({}));
jest.mock('../eventLiveActivityService', () => ({ refreshSoon: () => {} }));
jest.mock('../eventVideoService', () => ({ isVisible: () => true, viewerVideoLimits: async () => null }));
jest.mock('../emailFallback', () => ({ pushReachable: () => true }));

const ev = require('../eventService');
const extras = require('../eventExtrasService');
const { fetchUsersById } = require('../userLookup');
const { COLLECTIONS } = require('../../models/FirestoreModels');

const put = (col, id, data) => mockDb.collection(col).doc(id).set(data);
let eventId;

beforeEach(async () => {
  mockDb.rows(COLLECTIONS.USERS).clear();
  await put(COLLECTIONS.USERS, 'wes', { displayName: 'Wes Sgroi', profilePicture: 'https://x/wes.jpg' });
  await put(COLLECTIONS.USERS, 'sal', { displayName: 'Sal Sgroi', profilePicture: 'https://x/sal.jpg' });
  await put(COLLECTIONS.USERS, 'amy', { displayName: 'Amy B' });
  const ref = await ev.eventsCol().add({
    name: 'Party Bus', hostId: 'wes', hostName: 'Wesley', inviteToken: 'tok_abcdefghijklmnop',
    memberIds: ['wes', 'sal', 'gone'], pendingInviteIds: ['amy'],
    members: { wes: { name: 'Wesley', avatarUrl: null }, sal: { name: 'Salvatore', avatarUrl: 'https://x/old.jpg' }, gone: { name: 'Ghost', avatarUrl: 'https://x/g.jpg' } },
    invited: { amy: { name: 'Amy' } },
    rollCall: { id: 'rc1', startedAt: '2026-10-06', startedBy: 'wes', startedByName: 'Wesley', here: {} },
    createdAt: '2026-10-06'
  });
  eventId = ref.id;
});

test('an event shows current host, member, invitee and roll-call names; a deleted member keeps the stored card', async () => {
  const [listed] = await ev.listEvents('sal');
  for (const e of [listed, (await ev.getEvent(eventId, 'sal')).event]) {
    expect(e.hostName).toBe('Wes Sgroi');
    expect(e.members).toEqual([
      { id: 'wes', name: 'Wes Sgroi', avatarUrl: 'https://x/wes.jpg', isHost: true },
      { id: 'sal', name: 'Sal Sgroi', avatarUrl: 'https://x/sal.jpg', isHost: false },
      { id: 'gone', name: 'Ghost', avatarUrl: 'https://x/g.jpg', isHost: false }
    ]);
    expect(e.invited).toEqual([{ id: 'amy', name: 'Amy B' }]);
    expect(e.rollCall.startedByName).toBe('Wes Sgroi');
  }
  // The pure mapper without a users map keeps the stored values
  const stored = ev.toClientEvent(eventId, (await ev.eventsCol().doc(eventId).get()).data(), 'sal');
  expect(stored.hostName).toBe('Wesley');
  expect(await ev.previewByToken('tok_abcdefghijklmnop', 'amy')).toMatchObject({ hostName: 'Wes Sgroi' });
  expect(await ev.publicPreview('tok_abcdefghijklmnop')).toMatchObject({ hostName: 'Wes Sgroi' });
});

test('photos and places in the album name the current uploader / tagger', async () => {
  await ev.photosCol().add({ eventId, imageUrl: 'https://x/p.jpg', uploaderId: 'sal', uploaderName: 'Salvatore', createdAt: '2026-10-06T21:00' });
  await ev.photosCol().add({ eventId, imageUrl: 'https://x/q.jpg', uploaderId: 'gone', uploaderName: 'Ghost', createdAt: '2026-10-06T20:00' });
  await ev.placesCol().add({ eventId, name: 'Bar', lat: 1, lng: 1, taggedById: 'sal', taggedByName: 'Salvatore', createdAt: '2026-10-06' });
  const { photos, places } = await ev.getEvent(eventId, 'wes');
  expect(photos.map(p => p.uploaderName)).toEqual(['Sal Sgroi', 'Ghost']);
  expect(places[0].taggedByName).toBe('Sal Sgroi');
});

test('wall, songs and the recap name people as they are now', async () => {
  const wall = ev.eventsCol().doc(eventId).collection('wall');
  await wall.add({ authorId: 'sal', authorName: 'Salvatore', text: 'woo', reactions: { '🔥': ['wes'] }, createdAt: '2026-10-06' });
  await wall.add({ authorId: 'gone', authorName: 'Ghost', text: 'boo', reactions: {}, createdAt: '2026-10-05' });
  const songs = ev.eventsCol().doc(eventId).collection('songs');
  await songs.add({ title: 'Song', addedById: 'sal', addedByName: 'Salvatore', votes: ['sal'], createdAt: '2026-10-06' });
  expect((await extras.listWall(eventId, 'wes')).posts.map(p => p.authorName)).toEqual(['Sal Sgroi', 'Ghost']);
  expect((await extras.listSongs(eventId, 'wes')).songs[0].addedByName).toBe('Sal Sgroi');

  await ev.photosCol().add({ eventId, imageUrl: 'https://x/p.jpg', uploaderId: 'sal', uploaderName: 'Salvatore', likes: ['wes'], createdAt: '2026-10-06T21:00' });
  const { recap } = await extras.getRecap(eventId, 'wes');
  expect(recap.memberNames).toEqual(['Wes Sgroi', 'Sal Sgroi', 'Ghost']);
  expect(recap.photoOfTheNight.uploaderName).toBe('Sal Sgroi');
  expect(recap.topPhotos[0].uploaderName).toBe('Sal Sgroi');
  expect(recap.topPhotographer.name).toBe('Sal Sgroi');
  expect(recap.topShoutout.authorName).toBe('Sal Sgroi');
});

test('fetchUsersById feeds the pure recap the same way', async () => {
  const people = await fetchUsersById(['sal']);
  const r = extras.buildRecap({ id: 'e', data: { memberIds: ['sal'], members: { sal: { name: 'Old' } } }, photos: [], places: [], posts: [], songs: [], people });
  expect(r.memberNames).toEqual(['Sal Sgroi']);
});
