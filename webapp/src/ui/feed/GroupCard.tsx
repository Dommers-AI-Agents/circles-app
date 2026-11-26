// A burst of one person's activities. Up to five: one card you swipe
// through, each page a whole activity with its own reactions and comments.
// More: a summary card with "Show all N" that opens into full cards
// (iOS Logic/ActivityGroupLayout.swift).
import { useRef, useState } from 'react';
import type { Activity } from '../../api/feed';
import { activityCard, groupSummary } from '../../logic/activityCopy';
import { groupLayout } from '../../logic/activityGroups';
import { ActivityPicture } from './ActivityPicture';
import { ActivityBody, ActivityCard, ActorHead } from './ActivityCard';

interface Props {
  activities: Activity[];
  expanded: boolean;
  onExpand: (open: boolean) => void;
  onReact: (activity: Activity, emoji: string) => void;
  onComments: (activity: Activity) => void;
}

export function GroupCard(props: Props) {
  return groupLayout(props.activities.length) === 'pages' ? <PagedGroup {...props} /> : <StackGroup {...props} />;
}

function PagedGroup({ activities, onReact, onComments }: Props) {
  const track = useRef<HTMLDivElement>(null);
  const [page, setPage] = useState(0);
  const go = (to: number) => {
    const el = track.current;
    if (!el) return;
    const next = Math.max(0, Math.min(activities.length - 1, to));
    el.scrollTo({ left: next * el.clientWidth, behavior: 'smooth' });
  };
  const onScroll = () => {
    const el = track.current;
    if (el && el.clientWidth) setPage(Math.round(el.scrollLeft / el.clientWidth));
  };
  return (
    <article className="card feed-card">
      <ActorHead activity={activities[0]} sentence={groupSummary(activities)} />
      <div className="feed-track" ref={track} onScroll={onScroll}>
        {activities.map((activity, index) => (
          <section key={activity._id} className="feed-page" aria-label={`${index + 1} of ${activities.length}`}>
            <ActivityBody activity={activity} onReact={onReact} onComments={onComments} showSentence />
          </section>
        ))}
      </div>
      <div className="feed-pager">
        <button type="button" className="icon-btn" onClick={() => go(page - 1)} disabled={page === 0} aria-label="Previous">‹</button>
        <span className="feed-dots" aria-label={`${page + 1} of ${activities.length}`}>
          {activities.map((activity, index) => <span key={activity._id} className={index === page ? 'on' : ''} />)}
        </span>
        <button type="button" className="icon-btn" onClick={() => go(page + 1)} disabled={page >= activities.length - 1} aria-label="Next">›</button>
      </div>
    </article>
  );
}

function StackGroup({ activities, expanded, onExpand, onReact, onComments }: Props) {
  const firsts = activities.slice(0, 4);
  return (
    <>
      <article className="card feed-card">
        <ActorHead activity={activities[0]} sentence={groupSummary(activities)} />
        {expanded ? null : (
          <div className="feed-stack" aria-hidden="true">
            {firsts.map((activity) => {
              const copy = activityCard(activity);
              return <ActivityPicture key={activity._id} pictures={copy.pictures} poster={copy.poster} chip={null} />;
            })}
          </div>
        )}
        <button type="button" className="btn block soft feed-showall" onClick={() => onExpand(!expanded)} aria-expanded={expanded}>
          {expanded ? 'Show less' : `Show all ${activities.length}`}
        </button>
      </article>
      {expanded ? activities.map((activity) => (
        <ActivityCard key={activity._id} activity={activity} onReact={onReact} onComments={onComments} />
      )) : null}
    </>
  );
}
