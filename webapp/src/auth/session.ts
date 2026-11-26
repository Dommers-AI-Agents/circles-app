// The saved sign-in. One key for the whole origin, the same one the store's
// web page uses (backend/public/store-page.js), so someone who joined at a
// store's QR is already signed in here and the other way round.
export interface Session {
  token: string;
  name: string;
  userId?: string;
}

const KEY = 'fc.store.session';
type Listener = (session: Session | null) => void;
const listeners = new Set<Listener>();
let memory: Session | null = read();

function read(): Session | null {
  try {
    const value = JSON.parse(localStorage.getItem(KEY) || 'null');
    return value && typeof value.token === 'string' ? value : null;
  } catch {
    return null;
  }
}

export const getSession = (): Session | null => memory;

export function setSession(session: Session | null): void {
  memory = session;
  try {
    if (session) localStorage.setItem(KEY, JSON.stringify(session));
    else localStorage.removeItem(KEY);
  } catch {
    // Private mode: signed in for this visit only
  }
  listeners.forEach((listener) => listener(memory));
}

export function onSessionChange(listener: Listener): () => void {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

// Another tab signed in or out
if (typeof window !== 'undefined') {
  window.addEventListener('storage', (event) => {
    if (event.key !== KEY) return;
    memory = read();
    listeners.forEach((listener) => listener(memory));
  });
}

/** The user id inside the token, for accounts saved before `userId` was kept. */
export function userIdFromToken(token: string): string | undefined {
  try {
    const payload = JSON.parse(atob(token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/')));
    return typeof payload.uid === 'string' ? payload.uid : undefined;
  } catch {
    return undefined;
  }
}

export const myUserId = (): string | undefined => {
  const session = getSession();
  return session ? session.userId || userIdFromToken(session.token) : undefined;
};
