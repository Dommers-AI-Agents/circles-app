// Someone's followers, or the people they follow, each with a follow button.
import { useQuery } from '@tanstack/react-query';
import { messageOf } from '../../api/client';
import { followers, following } from '../../api/people';
import { reasonFor } from '../../logic/relationship';
import { LoadError, Sheet, Spinner } from '../kit';
import { FollowButton } from './FollowButton';
import { PersonRow } from './PersonRow';

export function PeopleListSheet({ userId, name, kind, myId, onClose }: {
  userId: string; name: string; kind: 'followers' | 'following'; myId: string | undefined; onClose: () => void;
}) {
  const mine = userId === myId;
  const list = useQuery({
    queryKey: ['user', userId, kind],
    queryFn: () => (kind === 'followers' ? followers(userId) : following(userId))
  });
  const title = kind === 'followers'
    ? (mine ? 'Your followers' : `Following ${name}`)
    : (mine ? 'People you follow' : `${name} follows`);
  return (
    <Sheet title={title} onClose={onClose}>
      {list.isPending ? <Spinner /> : null}
      {list.isError ? <LoadError message={messageOf(list.error)} retry={() => list.refetch()} /> : null}
      {list.data && list.data.length === 0 ? (
        <p className="muted people-none">
          {kind === 'followers'
            ? (mine ? 'Nobody follows you yet.' : `Nobody follows ${name} yet.`)
            : (mine ? "You don't follow anyone yet." : `${name} doesn't follow anyone yet.`)}
        </p>
      ) : null}
      {list.data && list.data.length > 0 ? (
        <ul className="list card people-list">
          {list.data.map((person) => (
            <li key={person._id} onClick={(event) => { if ((event.target as HTMLElement).closest('a')) onClose(); }}>
              <PersonRow person={person} detail={person.bio || reasonFor(person)}>
                {person._id === myId ? <span className="chip gray">You</span> : <FollowButton person={person} small />}
              </PersonRow>
            </li>
          ))}
        </ul>
      ) : null}
      <button className="btn block plain" type="button" onClick={onClose}>Close</button>
    </Sheet>
  );
}
