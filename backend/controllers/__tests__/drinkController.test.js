jest.mock('../../config/firebase', () => ({ getFirestore: () => ({}) }));
jest.mock('../../services/postcardShareService', () => ({
  isAllowedImageUrl: (u) => typeof u === 'string' && u.startsWith('https://storage.googleapis.com/bucket/')
}));
jest.mock('../../services/messagingService', () => ({}));
jest.mock('../../services/piggyBankService', () => ({}));
jest.mock('../../services/moderationService', () => ({ isBlockedEitherWay: () => false }));
jest.mock('../../utils/networkAccess', () => ({ getConnectedUserIds: async () => new Set() }));

const { parseDrinkSend } = require('../widgets/drinkController');
const { derivePiggyDedupKey } = require('../../models/PiggyBankModels');

const good = {
  recipientId: 'sal', drinkId: 'paper-plane', drinkName: 'Paper Plane',
  imageUrl: 'https://storage.googleapis.com/bucket/circles/card.jpg', note: 'You have to try this'
};

describe('parseDrinkSend', () => {
  test('a good request', () => {
    expect(parseDrinkSend(good, 'wes').value).toEqual({
      recipient: 'sal', drinkId: 'paper-plane', name: 'Paper Plane',
      note: 'You have to try this', imageUrl: good.imageUrl
    });
  });
  test('refuses yourself, bad ids, long notes and outside images', () => {
    expect(parseDrinkSend({ ...good, recipientId: 'wes' }, 'wes').error[1]).toBe('invalid_recipient');
    expect(parseDrinkSend({ ...good, drinkId: 'Paper Plane!' }, 'wes').error[1]).toBe('invalid_drink');
    expect(parseDrinkSend({ ...good, drinkName: '' }, 'wes').error[1]).toBe('invalid_drink');
    expect(parseDrinkSend({ ...good, note: 'x'.repeat(201) }, 'wes').error[1]).toBe('note_too_long');
    expect(parseDrinkSend({ ...good, imageUrl: 'https://evil.example/x.jpg' }, 'wes').error[1]).toBe('invalid_image');
  });
});

describe('drink_received bonus key', () => {
  test('once ever per sender→recipient pair, whatever the message', () => {
    const a = derivePiggyDedupKey('drink_received', { userId: 'sal', senderId: 'wes', messageId: 'm1' });
    const b = derivePiggyDedupKey('drink_received', { userId: 'sal', senderId: 'wes', messageId: 'm2' });
    expect(a).toBe(b);
    expect(derivePiggyDedupKey('drink_received', { userId: 'sal', senderId: 'joey' })).not.toBe(a);
    expect(derivePiggyDedupKey('drink_received', { userId: 'sal' })).toBeNull();
  });
});
