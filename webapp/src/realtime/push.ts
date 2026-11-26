// Browser notifications: this browser's on/off switch. The server keeps the
// subscription in its own list (backend/services/webPush.js) and sends to it
// beside the phone push, under the same per-type switches.
import { get, post } from '../api/client';

export type PushState = 'unsupported' | 'blocked' | 'off' | 'on';

const supported = (): boolean =>
  typeof window !== 'undefined' && 'serviceWorker' in navigator && 'PushManager' in window && 'Notification' in window;

const keyBytes = (base64Url: string): Uint8Array => {
  const padded = base64Url.replace(/-/g, '+').replace(/_/g, '/') + '='.repeat((4 - (base64Url.length % 4)) % 4);
  const raw = atob(padded);
  const bytes = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i);
  return bytes;
};

const registration = () => navigator.serviceWorker.register('/sw.js', { scope: '/' });

export async function pushState(): Promise<PushState> {
  if (!supported()) return 'unsupported';
  if (Notification.permission === 'denied') return 'blocked';
  const existing = await navigator.serviceWorker.getRegistration('/');
  const subscription = existing ? await existing.pushManager.getSubscription() : null;
  return subscription && Notification.permission === 'granted' ? 'on' : 'off';
}

/** Ask (once, from a tap), subscribe, and tell the server. */
export async function turnPushOn(): Promise<PushState> {
  if (!supported()) return 'unsupported';
  const { data } = await get<{ data: { publicKey: string | null } }>('/web-push/key');
  if (!data.publicKey) throw new Error("Notifications aren't available right now.");
  const permission = await Notification.requestPermission();
  if (permission !== 'granted') return permission === 'denied' ? 'blocked' : 'off';
  const worker = await registration();
  await navigator.serviceWorker.ready;
  const subscription = await worker.pushManager.getSubscription()
    || await worker.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: keyBytes(data.publicKey).buffer as ArrayBuffer });
  await post('/web-push/subscribe', { subscription: subscription.toJSON() });
  return 'on';
}

export async function turnPushOff(): Promise<PushState> {
  if (!supported()) return 'unsupported';
  const existing = await navigator.serviceWorker.getRegistration('/');
  const subscription = existing ? await existing.pushManager.getSubscription() : null;
  if (subscription) {
    await post('/web-push/unsubscribe', { endpoint: subscription.endpoint }).catch(() => undefined);
    await subscription.unsubscribe();
  }
  return 'off';
}
