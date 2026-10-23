// Google answering a business search with a street address must never name
// the venue (2026-10-23: "Uptown Yolk Cafe" saved as "116 W Catherine St")
const { isAddressOnly, isStreetLineName } = require('../googleAddressGuard');

test('an address entry is address-only; a business is not, even when Google adds address types', () => {
  expect(isAddressOnly(['premise'])).toBe(true);
  expect(isAddressOnly(['street_address'])).toBe(true);
  expect(isAddressOnly(['route', 'geocode'])).toBe(true);
  expect(isAddressOnly(['american_restaurant', 'restaurant', 'food', 'point_of_interest', 'establishment'])).toBe(false);
  expect(isAddressOnly(['premise', 'establishment'])).toBe(false);
  expect(isAddressOnly(undefined)).toBe(false);
  expect(isAddressOnly([])).toBe(false);
});

test('a name that is only the address’s street line', () => {
  const address = '116 W Catherine St, Charlotte, NC 28203, USA';
  expect(isStreetLineName('116 W Catherine St', address)).toBe(true);
  expect(isStreetLineName('116 w. catherine st', address)).toBe(true);
  expect(isStreetLineName('Uptown Yolk', address)).toBe(false);
  // A business named for its address stays a business unless it IS the street line
  expect(isStreetLineName('300 East', '300 East Blvd, Charlotte, NC')).toBe(false);
  expect(isStreetLineName('', address)).toBe(false);
});
