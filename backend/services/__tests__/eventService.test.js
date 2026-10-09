jest.mock('../../config/firebase', () => ({ getFirestore: () => ({}) }));
jest.mock('../notifyQuiet', () => ({ sendInBackground: () => {} }));

const svc = require('../eventService');
const { derivePiggyDedupKey } = require('../../models/PiggyBankModels');
const config = require('../../config/piggyBankConfig');
const { renderEventInvite } = require('../../views/eventPage');

describe('event names and emoji', () => {
  test('a blank name becomes Party Bus; long names are cut', () => {
    expect(svc.cleanEventName('')).toBe('Party Bus');
    expect(svc.cleanEventName(undefined)).toBe('Party Bus');
    expect(svc.cleanEventName('  Sal’s 40th  ')).toBe('Sal’s 40th');
    expect(svc.cleanEventName('x'.repeat(80))).toHaveLength(40);
  });
  test('emoji: short or the bus', () => {
    expect(svc.cleanEmoji('🎉')).toBe('🎉');
    expect(svc.cleanEmoji('not an emoji at all')).toBe('🚌');
    expect(svc.cleanEmoji(null)).toBe('🚌');
  });
});

describe('tagged places', () => {
  test('needs a name and a real location', () => {
    expect(svc.parsePlace({ name: 'Midnight Diner', lat: 35.22, lng: -80.84, address: '115 Graham St' }))
      .toMatchObject({ name: 'Midnight Diner', lat: 35.22, lng: -80.84, category: 'other' });
    const code = (b) => { try { svc.parsePlace(b); return null; } catch (e) { return e.code; } };
    expect(code({ lat: 1, lng: 1 })).toBe('invalid_place');
    expect(code({ name: 'X', lat: 'abc', lng: 1 })).toBe('invalid_place');
    expect(code({ name: 'X', lat: 95, lng: 1 })).toBe('invalid_place');
  });
});

describe('where a photo was taken (Wes, 2026-10-09)', () => {
  const now = Date.parse('2026-10-09T12:00:00Z');
  test('keeps a real spot and time; drops anything that does not parse', () => {
    expect(svc.parsePhotoCapture({ lat: 35.2271, lng: -80.8431, takenAt: '2026-10-04T18:10:05Z' }, now))
      .toEqual({ lat: 35.2271, lng: -80.8431, takenAt: '2026-10-04T18:10:05.000Z' });
    expect(svc.parsePhotoCapture({ lat: '35.2271', lng: '-80.8431' }, now)).toMatchObject({ lat: 35.2271, lng: -80.8431, takenAt: null });
    expect(svc.parsePhotoCapture({}, now)).toEqual({ lat: null, lng: null, takenAt: null });
    expect(svc.parsePhotoCapture({ lat: 0, lng: 0 }, now)).toMatchObject({ lat: null, lng: null });
    expect(svc.parsePhotoCapture({ lat: 95, lng: 1 }, now)).toMatchObject({ lat: null, lng: null });
    expect(svc.parsePhotoCapture({ lat: 35, lng: 'abc' }, now)).toMatchObject({ lat: null, lng: null });
    expect(svc.parsePhotoCapture({ lat: 35 }, now)).toMatchObject({ lat: null, lng: null });
    expect(svc.parsePhotoCapture({ takenAt: 'yesterday' }, now).takenAt).toBeNull();
    expect(svc.parsePhotoCapture({ takenAt: '1999-12-31T00:00:00Z' }, now).takenAt).toBeNull();
    expect(svc.parsePhotoCapture({ takenAt: '2026-10-12T00:00:00Z' }, now).takenAt).toBeNull();
    expect(svc.parsePhotoCapture({ takenAt: '2026-10-09T20:00:00Z' }, now).takenAt).toBe('2026-10-09T20:00:00.000Z');
  });
  test('the nearest tagged place within 150 m, else none', () => {
    const places = [
      { id: 'a', name: 'Midnight Diner', lat: 35.2271, lng: -80.8431 },
      { id: 'b', name: 'Next Door', lat: 35.2276, lng: -80.8431 },      // ~55 m north
      { id: 'c', name: 'Across Town', lat: 35.30, lng: -80.80 },
      { id: 'd', name: 'No spot' }
    ];
    expect(svc.distanceMeters(35.2271, -80.8431, 35.2276, -80.8431)).toBeCloseTo(55.6, 0);
    expect(svc.nearestTaggedPlace({ lat: 35.2272, lng: -80.8431 }, places)).toEqual({ id: 'a', name: 'Midnight Diner' });
    expect(svc.nearestTaggedPlace({ lat: 35.2275, lng: -80.8431 }, places)).toEqual({ id: 'b', name: 'Next Door' });
    expect(svc.nearestTaggedPlace({ lat: 35.25, lng: -80.8431 }, places)).toBeNull();
    expect(svc.nearestTaggedPlace({ lat: null, lng: null }, places)).toBeNull();
    expect(svc.nearestTaggedPlace({ lat: 35.2271, lng: -80.8431 }, [])).toBeNull();
    expect(svc.PHOTO_PLACE_RADIUS_M).toBe(150);
  });
  test('a member sees where and when; older photos read as unknown', () => {
    const places = [{ id: 'a', name: 'Midnight Diner', lat: 35.2271, lng: -80.8431 }];
    const located = { id: 'p1', data: () => ({ imageUrl: 'https://x/1.jpg', uploaderId: 'sal', uploaderName: 'Sal', likes: ['wes'],
      createdAt: '2026-10-04T21:00:00Z', lat: 35.2272, lng: -80.8431, takenAt: '2026-10-04T18:10:05.000Z' }) };
    expect(svc.toClientPhoto(located, 'wes', 'wes', places)).toMatchObject({
      id: 'p1', likedByMe: true, canDelete: true,
      lat: 35.2272, lng: -80.8431, takenAt: '2026-10-04T18:10:05.000Z', placeId: 'a', placeName: 'Midnight Diner'
    });
    // No places tagged (yet): the spot still comes back, the place does not
    expect(svc.toClientPhoto(located, 'sal', 'wes')).toMatchObject({ lat: 35.2272, placeId: null, placeName: null });
    const old = { id: 'p0', data: () => ({ imageUrl: 'https://x/0.jpg', uploaderId: 'sal', uploaderName: 'Sal', createdAt: '2026-10-04T20:00:00Z' }) };
    expect(svc.toClientPhoto(old, 'wes', 'wes', places)).toMatchObject({ takenAt: null, lat: null, lng: null, placeId: null, placeName: null });
  });
});

