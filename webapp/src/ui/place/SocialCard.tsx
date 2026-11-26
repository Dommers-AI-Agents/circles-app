// Likes and who saved it. Both go through a save id; a venue nobody I can
// see has saved yet shows the count and a line instead of a dead button.
import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { messageOf } from '../../api/client';
import { placeSavers, toggleLike } from '../../api/places';
import { useAuth } from '../../auth/AuthContext';
import { plural } from '../../logic/labels';
import { likedBy, toggledLikes } from '../../logic/placeComments';
import type { PlaceView } from '../../logic/placeView';
import { Avatar, Empty, LoadError, Sheet, Spinner, toast } from '../kit';
import { PersonRow } from '../people/PersonRow';
import { usePatchView } from './hooks';

export function SocialCard({ view }: { view: PlaceView }) {
  const { userId } = useAuth();
  const patch = usePatchView(view.routeId);
  const [busy, setBusy] = useState(false);
  const [showSavers, setShowSavers] = useState(false);
  const socialId = view.socialId;
  const savers = useQuery({
    queryKey: ['place', view.routeId, 'savers', socialId],
    queryFn: () => placeSavers(socialId!),
    enabled: !!socialId
  });
  const liked = likedBy(view.likes, userId);
  const likeCount = view.likes.length;

  const like = async () => {
    if (!socialId || !userId || busy) return;
    const before = view.likes;
    setBusy(true);
    patch((v) => ({ ...v, likes: toggledLikes(v.likes, userId) }));
    try {
      const result = await toggleLike(socialId);
      if (result.place && Array.isArray(result.place.likes)) {
        const likes = result.place.likes;
        patch((v) => ({ ...v, likes }));
      }
    } catch (e) {
      patch((v) => ({ ...v, likes: before }));
      toast(messageOf(e));
    } finally {
      setBusy(false);
    }
  };

  const list = savers.data ? savers.data.savers : [];
  const hidden = savers.data ? Math.max(0, (savers.data.totalCount ?? list.length) - list.length) : 0;

  return (
    <section className="card pl-card" aria-label="Likes and saves">
      <div className="row">
        {socialId ? (
          <button className={`btn small ${liked ? '' : 'soft'} pl-like`} onClick={like} disabled={busy} aria-pressed={liked}>
            <span aria-hidden="true">{liked ? '♥' : '♡'}</span>{liked ? 'Liked' : 'Like'}
          </button>
        ) : null}
        <span className="grow small muted">{likeCount > 0 ? plural(likeCount, 'like') : 'No likes yet'}</span>
      </div>
      {!socialId ? <p className="small muted pl-note">Save it to one of your circles to like it, comment and see who else saved it.</p> : null}
      {socialId ? (
        <button className="pl-savers" onClick={() => setShowSavers(true)} disabled={!savers.data || savers.data.savers.length === 0}>
          <span className="pl-stack" aria-hidden="true">
            {list.slice(0, 4).map((person) => (
              <Avatar key={person._id} name={person.displayName || '?'} src={person.profilePicture} size={30} seed={person._id} />
            ))}
          </span>
          <span className="grow small">
            {savers.isPending ? 'Finding who saved it…'
              : savers.isError ? "Couldn't load who saved it"
                : list.length === 0 ? (hidden > 0 ? `Saved by ${plural(hidden, 'person', 'people')} you can't see` : 'Nobody you can see has saved it yet')
                  : `Saved by ${plural(list.length, 'person', 'people')}${hidden > 0 ? ` · ${hidden} more you can't see` : ''}`}
          </span>
          {list.length > 0 ? <span className="small muted" aria-hidden="true">›</span> : null}
        </button>
      ) : null}
      {showSavers ? (
        <Sheet title="Who saved it" onClose={() => setShowSavers(false)}>
          {savers.isPending ? <Spinner /> : null}
          {savers.isError ? <LoadError message={messageOf(savers.error)} retry={() => savers.refetch()} /> : null}
          {savers.data && list.length === 0 ? <Empty mark="👥" title="Nobody to show">The people who saved it keep it to themselves.</Empty> : null}
          {list.length > 0 ? (
            <div className="card" style={{ overflow: 'hidden' }}>
              {list.map((person) => (
                <PersonRow key={person._id} person={{ _id: person._id, displayName: person.displayName || 'Someone', profilePicture: person.profilePicture }}
                  detail={person._id === userId ? 'You' : person.bio || undefined} />
              ))}
            </div>
          ) : null}
        </Sheet>
      ) : null}
    </section>
  );
}
