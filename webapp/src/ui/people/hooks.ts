// Small hooks the people screens share.
import { useCallback, useEffect, useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import type { LatLng } from '../../logic/geo';

/** The value, once it has stopped changing for `ms`. */
export function useDebounced<T>(value: T, ms = 300): T {
  const [settled, setSettled] = useState(value);
  useEffect(() => {
    const timer = setTimeout(() => setSettled(value), ms);
    return () => clearTimeout(timer);
  }, [value, ms]);
  return settled;
}

/**
 * Where the browser says the person is. `null` until it answers, and for
 * good when they say no or the browser can't tell: callers carry on without
 * it. With `ask: false` the browser is only read when the person has already
 * allowed this site to know, so the screen never raises the question itself.
 */
export function useBrowserLocation({ ask }: { ask: boolean }): { where: LatLng | null; settled: boolean } {
  const [where, setWhere] = useState<LatLng | null>(null);
  const [settled, setSettled] = useState(false);
  useEffect(() => {
    let live = true;
    const done = () => { if (live) setSettled(true); };
    const read = () => navigator.geolocation.getCurrentPosition(
      (position) => {
        if (!live) return;
        setWhere({ lat: position.coords.latitude, lng: position.coords.longitude });
        setSettled(true);
      },
      done,
      { maximumAge: 10 * 60 * 1000, timeout: 6000 }
    );
    if (!('geolocation' in navigator)) { done(); return () => { live = false; }; }
    if (ask) { read(); return () => { live = false; }; }
    if (!navigator.permissions || !navigator.permissions.query) { done(); return () => { live = false; }; }
    navigator.permissions.query({ name: 'geolocation' })
      .then((status) => { if (!live) return; if (status.state === 'granted') read(); else done(); })
      .catch(done);
    return () => { live = false; };
  }, [ask]);
  return { where, settled };
}

/**
 * After a follow, connect, block or their undoing: reload what those change.
 * The discover and search lists are left alone on purpose, so the person I
 * just followed doesn't jump out from under my finger; their button keeps
 * the new state itself.
 */
export function useRelationshipRefresh(): () => Promise<void> {
  const queryClient = useQueryClient();
  return useCallback(async () => {
    await Promise.all([
      queryClient.invalidateQueries({ queryKey: ['user'] }),
      queryClient.invalidateQueries({ queryKey: ['me'] }),
      queryClient.invalidateQueries({ queryKey: ['people', 'connections'] }),
      queryClient.invalidateQueries({ queryKey: ['people', 'requests'] }),
      queryClient.invalidateQueries({ queryKey: ['people', 'following'] }),
      queryClient.invalidateQueries({ queryKey: ['people', 'blocks'] }),
      queryClient.invalidateQueries({ queryKey: ['feed'] })
    ]);
  }, [queryClient]);
}
