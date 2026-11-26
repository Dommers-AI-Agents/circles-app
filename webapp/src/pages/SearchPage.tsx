// Search everything from one field: my places, people, my friends' places
// and every venue on FavCircles. The words live in the address (?q=) so a
// search survives Back and a reload.
import { useEffect, useState, type ReactNode } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import { messageOf } from '../api/client';
import {
  myPlaces, searchCatalog, searchFriendsPlaces, searchPeople, type CatalogPlace, type FriendPlace
} from '../api/people';
import type { Place } from '../api/types';
import { DEFAULT_CENTER } from '../logic/geo';
import { filterMyPlaces, isSearchable } from '../logic/placeMatch';
import { reasonFor } from '../logic/relationship';
import { catalogNotListed, catalogPhoto, friendsPlacesOnce, listedVenues } from '../logic/searchResults';
import { Empty, Head } from '../ui/kit';
import { PlaceRow } from '../ui/PlaceRow';
import { FollowButton } from '../ui/people/FollowButton';
import { PersonRow } from '../ui/people/PersonRow';
import { useBrowserLocation, useDebounced } from '../ui/people/hooks';
import '../ui/people/people.css';
import './search.css';

const placeLink = (id: string) => `/place/${encodeURIComponent(id)}`;

export function SearchPage() {
  const navigate = useNavigate();
  const [params, setParams] = useSearchParams();
  const [typed, setTyped] = useState(params.get('q') || '');
  const query = useDebounced(typed.trim(), 300);
  const ready = isSearchable(query) && isSearchable(typed);
  const [askWhere, setAskWhere] = useState(false);
  // Only asks the browser when the person taps "Use my location"
  const { where } = useBrowserLocation({ ask: askWhere });
  const origin = where || DEFAULT_CENTER;
  const originKey = `${origin.lat.toFixed(2)},${origin.lng.toFixed(2)}`;

  // Keep ?q= in step with what was searched, without stacking history
  useEffect(() => {
    if ((params.get('q') || '') !== query) setParams(query ? { q: query } : {}, { replace: true });
  }, [query, params, setParams]);

  const mine = useQuery({ queryKey: ['places', 'my-places'], queryFn: myPlaces, staleTime: 60_000 });
  const people = useQuery({
    queryKey: ['people', 'search', query.toLowerCase()],
    queryFn: ({ signal }) => searchPeople(query, signal),
    enabled: ready
  });
  const friends = useQuery({
    queryKey: ['search', 'friends', query.toLowerCase(), originKey],
    queryFn: ({ signal }) => searchFriendsPlaces(query, origin, signal),
    enabled: ready
  });
  const catalog = useQuery({
    queryKey: ['search', 'catalog', query.toLowerCase(), originKey],
    queryFn: ({ signal }) => searchCatalog(query, origin, signal),
    enabled: ready
  });

  const myMatches = ready && mine.data ? filterMyPlaces(mine.data, query) : [];
  const myVenues = listedVenues(mine.data);
  const friendRows = friendsPlacesOnce(friends.data, myVenues);
  const venueRows = catalogNotListed(catalog.data, listedVenues(mine.data, friends.data));

  return (
    <>
      <Head title="Search" back />
      <main className="page">
        <div className="search-field">
          <input type="search" value={typed} onChange={(event) => setTyped(event.target.value)} autoFocus
            placeholder="Places, people, a kind of food…" aria-label="Search places and people"
            autoComplete="off" enterKeyHint="search" />
          {typed ? <button type="button" aria-label="Clear" onClick={() => setTyped('')}>✕</button> : null}
        </div>
        <p className="small muted search-where">
          {where ? 'Places near you first.' : (
            <>Places near Charlotte first. <button type="button" className="search-where-btn" onClick={() => setAskWhere(true)}>Use my location</button></>
          )}
        </p>

        {!isSearchable(typed) ? (
          <Empty mark="🔎" title="Search FavCircles">
            {typed.trim() ? 'Type one more letter to search.' : 'Find a place you saved, a friend, somewhere your people love, or any place on FavCircles.'}
          </Empty>
        ) : (
          <>
            <Section title="My places" loading={!ready || mine.isPending} error={mine.isError ? messageOf(mine.error) : ''}
              retry={() => mine.refetch()} none={myMatches.length === 0 ? 'None of your saved places match.' : ''}>
              <ul className="list card search-list">
                {myMatches.map((place) => (
                  <li key={place._id}>
                    <PlaceRow place={place} trailing={place.circleName || undefined} onOpen={() => navigate(placeLink(place._id))} />
                  </li>
                ))}
              </ul>
            </Section>

            <Section title="People" loading={!ready || people.isPending} error={people.isError ? messageOf(people.error) : ''}
              retry={() => people.refetch()} none={people.data && people.data.length === 0 ? 'Nobody by that name.' : ''}>
              <ul className="list card search-list">
                {(people.data || []).map((person) => (
                  <li key={person._id}>
                    <PersonRow person={person} detail={person.location || person.bio || reasonFor(person)}>
                      <FollowButton person={person} small />
                    </PersonRow>
                  </li>
                ))}
              </ul>
            </Section>

            <Section title="Your people's places" loading={!ready || friends.isPending} error={friends.isError ? messageOf(friends.error) : ''}
              retry={() => friends.refetch()} none={friends.data && friendRows.length === 0 ? 'Nothing your people saved matches.' : ''}>
              <ul className="list card search-list">
                {friendRows.map((place) => (
                  <li key={place._id}>
                    <PlaceRow place={friendPlace(place)} trailing={saverOf(place)} onOpen={() => navigate(placeLink(place._id))} />
                  </li>
                ))}
              </ul>
            </Section>

            <Section title="On FavCircles" loading={!ready || catalog.isPending} error={catalog.isError ? messageOf(catalog.error) : ''}
              retry={() => catalog.refetch()} none={catalog.data && venueRows.length === 0 ? 'No other places on FavCircles match nearby.' : ''}>
              <ul className="list card search-list">
                {venueRows.map((venue) => (
                  <li key={venue._id}>
                    <PlaceRow place={catalogPlace(venue)} onOpen={() => navigate(placeLink(venue._id))} />
                  </li>
                ))}
              </ul>
            </Section>
          </>
        )}
      </main>
    </>
  );
}

/** One list: its heading, then a loading line, an error with Try again, an empty line, or the rows. */
function Section({ title, loading, error, retry, none, children }: {
  title: string; loading: boolean; error: string; retry: () => void; none: string; children: ReactNode;
}) {
  return (
    <section aria-label={title}>
      <p className="section-title">{title}</p>
      {loading ? <p className="search-line"><span className="search-dot" aria-hidden="true" />Looking…</p>
        : error ? (
          <p className="search-line">{error} <button type="button" className="search-where-btn" onClick={retry}>Try again</button></p>
        ) : none ? <p className="search-line">{none}</p> : children}
    </section>
  );
}

const friendPlace = (place: FriendPlace): Place => ({ ...place, addedByUser: null });

const saverOf = (place: FriendPlace): string | undefined => {
  const name = place.addedByUser && (place.addedByUser.displayName || place.addedByUser.name);
  return name ? name.split(' ')[0] : undefined;
};

const catalogPlace = (venue: CatalogPlace): Place => {
  const photo = catalogPhoto(venue);
  return { _id: venue._id, name: venue.name, address: venue.address, category: venue.category, photos: photo ? [photo] : [] };
};
