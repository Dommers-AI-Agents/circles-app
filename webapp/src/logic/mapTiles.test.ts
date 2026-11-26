import { describe, expect, it } from 'vitest';
import { TILE_SIZE, tileUrl, tilesAround, worldPixel } from './mapTiles';

describe('worldPixel', () => {
  it('puts 0,0 in the middle of the world', () => {
    expect(worldPixel(0, 0, 0)).toEqual({ x: 128, y: 128 });
    expect(worldPixel(0, 0, 3).x).toBe(1024);
  });
  it('matches the standard tile formula for Charlotte at zoom 15 (x 9025, y 12954)', () => {
    const p = worldPixel(35.2271, -80.8431, 15);
    expect(Math.floor(p.x / TILE_SIZE)).toBe(9025);
    expect(Math.floor(p.y / TILE_SIZE)).toBe(12954);
  });
});

describe('tilesAround', () => {
  it('covers the picture and centres the point', () => {
    const tiles = tilesAround(35.2271, -80.8431, 15, 400, 200);
    expect(tiles.length).toBeGreaterThanOrEqual(2);
    expect(tiles.length).toBeLessThanOrEqual(6);
    // Together the tiles reach every edge of the 400 × 200 box around the centre
    expect(Math.min(...tiles.map((t) => t.left))).toBeLessThanOrEqual(-200);
    expect(Math.max(...tiles.map((t) => t.left + TILE_SIZE))).toBeGreaterThanOrEqual(200);
    expect(Math.min(...tiles.map((t) => t.top))).toBeLessThanOrEqual(-100);
    expect(Math.max(...tiles.map((t) => t.top + TILE_SIZE))).toBeGreaterThanOrEqual(100);
    // The tile holding the point is among them
    expect(tiles.some((t) => t.x === 9025 && t.y === 12954 && t.left <= 0 && t.top <= 0)).toBe(true);
  });
  it('wraps across the date line and stops at the poles', () => {
    const wrapped = tilesAround(0, 179.99, 2, 600, 100);
    expect(wrapped.every((t) => t.x >= 0 && t.x < 4)).toBe(true);
    expect(wrapped.some((t) => t.x === 0)).toBe(true);
    const polar = tilesAround(85, 0, 1, 300, 600);
    expect(polar.every((t) => t.y >= 0 && t.y < 2)).toBe(true);
  });
});

describe('tileUrl', () => {
  it('fills the template', () => {
    expect(tileUrl('https://tile.example/{z}/{x}/{y}.png', { z: 15, x: 9025, y: 12954 })).toBe('https://tile.example/15/9025/12954.png');
  });
});
