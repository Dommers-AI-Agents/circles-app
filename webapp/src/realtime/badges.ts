// The numbers on the tab bar. Plain queries under fixed keys, so anything
// that learns of a change (the live stream, opening a chat, reading the
// notifications) refreshes a badge with
//   queryClient.invalidateQueries({ queryKey: BADGE_KEYS.messages })
import { useQuery } from '@tanstack/react-query';
import { get } from '../api/client';

export const BADGE_KEYS = {
  messages: ['badge', 'messages'] as const,
  notifications: ['badge', 'notifications'] as const
};

export function useUnreadMessages(): number {
  const query = useQuery({
    queryKey: BADGE_KEYS.messages,
    queryFn: () => get<{ totalUnread?: number }>('/messages/unread-count').then((r) => r.totalUnread || 0),
    refetchInterval: 60_000
  });
  return query.data || 0;
}

export function useUnreadNotifications(): number {
  const query = useQuery({
    queryKey: BADGE_KEYS.notifications,
    queryFn: () => get<{ unreadCount?: number }>('/notifications/unread-count').then((r) => r.unreadCount || 0),
    refetchInterval: 60_000
  });
  return query.data || 0;
}
