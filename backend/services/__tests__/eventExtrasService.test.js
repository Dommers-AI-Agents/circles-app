jest.mock('../../config/firebase', () => ({ getFirestore: () => ({}) }));
jest.mock('../notifyQuiet', () => ({ sendInBackground: jest.fn() }));
const { buildRecap, sortSongs } = require('../eventExtrasService');
const { toClientEvent } = require('../eventService');
const { derivePiggyDedupKey } = require('../../models/PiggyBankModels');

const event = {
  name: 'Party Bus', emoji: '🚌', hostId: 'wes', hostName: 'Wes', inviteToken: 'abcdefghijklmnopqrst',
  memberIds: ['wes', 'sal', 'brit'],
  members: { wes: { name: 'Wes' }, sal: { name: 'Sal' }, brit: { name: 'Brit' } },
  challenges: [{ id: 'c1', text: 'Group selfie', emoji: '🤳' }, { id: 'c2', text: 'Best dance move', emoji: '💃' }],
  createdAt: '2026-10-06T20:00:00Z'
};

describe('event extras', () => {
  test('recap: photo of the night, top photographer, challenges done, top shout-out and song', () => {
    const photos = [
      { imageUrl: 'a', uploaderId: 'sal', uploaderName: 'Sal', likes: ['wes'], createdAt: '2026-10-06T21:00:00Z', challengeId: 'c1' },
      { imageUrl: 'b', uploaderId: 'sal', uploaderName: 'Sal', likes: ['wes', 'brit'], createdAt: '2026-10-06T22:00:00Z' },
      { imageUrl: 'c', uploaderId: 'brit', uploaderName: 'Brit', likes: [], createdAt: '2026-10-06T20:30:00Z', challengeId: 'gone' }
    ];
    const r = buildRecap({
      id: 'e1', data: { ...event, endedAt: '2026-10-07T02:00:00Z' }, photos,
      places: [{ name: 'Midnight Diner', lat: 35.22, lng: -80.84 }],
      posts: [{ text: 'Happy birthday Brit!', authorName: 'Sal', reactions: { '🎉': ['wes', 'brit'] } }, { text: 'hi', authorName: 'Wes', reactions: {} }],
      songs: [{ title: 'Mr. Brightside', votes: ['wes', 'sal', 'brit'] }, { title: 'Wagon Wheel', votes: ['sal'] }]
    });
    expect(r.photoOfTheNight).toEqual({ imageUrl: 'b', uploaderName: 'Sal', likes: 2 });
    expect(r.topPhotographer).toEqual({ name: 'Sal', photos: 2 });
    expect(r.challenges).toEqual({ total: 2, done: 1 });          // a deleted challenge doesn't count
    expect(r.topShoutout.text).toBe('Happy birthday Brit!');
    expect(r.topSong.title).toBe('Mr. Brightside');
    expect(r.startedAt).toBe('2026-10-06T20:30:00Z');             // first photo
    expect(r.memberNames).toEqual(['Wes', 'Sal', 'Brit']);
  });

  test('recap with nothing liked or posted stays honest', () => {
    const r = buildRecap({ id: 'e1', data: event, photos: [], places: [], posts: [], songs: [] });
    expect(r.photoOfTheNight).toBeNull();
    expect(r.topShoutout).toBeNull();
    expect(r.topSong).toBeNull();
    expect(r.photoCount).toBe(0);
  });

  test('songs: unplayed first, most votes, then oldest', () => {
    const songs = sortSongs([
      { id: 'a', votes: 1, played: false, createdAt: '2' },
      { id: 'b', votes: 5, played: true, createdAt: '1' },
      { id: 'c', votes: 3, played: false, createdAt: '3' },
      { id: 'd', votes: 1, played: false, createdAt: '1' }
    ]);
    expect(songs.map(s => s.id)).toEqual(['c', 'd', 'a', 'b']);
  });

  test('roll call: who is here, my answer, locations only for members', () => {
    const data = { ...event, rollCall: { id: 'rc1', startedAt: 't', startedByName: 'Wes', here: { wes: 't', sal: 't', gone: 't' },
      locations: { sal: { lat: 35.2, lng: -80.8, at: 't' }, gone: { lat: 1, lng: 1, at: 't' } } } };
    const forSal = toClientEvent('e1', data, 'sal');
    expect(forSal.rollCall.hereIds.sort()).toEqual(['sal', 'wes']);
    expect(forSal.rollCall.imHere).toBe(true);
    expect(forSal.rollCall.locations).toEqual([{ userId: 'sal', lat: 35.2, lng: -80.8, at: 't' }]);
    expect(toClientEvent('e1', data, 'brit').rollCall.imHere).toBe(false);
    expect(toClientEvent('e1', { ...data, rollCall: { ...data.rollCall, closedAt: 'x' } }, 'sal').rollCall).toBeNull();
  });

  test('ended events and challenges reach the client', () => {
    const c = toClientEvent('e1', { ...event, endedAt: 'z' }, 'wes');
    expect(c.endedAt).toBe('z');
    expect(c.challenges.map(x => x.id)).toEqual(['c1', 'c2']);
  });

  test('a challenge coin is once per challenge per person', () => {
    expect(derivePiggyDedupKey('event_challenge', { userId: 'sal', eventId: 'e1', challengeId: 'c1' })).toBe('event_challenge:sal:e1:c1');
    expect(derivePiggyDedupKey('event_challenge', { userId: 'sal', eventId: 'e1' })).toBeNull();
  });
});

describe('event lock screen', () => {
  const { contentState } = require('../eventLiveActivityService');
  const base = { name: 'Party Bus', hostName: 'Wes', memberIds: ['wes', 'sal', 'brit'], photoCount: 12, challenges: [{ id: 'c1' }] };

  test('the newest thing is the headline', () => {
    const s = contentState({ ...base,
      lastPhoto: { by: 'Sal', count: 3, at: '2026-10-06T21:00:00Z' },
      lastShoutout: { text: 'Happy birthday Brit!', authorName: 'Wes', at: '2026-10-06T21:05:00Z' } }, { title: 'Mr. Brightside', artist: 'The Killers' });
    expect(s).toEqual({ members: 3, photos: 12, headline: '💬 Wes: Happy birthday Brit!', rollCall: null,
      song: '🎵 Mr. Brightside · The Killers', challenges: '1 photo challenge', ended: false });
  });

  test('roll call shows who is here, ended says so', () => {
    const rc = { id: 'r', startedAt: '2026-10-06T22:00:00Z', startedByName: 'Wes', here: { wes: 't', sal: 't' } };
    const s = contentState({ ...base, rollCall: rc, lastPhoto: { by: 'Sal', count: 1, at: '2026-10-06T21:00:00Z' } }, null);
    expect(s.rollCall).toBe('Roll call: 2 of 3 here');
    expect(s.headline).toBe('🙋 Wes called roll');
    const ended = contentState({ ...base, endedAt: 'x' }, null);
    expect(ended.ended).toBe(true);
    expect(ended.headline).toBe('Party Bus has ended. See the recap ✨');
  });
});
