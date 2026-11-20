// NFC stickers: tagged window links written from Manage Store (2026-11-01)
const mockUpdates = [];
jest.mock('../../config/firebase', () => ({
  getFirestore: () => ({
    collection: () => ({ doc: (id) => ({ update: async (data) => { mockUpdates.push({ id, data }); } }) })
  }),
  FieldValue: { increment: (n) => ({ inc: n }), delete: () => ({ del: true }) }
}));
jest.mock('../rewardService', () => ({
  stickerUrl: (code) => `https://api.favcircles.com/s/${code}`,
  incrementVenueStats: jest.fn()
}));
const svc = require('../nfcStickerService');

const venue = (stickers = {}) => ({ venueId: 'v1', windowCode: 'WIN123', registerCode: 'REG456', nfcStickers: stickers });

beforeEach(() => { mockUpdates.length = 0; });

test('tagKey keeps only url- and field-path-safe characters', () => {
  expect(svc.tagKey('Table 7')).toBe('table-7');
  expect(svc.tagKey('  Patio / Bar.Top!! ')).toBe('patio-bar-top');
  expect(svc.tagKey('Café')).toBe('caf');
  expect(svc.tagKey('a'.repeat(40))).toHaveLength(svc.TAG_MAX);
  expect(svc.tagKey('!!!')).toBeNull();
  expect(svc.tagKey(7)).toBeNull();
});

test('uniqueTag numbers repeats and stays within the length cap', () => {
  expect(svc.uniqueTag('table-7', new Set())).toBe('table-7');
  expect(svc.uniqueTag('table-7', new Set(['table-7']))).toBe('table-7-2');
  expect(svc.uniqueTag('table-7', new Set(['table-7', 'table-7-2']))).toBe('table-7-3');
  const long = 'x'.repeat(svc.TAG_MAX);
  const next = svc.uniqueTag(long, new Set([long]));
  expect(next.length).toBeLessThanOrEqual(svc.TAG_MAX);
  expect(next.endsWith('-2')).toBe(true);
});

test('the sticker link is the window link with the tag', () => {
  expect(svc.stickerLink(venue(), 'table-7')).toBe('https://api.favcircles.com/s/WIN123?t=table-7');
});

test('createSticker stores the label under a fresh tag and returns its link', async () => {
  const sticker = await svc.createSticker(venue({ 'table-7': { label: 'Table 7' } }), ' Table 7 ');
  expect(sticker).toMatchObject({ tag: 'table-7-2', label: 'Table 7', taps: 0, url: 'https://api.favcircles.com/s/WIN123?t=table-7-2' });
  expect(Object.keys(mockUpdates[0].data)).toEqual(['nfcStickers.table-7-2']);
});

test('createSticker needs a name', async () => {
  await expect(svc.createSticker(venue(), '   ')).rejects.toMatchObject({ status: 400, code: 'LABEL_REQUIRED' });
});

test('a tap counts only for a sticker the store made, on the window link', async () => {
  const v = venue({ 'table-7': { label: 'Table 7' } });
  expect(await svc.recordTap(v, 'win123', 'table-7')).toBe(true);
  expect(mockUpdates[0].data['nfcStickers.table-7.taps']).toEqual({ inc: 1 });

  expect(await svc.recordTap(v, 'WIN123', 'made-up')).toBe(false);
  expect(await svc.recordTap(v, 'REG456', 'table-7')).toBe(false); // a window sticker never on the register code
  expect(await svc.recordTap(v, 'WIN123', '')).toBe(false);
  expect(mockUpdates).toHaveLength(1);
});

test('markWritten records the lock; unknown tags are refused', async () => {
  await svc.markWritten(venue({ 'bar': { label: 'Bar' } }), 'bar', { locked: true });
  expect(mockUpdates[0].data['nfcStickers.bar.locked']).toBe(true);
  await expect(svc.markWritten(venue(), 'bar')).rejects.toMatchObject({ status: 404 });
});

test('listStickers is oldest first with links and defaults', () => {
  const list = svc.listStickers(venue({
    b: { label: 'B', createdAt: '2026-11-02' },
    a: { label: 'A', createdAt: '2026-11-01', taps: 4, locked: true }
  }));
  expect(list.map((s) => s.tag)).toEqual(['a', 'b']);
  expect(list[0]).toMatchObject({ taps: 4, locked: true, url: 'https://api.favcircles.com/s/WIN123?t=a' });
  expect(list[1]).toMatchObject({ taps: 0, locked: false, writes: 0 });
});

// Wes, 2026-11-05: window AND register stickers. 2026-11-20 (Favvy): a
// register ("Points") sticker carries the window code too; its kind pays
describe('register (points) stickers', () => {
  test('a register sticker carries the lasting window link', async () => {
    const made = await svc.createSticker(venue(), 'Counter', 'register');
    expect(made.kind).toBe('register');
    expect(made.url).toBe('https://api.favcircles.com/s/WIN123?t=counter');
  });

  test('a register sticker works for a store with no register code', async () => {
    const made = await svc.createSticker({ ...venue(), registerCode: undefined }, 'Favvy', 'register');
    expect(made.url).toBe('https://api.favcircles.com/s/WIN123?t=favvy');
  });

  test('its taps count on the window link, and on the register link it was once written with', async () => {
    const v = venue({ counter: { label: 'Counter', kind: 'register' } });
    expect(await svc.recordTap(v, 'WIN123', 'counter')).toBe(true);
    expect(await svc.recordTap(v, 'REG456', 'counter')).toBe(true);
    expect(await svc.recordTap(v, 'NOPE00', 'counter')).toBe(false);
  });

  test('window stays the default and keeps its window link', async () => {
    const made = await svc.createSticker(venue(), 'Table 7');
    expect(made.kind).toBe('window');
    expect(made.url).toContain('WIN123?t=table-7');
  });

  test('a register sticker can be locked; one written with the old register code needs a rewrite', async () => {
    await svc.markWritten(venue({ counter: { label: 'Counter', kind: 'register' } }), 'counter', { locked: true });
    expect(mockUpdates[0].data['nfcStickers.counter.locked']).toBe(true);
    expect(mockUpdates[0].data['nfcStickers.counter.writtenCode']).toBe('WIN123');
    const old = venue({ counter: { label: 'Counter', kind: 'register', writtenCode: 'REG456' } });
    expect(svc.listStickers(old)[0].needsRewrite).toBe(true);
    const current = venue({ counter: { label: 'Counter', kind: 'register', writtenCode: 'WIN123' } });
    expect(svc.listStickers({ ...current, registerCode: 'NEW789' })[0].needsRewrite).toBe(false);
  });

  test('pointsStickerTag names only a register sticker the store made', () => {
    const v = venue({ favvy: { label: 'Favvy', kind: 'register' }, 'table-7': { label: 'Table 7' } });
    expect(svc.pointsStickerTag(v, 'Favvy')).toBe('favvy');
    expect(svc.pointsStickerTag(v, 'table-7')).toBeNull();
    expect(svc.pointsStickerTag(v, 'made-up')).toBeNull();
    expect(svc.pointsStickerTag(v, undefined)).toBeNull();
  });
});
