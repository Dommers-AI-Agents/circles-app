// The scan bubble's lookup: a window sticker says "save", a register card
// says "rewards" (Wes, 2026-11-12: "setting you up to save store xyz", not
// "checking rewards", for a window scan)
jest.mock('../../../config/firebase', () => ({ getFirestore: () => ({}) }));
const venues = {
  WIN123: { venueId: 'v1', venueName: 'Pasta & Provisions', kind: 'window', active: true },
  REG456: { venueId: 'v1', venueName: 'Pasta & Provisions', kind: 'register', active: true },
  GONE: { venueId: 'v2', venueName: 'Closed', kind: 'window', active: false }
};
jest.mock('../../../services/rewardService', () => ({ findVenueByCode: async (code) => venues[code] || null }));
const { codeName } = require('../rewardScanController');

const run = async (code) => {
  let out; let status = 200;
  const res = { status(s) { status = s; return this; }, json(b) { out = b; return this; } };
  await codeName({ params: { code } }, res);
  return { status, out };
};

test('window and register codes of the same store answer their own kind', async () => {
  expect((await run('win123')).out.data).toEqual({ venueName: 'Pasta & Provisions', kind: 'window' });
  expect((await run('REG456')).out.data).toEqual({ venueName: 'Pasta & Provisions', kind: 'register' });
});

test('an inactive or unknown code is a 404', async () => {
  expect((await run('GONE')).status).toBe(404);
  expect((await run('NOPE')).status).toBe(404);
});
