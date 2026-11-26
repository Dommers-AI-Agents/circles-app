// The Activity feed: what the people and stores I follow did, newest first,
// every row a card with a picture. Bursts by one person are one card. More
// loads as I scroll; it refreshes when I come back to the tab.
import { useEffect, useRef, useState } from 'react';
import { Link } from 'react-router-dom';
import { useInfiniteQuery } from '@tanstack/react-query';
import { feedPage, type Activity } from '../api/feed';
import { messageOf } from '../api/client';
import { groupFeed, mergePages, nextOffset } from '../logic/activityGroups';
import { useUnreadNotifications } from '../realtime/badges';
import { Empty, Head, LoadError, Spinner } from '../ui/kit';
import { ActivityCard } from '../ui/feed/ActivityCard';
import { CommentsSheet } from '../ui/feed/CommentsSheet';
import { GroupCard } from '../ui/feed/GroupCard';
import { FEED_KEY, useReact } from '../ui/feed/useActivityActions';
import '../ui/feed/feed.css';

/** Keep loading while a page groups down to too few cards to scroll, but not forever */
const FILL_CARDS = 8;
const FILL_CAP = 300;

export function FeedPage() {
  const unread = useUnreadNotifications();
  const onReact = useReact();
  const [commentsFor, setCommentsFor] = useState<string | null>(null);
  const [expanded, setExpanded] = useState<Set<string>>(() => new Set());
  const sentinel = useRef<HTMLDivElement>(null);

  const feed = useInfiniteQuery({
    queryKey: FEED_KEY,
    queryFn: ({ pageParam, signal }) => feedPage(pageParam, signal),
    initialPageParam: 0,
    getNextPageParam: (_last, pages) => nextOffset(pages),
    refetchOnWindowFocus: true
  });

  const activities = feed.data ? mergePages(feed.data.pages) : [];
  const items = groupFeed(activities);
  const { hasNextPage, isFetchingNextPage, fetchNextPage, isError } = feed;

  // Load the next page when the end of the list comes into view
  useEffect(() => {
    const el = sentinel.current;
    if (!el || !hasNextPage) return;
    const observer = new IntersectionObserver((entries) => {
      if (entries.some((entry) => entry.isIntersecting) && !isFetchingNextPage) fetchNextPage();
    }, { rootMargin: '600px 0px' });
    observer.observe(el);
    return () => observer.disconnect();
  }, [hasNextPage, isFetchingNextPage, fetchNextPage, items.length]);

  // A page can collapse into one card (someone saved twenty places): fill the screen
  useEffect(() => {
    if (hasNextPage && !isFetchingNextPage && !isError && items.length < FILL_CARDS && activities.length > 0 && activities.length < FILL_CAP) fetchNextPage();
  }, [hasNextPage, isFetchingNextPage, isError, items.length, activities.length, fetchNextPage]);

  const openComments = (activity: Activity) => setCommentsFor(activity._id);
  const commentsActivity = commentsFor ? activities.find((a) => a._id === commentsFor) || null : null;
  const setOpen = (key: string, open: boolean) => setExpanded((current) => {
    const next = new Set(current);
    if (open) next.add(key); else next.delete(key);
    return next;
  });

  return (
    <>
      <Head title="Activity" lead>
        <Link to="/notifications" className="icon-btn feed-bell" aria-label={unread > 0 ? `Notifications, ${unread} unread` : 'Notifications'}>
          <svg viewBox="0 0 24 24" width="24" height="24" aria-hidden="true" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round">
            <path d="M6 9a6 6 0 1 1 12 0c0 5 2 6.5 2 6.5H4S6 14 6 9Z" /><path d="M10 19a2 2 0 0 0 4 0" />
          </svg>
          {unread > 0 ? <span className="feed-bell-count">{unread > 99 ? '99+' : unread}</span> : null}
        </Link>
      </Head>
      <main className="page feed-list">
        {feed.isPending ? <Spinner /> : null}
        {feed.isError && !feed.data ? <LoadError message={messageOf(feed.error)} retry={() => feed.refetch()} /> : null}
        {feed.data && activities.length === 0 ? (
          <Empty mark="✨" title="Nothing here yet — follow a few people"
            action={<Link className="btn" to="/people">Find people to follow</Link>}>
            When people you follow save places, check in or post, it shows up here.
          </Empty>
        ) : null}

        {items.map((item) => item.kind === 'single' ? (
          <ActivityCard key={item.activity._id} activity={item.activity} onReact={onReact} onComments={openComments} />
        ) : (
          <GroupCard key={`group-${item.key}`} activities={item.activities} expanded={expanded.has(item.key)}
            onExpand={(open) => setOpen(item.key, open)} onReact={onReact} onComments={openComments} />
        ))}

        <div ref={sentinel} />
        {isFetchingNextPage ? <Spinner /> : null}
        {feed.isFetchNextPageError ? (
          <LoadError message={`Older activity didn't load. ${messageOf(feed.error)}`} retry={() => fetchNextPage()} />
        ) : null}
        {feed.data && activities.length > 0 && !hasNextPage && !isFetchingNextPage ? (
          <div className="feed-end card">
            <p>You're all caught up. Follow more people to see more here.</p>
            <Link className="btn soft small" to="/people">Find people</Link>
          </div>
        ) : null}
      </main>
      {commentsActivity ? <CommentsSheet activity={commentsActivity} onClose={() => setCommentsFor(null)} /> : null}
    </>
  );
}
