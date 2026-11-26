// A still map picture of one point, built from ordinary map tile images
// (no script, no fetch: each tile is an <img>). This is the arithmetic:
// which tiles cover a box around the point, and where each one sits so the
// point lands in the middle of the picture.
export const TILE_SIZE = 256;

export interface PlacedTile {
  z: number;
  x: number;
  y: number;
  /** Pixels from the picture's centre to the tile's left and top edges */
  left: number;
  top: number;
}

/** The point in world pixels at a zoom (Web Mercator, the tile scheme every slippy map uses). */
export function worldPixel(lat: number, lng: number, zoom: number): { x: number; y: number } {
  const scale = TILE_SIZE * 2 ** zoom;
  const clamped = Math.max(-85.0511, Math.min(85.0511, lat));
  const sin = Math.sin((clamped * Math.PI) / 180);
  return {
    x: ((lng + 180) / 360) * scale,
    y: (0.5 - Math.log((1 + sin) / (1 - sin)) / (4 * Math.PI)) * scale
  };
}

/**
 * The tiles covering a `width` × `height` picture centred on the point.
 * Columns wrap around the date line; rows above or below the map are left out.
 */
export function tilesAround(lat: number, lng: number, zoom: number, width: number, height: number): PlacedTile[] {
  const centre = worldPixel(lat, lng, zoom);
  const count = 2 ** zoom;
  const firstX = Math.floor((centre.x - width / 2) / TILE_SIZE);
  const lastX = Math.floor((centre.x + width / 2 - 0.001) / TILE_SIZE);
  const firstY = Math.floor((centre.y - height / 2) / TILE_SIZE);
  const lastY = Math.floor((centre.y + height / 2 - 0.001) / TILE_SIZE);
  const tiles: PlacedTile[] = [];
  for (let ty = firstY; ty <= lastY; ty++) {
    if (ty < 0 || ty >= count) continue;
    for (let tx = firstX; tx <= lastX; tx++) {
      tiles.push({
        z: zoom,
        x: ((tx % count) + count) % count,
        y: ty,
        left: Math.round(tx * TILE_SIZE - centre.x),
        top: Math.round(ty * TILE_SIZE - centre.y)
      });
    }
  }
  return tiles;
}

/** Fills a "…/{z}/{x}/{y}.png" template. */
export const tileUrl = (template: string, tile: { z: number; x: number; y: number }): string =>
  template.replace('{z}', String(tile.z)).replace('{x}', String(tile.x)).replace('{y}', String(tile.y));
