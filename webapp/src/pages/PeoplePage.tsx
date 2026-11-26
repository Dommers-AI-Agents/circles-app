// People: who is waiting on me, people worth following, and the people I
// already have. A search field on top finds anyone by name.
import { useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { useInfiniteQuery, useQuery } from '@tanstack/react-query';
import { messageOf } from '../api/client';
import {
  acceptConnection, acceptFollowRequest, connections as loadConnections, declineConnection, declineFollowRequest,
  discover, followRequests as loadFollowRequests, following as loadFollowing, personOf, searchPeople,
  type Connection, type DiscoverType, type Person
} from '../api/people';
import { useAuth } from '../auth/AuthContext';
import { isSearchable } from '../logic/placeMatch';
import { otherIdOf, reasonFor, splitConnections, stillToMeet } from '../logic/relationship';
import { Empty, Head, LoadError, Spinner, toast } from '../ui/kit';
import { FollowButton } from '../ui/people/FollowButton';
import { PersonRow } from '../ui/people/PersonRow';
import { useBrowserLocation, useDebounced, useRelationshipRefresh } from '../ui/people/hooks';
import '../ui/people/people.css';

type Tab = 'discover' | 'requests' | 'mine';
const TABS: { id: Tab; name: string }[] = [
  { id: 'discover', name: 'Discover' },
  { id: 'requests', name: 'Requests' },
  { id: 'mine', name: 'My people' }
];

// The lists the iOS Discover page draws from, in its order, plus Popular
const LISTS: { id: DiscoverType; name: string; none: string }[] = [
  { id: 'nearby', name: 'People near you', none: 'Nobody new near you yet. Adding your zip code to your profile helps us look in the right place.' },
  { id: 'followsYou', name: 'Follows you', none: "Everyone who follows you, you already follow back. Nobody's waiting here." },
  { id: 'friendsOfFriends', name: 'Friends of friends', none: 'No friends of friends to suggest yet. They show up as you connect with people.' },
  { id: 'popular', name: 'Popular', none: 'Nobody new to suggest right now.' }
];
const PAGE = 20;

const personIn = (connection: Connection, myId: string | undefined): Person =>
  personOf({ displayName: 'Someone', ...(connection.connectedUser || {}), _id: otherIdOf(connection, myId) });

export function PeoplePage() {
  const { userId: myId } = useAuth();
  const [params, setParams] = useSearchParams();
  const tab = (TABS.find((t) => t.id === params.get('tab')) || TABS[0]).id;
  const [typed, setTyped] = useState('');
  const query = useDebounced(typed.trim(), 300);
  const searching = isSearchable(typed) && isSearchable(query);

  // Both feed the Requests count, so they load whichever tab is open
  const connections = useQuery({ queryKey: ['people', 'connections'], queryFn: loadConnections });
  const followRequests = useQuery({ queryKey: ['people', 'requests'], queryFn: loadFollowRequests });
  const lists = splitConnections(connections.data, myId);
  const waiting = lists.incoming.length + (followRequests.data ? followRequests.data.length : 0);

  const results = useQuery({
    queryKey: ['people', 'search', query.toLowerCase()],
    queryFn: ({ signal }) => searchPeople(query, signal),
    enabled: searching
  });

  return (
    <>
      <Head title="People" back />
      <main className="page">
        <div className="search-field">
          <input type="search" value={typed} onChange={(event) => setTyped(event.target.value)}
            placeholder="Find someone by name" aria-label="Find someone by name" autoComplete="off" enterKeyHint="search" />
          {typed ? <button type="button" aria-label="Clear" onClick={() => setTyped('')}>✕</button> : null}
        </div>

        {isSearchable(typed) ? (
          <section aria-label="Search results">
            <p className="section-title">People named “{typed.trim()}”</p>
            {!searching || results.isPending ? <Spinner /> : null}
            {searching && results.isError ? <LoadError message={messageOf(results.error)} retry={() => results.refetch()} /> : null}
            {searching && results.data && results.data.length === 0 ? (
              <Empty mark="🔎" title="Nobody by that name">Check the spelling, or try their first or last name on its own.</Empty>
            ) : null}
            {searching && results.data && results.data.length > 0 ? (
              <ul className="list card people-list">
                {results.data.map((person) => (
                  <li key={person._id}>
                    <PersonRow person={person} detail={person.location || person.bio || reasonFor(person)}>
                      <FollowButton person={person} small />
                    </PersonRow>
                  </li>
                ))}
              </ul>
            ) : null}
          </section>
        ) : (
          <>
            <div className="seg" role="tablist" aria-label="People">
              {TABS.map((t) => (
                <button key={t.id} type="button" role="tab" aria-selected={tab === t.id}
                  onClick={() => setParams(t.id === 'discover' ? {} : { tab: t.id }, { replace: true })}>
                  {t.name}{t.id === 'requests' && waiting > 0 ? <span className="count">{waiting}</span> : null}
                </button>
              ))}
            </div>
            {typed.trim().length === 1 ? <p className="people-line">Type one more letter to search.</p> : null}
            {tab === 'discover' ? <Discover /> : null}
            {tab === 'requests' ? (
              <Requests incoming={lists.incoming} outgoing={lists.outgoing} myId={myId}
                connections={connections} followRequests={followRequests} />
            ) : null}
            {tab === 'mine' ? <Mine connected={lists.connected} myId={myId} connections={connections} /> : null}
          </>
        )}
      </main>
    </>
  );
}

// ---- Discover: one list at a time, a page of 20, more on request
function Discover() {
  const [type, setType] = useState<DiscoverType>('nearby');
  // Only read where they are if they already let this site know: the server
  // falls back to their zip code and the places they save
  const { where, settled } = useBrowserLocation({ ask: false });
  const list = LISTS.find((l) => l.id === type) || LISTS[0];
  const people = useInfiniteQuery({
    queryKey: ['people', 'discover', type, type === 'nearby' && where ? `${where.lat.toFixed(2)},${where.lng.toFixed(2)}` : ''],
    queryFn: ({ pageParam }) => discover(type, {
      limit: PAGE, offset: pageParam,
      lat: type === 'nearby' ? where?.lat : undefined,
      lng: type === 'nearby' ? where?.lng : undefined
    }),
    initialPageParam: 0,
    getNextPageParam: (last, pages) => (last.hasMore ? pages.length * PAGE : undefined),
    enabled: type !== 'nearby' || settled
  });
  // A person once, even if two pages overlap
  const seen = new Set<string>();
  const rows = stillToMeet((people.data?.pages || []).flatMap((page) => page.users))
    .filter((p) => (seen.has(p._id) ? false : (seen.add(p._id), true)));

  return (
    <section aria-label="Discover">
      <div className="chip-row">
        {LISTS.map((l) => (
          <button key={l.id} type="button" aria-pressed={type === l.id} onClick={() => setType(l.id)}>{l.name}</button>
        ))}
      </div>
      {people.isPending ? <Spinner /> : null}
      {people.isError ? <LoadError message={messageOf(people.error)} retry={() => people.refetch()} /> : null}
      {people.data && rows.length === 0 ? <Empty mark="👋" title={list.name}>{list.none}</Empty> : null}
      {rows.length > 0 ? (
        <>
          <ul className="list card people-list" style={{ marginTop: 12 }}>
            {rows.map((person) => (
              <li key={person._id}>
                <PersonRow person={person} detail={reasonFor(person)}>
                  <FollowButton person={person} small />
                </PersonRow>
              </li>
            ))}
          </ul>
          {people.hasNextPage ? (
            <button className="btn block soft" disabled={people.isFetchingNextPage} onClick={() => people.fetchNextPage()}>
              {people.isFetchingNextPage ? 'Loading…' : 'Show more'}
            </button>
          ) : null}
        </>
      ) : null}
    </section>
  );
}

// ---- Requests: invitations to connect, people asking to follow me, and what I sent
function Requests({ incoming, outgoing, myId, connections, followRequests }: {
  incoming: Connection[]; outgoing: Connection[]; myId: string | undefined;
  connections: { isPending: boolean; isError: boolean; error: unknown; refetch: () => unknown };
  followRequests: { data?: { requesterId: string; user: Person }[]; isPending: boolean; isError: boolean; error: unknown; refetch: () => unknown };
}) {
  const refresh = useRelationshipRefresh();
  const [busy, setBusy] = useState('');
  const answer = async (key: string, work: () => Promise<unknown>, said: string) => {
    setBusy(key);
    try {
      await work();
      await refresh();
      toast(said);
    } catch (error) {
      toast(messageOf(error));
    } finally {
      setBusy('');
    }
  };
  const asks = followRequests.data || [];
  const loading = connections.isPending || followRequests.isPending;
  const nothing = !loading && !connections.isError && !followRequests.isError && incoming.length === 0 && asks.length === 0 && outgoing.length === 0;

  return (
    <section aria-label="Requests">
      {loading ? <Spinner /> : null}
      {connections.isError ? <LoadError message={messageOf(connections.error)} retry={() => connections.refetch()} /> : null}
      {followRequests.isError ? <LoadError message={messageOf(followRequests.error)} retry={() => followRequests.refetch()} /> : null}
      {nothing ? (
        <Empty mark="📭" title="Nothing waiting for you">
          Invitations to connect and requests to follow you show up here.
        </Empty>
      ) : null}

      {incoming.length > 0 ? (
        <>
          <p className="section-title">Wants to connect</p>
          <ul className="list card people-list">
            {incoming.map((connection) => {
              const person = personIn(connection, myId);
              const id = String(connection._id || connection.id);
              return (
                <li key={id}>
                  <PersonRow person={person} detail={reasonFor(person)}>
                    <button className="btn small" disabled={busy === id}
                      onClick={() => answer(id, () => acceptConnection(id), `You're connected with ${person.displayName}`)}>Accept</button>
                    <button className="btn small soft" disabled={busy === id}
                      onClick={() => answer(id, () => declineConnection(id), 'Invitation declined')}>Decline</button>
                  </PersonRow>
                </li>
              );
            })}
          </ul>
        </>
      ) : null}

      {asks.length > 0 ? (
        <>
          <p className="section-title">Wants to follow you</p>
          <ul className="list card people-list">
            {asks.map((request) => (
              <li key={request.requesterId}>
                <PersonRow person={request.user} detail={reasonFor(request.user)}>
                  <button className="btn small" disabled={busy === request.requesterId}
                    onClick={() => answer(request.requesterId, () => acceptFollowRequest(request.requesterId), `${request.user.displayName} follows you now`)}>Accept</button>
                  <button className="btn small soft" disabled={busy === request.requesterId}
                    onClick={() => answer(request.requesterId, () => declineFollowRequest(request.requesterId), 'Request declined')}>Decline</button>
                </PersonRow>
              </li>
            ))}
          </ul>
          <p className="small muted" style={{ margin: '-4px 4px 0' }}>Someone you decline isn't told.</p>
        </>
      ) : null}

      {outgoing.length > 0 ? (
        <>
          <p className="section-title">Invitations you sent</p>
          <ul className="list card people-list">
            {outgoing.map((connection) => {
              const person = personIn(connection, myId);
              const id = String(connection._id || connection.id);
              return (
                <li key={id}>
                  <PersonRow person={person} detail="Hasn't answered yet">
                    <button className="btn small soft" disabled={busy === id}
                      onClick={() => answer(id, () => declineConnection(id), 'Invitation taken back')}>Take back</button>
                  </PersonRow>
                </li>
              );
            })}
          </ul>
        </>
      ) : null}
    </section>
  );
}

// ---- My people: connections, then everyone I follow
function Mine({ connected, myId, connections }: {
  connected: Connection[]; myId: string | undefined;
  connections: { isPending: boolean; isError: boolean; error: unknown; refetch: () => unknown };
}) {
  const following = useQuery({
    queryKey: ['people', 'following'],
    queryFn: () => loadFollowing(myId || ''),
    enabled: !!myId
  });
  const connectedIds = new Set(connected.map((c) => otherIdOf(c, myId)));
  // Connected always means following, so they are listed once, above
  const followed = (following.data || []).filter((p) => !connectedIds.has(p._id));

  return (
    <section aria-label="My people">
      <p className="section-title">Connections{connected.length ? ` · ${connected.length}` : ''}</p>
      {connections.isPending ? <Spinner /> : null}
      {connections.isError ? <LoadError message={messageOf(connections.error)} retry={() => connections.refetch()} /> : null}
      {!connections.isPending && !connections.isError && connected.length === 0 ? (
        <p className="card people-line" style={{ padding: '14px 16px', margin: 0 }}>
          No connections yet. Open someone's profile and tap Connect: once they accept, you see each other's My Network circles.
        </p>
      ) : null}
      {connected.length > 0 ? (
        <ul className="list card people-list">
          {connected.map((connection) => {
            const person = personIn(connection, myId);
            return (
              <li key={String(connection._id || connection.id)}>
                <PersonRow person={person} detail={reasonFor({ location: person.location, placesCount: person.placesCount })}>
                  <span className="chip">Connected</span>
                </PersonRow>
              </li>
            );
          })}
        </ul>
      ) : null}

      <p className="section-title">Following{following.data ? ` · ${followed.length}` : ''}</p>
      {following.isPending ? <Spinner /> : null}
      {following.isError ? <LoadError message={messageOf(following.error)} retry={() => following.refetch()} /> : null}
      {following.data && followed.length === 0 ? (
        <p className="card people-line" style={{ padding: '14px 16px', margin: 0 }}>
          {connected.length > 0 ? "You don't follow anyone beyond your connections." : "You don't follow anyone yet. Discover has people to start with."}
        </p>
      ) : null}
      {followed.length > 0 ? (
        <ul className="list card people-list">
          {followed.map((person) => (
            <li key={person._id}>
              <PersonRow person={person} detail={reasonFor({ location: person.location, placesCount: person.placesCount, followsYou: person.followsYou })}>
                <FollowButton person={{ ...person, isFollowing: true }} small />
              </PersonRow>
            </li>
          ))}
        </ul>
      ) : null}
    </section>
  );
}
