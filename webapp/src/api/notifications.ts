// The Notifications list (the bell): requests, answers and news about my
// own things. Shapes from backend/controllers/notificationController.js.
import { get, put } from './client';

export interface AppNotification {
  id: string;
  type: string;
  title?: string | null;
  body?: string | null;
  data?: Record<string, unknown> | null;
  read?: boolean;
  createdAt?: string;
}

export interface NotificationsPage {
  notifications: AppNotification[];
  hasMore: boolean;
  offset: number;
}

export const NOTIFICATIONS_PAGE_SIZE = 50;

export const notificationsPage = (offset: number, signal?: AbortSignal): Promise<NotificationsPage> =>
  get<{ notifications?: AppNotification[]; hasMore?: boolean }>('/notifications', { limit: NOTIFICATIONS_PAGE_SIZE, offset }, signal)
    .then((r) => ({ notifications: r.notifications || [], hasMore: r.hasMore === true, offset }));

export const markNotificationRead = (id: string) => put(`/notifications/${encodeURIComponent(id)}/read`);

export const markAllNotificationsRead = () => put('/notifications/read-all');
