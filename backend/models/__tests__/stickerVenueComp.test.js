// Rewards exist only once a store is claimed and its owner is on Business.
// A venue enrolled without an owner used to be comped by default, so its
// page told everyone "Earn 25 pts per purchase" (Wes, 2026-10-28).
const { createStickerVenue } = require('../StickerModels');

const base = { venueName: 'Pasta & Provisions', globalPlaceId: 'gp1' };

it('does not comp a venue enrolled without an owner', () => {
  const venue = createStickerVenue(base, 'WIN1', 'REG1');
  expect(venue.ownerUserId).toBeNull();
  expect(venue.loyaltyComped).toBe(false);
  expect(venue.loyaltyCompedUntil).toBeNull();
  expect(venue.loyaltyCompReason).toBeNull();
});

it('keeps an explicit comp, with its end date and reason', () => {
  const venue = createStickerVenue(
    { ...base, loyaltyComped: true, loyaltyCompedUntil: '2027-01-01T00:00:00.000Z', loyaltyCompReason: 'storefront_demo' },
    'WIN1', 'REG1'
  );
  expect(venue.loyaltyComped).toBe(true);
  expect(venue.loyaltyCompedUntil).toBe('2027-01-01T00:00:00.000Z');
  expect(venue.loyaltyCompReason).toBe('storefront_demo');
});

it('ignores a comp end date or reason without the comp itself', () => {
  const venue = createStickerVenue({ ...base, loyaltyCompedUntil: '2027-01-01T00:00:00.000Z', loyaltyCompReason: 'x' }, 'WIN1', 'REG1');
  expect(venue.loyaltyComped).toBe(false);
  expect(venue.loyaltyCompedUntil).toBeNull();
  expect(venue.loyaltyCompReason).toBeNull();
});