describe('what a member sees', () => {
  const data = {
    name: 'Party Bus', emoji: '🚌', hostId: 'wes', hostName: 'Wesley', joinOpen: true, inviteToken: 'abcdefghijklmnopqrst',
    memberIds: ['wes', 'sal'], members: { wes: { name: 'Wesley', circleId: 'c1' }, sal: { name: 'Sal', innerListId: 'ic_x' } },
    createdAt: '2026-10-04T20:00:00Z'
  };
  test('host view, invite link, own circle only', () => {
    const e = svc.toClientEvent('e1', data, 'wes');
    expect(e.isHost).toBe(true);
    expect(e.inviteUrl).toBe(`${svc.LINK_BASE}abcdefghijklmnopqrst`);
    expect(e.myCircleId).toBe('c1');
    expect(e.members.map(m => m.id)).toEqual(['wes', 'sal']);
    expect(JSON.stringify(e)).not.toContain('ic_x');
    expect(svc.toClientEvent('e1', data, 'sal')).toMatchObject({ isHost: false, myCircleId: null });
    const withInvites = { ...data, pendingInviteIds: ['amy', 'sal'], invited: { amy: { name: 'Amy' } } };
    expect(svc.toClientEvent('e1', withInvites, 'wes').invited).toEqual([{ id: 'amy', name: 'Amy' }]);
    expect(svc.toClientEvent('e1', data, 'wes').invited).toEqual([]);
    expect(svc.toClientEvent('e1', data, 'wes')).toMatchObject({ archived: false, archivedForEveryone: false });
    const mine = { ...data, members: { ...data.members, sal: { name: 'Sal', archivedAt: '2026-10-06' } } };
    expect(svc.toClientEvent('e1', mine, 'sal').archived).toBe(true);
    expect(svc.toClientEvent('e1', mine, 'wes').archived).toBe(false);
    expect(svc.toClientEvent('e1', { ...data, archivedAt: '2026-10-06' }, 'sal')).toMatchObject({ archived: true, archivedForEveryone: true });
  });
  test('event Inner Circle list = other members I am connected to', () => {
    expect(svc.listMembersFor(['wes', 'sal', 'joe', 'amy'], 'wes', new Set(['sal', 'amy', 'zed']))).toEqual(['sal', 'amy']);
    expect(svc.listMembersFor(['wes'], 'wes', new Set(['sal']))).toEqual([]);
  });
});

describe('FavCoin for joining', () => {
  test('once per event per person, 1 coin, 3 a day', () => {
    expect(derivePiggyDedupKey('event_joined', { userId: 'sal', eventId: 'e1' })).toBe('event_joined:sal:e1');
    expect(derivePiggyDedupKey('event_joined', { userId: 'sal' })).toBeNull();
    expect(config.COINS.EVENT_JOINED).toBe(1);
    expect(config.DAILY_CAPS.EVENT_JOINED).toBe(3);
  });
});

describe('public invite page', () => {
  test('shows the event and the two steps, never members; escapes', () => {
    const html = renderEventInvite('abcdefghijklmnopqrst', { name: '<b>Bus</b>', emoji: '🚌', hostName: 'Wesley', memberCount: 12, joinOpen: true });
    expect(html).toContain('Wesley invited you');
    expect(html).toContain('12 people are in');
    expect(html).toContain('circles://event/abcdefghijklmnopqrst');
    expect(html).toContain('apple-itunes-app');
    expect(html).not.toContain('<b>Bus</b>');
    expect(renderEventInvite('nope', null)).toContain("isn't valid");
  });
});

describe('event invites ask older apps to update (Wes, 2026-10-08)', () => {
  const { canOpenEvents } = require('../eventService');
  test('1.3.8 and newer can; 1.3.7 — any build — and unknown are asked to update', () => {
    expect(canOpenEvents({ appVersion: '1.3.8', appBuild: '1' })).toBe(true);
    expect(canOpenEvents({ appVersion: '1.4.0' })).toBe(true);
    expect(canOpenEvents({ appVersion: '1.3.7', appBuild: '8' })).toBe(false);
    expect(canOpenEvents({ appVersion: '1.3.6', appBuild: '7' })).toBe(false);
    expect(canOpenEvents({})).toBe(false);
    expect(canOpenEvents(null)).toBe(false);
  });
  test('any phone on 1.3.8 is enough', () => {
    expect(canOpenEvents({ appVersion: '1.3.7', appBuild: '8',
      deviceTokens: [{ appVersion: '1.3.6' }, { appVersion: '1.3.8', appBuild: '1' }] })).toBe(true);
  });
});
