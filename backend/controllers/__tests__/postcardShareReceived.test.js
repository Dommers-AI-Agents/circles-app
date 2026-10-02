jest.mock('../../config/firebase', () => ({ getFirestore: () => ({}) }));
jest.mock('../../services/messagingService', () => ({}));
jest.mock('../../services/piggyBankService', () => ({}));
jest.mock('../../services/moderationService', () => ({ isBlockedEitherWay: () => false }));
jest.mock('../../utils/networkAccess', () => ({ getConnectedUserIds: async () => new Set() }));
jest.mock('../../services/ownActivity/record', () => ({ recordPostcardSent: async () => {} }));

const { presentReceivedShare } = require('../widgets/postcardController');
const shareService = require('../../services/postcardShareService');
const { renderPostcard } = require('../../views/postcardPage');

const share = {
  token: 'abcdefghijklmnopqrst', senderId: 'wes', senderName: 'Wesley', imageUrl: 'https://x/card.jpg',
  message: 'Hope you are having a lovely day!!', placeName: null, placeCity: null, createdAt: '2026-09-18T13:21:08Z', views: 3
};

describe('presentReceivedShare', () => {
  test('a friend opening the card', () => {
    const p = presentReceivedShare(share, 'sal', new Set(['wes']));
    expect(p).toMatchObject({ senderId: 'wes', senderName: 'Wesley', isMine: false, senderIsConnection: true, message: share.message });
    expect(p.views).toBeUndefined();
  });
  test('the sender scanning their own card, and a stranger', () => {
    expect(presentReceivedShare(share, 'wes', new Set(['wes']))).toMatchObject({ isMine: true, senderIsConnection: false });
    expect(presentReceivedShare(share, 'sal', new Set())).toMatchObject({ isMine: false, senderIsConnection: false });
    expect(presentReceivedShare({ ...share, senderId: undefined, senderName: '' }, 'sal', new Set()))
      .toMatchObject({ senderId: null, senderName: 'A FavCircles member', isMine: false, senderIsConnection: false });
  });
});

describe('postcard app links switch', () => {
  const saved = process.env.POSTCARD_APP_LINKS;
  afterEach(() => { process.env.POSTCARD_APP_LINKS = saved; });
  test('off: QR keeps the friendly page and the page has no app offer', () => {
    delete process.env.POSTCARD_APP_LINKS;
    expect(shareService.qrTarget(share.token)).toBe('https://favcircles.com/postcard/abcdefghijklmnopqrst');
    expect(renderPostcard(share, { appLinks: shareService.appLinksEnabled() })).not.toContain('circles://');
  });
  test('on: QR is the claimed /app/ link; page has the banner and the button', () => {
    process.env.POSTCARD_APP_LINKS = '1';
    expect(shareService.qrTarget(share.token)).toBe(`${shareService.ASSET_BASE_URL}/app/postcard/abcdefghijklmnopqrst`);
    const html = renderPostcard(share, { appLinks: true, appLinkUrl: shareService.appLinkUrl(share.token) });
    expect(html).toContain('name="apple-itunes-app"');
    expect(html).toContain('circles://postcard/abcdefghijklmnopqrst');
  });
});
