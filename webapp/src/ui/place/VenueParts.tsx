// The venue itself: photos, the buttons that take you there, and its hours.
import { useState } from 'react';
import { categoryOf } from '../../logic/labels';
import { latLngOf } from '../../logic/geo';
import { hoursStatus, weekRows } from '../../logic/openingHours';
import { directionsHref, telHref, websiteHref, type Venue } from '../../logic/placeView';
import { SHARE_BASE, shareLink } from '../share';

function Photo({ src, onBroken }: { src: string; onBroken: () => void }) {
  return <img src={src} alt="" loading="lazy" onError={onBroken} />;
}

/** The venue's photos side by side; the category mark on the brand tint when there are none. */
export function PhotoStrip({ venue }: { venue: Venue }) {
  const [broken, setBroken] = useState<string[]>([]);
  const photos = venue.photos.filter((url) => !broken.includes(url)).slice(0, 12);
  if (photos.length === 0) {
    return <div className="pl-photos none" aria-hidden="true"><span>{categoryOf(venue.category).mark}</span></div>;
  }
  return (
    <div className={`pl-photos${photos.length === 1 ? ' one' : ''}`} aria-label={`${photos.length} photos`}>
      {photos.map((url) => <Photo key={url} src={url} onBroken={() => setBroken((list) => [...list, url])} />)}
    </div>
  );
}

/** Directions, Call, Website, Share: only the ones the venue has. */
export function ActionBar({ venue, shareId }: { venue: Venue; shareId: string }) {
  const point = latLngOf(venue.location);
  const tel = telHref(venue.phone);
  const site = websiteHref(venue.website);
  return (
    <nav className="pl-actions" aria-label="Place actions">
      {point ? (
        <a className="pl-action" href={directionsHref(point.lat, point.lng)} target="_blank" rel="noopener noreferrer">
          <span aria-hidden="true">🧭</span>Directions
        </a>
      ) : null}
      {tel ? <a className="pl-action" href={tel}><span aria-hidden="true">📞</span>Call</a> : null}
      {site ? (
        <a className="pl-action" href={site} target="_blank" rel="noopener noreferrer"><span aria-hidden="true">🌐</span>Website</a>
      ) : null}
      <button className="pl-action" onClick={() => shareLink(venue.name, `${SHARE_BASE}/place/${encodeURIComponent(shareId)}`)}>
        <span aria-hidden="true">↗︎</span>Share
      </button>
    </nav>
  );
}

/** "Open now · closes 5:00 PM", and the whole week on a tap. Nothing when the hours aren't known. */
export function HoursCard({ venue, now = new Date() }: { venue: Venue; now?: Date }) {
  const [open, setOpen] = useState(false);
  const status = hoursStatus(venue.hours, now);
  const week = weekRows(venue.hours, now);
  if (!status && week.length === 0) return null;
  return (
    <section className="card pl-card pl-hours" aria-label="Hours">
      <button className="pl-hours-head" onClick={() => setOpen(!open)} aria-expanded={open} disabled={week.length === 0}>
        <span aria-hidden="true">🕘</span>
        <span className={`grow ${status ? (status.open ? 'pl-open' : 'pl-closed') : 'muted'}`}>{status ? status.text : 'Hours'}</span>
        {week.length > 0 ? <span className="small muted">{open ? 'Hide' : 'All week'}</span> : null}
      </button>
      {open ? (
        <table className="pl-week">
          <tbody>
            {week.map((row) => (
              <tr key={row.day} className={row.today ? 'today' : undefined}>
                <th scope="row">{row.name}</th><td>{row.text}</td>
              </tr>
            ))}
          </tbody>
        </table>
      ) : null}
    </section>
  );
}
