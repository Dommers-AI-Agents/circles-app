import { describe, expect, it } from 'vitest';
import type { AppNotification } from '../api/notifications';
import { isoOf, mergeNotificationPages, nextNotificationOffset, notificationRow } from './notificationRow';

const n = (extra: Partial<AppNotification> = {}): AppNotification => ({ id: 'n1', type: 'activity_comment', ...extra });

describe('isoOf', () => {
  it('keeps a readable ISO string', () => {
    expect(isoOf('2026-11-26T14:03:30.771Z')).toBe('2026-11-26T14:03:30.771Z');
  });
  it('reads a Firestore timestamp', () => {
    expect(isoOf({ _seconds: 1764165810, _nanoseconds: 0 })).toBe(new Date(1764165810000).toISOString());
    expect(isoOf({ seconds: 1764165810 })).toBe(new Date(1764165810000).toISOString());
  });
  it('reads epoch seconds and milliseconds', () => {
    expect(isoOf(1764165810)).toBe(new Date(1764165810000).toISOString());
    expect(isoOf(1764165810000)).toBe(new Date(1764165810000).toISOString());
  });
  it('is null for nothing or garbage', () => {
    expect(isoOf(undefined)).toBeNull();
    expect(isoOf('not a date')).toBeNull();
    expect(isoOf({})).toBeNull();
  });
});

describe('notificationRow', () => {
  it('takes the sender from fromUser fields', () => {
    const row = notificationRow(n({ title: 'New Comment', body: 'Blake commented on your check-in', data: { fromUserId: 'b', fromUserName: 'Blake', fromUserPhoto: 'https://x/p.jpg' } }));
    expect(row).toMatchObject({ senderName: 'Blake', senderPhoto: 'https://x/p.jpg', senderId: 'b', title: 'New Comment', body: 'Blake commented on your check-in', unread: true, mark: '💬' });
  });
  it('falls back to sender fields (messages)', () => {
    const row = notificationRow(n({ type: 'new_message', data: { senderId: 's', senderName: 'Sam', senderPhoto: null } }));
    expect(row.senderName).toBe('Sam');
    expect(row.senderPhoto).toBeNull();
    expect(row.senderId).toBe('s');
    expect(row.mark).toBe('✉️');
  });
  it('drops a photo that is not a web address', () => {
    expect(notificationRow(n({ data: { fromUserPhoto: 'gs://bucket/x.jpg' } })).senderPhoto).toBeNull();
  });
  it('uses the body as the title when there is no title, and never repeats it', () => {
    expect(notificationRow(n({ body: 'Hello there' }))).toMatchObject({ title: 'Hello there', body: null });
    expect(notificationRow(n({ title: 'Same', body: 'Same' }))).toMatchObject({ title: 'Same', body: null });
  });
  it('always has some title', () => {
    expect(notificationRow(n({ title: '  ', body: null, data: null })).title).toBe('Notification');
  });
  it('read rows are not unread', () => {
    expect(notificationRow(n({ read: true })).unread).toBe(false);
    expect(notificationRow(n({ read: false })).unread).toBe(true);
  });
  it('reads the time', () => {
    expect(notificationRow(n({ createdAt: '2026-11-26T14:03:30.771Z' })).at).toBe('2026-11-26T14:03:30.771Z');
  });
});

describe('notification paging', () => {
  it('merges without repeats', () => {
    const merged = mergeNotificationPages([{ notifications: [n({ id: 'a' }), n({ id: 'b' })] }, { notifications: [n({ id: 'b' }), n({ id: 'c' })] }]);
    expect(merged.map((x) => x.id)).toEqual(['a', 'b', 'c']);
  });
  it('asks from where the last page ended', () => {
    expect(nextNotificationOffset([])).toBe(0);
    expect(nextNotificationOffset([{ notifications: [n(), n()], hasMore: true, offset: 50 }])).toBe(52);
  });
  it('ends when the server says so or a page is empty', () => {
    expect(nextNotificationOffset([{ notifications: [n()], hasMore: false, offset: 0 }])).toBeUndefined();
    expect(nextNotificationOffset([{ notifications: [], hasMore: true, offset: 50 }])).toBeUndefined();
  });
});
