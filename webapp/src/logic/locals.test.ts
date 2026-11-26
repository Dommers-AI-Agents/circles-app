import { describe, expect, it } from 'vitest';
import type { NearbyVenue } from '../api/rewards';
import {
  areaLine, dealLine, directionsLink, eventWhenLine, eventWhereLine, isStoreEvent, marketLine, safeLink, storeDeals, storeMeta, storeTarget
} from './locals';

const store = (over: Partial<NearbyVenue>): NearbyVenue => ({
  venueId: 'v1', venueName: 'Sal’s Bakery', offers: [], announcements: [], ...over
});

describe('which area Locals shows', () => {
  it('says where the list is centred', () => {
    expect(areaLine('device')).toMatch(/near you/);
    expect(areaLine('account')).toMatch(/last used/);
    expect(areaLine('default')).toMatch(/Charlotte/);
    expect(areaLine('default')).toMatch(/Use your location/);
  });
});

describe("a store's deals", () => {
  it('puts rewards first, cheapest first, then posts; keeps the store order', () => {
    const rows = storeDeals([
      store({
        venueId: 'a',
        offers: [{ offerId: 'x', title: 'Croissant', pointsCost: 150 }, { offerId: 'y', title: 'Coffee', pointsCost: 100 }],
        announcements: [{ announcementId: 'p', title: 'Pumpkin bread is back' }]
      }),
      store({ venueId: 'b', announcements: [{ announcementId: 'q', title: 'Open late' }] })
    ]);
    expect(rows.map((r) => r.venue.venueId)).toEqual(['a', 'b']);
    expect(rows[0].deals.map(dealLine)).toEqual(['Coffee · 100 points', 'Croissant · 150 points', 'Pumpkin bread is back']);
  });
  it('leaves out stores with nothing to show and free or untitled offers', () => {
    const rows = storeDeals([store({ offers: [{ title: 'Free', pointsCost: 0 }, { title: '', pointsCost: 10 }] })]);
    expect(rows).toEqual([]);
    expect(storeDeals(undefined)).toEqual([]);
  });
  it('says if it is on my map and how far', () => {
    expect(storeMeta({ savedByUser: true, distanceMeters: 640 })).toBe('On your map · 0.4 mi');
    expect(storeMeta({ isVirtual: true, distanceMeters: 640 })).toBe('Online store');
    expect(storeMeta({ distanceMeters: null })).toBe('');
  });
});

describe('where a row opens', () => {
  it('an enrolled store opens its rewards, any other place its page', () => {
    expect(storeTarget({ venueId: 'v1', globalPlaceId: 'g1' })).toEqual({ kind: 'rewards', venueId: 'v1', globalPlaceId: 'g1' });
    expect(storeTarget({ venueId: 'v1' })).toEqual({ kind: 'rewards', venueId: 'v1', globalPlaceId: null });
    expect(storeTarget({ globalPlaceId: 'g1' })).toEqual({ kind: 'place', globalPlaceId: 'g1' });
    expect(storeTarget({})).toBeNull();
  });
  it('lets only web links out', () => {
    expect(safeLink('https://cmlibrary.org/e/1')).toBe('https://cmlibrary.org/e/1');
    expect(safeLink('javascript:alert(1)')).toBeNull();
    expect(safeLink('')).toBeNull();
  });
  it('gives directions to a real spot only', () => {
    expect(directionsLink(35.2, -80.8)).toBe('https://www.google.com/maps/dir/?api=1&destination=35.2,-80.8');
    expect(directionsLink(0, 0)).toBeNull();
    expect(directionsLink(Number.NaN, 1)).toBeNull();
  });
});

describe('the lines under an event and a market', () => {
  it('when and what it costs', () => {
    expect(eventWhenLine({ startLocalDate: '2026-11-26', startLocalTime: '19:00:00', isFree: true }, '2026-11-26')).toBe('Today 7:00 PM · Free');
    expect(eventWhenLine({ startLocalDate: '2026-11-28', startLocalTime: null, priceMin: 25, priceMax: 80, currency: 'USD' }, '2026-11-26'))
      .toBe('Sat, Nov 28 · $25–$80');
  });
  it('where and how far', () => {
    expect(eventWhereLine({ venueName: 'ImaginOn', distanceMeters: 491 })).toBe('ImaginOn · 0.3 mi');
    expect(eventWhereLine({ city: 'Charlotte' })).toBe('Charlotte');
  });
  it('tells a store event from a listing', () => {
    expect(isStoreEvent({ source: 'store' })).toBe(true);
    expect(isStoreEvent({ source: 'ticketmaster' })).toBe(false);
  });
  it("a market's hours, distance and what it takes", () => {
    expect(marketLine({ hoursSummary: 'Sat 8 AM–12:30 PM', distanceMeters: 659, acceptsSnap: true, organic: false }))
      .toBe('Sat 8 AM–12:30 PM · 0.4 mi · SNAP accepted');
    expect(marketLine({})).toBe('');
  });
});
