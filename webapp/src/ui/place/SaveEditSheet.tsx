// Edit my save: private notes, my 0–10 rating, who sees it, tags. Sends only
// what changed, so a privacy I didn't touch is never written back.
import { useState, type FormEvent } from 'react';
import { messageOf } from '../../api/client';
import { updateSave } from '../../api/places';
import type { PlacePrivacy } from '../../api/types';
import { PRIVACY } from '../../logic/labels';
import { formOf, ratingWord, saveChanges, tagsOf } from '../../logic/placeSave';
import type { MySave } from '../../logic/placeView';
import { Sheet, toast } from '../kit';
import { usePlaceRefresh } from './hooks';

const TIERS: { id: PlacePrivacy; name: string; detail: string; mark: string }[] = [
  { id: 'followCircle', name: 'Same as its circle', detail: 'Whoever can see the circle sees it', mark: '🔗' },
  ...PRIVACY
];

export function SaveEditSheet({ save, onClose }: { save: MySave; onClose: () => void }) {
  const refresh = usePlaceRefresh();
  const start = formOf(save);
  const [notes, setNotes] = useState(start.privateNotes);
  const [rating, setRating] = useState<number | null>(start.userRating);
  const [privacy, setPrivacy] = useState<PlacePrivacy>(start.privacy);
  const [tags, setTags] = useState(start.tags.join(', '));
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    const changes = saveChanges(save, { privateNotes: notes, userRating: rating, privacy, tags: tagsOf(tags) });
    if (Object.keys(changes).length === 0) { onClose(); return; }
    setBusy(true);
    setError('');
    try {
      await updateSave(save.id, changes);
      await refresh([save.circleId]);
      toast('Saved your changes');
      onClose();
    } catch (e) {
      setError(messageOf(e));
    } finally {
      setBusy(false);
    }
  };

  return (
    <Sheet title="Edit my save" onClose={onClose}>
      <form onSubmit={submit} noValidate>
        <label className="field"><span>Private notes · only you see these</span>
          <textarea maxLength={2000} value={notes} onChange={(e) => setNotes(e.target.value)} placeholder="What to order, who to ask for, when to go…" />
        </label>

        <div className="field">
          <span>My rating · {rating === null ? 'Not rated' : `${rating} · ${ratingWord(rating)}`}</span>
          <div className="pl-rate" role="radiogroup" aria-label="My rating, 0 to 10">
            {Array.from({ length: 11 }, (_, n) => (
              <button type="button" key={n} role="radio" aria-checked={rating === n}
                className={rating === n ? 'on' : undefined} onClick={() => setRating(n)}>{n}</button>
            ))}
          </div>
          {rating !== null ? <button type="button" className="btn small plain" onClick={() => setRating(null)}>Clear my rating</button> : null}
        </div>

        <p className="section-title" style={{ marginTop: 6 }}>Who can see it</p>
        <div className="card" style={{ padding: '0 12px' }} role="radiogroup" aria-label="Who can see it">
          {TIERS.map((tier, index) => (
            <label className="radio" key={tier.id} style={index === 0 ? { borderTop: 0 } : undefined}>
              <input type="radio" name="privacy" checked={privacy === tier.id} onChange={() => setPrivacy(tier.id)} />
              <span><strong>{tier.mark} {tier.name}</strong><br /><span className="small muted">{tier.detail}</span></span>
            </label>
          ))}
        </div>

        <label className="field" style={{ marginTop: 14 }}><span>Tags, separated by commas</span>
          <input type="text" value={tags} onChange={(e) => setTags(e.target.value)} placeholder="patio, date night" />
        </label>

        <p className="err" role="alert">{error}</p>
        <button className="btn block" type="submit" disabled={busy} style={{ marginTop: 8 }}>{busy ? 'Saving…' : 'Save'}</button>
        <button className="btn block plain" type="button" onClick={onClose}>Cancel</button>
      </form>
    </Sheet>
  );
}
