// Under each card: the three most used reactions with the total, my own
// reaction (tap to pick or change; my emoji again takes it off), and the
// comments button.
import { useEffect, useRef, useState } from 'react';
import type { Activity } from '../../api/feed';
import { REACTIONS, topReactions } from '../../logic/reactions';
import { plural } from '../../logic/labels';

export function ReactionBar({ activity, onReact, onComments }: {
  activity: Activity;
  onReact: (emoji: string) => void;
  onComments: () => void;
}) {
  const [picking, setPicking] = useState(false);
  const wrap = useRef<HTMLDivElement>(null);
  const top = topReactions(activity.reactionSummary);
  const total = activity.reactionCount || 0;
  const comments = activity.commentCount || 0;
  const mine = activity.userReaction || null;
  const mineName = REACTIONS.find((r) => r.emoji === mine)?.name;

  useEffect(() => {
    if (!picking) return;
    const close = (event: MouseEvent | KeyboardEvent) => {
      if (event instanceof KeyboardEvent ? event.key === 'Escape' : !wrap.current?.contains(event.target as Node)) setPicking(false);
    };
    document.addEventListener('mousedown', close);
    document.addEventListener('keydown', close);
    return () => { document.removeEventListener('mousedown', close); document.removeEventListener('keydown', close); };
  }, [picking]);

  const pick = (emoji: string) => { setPicking(false); onReact(emoji); };

  return (
    <div className="feed-actions" ref={wrap}>
      {total > 0 ? (
        <span className="feed-summary" aria-label={plural(total, 'reaction')}>
          <span className="feed-summary-emoji" aria-hidden="true">{top.map((r) => r.emoji).join('')}</span>
          <span>{total}</span>
        </span>
      ) : null}
      <span className="grow" />
      <button type="button" className={`feed-act ${mine ? 'on' : ''}`} aria-expanded={picking}
        aria-label={mine ? `Your reaction: ${mineName}. Change it` : 'React'} onClick={() => setPicking((v) => !v)}>
        <span aria-hidden="true">{mine || '👍'}</span> {mine ? mineName : 'React'}
      </button>
      <button type="button" className="feed-act" onClick={onComments} aria-label={comments ? plural(comments, 'comment') : 'Comment'}>
        <span aria-hidden="true">💬</span> {comments > 0 ? comments : 'Comment'}
      </button>
      {picking ? (
        <div className="feed-picker card" role="menu" aria-label="Pick a reaction">
          {REACTIONS.map((r) => (
            <button key={r.emoji} type="button" role="menuitem" className={r.emoji === mine ? 'on' : ''}
              title={r.emoji === mine ? `Take off ${r.name}` : r.name} aria-label={r.emoji === mine ? `Take off ${r.name}` : r.name}
              onClick={() => pick(r.emoji)}>{r.emoji}</button>
          ))}
        </div>
      ) : null}
    </div>
  );
}
