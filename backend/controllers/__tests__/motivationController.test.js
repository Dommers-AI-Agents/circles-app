jest.mock('../../config/firebase', () => ({ getFirestore: () => ({}) }));
jest.mock('../../services/postcardShareService', () => ({
  isAllowedImageUrl: (u) => typeof u === 'string' && u.startsWith('https://storage.googleapis.com/bucket/')
}));
jest.mock('../../services/messagingService', () => ({}));
jest.mock('../../services/moderationService', () => ({ isBlockedEitherWay: () => false }));
jest.mock('../../utils/networkAccess', () => ({ getConnectedUserIds: async () => new Set() }));

const { parseMotivationSend, chatText } = require('../widgets/motivationController');

const good = {
  recipientId: 'sal', lineId: '0a1b2c3d', line: '  Your fastest mile was to the fridge.  ',
  imageUrl: 'https://storage.googleapis.com/bucket/circles/card.jpg'
};

const codeOf = (fn) => { try { fn(); return null; } catch (e) { return e.code; } };

describe('parseMotivationSend', () => {
  test('a good request, line trimmed', () => {
    expect(parseMotivationSend(good, 'wes')).toEqual({
      recipient: 'sal', lineId: '0a1b2c3d', line: 'Your fastest mile was to the fridge.', imageUrl: good.imageUrl
    });
  });
  test('refuses yourself, bad ids, empty or long lines and outside images', () => {
    expect(codeOf(() => parseMotivationSend({ ...good, recipientId: 'wes' }, 'wes'))).toBe('invalid_recipient');
    expect(codeOf(() => parseMotivationSend({ ...good, recipientId: '' }, 'wes'))).toBe('invalid_recipient');
    expect(codeOf(() => parseMotivationSend({ ...good, lineId: 'ZZZZ' }, 'wes'))).toBe('invalid_line');
    expect(codeOf(() => parseMotivationSend({ ...good, line: '   ' }, 'wes'))).toBe('invalid_line');
    expect(codeOf(() => parseMotivationSend({ ...good, line: 'x'.repeat(161) }, 'wes'))).toBe('invalid_line');
    expect(codeOf(() => parseMotivationSend({ ...good, imageUrl: 'https://evil.example/x.jpg' }, 'wes'))).toBe('invalid_image');
    expect(codeOf(() => parseMotivationSend(null, 'wes'))).toBe('invalid_recipient');
  });
  test('the chat text matches the app (MotivationShareText.chatText)', () => {
    expect(chatText('Get up.')).toBe('📣 Coach Mane says: Get up.');
  });
});
