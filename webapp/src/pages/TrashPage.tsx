// The trash: circles and places taken off the map, kept until the person
// either puts them back or removes them for good. Nothing leaves on its own.
import { useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { deleteCircleForever, deletePlaceForever, restoreCircle, restorePlace, trash } from '../api/trash';
import { messageOf } from '../api/client';
import { categoryOf, plural, timeAgo } from '../logic/labels';
import { ConfirmSheet, Empty, Head, LoadError, Spinner, Thumb, toast } from '../ui/kit';

type Target = { kind: 'circle' | 'place'; id: string; name: string };

export function TrashPage() {
  const queryClient = useQueryClient();
  const [forever, setForever] = useState<Target | null>(null);
  const [busy, setBusy] = useState<string | null>(null);
  const query = useQuery({ queryKey: ['trash'], queryFn: trash });

  const after = async (text: string) => {
    await Promise.all([
      queryClient.invalidateQueries({ queryKey: ['trash'] }),
      queryClient.invalidateQueries({ queryKey: ['circles'] }),
      queryClient.invalidateQueries({ queryKey: ['circle'] }),
      queryClient.invalidateQueries({ queryKey: ['map'] })
    ]);
    toast(text);
  };
  const restore = async (target: Target) => {
    setBusy(target.id);
    try {
      await (target.kind === 'circle' ? restoreCircle(target.id) : restorePlace(target.id));
      await after(`${target.name} is back`);
    } catch (e) {
      toast(messageOf(e));
    } finally {
      setBusy(null);
    }
  };
  const remove = async () => {
    if (!forever) return;
    const target = forever;
    setForever(null);
    setBusy(target.id);
    try {
      await (target.kind === 'circle' ? deleteCircleForever(target.id) : deletePlaceForever(target.id));
      await after(`${target.name} was removed for good`);
    } catch (e) {
      toast(messageOf(e));
    } finally {
      setBusy(null);
    }
  };

  const data = query.data;
  const nothing = !!data && data.circles.length === 0 && data.places.length === 0;
  const row = (target: Target, detail: string, mark: string, photo?: string | null) => (
    <li key={`${target.kind}-${target.id}`}>
      <div className="item">
        <Thumb src={photo} mark={mark} />
        <span className="grow">
          <span className="clip" style={{ display: 'block', fontWeight: 600 }}>{target.name}</span>
          <span className="small muted clip" style={{ display: 'block' }}>{detail}</span>
        </span>
        <button className="btn small soft" disabled={busy === target.id} onClick={() => restore(target)}>Put back</button>
        <button className="btn small danger" disabled={busy === target.id} onClick={() => setForever(target)} aria-label={`Remove ${target.name} for good`}>Remove</button>
      </div>
    </li>
  );

  return (
    <>
      <Head title="Trash" back="/me" />
      <main className="page">
        {query.isPending ? <Spinner /> : null}
        {query.isError ? <LoadError message={messageOf(query.error)} retry={() => query.refetch()} /> : null}
        {nothing ? <Empty mark="🗑️" title="The trash is empty">Circles you delete and places you unsave wait here until you put them back.</Empty> : null}
        {data && data.circles.length > 0 ? (
          <>
            <p className="section-title">Circles</p>
            <ul className="list card" style={{ overflow: 'hidden' }}>
              {data.circles.map((circle) => row(
                { kind: 'circle', id: circle._id, name: circle.name },
                `${plural(circle.placesCount ?? (circle.places ? circle.places.length : 0), 'place')}${circle.deletedAt ? ` · deleted ${timeAgo(circle.deletedAt).toLowerCase()}` : ''}`,
                '⭕', circle.coverImage
              ))}
            </ul>
          </>
        ) : null}
        {data && data.places.length > 0 ? (
          <>
            <p className="section-title">Places</p>
            <ul className="list card" style={{ overflow: 'hidden' }}>
              {data.places.map((place) => row(
                { kind: 'place', id: place._id, name: place.name },
                `${categoryOf(place.category).name}${place.deletedAt ? ` · unsaved ${timeAgo(place.deletedAt).toLowerCase()}` : ''}`,
                categoryOf(place.category).mark, place.photos && place.photos[0]
              ))}
            </ul>
          </>
        ) : null}
      </main>
      {forever ? (
        <ConfirmSheet title={`Remove “${forever.name}” for good?`} danger action="Remove for good"
          body={forever.kind === 'circle' ? 'The circle and the places saved in it are removed from your account. This can\'t be undone.' : 'Your save of this place is removed. The place itself stays for everyone else. This can\'t be undone.'}
          onConfirm={remove} onClose={() => setForever(null)} />
      ) : null}
    </>
  );
}
