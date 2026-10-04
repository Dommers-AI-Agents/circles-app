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
