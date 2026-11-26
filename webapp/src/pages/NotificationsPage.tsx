// The bell: requests, answers and news about my own things, newest first.
// A tap marks the row read and opens what it's about, where the iPhone app
// would go. "Mark all read" clears the badge.
import { useEffect, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useInfiniteQuery, useQueryClient, type InfiniteData } from '@tanstack/react-query';
import { markAllNotificationsRead, markNotificationRead, notificationsPage, type AppNotification, type NotificationsPage as Page } from '../api/notifications';
import { messageOf } from '../api/client';
import { timeAgo } from '../logic/labels';
import { notificationPath } from '../logic/notificationRoute';
import { mergeNotificationPages, nextNotificationOffset, notificationRow } from '../logic/notificationRow';
import { BADGE_KEYS } from '../realtime/badges';
import { Avatar, Empty, Head, LoadError, Spinner, toast } from '../ui/kit';
import './notifications.css';

const KEY = ['notifications'] as const;
type Data = InfiniteData<Page, number>;

const markRead = (data: Data | undefined, id: string | null): Data | undefined => data && {
  ...data,
  pages: data.pages.map((page) => ({
    ...page,
    notifications: page.notifications.map((n) => (id === null || n.id === id ? { ...n, read: true } : n))
  }))
};

export function NotificationsPage() {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const sentinel = useRef<HTMLDivElement>(null);
  const [clearing, setClearing] = useState(false);

  const list = useInfiniteQuery({
    queryKey: KEY,
    queryFn: ({ pageParam, signal }) => notificationsPage(pageParam, signal),
    initialPageParam: 0,
    getNextPageParam: (_last, pages) => nextNotificationOffset(pages)
  });
  const rows = list.data ? mergeNotificationPages(list.data.pages) : [];
  const anyUnread = rows.some((n) => n.read !== true);
  const { hasNextPage, isFetchingNextPage, fetchNextPage } = list;

  useEffect(() => {
    const el = sentinel.current;
    if (!el || !hasNextPage) return;
    const observer = new IntersectionObserver((entries) => {
      if (entries.some((entry) => entry.isIntersecting) && !isFetchingNextPage) fetchNextPage();
    }, { rootMargin: '400px 0px' });
    observer.observe(el);
    return () => observer.disconnect();
  }, [hasNextPage, isFetchingNextPage, fetchNextPage, rows.length]);

  const open = (notification: AppNotification) => {
    if (notification.read !== true) {
      queryClient.setQueryData<Data>(KEY, (data) => markRead(data, notification.id));
      // Opening goes on at once; the badge catches up when the server has it
      markNotificationRead(notification.id)
        .then(() => queryClient.invalidateQueries({ queryKey: BADGE_KEYS.notifications }))
        .catch(() => queryClient.invalidateQueries({ queryKey: KEY }));
    }
    navigate(notificationPath(notification.type, notification.data));
  };

  const readAll = async () => {
    setClearing(true);
    try {
      await markAllNotificationsRead();
      queryClient.setQueryData<Data>(KEY, (data) => markRead(data, null));
      await queryClient.invalidateQueries({ queryKey: BADGE_KEYS.notifications });
      toast('All caught up');
    } catch (error) {
      toast(`Couldn't mark them read. ${messageOf(error)}`);
    } finally {
      setClearing(false);
    }
  };

  return (
    <>
      <Head title="Notifications" back>
        {anyUnread ? <button className="icon-btn" onClick={readAll} disabled={clearing}>{clearing ? 'Marking…' : 'Mark all read'}</button> : null}
      </Head>
      <main className="page">
        {list.isPending ? <Spinner /> : null}
        {list.isError && !list.data ? <LoadError message={messageOf(list.error)} retry={() => list.refetch()} /> : null}
        {list.data && rows.length === 0 ? (
          <Empty mark="🔔" title="No notifications yet">
            When someone follows you, reacts to or comments on what you share, or a store you follow has news, it shows up here.
          </Empty>
        ) : null}
        {rows.length > 0 ? (
          <ul className="list card notif-list">
            {rows.map((notification) => {
              const row = notificationRow(notification);
              return (
                <li key={notification.id}>
                  <button type="button" className={`item notif-row ${row.unread ? 'unread' : ''}`} onClick={() => open(notification)}>
                    <span className="notif-who">
                      {row.senderName || row.senderPhoto ? (
                        <Avatar name={row.senderName || 'FavCircles'} src={row.senderPhoto} size={44} seed={row.senderId || undefined} />
                      ) : (
                        <span className="notif-mark" aria-hidden="true">{row.mark}</span>
                      )}
                      {row.senderName || row.senderPhoto ? <span className="notif-kind" aria-hidden="true">{row.mark}</span> : null}
                    </span>
                    <span className="grow">
                      <span className="notif-title">{row.title}</span>
                      {row.body ? <span className="notif-body">{row.body}</span> : null}
                      {row.at ? <span className="notif-time">{timeAgo(row.at)}</span> : null}
                    </span>
                    {row.unread ? <span className="notif-dot" aria-label="Unread" /> : null}
                  </button>
                </li>
              );
            })}
          </ul>
        ) : null}
        <div ref={sentinel} />
        {isFetchingNextPage ? <Spinner /> : null}
        {list.isFetchNextPageError ? (
          <LoadError message={`Older notifications didn't load. ${messageOf(list.error)}`} retry={() => fetchNextPage()} />
        ) : null}
      </main>
    </>
  );
}
