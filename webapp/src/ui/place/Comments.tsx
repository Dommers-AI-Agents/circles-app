// What people say about the place: newest first, a like on each, replies one
// level deep. Comments live on the venue; the routes take a save id.
import { useState, type FormEvent } from 'react';
import { Link } from 'react-router-dom';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { messageOf } from '../../api/client';
import {
  addComment, addReply, commentReplies, deleteComment, likeComment, placeComments, type PlaceComment
} from '../../api/places';
import { useAuth } from '../../auth/AuthContext';
import { plural, timeAgo } from '../../logic/labels';
import { authorName, canDeleteComment, canReplyTo, likedBy, ownsSocial } from '../../logic/placeComments';
import type { PlaceView } from '../../logic/placeView';
import { Avatar, ConfirmSheet, LoadError, Spinner, toast } from '../kit';
import { usePatchView } from './hooks';

type Key = readonly unknown[];

function Composer({ placeholder, submitLabel, onSubmit, autoFocus }: {
  placeholder: string; submitLabel: string; onSubmit: (text: string) => Promise<void>; autoFocus?: boolean;
}) {
  const [text, setText] = useState('');
  const [busy, setBusy] = useState(false);
  const send = async (event: FormEvent) => {
    event.preventDefault();
    const value = text.trim();
    if (!value || busy) return;
    setBusy(true);
    try {
      await onSubmit(value);
      setText('');
    } catch (e) {
      toast(messageOf(e));
    } finally {
      setBusy(false);
    }
  };
  return (
    <form className="pl-compose" onSubmit={send}>
      <textarea className="input" rows={2} maxLength={2000} value={text} placeholder={placeholder} aria-label={placeholder}
        onChange={(e) => setText(e.target.value)} autoFocus={autoFocus} />
      <button className="btn small" type="submit" disabled={busy || !text.trim()}>{busy ? 'Posting…' : submitLabel}</button>
    </form>
  );
}

function CommentItem({ comment, socialId, mineSocial, listKey, onDeleted }: {
  comment: PlaceComment; socialId: string; mineSocial: boolean; listKey: Key; onDeleted: () => void;
}) {
  const { userId } = useAuth();
  const queryClient = useQueryClient();
  const [showReplies, setShowReplies] = useState(false);
  const [replying, setReplying] = useState(false);
  const [confirming, setConfirming] = useState(false);
  const [liking, setLiking] = useState(false);
  const topLevel = canReplyTo(comment);
  const repliesKey = ['place', 'replies', comment._id] as const;
  const replies = useQuery({ queryKey: repliesKey, queryFn: () => commentReplies(socialId, comment._id), enabled: topLevel && showReplies });
  const liked = likedBy(comment.likes, userId);
  const likes = comment.likesCount ?? (comment.likes || []).length;
  const replyCount = Math.max(comment.replyCount || 0, replies.data ? replies.data.length : 0);

  const setComment = (patch: Partial<PlaceComment>) =>
    queryClient.setQueryData<PlaceComment[]>(listKey, (list) => list && list.map((c) => (c._id === comment._id ? { ...c, ...patch } : c)));

  const like = async () => {
    if (!userId || liking) return;
    setLiking(true);
    try {
      const result = await likeComment(socialId, comment._id);
      const others = (comment.likes || []).filter((id) => id !== userId);
      setComment({ likes: result.liked ? [...others, userId] : others, likesCount: result.likesCount });
    } catch (e) {
      toast(messageOf(e));
    } finally {
      setLiking(false);
    }
  };

  const remove = async () => {
    setConfirming(false);
    try {
      await deleteComment(socialId, comment._id);
      queryClient.setQueryData<PlaceComment[]>(listKey, (list) => list && list.filter((c) => c._id !== comment._id));
      onDeleted();
      toast(topLevel ? 'Comment deleted' : 'Reply deleted');
    } catch (e) {
      toast(messageOf(e));
    }
  };

  const reply = async (text: string) => {
    const added = await addReply(socialId, comment._id, text);
    queryClient.setQueryData<PlaceComment[]>(repliesKey, (list) => [...(list || []), added]);
    setComment({ replyCount: (comment.replyCount || 0) + 1 });
    setShowReplies(true);
    setReplying(false);
  };

  const name = authorName(comment);
  return (
    <li className={`pl-comment${topLevel ? '' : ' reply'}`}>
      <Link to={`/user/${encodeURIComponent(comment.userId)}`} aria-label={name}>
        <Avatar name={name} src={comment.user?.profilePicture} size={topLevel ? 36 : 28} seed={comment.userId} />
      </Link>
      <div className="grow">
        <p className="pl-comment-head">
          <Link to={`/user/${encodeURIComponent(comment.userId)}`} className="pl-author">{name}</Link>
          {comment.isVenueOwner ? <span className="chip gold">Store</span> : null}
          <span className="small muted">{timeAgo(comment.createdAt)}{comment.editedAt ? ' · edited' : ''}</span>
        </p>
        <p className="pl-comment-text">{comment.text}</p>
        <div className="pl-comment-actions">
          <button onClick={like} disabled={liking} aria-pressed={liked} className={liked ? 'on' : undefined}>
            {liked ? '♥' : '♡'}{likes > 0 ? ` ${likes}` : ''}<span className="pl-sr"> {liked ? 'Unlike' : 'Like'}</span>
          </button>
          {topLevel ? <button onClick={() => setReplying(!replying)}>Reply</button> : null}
          {canDeleteComment(comment, userId, socialId, mineSocial) ? <button className="del" onClick={() => setConfirming(true)}>Delete</button> : null}
        </div>
        {topLevel && replyCount > 0 ? (
          <button className="pl-more" onClick={() => setShowReplies(!showReplies)}>
            {showReplies ? 'Hide replies' : `View ${plural(replyCount, 'reply', 'replies')}`}
          </button>
        ) : null}
        {topLevel && showReplies ? (
          <>
            {replies.isPending ? <Spinner /> : null}
            {replies.isError ? <LoadError message={messageOf(replies.error)} retry={() => replies.refetch()} /> : null}
            {replies.data && replies.data.length > 0 ? (
              <ul className="list pl-replies">
                {replies.data.map((r) => (
                  <CommentItem key={r._id} comment={r} socialId={socialId} mineSocial={mineSocial} listKey={repliesKey}
                    onDeleted={() => setComment({ replyCount: Math.max(0, (comment.replyCount || 1) - 1) })} />
                ))}
              </ul>
            ) : null}
          </>
        ) : null}
        {replying ? <Composer placeholder={`Reply to ${name}`} submitLabel="Reply" onSubmit={reply} autoFocus /> : null}
      </div>
      {confirming ? (
        <ConfirmSheet title={topLevel ? 'Delete this comment?' : 'Delete this reply?'} danger action="Delete"
          body={topLevel && replyCount > 0 ? 'It comes off the place for everyone. Its replies go with it.' : 'It comes off the place for everyone.'}
          onConfirm={remove} onClose={() => setConfirming(false)} />
      ) : null}
    </li>
  );
}

