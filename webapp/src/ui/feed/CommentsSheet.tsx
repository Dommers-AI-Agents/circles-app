// The comments on one Activity row, newest first: read, add, delete my own.
// The card's count follows each add and delete.
import { useState, type FormEvent } from 'react';
import { Link } from 'react-router-dom';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { activityComments, addActivityComment, deleteActivityComment, type Activity, type FeedPage } from '../../api/feed';
import { messageOf } from '../../api/client';
import { useAuth } from '../../auth/AuthContext';
import { bumpComments, patchActivity, type PagedRows } from '../../logic/feedCache';
import { timeAgo } from '../../logic/labels';
import { Avatar, Empty, LoadError, Sheet, Spinner, toast } from '../kit';
import { FEED_KEY } from './useActivityActions';

export const commentsKey = (activityId: string) => ['feed', 'comments', activityId] as const;

export function CommentsSheet({ activity, onClose }: { activity: Activity; onClose: () => void }) {
  const { userId } = useAuth();
  const queryClient = useQueryClient();
  const key = commentsKey(activity._id);
  const comments = useQuery({ queryKey: key, queryFn: () => activityComments(activity._id) });
  const [draft, setDraft] = useState('');
  const [sending, setSending] = useState(false);
  const [confirming, setConfirming] = useState<string | null>(null);

  const bump = (by: number) =>
    queryClient.setQueryData<PagedRows<FeedPage>>(FEED_KEY, (data) => patchActivity(data, activity._id, (row) => bumpComments(row, by)));

  const send = async (event: FormEvent) => {
    event.preventDefault();
    const text = draft.trim();
    if (!text || sending) return;
    setSending(true);
    try {
      await addActivityComment(activity._id, text);
      setDraft('');
      bump(1);
      await queryClient.invalidateQueries({ queryKey: key });
    } catch (error) {
      toast(`Your comment didn't post. ${messageOf(error)}`);
    } finally {
      setSending(false);
    }
  };

  const remove = async (commentId: string) => {
    setConfirming(null);
    try {
      await deleteActivityComment(activity._id, commentId);
      queryClient.setQueryData(key, (list: typeof comments.data) => (list || []).filter((c) => c._id !== commentId));
      bump(-1);
      toast('Comment deleted');
    } catch (error) {
      toast(`That comment wasn't deleted. ${messageOf(error)}`);
    }
  };

  return (
    <Sheet title="Comments" onClose={onClose}>
      <form className="feed-compose" onSubmit={send}>
        <input className="input" value={draft} onChange={(e) => setDraft(e.target.value)} placeholder="Add a comment" maxLength={1000}
          aria-label="Add a comment" autoFocus />
        <button className="btn small" type="submit" disabled={!draft.trim() || sending}>{sending ? 'Posting…' : 'Post'}</button>
      </form>
      {comments.isPending ? <Spinner /> : null}
      {comments.isError ? <LoadError message={messageOf(comments.error)} retry={() => comments.refetch()} /> : null}
      {comments.data && comments.data.length === 0 ? (
        <Empty mark="💬" title="No comments yet">Say something nice. Your comment shows to everyone who can see this.</Empty>
      ) : null}
      {comments.data && comments.data.length > 0 ? (
        <ul className="list feed-comments">
          {comments.data.map((comment) => {
            const mine = comment.userId === userId;
            const name = comment.userName || 'Someone';
            return (
              <li key={comment._id} className="feed-comment">
                <Link to={`/user/${encodeURIComponent(comment.userId)}`} onClick={onClose} aria-label={name}>
                  <Avatar name={name} src={comment.userPhoto} size={34} seed={comment.userId} />
                </Link>
                <div className="grow">
                  <div className="small"><strong>{name}</strong> <span className="muted">{timeAgo(comment.createdAt)}</span></div>
                  <p className="feed-comment-text">{comment.text}</p>
                </div>
                {mine ? (
                  confirming === comment._id ? (
                    <button type="button" className="btn small danger" onClick={() => remove(comment._id)}>Delete?</button>
                  ) : (
                    <button type="button" className="icon-btn feed-comment-del" aria-label="Delete your comment" onClick={() => setConfirming(comment._id)}>✕</button>
                  )
                ) : null}
              </li>
            );
          })}
        </ul>
      ) : null}
    </Sheet>
  );
}
