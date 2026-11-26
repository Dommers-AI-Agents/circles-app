// One person in a list: photo, name, one line about them, and whatever the
// list offers on the right (a follow button, Accept / Decline…).
import type { ReactNode } from 'react';
import { Link } from 'react-router-dom';
import { Avatar } from '../kit';
import './people.css';

export function PersonRow({ person, detail, children }: {
  person: { _id: string; displayName: string; profilePicture?: string | null };
  detail?: string;
  children?: ReactNode;
}) {
  return (
    <div className="person-row">
      <Link className="person-link" to={`/user/${encodeURIComponent(person._id)}`}>
        <Avatar name={person.displayName || '?'} src={person.profilePicture} size={46} seed={person._id} />
        <span className="grow">
          <span className="person-name clip">{person.displayName || 'Someone'}</span>
          {detail ? <span className="small muted clip person-detail">{detail}</span> : null}
        </span>
      </Link>
      {children ? <span className="person-actions">{children}</span> : null}
    </div>
  );
}
