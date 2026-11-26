import { Link } from 'react-router-dom';
import type { Circle } from '../api/types';
import { plural, privacyMark, privacyName } from '../logic/labels';
import './circles.css';

/** One circle as a cover tile. A locked circle says what would open it. */
export function CircleCard({ circle }: { circle: Circle }) {
  const count = circle.placesCount ?? (circle.places ? circle.places.length : 0);
  const inner = (
    <>
      <div className="circle-cover" style={circle.coverImage ? { backgroundImage: `url("${circle.coverImage.replace(/"/g, '%22')}")` } : undefined}>
        {circle.locked ? <span className="circle-lock" aria-hidden="true">🔒</span> : null}
        {circle.newPlacesCount ? <span className="chip gold circle-new">{circle.newPlacesCount} new</span> : null}
      </div>
      <div className="circle-meta">
        <strong className="clip">{circle.name}</strong>
        <span className="small muted clip">
          {circle.locked
            ? (circle.lockedReason === 'follow' ? 'Follow to see this circle' : 'Connect to see this circle')
            : `${plural(count, 'place')} · ${privacyMark(circle.privacy)} ${privacyName(circle.privacy)}`}
        </span>
      </div>
    </>
  );
  if (circle.locked) return <div className="circle-card card locked" aria-label={`${circle.name}, locked`}>{inner}</div>;
  return <Link className="circle-card card" to={`/circle/${circle._id}`}>{inner}</Link>;
}
