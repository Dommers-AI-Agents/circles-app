// Make a circle, or change one. An edit sends only the fields the person
// changed, so a privacy tier they didn't touch is never written back.
import { useState, type FormEvent } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { createCircle, updateCircle, type CircleInput } from '../api/circles';
import { ApiError, messageOf } from '../api/client';
import type { Circle, Privacy } from '../api/types';
import { PRIVACY } from '../logic/labels';
import { Sheet, toast } from './kit';

export function circleChanges(before: Circle, after: CircleInput): Partial<CircleInput> {
  const changes: Partial<CircleInput> = {};
  if (after.name !== before.name) changes.name = after.name;
  if ((after.description || '') !== (before.description || '')) changes.description = after.description || '';
  if (after.privacy !== before.privacy) changes.privacy = after.privacy;
  if ((after.showOnMap !== false) !== (before.showOnMap !== false)) changes.showOnMap = after.showOnMap !== false;
  return changes;
}

export function CircleEditSheet({ circle, onClose, onSaved }: { circle?: Circle; onClose: () => void; onSaved?: (circle: Circle) => void }) {
  const queryClient = useQueryClient();
  const [name, setName] = useState(circle ? circle.name : '');
  const [description, setDescription] = useState(circle?.description || '');
  const [privacy, setPrivacy] = useState<Privacy>(circle ? circle.privacy : 'public');
  const [showOnMap, setShowOnMap] = useState(circle ? circle.showOnMap !== false : true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  const save = async (event: FormEvent) => {
    event.preventDefault();
    const input: CircleInput = { name: name.replace(/\s+/g, ' ').trim(), description: description.trim(), privacy, showOnMap };
    if (input.name.length < 1) { setError('Give the circle a name.'); return; }
    setBusy(true);
    setError('');
    try {
      let saved: Circle;
      if (circle) {
        const changes = circleChanges(circle, input);
        if (Object.keys(changes).length === 0) { onClose(); return; }
        saved = await updateCircle(circle._id, changes);
      } else {
        saved = await createCircle(input);
      }
      await queryClient.invalidateQueries({ queryKey: ['circles'] });
      await queryClient.invalidateQueries({ queryKey: ['circle', saved._id] });
      toast(circle ? 'Circle updated' : 'Circle created');
      onSaved?.(saved);
      onClose();
    } catch (e) {
      setError(e instanceof ApiError && e.body.upgradeRequired
        ? `You've reached the number of circles your plan allows (${String(e.body.maxAllowed ?? '')}).`
        : messageOf(e));
    } finally {
      setBusy(false);
    }
  };

  return (
    <Sheet title={circle ? 'Edit circle' : 'New circle'} onClose={onClose}>
      <form onSubmit={save} noValidate>
        <label className="field"><span>Name</span>
          <input type="text" maxLength={50} value={name} onChange={(e) => setName(e.target.value)} placeholder="Date night, Coffee, Charlotte with kids…" autoFocus={!circle} />
        </label>
        <label className="field"><span>What it's for (optional)</span>
          <textarea maxLength={500} value={description} onChange={(e) => setDescription(e.target.value)} />
        </label>
        <p className="section-title" style={{ marginTop: 6 }}>Who can see it</p>
        <div className="card" style={{ padding: '0 12px' }}>
          {PRIVACY.map((tier, index) => (
            <label className="radio" key={tier.id} style={index === 0 ? { borderTop: 0 } : undefined}>
              <input type="radio" name="privacy" checked={privacy === tier.id} onChange={() => setPrivacy(tier.id)} />
              <span><strong>{tier.mark} {tier.name}</strong><br /><span className="small muted">{tier.detail}</span></span>
            </label>
          ))}
        </div>
        <label className="radio" style={{ borderTop: 0, marginTop: 6 }}>
          <input type="checkbox" checked={showOnMap} onChange={(e) => setShowOnMap(e.target.checked)} />
          <span><strong>Show its places on my map</strong></span>
        </label>
        <p className="err" role="alert">{error}</p>
        <button className="btn block" type="submit" disabled={busy} style={{ marginTop: 12 }}>{busy ? 'Saving…' : circle ? 'Save' : 'Create circle'}</button>
        <button className="btn block plain" type="button" onClick={onClose}>Cancel</button>
      </form>
    </Sheet>
  );
}
