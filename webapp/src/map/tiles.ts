// The map's tile source, in one place so another provider can be swapped in.
// OpenStreetMap's standard tiles: free, no key, and the credit line below is
// required wherever the map shows. Tiles are images (the CSP allows https
// images); nothing here adds a script or a fetch.
import L from 'leaflet';

export const TILES = {
  url: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  attribution: '&copy; <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noopener noreferrer">OpenStreetMap</a> contributors',
  maxZoom: 19
};

export const tileLayer = (): L.TileLayer =>
  L.tileLayer(TILES.url, { attribution: TILES.attribution, maxZoom: TILES.maxZoom });
