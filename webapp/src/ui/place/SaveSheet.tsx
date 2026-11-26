// "Save to a circle": pick one of my circles (the one used last comes
// preselected) and save the venue there.
import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { ApiError, messageOf } from '../../api/client';
import { savePlace, type NewSave } from '../../api/places';
import { LAST_CIRCLE_KEY, startingCircle } from '../../logic/placeSave';
import type { Venue } from '../../logic/placeView';
import { Sheet, toast } from '../kit';
import { CirclePicker, useSaveTargets } from './CirclePicker';
import { readLastCircle, usePlaceRefresh, writeLastCircle } from './hooks';

// `otherCircle`: it's in a different circle of mine, so a second copy here can make sense
interface Duplicate { message: string; existingPlaceId: string | null; otherCircle: boolean }

export function SaveSheet({ venue, onClose }: { venue: Venue; onClose: () => void }) {
  const navigate = useNavigate();
  const refresh = usePlaceRefresh();
  const { targets } = useSaveTargets();
  const [circleId, setCircleId] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [duplicate, setDuplicate] = useState<Duplicate | null>(null);

  // Preselect once the circles are in: the last one used, else my first
  useEffect(() => {
    if (circleId === null && targets.length > 0) setCircleId(startingCircle(targets, readLastCircle(LAST_CIRCLE_KEY)));
  }, [targets, circleId]);

  const save = async (force = false) => {
    if (!circleId) { setError('Pick a circle to save it to.'); return; }
    // The server refuses a save without coordinates, even for a known venue
    if (!venue.location) { setError("This place has no spot on the map yet, so it can't be saved from here. Try Add Place."); return; }
    setBusy(true);
    setError('');
    const body: NewSave = {
      circleId,
      globalPlaceId: venue.globalPlaceId,
      googlePlaceId: venue.googlePlaceId,
      name: venue.name,
      address: venue.address,
      category: venue.category,
      location: venue.location,
      ...(force ? { force: true } : {})
    };
    try {
      await savePlace(body);
      writeLastCircle(LAST_CIRCLE_KEY, circleId);
      await refresh([circleId]);
      const name = targets.find((circle) => circle._id === circleId)?.name;
      toast(name ? `Saved to ${name}` : 'Saved');
      onClose();
    } catch (e) {
      if (e instanceof ApiError && e.code === 'DUPLICATE_PLACE') {
        setDuplicate({
          message: e.message || 'You already saved this place.',
          existingPlaceId: typeof e.body.existingPlaceId === 'string' ? e.body.existingPlaceId : null,
          otherCircle: typeof e.body.existingCircleId === 'string' && e.body.existingCircleId !== circleId
        });
      } else {
        setError(messageOf(e));
      }
    } finally {
      setBusy(false);
    }
  };

  return (
    <Sheet title={`Save ${venue.name}`} onClose={onClose}>
      {duplicate ? (
        <div className="card pl-dup" role="alert">
          <p><strong>{duplicate.message}</strong></p>
          <p className="small muted">{duplicate.otherCircle ? 'Open the one you have, or keep a copy in this circle too.' : 'It is already in this circle.'}</p>
          <div className="pl-dup-actions">
            {duplicate.existingPlaceId ? (
              <button className="btn small soft" onClick={() => { onClose(); navigate(`/place/${duplicate.existingPlaceId}`); }}>Open it</button>
            ) : null}
            {duplicate.otherCircle ? <button className="btn small" disabled={busy} onClick={() => save(true)}>Save it here too</button> : null}
          </div>
        </div>
      ) : null}
      <p className="section-title" style={{ marginTop: 4 }}>Which circle</p>
      <CirclePicker value={circleId} onChange={(id) => { setCircleId(id); setDuplicate(null); }} />
      <p className="err" role="alert">{error}</p>
      <button className="btn block" style={{ marginTop: 14 }} disabled={busy || !circleId} onClick={() => save(false)}>
        {busy ? 'Saving…' : 'Save'}
      </button>
      <button className="btn block plain" onClick={onClose}>Cancel</button>
    </Sheet>
  );
}
