// Where the phone is, for a register scan. The same rule as the store's web
// page (backend/public/store-page.js askWhere) and the app: the fix goes
// with the scan; a phone that won't say still earns, marked "location off";
// a fix that failed or took too long sends neither.
import type { ScanWhere } from '../../api/rewards';

export function askWhere(): Promise<ScanWhere> {
  return new Promise((resolve) => {
    if (!navigator.geolocation) { resolve({ locationOff: true }); return; }
    let answered = false;
    const finish = (value: ScanWhere) => { if (!answered) { answered = true; resolve(value); } };
    navigator.geolocation.getCurrentPosition(
      (position) => finish({ location: { latitude: position.coords.latitude, longitude: position.coords.longitude, accuracy: position.coords.accuracy } }),
      (error) => finish(error && error.code === 1 ? { locationOff: true } : {}),
      { enableHighAccuracy: true, timeout: 8000, maximumAge: 60000 }
    );
    setTimeout(() => finish({}), 9000);
  });
}

/** Where this browser is, for Locals: a spot, 'denied' when the person said no, null when no fix came. */
export function currentSpot(): Promise<{ lat: number; lng: number } | 'denied' | null> {
  return new Promise((resolve) => {
    if (!navigator.geolocation) { resolve(null); return; }
    let answered = false;
    const finish = (value: { lat: number; lng: number } | 'denied' | null) => { if (!answered) { answered = true; resolve(value); } };
    navigator.geolocation.getCurrentPosition(
      (position) => finish({ lat: position.coords.latitude, lng: position.coords.longitude }),
      (error) => finish(error && error.code === 1 ? 'denied' : null),
      { enableHighAccuracy: false, timeout: 10000, maximumAge: 5 * 60000 }
    );
    setTimeout(() => finish(null), 11000);
  });
}

/** True only when this site may already read the location without asking. */
export async function locationAlreadyAllowed(): Promise<boolean> {
  try {
    if (!navigator.permissions || !navigator.geolocation) return false;
    const status = await navigator.permissions.query({ name: 'geolocation' as PermissionName });
    return status.state === 'granted';
  } catch {
    return false;
  }
}