export function Comments({ view }: { view: PlaceView }) {
  const socialId = view.socialId;
  const patch = usePatchView(view.routeId);
  const queryClient = useQueryClient();
  const listKey = ['place', view.routeId, 'comments', socialId] as const;
  const comments = useQuery({ queryKey: listKey, queryFn: () => placeComments(socialId!), enabled: !!socialId });
  const mineSocial = ownsSocial(view);

  const post = async (text: string) => {
    const added = await addComment(socialId!, text);
    queryClient.setQueryData<PlaceComment[]>(listKey, (list) => [added, ...(list || [])]);
    patch((v) => ({ ...v, commentsCount: v.commentsCount + 1 }));
  };

  return (
    <section className="card pl-card" aria-label="Comments">
      <h3>Comments{comments.data && comments.data.length > 0 ? ` · ${comments.data.length}` : ''}</h3>
      {!socialId ? (
        <p className="small muted pl-note">
          {view.commentsCount > 0 ? `${plural(view.commentsCount, 'comment')} so far. ` : ''}Save it to one of your circles to read and add comments.
        </p>
      ) : (
        <>
          <Composer placeholder="Say something about this place" submitLabel="Post" onSubmit={post} />
          {comments.isPending ? <Spinner /> : null}
          {comments.isError ? <LoadError message={messageOf(comments.error)} retry={() => comments.refetch()} /> : null}
          {comments.data && comments.data.length === 0 ? <p className="small muted pl-note">No comments yet. Be the first to say what's good here.</p> : null}
          {comments.data && comments.data.length > 0 ? (
            <ul className="list pl-comments">
              {comments.data.map((c) => (
                <CommentItem key={c._id} comment={c} socialId={socialId} mineSocial={mineSocial} listKey={listKey}
                  onDeleted={() => patch((v) => ({ ...v, commentsCount: Math.max(0, v.commentsCount - 1) }))} />
              ))}
            </ul>
          ) : null}
        </>
      )}
    </section>
  );
}
