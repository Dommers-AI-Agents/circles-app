// Runs the live stream while someone is signed in and turns what it says into
// refreshed screens: each event marks the queries it changed as stale
// (logic/liveInvalidations.ts), and a stream that came back after a gap
// refreshes everything it might have missed. Renders nothing; mounted once,
// in ui/Layout.tsx.
import { useEffect } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { useAuth } from '../auth/AuthContext';
import { invalidationsFor, type Key } from '../logic/liveInvalidations';
import { BADGE_KEYS } from './badges';
import { liveStream } from './sse';

/** What a stream that was down for a while may have missed */
const AFTER_A_GAP: Key[] = [['messages'], BADGE_KEYS.messages, BADGE_KEYS.notifications, ['notifications'], ['feed']];

export function LiveUpdates() {
  const { session, userId } = useAuth();
  const queryClient = useQueryClient();
  const token = session?.token;

  useEffect(() => {
    if (!token) { liveStream.stop(); return undefined; }
    const refresh = (keys: Key[]) => keys.forEach((queryKey) => { queryClient.invalidateQueries({ queryKey: [...queryKey] }); });
    const offEvents = liveStream.subscribe('*', (event) => refresh(invalidationsFor(event, BADGE_KEYS, userId)));
    const offGap = liveStream.subscribe('reconnected', () => refresh(AFTER_A_GAP));
    liveStream.start();
    return () => {
      offEvents();
      offGap();
      liveStream.stop();
    };
  }, [token, userId, queryClient]);

  return null;
}
