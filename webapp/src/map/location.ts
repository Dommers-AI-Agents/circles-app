// Where the person is, from the browser. Two ways to ask: quietly (only when
// they already said yes, so opening the map never throws a permission box at
// them) and out loud (they tapped "locate me" / "near me").
import type { LatLng } from '../logic/geo';

let last: LatLng | null = null;

/** The last position this page learned, if any. */
export const lastPosition = (): LatLng | null => last;

const read = (timeout: number): Promise<LatLng> =>
  new Promise((resolve, reject) => {
    if (!('geolocation' in navigator)) {
      reject(new Error("This browser can't share your location."));
      return;
    }
    navigator.geolocation.getCurrentPosition(
      (position) => {
        last = { lat: position.coords.latitude, lng: position.coords.longitude };
        resolve(last);
      },
      (error) => reject(new Error(error.code === error.PERMISSION_DENIED
        ? "Location is turned off for this site. Allow it in your browser's settings to use this."
        : "We couldn't find where you are. Try again in a moment.")),
      { enableHighAccuracy: false, timeout, maximumAge: 120000 }
    );
  });

/** Asks the browser (which asks the person the first time). Rejects with words to show. */
export const askPosition = (): Promise<LatLng> => read(12000);

/** The position only when location is already allowed; null otherwise. Never prompts. */
export async function quietPosition(): Promise<LatLng | null> {
  if (last) return last;
  try {
    if (!navigator.permissions || !navigator.permissions.query) return null;
    const status = await navigator.permissions.query({ name: 'geolocation' });
    if (status.state !== 'granted') return null;
    return await read(6000);
  } catch {
    return null;
  }
}
