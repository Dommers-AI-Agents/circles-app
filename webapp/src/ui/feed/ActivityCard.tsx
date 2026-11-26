// One Activity row as a card: who (to their profile, or the store's page),
// what they did, when, the picture, and reactions and comments. A tap on
// the words or the picture opens what the row is about.
import { Link, useNavigate } from 'react-router-dom';
import type { Activity } from '../../api/feed';
import { activityCard } from '../../logic/activityCopy';
import { timeAgo } from '../../logic/labels';
import { Avatar } from '../kit';
import { ActivityPicture } from './ActivityPicture';
import { ReactionBar } from './ReactionBar';

export function ActorHead({ activity, sentence }: { activity: Activity; sentence?: string }) {
  const copy = activityCard(activity);
  return (
    <div className="feed-head">
      <Link to={copy.actorPath} className="feed-avatar" aria-label={copy.actorName}>
        <Avatar name={copy.actorName} src={activity.actor?.profilePicture} size={40} seed={activity.actorId} />
      </Link>
      <p className="grow feed-sentence">
        <Link to={copy.actorPath} className="feed-actor">{copy.actorName}</Link> {sentence ?? copy.sentence}
        {activity.timestamp ? <span className="feed-time"> · {timeAgo(activity.timestamp)}</span> : null}
      </p>
    </div>
  );
}

/** The body of a card without the actor line (the group card shows that once for the burst). */
export function ActivityBody({ activity, onReact, onComments, showSentence }: {
  activity: Activity;
  onReact: (activity: Activity, emoji: string) => void;
  onComments: (activity: Activity) => void;
  showSentence?: boolean;
}) {
  const navigate = useNavigate();
  const copy = activityCard(activity);
  const open = () => navigate(copy.target);
  return (
    <>
      <button type="button" className="feed-open" onClick={open} aria-label={`Open: ${copy.actorName} ${copy.sentence}`}>
        <ActivityPicture key={activity._id} pictures={copy.pictures} poster={copy.poster} chip={copy.chip} />
        {showSentence ? <span className="feed-page-sentence">{copy.sentence}{activity.timestamp ? <span className="feed-time"> · {timeAgo(activity.timestamp)}</span> : null}</span> : null}
        {copy.quote ? <span className="feed-quote">“{copy.quote}”</span> : null}
      </button>
      <ReactionBar activity={activity} onReact={(emoji) => onReact(activity, emoji)} onComments={() => onComments(activity)} />
    </>
  );
}

export function ActivityCard({ activity, onReact, onComments }: {
  activity: Activity;
  onReact: (activity: Activity, emoji: string) => void;
  onComments: (activity: Activity) => void;
}) {
  return (
    <article className="card feed-card">
      <ActorHead activity={activity} />
      <ActivityBody activity={activity} onReact={onReact} onComments={onComments} />
    </article>
  );
}
