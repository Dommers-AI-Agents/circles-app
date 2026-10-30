jest.mock('../rewardService', () => ({
  stickerUrl: (code) => `https://api.favcircles.com/s/${code}`,
  effectiveEarnRate: () => 10
}));
const svc = require('../printAssetService');

const venue = { venueId: 'v1', venueName: 'Tommy\'s Tavern + Tap', windowCode: 'WIN123', registerCode: 'REG456' };
const mediaBox = (pdf) => pdf.toString('latin1').match(/MediaBox \[0 0 ([\d.]+) ([\d.]+)\]/).slice(1).map(Number);

describe('printAssetService', () => {
  test('every kind × format renders a PDF at the right page size', async () => {
    const pages = { sign: [612, 792], tent: [792, 612], smallTent: [612, 792], card: [288, 432] };
    for (const kind of svc.KINDS) {
      for (const format of svc.FORMATS) {
        const pdf = await svc.renderPDF(venue, { kind, format, qr: 'medium' });
        expect(pdf.slice(0, 4).toString()).toBe('%PDF');
        expect(mediaBox(pdf)).toEqual(pages[format]);
      }
    }
  }, 60000);

  test('QR size options are 1, 3 and 4 inches', () => {
    expect(svc.printOptions({ qr: 'small' }).qrInches).toBe(1);
    expect(svc.printOptions({ qr: 'medium' }).qrInches).toBe(3);
    expect(svc.printOptions({ qr: 'large' }).qrInches).toBe(4);
    expect(svc.printOptions({}).qr).toBe('small');
    expect(svc.printOptions({}).format).toBe('smallTent');
  });

  test('bad options are refused with a 400', () => {
    for (const bad of [{ kind: 'door' }, { format: 'poster' }, { qr: 'huge' }]) {
      expect(() => svc.printOptions(bad)).toThrow(expect.objectContaining({ status: 400 }));
    }
  });

  test('a store without a register code cannot print one', async () => {
    await expect(svc.renderPDF({ ...venue, registerCode: null }, { kind: 'register', format: 'card' }))
      .rejects.toMatchObject({ status: 404 });
  });

  test('file names say what they are', () => {
    expect(svc.fileName(venue, { kind: 'window', format: 'smallTent', qr: 'small' }))
      .toBe('Tommys Tavern  Tap - window small table tent - 1in QR.pdf');
  });

  test('the email names still work', async () => {
    for (const fn of [svc.windowSignPDF, svc.registerCardPDF, svc.tableTentPDF]) {
      expect((await fn(venue)).slice(0, 4).toString()).toBe('%PDF');
    }
  }, 30000);
});
