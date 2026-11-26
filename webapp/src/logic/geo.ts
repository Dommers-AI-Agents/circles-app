// Places carry GeoJSON points: [longitude, latitude]. Everything that needs
// latitude first goes through here, so the order is flipped in one place.
import type { GeoPoint } from '../api/types';

export interface LatLng {
  lat: number;
  lng: number;
}

export function latLngOf(point: GeoPoint | null | undefined): LatLng | null {
  const pair = point && Array.isArray(point.coordinates) ? point.coordinates : null;
  if (!pair || pair.length < 2) return null;
  const [lng, lat] = pair;
  if (!Number.isFinite(lat) || !Number.isFinite(lng) || (lat === 0 && lng === 0)) return null;
  if (Math.abs(lat) > 90 || Math.abs(lng) > 180) return null;
  return { lat, lng };
}

export const pointOf = ({ lat, lng }: LatLng): GeoPoint => ({ type: 'Point', coordinates: [lng, lat] });

/** Metres between two points (haversine). */
export function distanceMeters(a: LatLng, b: LatLng): number {
  const rad = (d: number) => (d * Math.PI) / 180;
  const dLat = rad(b.lat - a.lat);
  const dLng = rad(b.lng - a.lng);
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * 6371000 * Math.asin(Math.min(1, Math.sqrt(h)));
}

/** "450 ft", "0.3 mi", "12 mi" */
export function distanceText(meters: number): string {
  const feet = meters * 3.28084;
  if (feet < 1000) return `${Math.max(10, Math.round(feet / 10) * 10)} ft`;
  const miles = meters / 1609.344;
  return miles < 10 ? `${miles.toFixed(1)} mi` : `${Math.round(miles)} mi`;
}

/** Charlotte: where the map opens when nothing says where the person is. */
export const DEFAULT_CENTER: LatLng = { lat: 35.2271, lng: -80.8431 };
