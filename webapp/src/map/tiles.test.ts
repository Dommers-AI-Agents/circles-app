import { describe, expect, it } from 'vitest';
import { TILE_OPTIONS } from './tileOptions';

describe('tile options', () => {
  // OpenStreetMap blocks tiles requested with no Referer, and the server
  // sends Referrer-Policy: no-referrer for every page.
  it('sends our origin as the Referer on tiles', () => {
    expect(TILE_OPTIONS.referrerPolicy).toBe('strict-origin-when-cross-origin');
  });
});
