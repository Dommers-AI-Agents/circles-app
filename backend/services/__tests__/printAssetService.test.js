jest.mock('../../config/rewardConfig', () => ({ GENERIC_JOIN_CODE: 'JOINUS' }));
jest.mock('../rewardService', () => ({
  stickerUrl: (code) => `https://api.favcircles.com/s/${code}`,
  effectiveEarnRate: () => 10
}));
const svc = require('../printAssetService');

const venue = { venueId: 'v1', venueName: 'Tommy\'s Tavern + Tap', windowCode: 'WIN123', registerCode: 'REG456' };
const mediaBox = (pdf) => pdf.toString('latin1').match(/MediaBox \[0 0 ([\d.]+) ([\d.]+)\]/).slice(1).map(Number);

describe('printAssetService', () => {
  test('every kind × format renders a PDF at the right page size', async () => {
    const pages = { sign: [612, 792], tent: [792, 612], smallTent: [612, 792], card: [288, 432], stickers: [612, 792] };
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

  test('stickers: 24 codes on one Avery 22805 sheet, named for the stock', async () => {
    const pdf = await svc.renderPDF(venue, { kind: 'window', format: 'stickers' });
    expect(mediaBox(pdf)).toEqual([612, 792]);
    expect(svc.fileName(venue, { kind: 'window', format: 'stickers' }))
      .toBe('Tommys Tavern  Tap - window stickers - Avery 22805.pdf');
  });

  test('store stickers: one per store, from any start position, onto more sheets as needed', async () => {
    const stores = Array.from({ length: 30 }, (_, i) => ({ ...venue, venueName: `Store ${i + 1}`, windowCode: `W${i}` }));
    const pageCount = (pdf) => (pdf.toString('latin1').match(/\/Type \/Page\b/g) || []).length;
    expect(pageCount(await svc.renderStoreStickers(stores.slice(0, 3)))).toBe(1);
    expect(pageCount(await svc.renderStoreStickers(stores.slice(0, 3), { startAt: 23 }))).toBe(2);
    expect(pageCount(await svc.renderStoreStickers(stores))).toBe(2);
    for (const bad of [{ startAt: 0 }, { startAt: 25 }, { startAt: 'x' }, { kind: 'door' }]) {
      await expect(svc.renderStoreStickers(stores.slice(0, 1), bad)).rejects.toMatchObject({ status: 400 });
    }
    await expect(svc.renderStoreStickers([])).rejects.toMatchObject({ status: 400 });
    await expect(svc.renderStoreStickers([{ ...venue, windowCode: null }])).rejects.toMatchObject({ status: 404 });
  }, 90000);

  test('coaster stickers: two per coaster, 80 to a sheet, from any start position', async () => {
    const pageCount = (pdf) => (pdf.toString('latin1').match(/\/Type \/Page\b/g) || []).length;
    expect(pageCount(await svc.renderCoasterStickers())).toBe(1); // 40 coasters = one sheet
    expect(pageCount(await svc.renderCoasterStickers({ coasters: 41 }))).toBe(2);
    expect(pageCount(await svc.renderCoasterStickers({ coasters: 1, startAt: 80 }))).toBe(2);
    for (const bad of [{ coasters: 0 }, { coasters: 1001 }, { coasters: 'x' }, { startAt: 0 }, { startAt: 81 }]) {
      await expect(svc.renderCoasterStickers(bad)).rejects.toMatchObject({ status: 400 });
    }
  }, 90000);

  test('totem labels: one per store on Avery 8293, from any start position, linking to the totem sticker', async () => {
    const stores = Array.from({ length: 21 }, (_, i) => ({ ...venue, venueId: `v${i}`, windowCode: `W${i}` }));
    const pageCount = (pdf) => (pdf.toString('latin1').match(/\/Type \/Page\b/g) || []).length;
    expect(svc.TOTEM_LABELS_PER_SHEET).toBe(20);
    expect(svc.totemUrl('WIN123')).toBe('https://api.favcircles.com/s/WIN123?t=totem');
    const one = await svc.renderTotemLabels(stores.slice(0, 1));
    expect(mediaBox(one)).toEqual([612, 792]);
    expect(pageCount(one)).toBe(1);
    expect(pageCount(await svc.renderTotemLabels(stores.slice(0, 2), { startAt: 20 }))).toBe(2);
    expect(pageCount(await svc.renderTotemLabels(stores))).toBe(2);
    for (const bad of [{ startAt: 0 }, { startAt: 21 }, { startAt: 'x' }]) {
      await expect(svc.renderTotemLabels(stores.slice(0, 1), bad)).rejects.toMatchObject({ status: 400 });
    }
    await expect(svc.renderTotemLabels([])).rejects.toMatchObject({ status: 400 });
    await expect(svc.renderTotemLabels([{ ...venue, windowCode: null }])).rejects.toMatchObject({ status: 404 });
    // label centres 1.25–7.25 in across, 1.5–9.5 in down
    const t = svc.TOTEM_SHEET;
    expect([t.firstX, t.firstY, t.pitch]).toEqual([90, 108, 144]);
    expect(t.firstX + (t.cols - 1) * t.pitch).toBe(7.25 * 72);
    expect(t.firstY + (t.rows - 1) * t.pitch).toBe(9.5 * 72);
  });

  test('table stickers: the same round sheet, one per store, linking to the plain window code', async () => {
    const stores = Array.from({ length: 21 }, (_, i) => ({ ...venue, venueId: `v${i}`, windowCode: `W${i}` }));
    const pageCount = (pdf) => (pdf.toString('latin1').match(/\/Type \/Page\b/g) || []).length;
    const one = await svc.renderTableStickers(stores.slice(0, 1));
    expect(mediaBox(one)).toEqual([612, 792]);
    expect(pageCount(one)).toBe(1);
    expect(pageCount(await svc.renderTableStickers(stores.slice(0, 2), { startAt: 20 }))).toBe(2);
    expect(pageCount(await svc.renderTableStickers(stores))).toBe(2);
    await expect(svc.renderTableStickers(stores.slice(0, 1), { startAt: 21 })).rejects.toMatchObject({ status: 400 });
    await expect(svc.renderTableStickers([])).rejects.toMatchObject({ status: 400 });
    await expect(svc.renderTableStickers([{ ...venue, windowCode: null }])).rejects.toMatchObject({ status: 404 });
  });

  test('table stickers: several of each store, one for every table; a Totem label stays one per store', async () => {
    const stores = Array.from({ length: 5 }, (_, i) => ({ ...venue, venueId: `v${i}`, windowCode: `W${i}` }));
    const pageCount = (pdf) => (pdf.toString('latin1').match(/\/Type \/Page\b/g) || []).length;
    expect(pageCount(await svc.renderTableStickers(stores.slice(0, 1), { copies: 20 }))).toBe(1);
    expect(pageCount(await svc.renderTableStickers(stores.slice(0, 1), { copies: 20, startAt: 2 }))).toBe(2);
    expect(pageCount(await svc.renderTableStickers(stores.slice(0, 2), { copies: '12' }))).toBe(2);
    expect(pageCount(await svc.renderTableStickers(stores.slice(0, 4), { copies: svc.MAX_TABLE_COPIES }))).toBe(20);
    for (const copies of [0, 1.5, 'x', svc.MAX_TABLE_COPIES + 1]) {
      await expect(svc.renderTableStickers(stores.slice(0, 1), { copies })).rejects.toMatchObject({ status: 400, code: 'BAD_COPIES' });
    }
    await expect(svc.renderTableStickers(stores, { copies: 100 })).rejects.toMatchObject({ status: 400, code: 'TOO_MANY_LABELS' });
    await expect(svc.renderTotemLabels(stores.slice(0, 1), { copies: 2 })).rejects.toMatchObject({ status: 400, code: 'BAD_COPIES' });
  });

  test('sticker sheets match Avery\'s templates', () => {
    const { avery22805: big, avery94102: small } = svc.STICKER_SHEETS;
    // Every sheet's columns and rows fit the letter page with equal side margins
    for (const s of [big, small]) {
      expect(s.left * 2 + (s.cols - 1) * s.pitchX + s.size).toBeCloseTo(612, 1);
      expect(s.top + (s.rows - 1) * s.pitchY + s.size).toBeLessThanOrEqual(792);
    }
    expect([big.left, big.pitchX]).toEqual([56.25, 130.5]);
    expect(big.pitchY).toBeCloseTo(122.4, 6);
    expect([small.left, small.top, small.pitchX]).toEqual([27, 45, 72]);
  });

  test('the email names still work', async () => {
    for (const fn of [svc.windowSignPDF, svc.registerCardPDF, svc.tableTentPDF]) {
      expect((await fn(venue)).slice(0, 4).toString()).toBe('%PDF');
    }
  }, 30000);
});
