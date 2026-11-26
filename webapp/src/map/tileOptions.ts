// Tile source and options, free of Leaflet so they can be tested without a
// browser.
export const TILES = {
  url: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  attribution: '&copy; <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noopener noreferrer">OpenStreetMap</a> contributors',
  maxZoom: 19
};

// OpenStreetMap refuses tiles asked for with no Referer ("Access blocked"),
// and the server's Referrer-Policy is no-referrer for every page. The tiles
// alone send our origin (never the path, so no place or profile leaks).
export const TILE_OPTIONS = {
  attribution: TILES.attribution,
  maxZoom: TILES.maxZoom,
  referrerPolicy: 'strict-origin-when-cross-origin' as const
};
