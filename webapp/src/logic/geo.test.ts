import { describe, expect, it } from 'vitest';
import { distanceMeters, distanceText, latLngOf, pointOf } from './geo';

describe('coordinates', () => {
  it('reads GeoJSON as longitude first', () => {
    expect(latLngOf({ type: 'Point', coordinates: [-80.84, 35.22] })).toEqual({ lat: 35.22, lng: -80.84 });
    expect(pointOf({ lat: 35.22, lng: -80.84 }).coordinates).toEqual([-80.84, 35.22]);
  });
  it('treats a missing, zero or impossible point as no location', () => {
    expect(latLngOf(null)).toBeNull();
    expect(latLngOf({ type: 'Point', coordinates: [0, 0] })).toBeNull();
    expect(latLngOf({ type: 'Point', coordinates: [35.22, -180.84] as [number, number] })).toBeNull();
  });
  it('measures and words a distance', () => {
    const d = distanceMeters({ lat: 35.2271, lng: -80.8431 }, { lat: 35.2371, lng: -80.8431 });
    expect(Math.round(d)).toBeGreaterThan(1100);
    expect(Math.round(d)).toBeLessThan(1120);
    expect(distanceText(100)).toBe('330 ft');
    expect(distanceText(1609.344 * 2.34)).toBe('2.3 mi');
    expect(distanceText(1609.344 * 42)).toBe('42 mi');
  });
});
