// The map's tile source, in one place so another provider can be swapped in.
// OpenStreetMap's standard tiles: free, no key, and the credit line below is
// required wherever the map shows. Tiles are images (the CSP allows https
// images); nothing here adds a script or a fetch.
import L from 'leaflet';
import { TILES, TILE_OPTIONS } from './tileOptions';

export { TILES, TILE_OPTIONS };

export const tileLayer = (): L.TileLayer => L.tileLayer(TILES.url, TILE_OPTIONS);
