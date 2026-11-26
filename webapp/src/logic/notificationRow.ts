// What one row of the Notifications list shows: who it's from, its words
// and when. The server keeps the sender as data.fromUser* (most types) or
// data.sender* (messages); createdAt is an ISO string, but older rows can
// carry a Firestore timestamp ({_seconds}) or epoch milliseconds.
import type { AppNotification } from '../api/notifications';
import { notificationMark } from './notificationRoute';

export interface NotificationRowCopy {
  senderName: string | null;
  senderPhoto: string | null;
  /** Seeds the initials colour */
  senderId: string | null;
  mark: string;
  title: string;
  body: string | null;
  /** ISO time, or null when the row has none we can read */
  at: string | null;
  unread: boolean;
}

const text = (value: unknown): string | null => (typeof value === 'string' && value.trim() ? value.trim() : null);

/** Any time shape the server has stored, as an ISO string. */
export function isoOf(value: unknown): string | null {
  if (typeof value === 'string') return Number.isNaN(Date.parse(value)) ? null : value;
  if (typeof value === 'number' && Number.isFinite(value)) return new Date(value < 1e12 ? value * 1000 : value).toISOString();
  if (value && typeof value === 'object') {
    const record = value as Record<string, unknown>;
    const seconds = typeof record._seconds === 'number' ? record._seconds : typeof record.seconds === 'number' ? record.seconds : null;
    if (seconds !== null) return new Date(seconds * 1000).toISOString();
  }
  return null;
}

export function notificationRow(notification: AppNotification): NotificationRowCopy {
  const data = notification.data || {};
  const senderName = text(data.fromUserName) || text(data.senderName);
  const senderPhoto = text(data.fromUserPhoto) || text(data.senderPhoto);
  const photo = senderPhoto && /^https?:\/\//i.test(senderPhoto) ? senderPhoto : null;
  const title = text(notification.title) || text(notification.body) || 'Notification';
  const body = text(notification.title) ? text(notification.body) : null;
  return {
    senderName,
    senderPhoto: photo,
    senderId: text(data.fromUserId) || text(data.senderId),
    mark: notificationMark(notification.type || ''),
    title,
    body: body && body !== title ? body : null,
    at: isoOf(notification.createdAt),
    unread: notification.read !== true
  };
}

/** Rows in order, each once (an offset can overlap the page before). */
export function mergeNotificationPages(pages: { notifications: AppNotification[] }[]): AppNotification[] {
  const seen = new Set<string>();
  const merged: AppNotification[] = [];
  pages.forEach((page) => page.notifications.forEach((notification) => {
    if (!notification || !notification.id || seen.has(notification.id)) return;
    seen.add(notification.id);
    merged.push(notification);
  }));
  return merged;
}

/** The next page's offset, or undefined at the end. */
export function nextNotificationOffset(pages: { notifications: AppNotification[]; hasMore: boolean; offset: number }[]): number | undefined {
  if (pages.length === 0) return 0;
  const last = pages[pages.length - 1];
  if (!last.hasMore || last.notifications.length === 0) return undefined;
  return last.offset + last.notifications.length;
}
