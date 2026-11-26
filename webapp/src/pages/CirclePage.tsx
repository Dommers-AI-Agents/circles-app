// One circle: its cover, who can see it, and its places in the circle's own order.
import { useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { circle as loadCircle, circlePlaces, deleteCircle } from '../api/circles';
import { messageOf } from '../api/client';
import { useAuth } from '../auth/AuthContext';
import { plural, privacyMark, privacyName } from '../logic/labels';
import { ConfirmSheet, Empty, Head, LoadError, Spinner, toast } from '../ui/kit';
import { CircleEditSheet } from '../ui/CircleEditSheet';
import { PlaceRow } from '../ui/PlaceRow';
import '../ui/circles.css';

export function CirclePage() {
  const { circleId = '' } = useParams();
  const { userId } = useAuth();
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const [editing, setEditing] = useState(false);
  const [removing, setRemoving] = useState(false);
  const circle = useQuery({ queryKey: ['circle', circleId], queryFn: () => loadCircle(circleId) });
  const places = useQuery({ queryKey: ['circle', circleId, 'places'], queryFn: () => circlePlaces(circleId) });
  const data = circle.data;
  const mine = !!data && data.owner === userId;
  // The app's own circles (check-ins, places I follow) aren't edited or deleted here
  const editable = mine && !data.isSystemCircle && !data.isCheckInCircle && !data.isFollowedPlacesCircle;

  const remove = async () => {
    try {
      await deleteCircle(circleId);
      await queryClient.invalidateQueries({ queryKey: ['circles'] });
      toast('Circle moved to the trash');
      navigate('/', { replace: true });
    } catch (e) {
      setRemoving(false);
      toast(messageOf(e));
    }
  };

  return (
    <>
      <Head title={data ? data.name : 'Circle'} back>
        {editable ? <button className="icon-btn" onClick={() => setEditing(true)}>Edit</button> : null}
      </Head>
      <main className="page">
        {circle.isPending ? <Spinner /> : null}
        {circle.isError ? <LoadError message={messageOf(circle.error)} retry={() => circle.refetch()} /> : null}
        {data ? (
          <>
            <div className="circle-hero" style={data.coverImage ? { backgroundImage: `url("${data.coverImage.replace(/"/g, '%22')}")` } : undefined}>
              <div>
                <h2>{data.name}</h2>
                <p>
                  {privacyMark(data.privacy)} {privacyName(data.privacy)}
                  {!mine && data.ownerDetails ? ` · by ${data.ownerDetails.displayName}` : ''}
                  {places.data ? ` · ${plural(places.data.length, 'place')}` : ''}
                </p>
              </div>
            </div>
            {data.description ? <p style={{ margin: '14px 2px 0' }}>{data.description}</p> : null}

            {places.isPending ? <Spinner /> : null}
            {places.isError ? <LoadError message={messageOf(places.error)} retry={() => places.refetch()} /> : null}
            {places.data && places.data.length === 0 ? (
              <Empty mark="📍" title="No places here yet">
                {mine ? 'Places you save to this circle show up here.' : 'Nothing has been saved to this circle yet.'}
              </Empty>
            ) : null}
            {places.data && places.data.length > 0 ? (
              <ul className="list card" style={{ marginTop: 16, overflow: 'hidden' }}>
                {places.data.map((place) => <li key={place._id}><PlaceRow place={place} /></li>)}
              </ul>
            ) : null}
            {editable ? (
              <button className="btn block danger" style={{ marginTop: 22 }} onClick={() => setRemoving(true)}>Delete this circle</button>
            ) : null}
          </>
        ) : null}
      </main>
      {editing && data ? <CircleEditSheet circle={data} onClose={() => setEditing(false)} /> : null}
      {removing && data ? (
        <ConfirmSheet title={`Delete “${data.name}”?`} danger action="Move to the trash"
          body="The circle and its places go to the trash. You can restore them from the iPhone app."
          onConfirm={remove} onClose={() => setRemoving(false)} />
      ) : null}
    </>
  );
}
