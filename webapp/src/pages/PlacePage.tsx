// One place, whichever id the link carries (my save, someone else's save,
// or the venue): the venue, my save of it, what people say, and the store.
import { useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import { ApiError, messageOf } from '../api/client';
import { loadPlaceView } from '../api/places';
import { useAuth } from '../auth/AuthContext';
import { categoryOf } from '../logic/labels';
import { priceText, ratingText, type PlaceView } from '../logic/placeView';
import { Avatar, Empty, Head, LoadError, Spinner } from '../ui/kit';
import { Comments } from '../ui/place/Comments';
import { placeKey } from '../ui/place/hooks';
import { MySaveCard } from '../ui/place/MySaveCard';
import { SaveSheet } from '../ui/place/SaveSheet';
import { SocialCard } from '../ui/place/SocialCard';
import { FollowCard, RewardsCard } from '../ui/place/StoreCard';
import { ActionBar, HoursCard, PhotoStrip } from '../ui/place/VenueParts';
import '../ui/circles.css';
import './place.css';

function Failed({ error, retry }: { error: unknown; retry: () => void }) {
  if (error instanceof ApiError && error.status === 403) {
    return (
      <Empty mark="🔒" title="This place is private" action={<Link className="btn soft" to="/">Back to my map</Link>}>
        Whoever saved it keeps it to themselves or a smaller group. If they want you to see it, they can change who sees it.
      </Empty>
    );
  }
  if (error instanceof ApiError && error.status === 404) {
    return (
      <Empty mark="📍" title="This place isn't here anymore" action={<Link className="btn soft" to="/">Back to my map</Link>}>
        It may have been unsaved, or the link is missing a part. Ask whoever sent it for a fresh link.
      </Empty>
    );
  }
  return <LoadError message={messageOf(error)} retry={retry} />;
}

function Header({ view }: { view: PlaceView }) {
  const { venue } = view;
  const category = categoryOf(venue.category);
  const rating = ratingText(venue.rating, venue.ratingCount);
  const price = priceText(venue.priceLevel);
  return (
    <div className="pl-head">
      <h2>{venue.name}</h2>
      <p className="pl-meta">
        <span>{category.mark} {category.name}</span>
        {rating ? <span><span className="pl-star" aria-hidden="true">★</span> {rating}</span> : null}
        {price ? <span aria-label={`Price level ${venue.priceLevel}`}>{price}</span> : null}
      </p>
      {venue.address ? <p className="muted pl-address">{venue.address}</p> : null}
      {view.pending && view.mine ? <span className="chip gray pl-pending">Waiting for review · only you see it</span> : null}
      {venue.description ? <p className="pl-desc">{venue.description}</p> : null}
    </div>
  );
}

export function PlacePage() {
  const { placeId = '' } = useParams();
  const { userId } = useAuth();
  const [saving, setSaving] = useState(false);
  const place = useQuery({ queryKey: placeKey(placeId), queryFn: () => loadPlaceView(placeId, userId) });
  const view = place.data;

  return (
    <>
      <Head title={view ? view.venue.name : 'Place'} back />
      <main className="page pl-page">
        {place.isPending ? <Spinner /> : null}
        {place.isError && !view ? <Failed error={place.error} retry={() => place.refetch()} /> : null}
        {view ? (
          <>
            <PhotoStrip venue={view.venue} />
            <Header view={view} />
            <ActionBar venue={view.venue} shareId={view.shareId} />

            {view.savedBy ? (
              <Link className="card pl-card pl-by" to={`/user/${encodeURIComponent(view.savedBy.id)}`}>
                <Avatar name={view.savedBy.name} src={view.savedBy.photo} size={40} seed={view.savedBy.id} />
                <span className="grow"><span className="small muted">Saved by</span><br /><strong>{view.savedBy.name}</strong></span>
                <span className="muted" aria-hidden="true">›</span>
              </Link>
            ) : null}

            {view.mine ? <MySaveCard view={view} /> : (
              <section className="card pl-card pl-save">
                <div className="grow">
                  <h3>Not in your circles yet</h3>
                  <p className="small muted">Save it to keep your own notes and rating, and to find it on your map.</p>
                </div>
                <button className="btn" onClick={() => setSaving(true)}>Save to a circle</button>
              </section>
            )}

            <HoursCard venue={view.venue} />
            <RewardsCard view={view} />
            <FollowCard view={view} />
            <SocialCard view={view} />
            <Comments view={view} />
          </>
        ) : null}
      </main>
      {saving && view ? <SaveSheet venue={view.venue} onClose={() => setSaving(false)} /> : null}
    </>
  );
}
