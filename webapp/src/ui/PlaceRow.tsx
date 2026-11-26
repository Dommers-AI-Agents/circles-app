import type { Place } from '../api/types';
import { categoryOf } from '../logic/labels';
import { Thumb } from './kit';

/** One saved place in a list: photo, name, what kind of place and where. */
export function PlaceRow({ place, onOpen, trailing }: { place: Place; onOpen?: (place: Place) => void; trailing?: string }) {
  const category = categoryOf(place.category);
  const where = (place.address || '').split(',').slice(0, 2).join(',');
  return (
    <button className="item place-row" onClick={onOpen ? () => onOpen(place) : undefined} disabled={!onOpen}>
      <Thumb src={place.photos && place.photos[0]} mark={category.mark} />
      <span className="grow">
        <span className="name clip" style={{ display: 'block' }}>{place.name}</span>
        <span className="small muted clip" style={{ display: 'block' }}>{category.name}{where ? ` · ${where}` : ''}</span>
        {place.approvalStatus === 'pending' ? <span className="chip gray" style={{ marginTop: 4 }}>Waiting for review · only you see it</span> : null}
      </span>
      {trailing ? <span className="small muted">{trailing}</span> : null}
    </button>
  );
}
