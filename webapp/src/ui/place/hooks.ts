// What the Place page's pieces share: the view's query key, and one refresh
// after a write (the same venue is cached under its save ids AND its venue
// id, so the whole ['place'] prefix goes).
import { useCallback } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import type { PlaceView } from '../../logic/placeView';

export const placeKey = (routeId: string) => ['place', routeId] as const;

export function usePlaceRefresh() {
  const queryClient = useQueryClient();
  return useCallback((circleIds: (string | null | undefined)[] = []) => Promise.all([
    queryClient.invalidateQueries({ queryKey: ['place'] }),
    queryClient.invalidateQueries({ queryKey: ['circles'] }),
    queryClient.invalidateQueries({ queryKey: ['map'] }),
    queryClient.invalidateQueries({ queryKey: ['user'] }),
    ...circleIds.filter((id): id is string => !!id).map((id) => queryClient.invalidateQueries({ queryKey: ['circle', id] }))
  ]), [queryClient]);
}

/** Change the loaded view at once (a like, a follow) without waiting for a reload. */
export function usePatchView(routeId: string) {
  const queryClient = useQueryClient();
  return useCallback((patch: (view: PlaceView) => PlaceView) => {
    queryClient.setQueryData<PlaceView>(placeKey(routeId), (view) => (view ? patch(view) : view));
  }, [queryClient, routeId]);
}

/** The last circle I saved to (Add Place shares the key). Storage can be blocked. */
export const readLastCircle = (key: string): string | null => {
  try { return window.localStorage.getItem(key); } catch { return null; }
};
export const writeLastCircle = (key: string, id: string) => {
  try { window.localStorage.setItem(key, id); } catch { /* private window: nothing to remember */ }
};
