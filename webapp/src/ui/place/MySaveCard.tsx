// My save of this place: which circle, my notes and rating, who sees it, and
// Edit / Move / Unsave. Every write goes to MY save's id, never the page's
// (which can be someone else's save or the venue).
import { useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { useQueryClient } from '@tanstack/react-query';
import { messageOf } from '../../api/client';
import { moveSave, unsave } from '../../api/places';
import { privacyMark, privacyName } from '../../logic/labels';
import { routeAfterMove, routeAfterUnsave } from '../../logic/placeComments';
import { ratingWord } from '../../logic/placeSave';
import type { PlaceView } from '../../logic/placeView';
import { ConfirmSheet, Sheet, toast } from '../kit';
import { CirclePicker, useSaveTargets } from './CirclePicker';
import { placeKey, usePlaceRefresh } from './hooks';
import { SaveEditSheet } from './SaveEditSheet';

export function MySaveCard({ view }: { view: PlaceView }) {
  const save = view.mine!;
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const refresh = usePlaceRefresh();
  const { query, targets } = useSaveTargets();
  const [sheet, setSheet] = useState<'edit' | 'move' | 'unsave' | null>(null);
  const [moveTo, setMoveTo] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const circle = (query.data || []).find((c) => c._id === save.circleId);

  const move = async () => {
    if (!moveTo) return;
    setBusy(true);
    try {
      const result = await moveSave(save.id, moveTo);
      const name = targets.find((c) => c._id === moveTo)?.name || 'the other circle';
      const next = routeAfterMove(view, result.merged === true, result.place && result.place._id);
      toast(result.merged ? `It was already in ${name}, so the two are now one` : `Moved to ${name}`);
      setSheet(null);
      if (next) {
        queryClient.removeQueries({ queryKey: placeKey(view.routeId) });
        navigate(next, { replace: true });
      }
      await refresh([save.circleId, moveTo]);
    } catch (e) {
      toast(messageOf(e));
    } finally {
      setBusy(false);
    }
  };

  const remove = async () => {
    setBusy(true);
    try {
      await unsave(save.id);
      toast(circle ? `Unsaved from ${circle.name}` : 'Unsaved');
      setSheet(null);
      const next = routeAfterUnsave(view);
      if (next !== null) {
        // This page's own link was my save: it's gone, so don't reload it
        queryClient.removeQueries({ queryKey: placeKey(view.routeId) });
        if (next) navigate(next, { replace: true });
        else navigate(-1);
      }
      await refresh([save.circleId]);
    } catch (e) {
      toast(messageOf(e));
    } finally {
      setBusy(false);
    }
  };

  return (
    <section className="card pl-card" aria-label="My save">
      <div className="row pl-card-head">
        <h3 className="grow">My save</h3>
        <button className="btn small soft" onClick={() => setSheet('edit')}>Edit</button>
      </div>
      <dl className="pl-facts">
        <div><dt>Circle</dt><dd>{circle ? <Link to={`/circle/${circle._id}`}>{circle.name}</Link> : query.isPending ? '…' : 'One of my circles'}</dd></div>
        <div><dt>Who sees it</dt><dd>{privacyMark(save.privacy)} {privacyName(save.privacy)}</dd></div>
        <div><dt>My rating</dt><dd>{save.userRating === null ? <span className="muted">Not rated yet</span> : <><b>{save.userRating}</b>/10 · {ratingWord(save.userRating)}</>}</dd></div>
        {save.tags.length > 0 ? <div><dt>Tags</dt><dd>{save.tags.map((tag) => <span className="chip gray pl-tag" key={tag}>{tag}</span>)}</dd></div> : null}
      </dl>
      <div className="pl-notes">
        <span className="small muted">Private notes · only you see these</span>
        {save.privateNotes ? <p>{save.privateNotes}</p> : <p className="muted">No notes yet. Tap Edit to jot down what to order or when to go.</p>}
      </div>
      <div className="pl-card-actions">
        <button className="btn small soft" onClick={() => { setMoveTo(null); setSheet('move'); }}>Move to another circle</button>
        <button className="btn small danger" onClick={() => setSheet('unsave')}>Unsave</button>
      </div>

      {sheet === 'edit' ? <SaveEditSheet save={save} onClose={() => setSheet(null)} /> : null}
      {sheet === 'move' ? (
        <Sheet title="Move to another circle" onClose={() => setSheet(null)}>
          <CirclePicker value={moveTo} onChange={setMoveTo} exclude={save.circleId} />
          <button className="btn block" style={{ marginTop: 14 }} disabled={busy || !moveTo} onClick={move}>{busy ? 'Moving…' : 'Move'}</button>
          <button className="btn block plain" onClick={() => setSheet(null)}>Cancel</button>
        </Sheet>
      ) : null}
      {sheet === 'unsave' ? (
        <ConfirmSheet title={`Unsave ${view.venue.name}?`} danger action={busy ? 'Unsaving…' : 'Unsave'}
          body={`It comes out of ${circle ? circle.name : 'your circle'}, with your notes and rating. The place stays on FavCircles for everyone else, and you can save it again any time.`}
          onConfirm={() => { if (!busy) remove(); }} onClose={() => setSheet(null)} />
      ) : null}
    </section>
  );
}
