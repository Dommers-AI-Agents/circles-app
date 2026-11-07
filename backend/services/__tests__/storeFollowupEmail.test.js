jest.mock('../appClipExperienceService', () => ({ cardPreviewJPEG: jest.fn(async () => Buffer.from('jpeg')) }));
jest.mock('../rewardService', () => ({ stickerUrl: (code) => `https://api.favcircles.com/s/${code}` }));
const { buildStoreFollowup, cardSlug } = require('../storeFollowupEmail');

const venue = { venueName: 'Pasta & Provisions', windowCode: '3OZM82' };

describe('store follow-up email', () => {
  test('the card is in the email itself, and every link goes straight to us (no redirects)', async () => {
    const email = await buildStoreFollowup(venue, { ownerName: 'Vickie' });
    expect(email.html).toContain('src="cid:storecard"');
    expect(email.html).toContain('src="cid:storeqr"');
    expect(email.attachments).toEqual([
      expect.objectContaining({ cid: 'storecard', contentType: 'image/jpeg' }),
      expect.objectContaining({ cid: 'storeqr', contentType: 'image/png' })
    ]);
    const hrefs = [...email.html.matchAll(/href="([^"]+)"/g)].map((m) => m[1]);
    expect(hrefs).toEqual(expect.arrayContaining([
      'https://favcircles.com/store-cards/pasta-and-provisions-3OZM82.jpg',
      'https://api.favcircles.com/s/3OZM82',
      'https://favcircles.com/store-owners.html'
    ]));
    for (const h of hrefs) expect(h).toMatch(/^(https:\/\/(api\.)?favcircles\.com\/|mailto:)/);
  });

  test('greets by name, escapes the store name, and says hi there without a name', async () => {
    const named = await buildStoreFollowup(venue, { ownerName: 'Vickie' });
    expect(named.html).toContain('Hi Vickie,');
    expect(named.html).toContain('Pasta &amp; Provisions');
    expect(named.subject).toBe('Pasta & Provisions on FavCircles: here\'s your store\'s card');
    expect((await buildStoreFollowup(venue)).text.startsWith('Hi there,')).toBe(true);
  });

  test('the website file name is the store name plus its window code', () => {
    expect(cardSlug(venue)).toBe('pasta-and-provisions-3OZM82.jpg');
    expect(cardSlug({ venueName: 'Café Rosé!', windowCode: 'AB12' })).toBe('cafe-rose-AB12.jpg');
  });

  test('a store without a window code has no card to send', async () => {
    await expect(buildStoreFollowup({ venueName: 'X' })).rejects.toThrow(/window code/);
  });
});
