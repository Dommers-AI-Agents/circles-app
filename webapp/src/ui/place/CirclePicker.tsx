// My circles as a list to pick one from, in my own order (never sorted).
import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { myCircles } from '../../api/circles';
import { messageOf } from '../../api/client';
import type { Circle } from '../../api/types';
import { useAuth } from '../../auth/AuthContext';
import { plural, privacyMark, privacyName } from '../../logic/labels';
import { saveTargets } from '../../logic/placeSave';
import { CircleEditSheet } from '../CircleEditSheet';
import { LoadError, Spinner } from '../kit';

export function useSaveTargets() {
  const { userId } = useAuth();
  const circles = useQuery({ queryKey: ['circles', 'mine'], queryFn: myCircles });
  return { query: circles, targets: circles.data ? saveTargets(circles.data, userId) : [] };
}

export function CirclePicker({ value, onChange, exclude, onCreated }: {
  value: string | null;
  onChange: (id: string) => void;
  /** The circle it's in now, when moving */
  exclude?: string | null;
  onCreated?: (circle: Circle) => void;
}) {
  const { query, targets } = useSaveTargets();
  const [creating, setCreating] = useState(false);
  const shown = targets.filter((circle) => circle._id !== exclude);
  if (query.isPending) return <Spinner />;
  if (query.isError) return <LoadError message={messageOf(query.error)} retry={() => query.refetch()} />;
  return (
    <>
      {shown.length === 0 ? (
        <p className="muted pl-note">{exclude ? 'You have no other circle to move it to yet.' : 'You have no circles yet.'} Make one and it opens here.</p>
      ) : (
        <div className="card pl-pick" role="radiogroup" aria-label="Circles">
          {shown.map((circle) => (
            <label className="radio" key={circle._id}>
              <input type="radio" name="circle" checked={value === circle._id} onChange={() => onChange(circle._id)} />
              <span className="grow">
                <strong className="clip" style={{ display: 'block' }}>{circle.name}</strong>
                <span className="small muted">
                  {privacyMark(circle.privacy)} {privacyName(circle.privacy)} · {plural(circle.placesCount ?? (circle.places || []).length, 'place')}
                </span>
              </span>
            </label>
          ))}
        </div>
      )}
      <button type="button" className="btn small soft pl-new" onClick={() => setCreating(true)}>＋ New circle</button>
      {creating ? (
        <CircleEditSheet onClose={() => setCreating(false)} onSaved={(circle) => { onChange(circle._id); onCreated?.(circle); }} />
      ) : null}
    </>
  );
}
