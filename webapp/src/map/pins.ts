// How places are drawn on the map: a round coloured pin with the category's
// mark, or a small dot when pins are crowded (logic/pinTiers). Built with
// L.divIcon and styled in pages/map.css: no marker images.
import L from 'leaflet';
import { categoryOf } from '../logic/labels';

export type PinTier = 'full' | 'dot';
export type PinOwner = 'mine' | 'friend';

const cache = new Map<string, L.DivIcon>();

export function pinIcon(category: string, owner: PinOwner, tier: PinTier, selected: boolean): L.DivIcon {
  const key = `${tier}|${owner}|${selected ? 1 : 0}|${tier === 'full' ? category : ''}`;
  const known = cache.get(key);
  if (known) return known;
  const size = tier === 'dot' ? 14 : selected ? 44 : 36;
  const icon = L.divIcon({
    className: `fc-pin ${tier} ${owner}${selected ? ' selected' : ''}`,
    // The mark comes from the fixed list in logic/labels, never from place data
    html: tier === 'full' ? `<span aria-hidden="true">${categoryOf(category).mark}</span>` : '',
    iconSize: [size, size],
    iconAnchor: [size / 2, size / 2]
  });
  cache.set(key, icon);
  return icon;
}

export const meIcon = (): L.DivIcon => L.divIcon({ className: 'fc-me', html: '', iconSize: [18, 18], iconAnchor: [9, 9] });

/** The draft pin on Add Place's "by hand" map. */
export const dropIcon = (): L.DivIcon =>
  L.divIcon({ className: 'fc-pin full mine selected', html: '<span aria-hidden="true">📍</span>', iconSize: [44, 44], iconAnchor: [22, 22] });
