// Locals (iOS Controllers/Home/Tabs/HomeSpecialsViewController.swift): store
// specials and rewards nearby (saved stores first, then the nearest, in the
// server's order), then "Happening nearby" (store events, library programs,
// Ticketmaster shows) and the nearest farmers markets, with the sources'
// credit line. Centred on this browser when it may say where it is, else
// where the account was last seen, else Charlotte.
import { useEffect, useState, type FormEvent } from 'react';
import { Link } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import { accountLocation, nearbyEvents, nearbyOffers, searchEvents, type LocalEvent } from '../api/rewards';
import { messageOf } from '../api/client';
import { DEFAULT_CENTER, type LatLng } from '../logic/geo';
import { localDayKey } from '../logic/eventTime';
import {
  areaLine, dealLine, directionsLink, eventWhenLine, eventWhereLine, isStoreEvent, marketLine, safeLink, storeDeals, storeMeta,
  storeTarget, type AreaSource
} from '../logic/locals';
import { Head, LoadError, Spinner, Thumb, toast } from '../ui/kit';
import { storeRewardsPath } from '../ui/rewards/venuePlaces';
import { currentSpot, locationAlreadyAllowed } from '../ui/rewards/where';
import '../ui/rewards/rewards.css';
import './locals.css';

const SHOWN_DEALS = 3;
const round = (n: number) => Math.round(n * 1000) / 1000;

/** Where the list is centred, and why. */
function useArea() {
  const [area, setArea] = useState<{ center: LatLng; source: AreaSource } | null>(null);
  const [locating, setLocating] = useState(false);
  useEffect(() => {
    let cancelled = false;
    (async () => {
      if (await locationAlreadyAllowed()) {
        const spot = await currentSpot();
        if (cancelled) return;
        if (spot && spot !== 'denied') { setArea({ center: spot, source: 'device' }); return; }
      }
      const seen = await accountLocation().catch(() => null);
      if (cancelled) return;
      setArea(seen ? { center: seen, source: 'account' } : { center: DEFAULT_CENTER, source: 'default' });
    })();
    return () => { cancelled = true; };
  }, []);
  const locateMe = async () => {
    setLocating(true);
    const spot = await currentSpot();
    setLocating(false);
    if (spot === 'denied') toast("Location is off for this site. Allow it in your browser's settings.");
    else if (!spot) toast("Couldn't find where you are. Try again in a moment.");
    else setArea({ center: spot, source: 'device' });
  };
  return { area, locating, locateMe };
}

function EventRow({ event, todayKey }: { event: LocalEvent; todayKey: string }) {
  const inner = (
    <>
      <Thumb src={event.imageUrl} mark={isStoreEvent(event) ? '🏬' : '📅'} />
      <span className="grow" style={{ minWidth: 0 }}>
        <span className="lc-title">{event.name}</span>
        <span className="small lc-when">{eventWhenLine(event, todayKey)}</span>
        <span className="small muted clip" style={{ display: 'block' }}>{eventWhereLine(event)}</span>
        {event.sourceName && !isStoreEvent(event) ? <span className="small muted clip" style={{ display: 'block' }}>{event.sourceName}</span> : null}
      </span>
    </>
  );
  const target = isStoreEvent(event) ? storeTarget(event) : null;
  if (target) {
    const to = target.kind === 'rewards' ? storeRewardsPath(target.venueId, target.globalPlaceId) : `/place/${encodeURIComponent(target.globalPlaceId)}`;
    return <Link className="item lc-item" to={to}>{inner}</Link>;
  }
  const url = safeLink(event.url);
  return url
    ? <a className="item lc-item" href={url} target="_blank" rel="noopener noreferrer">{inner}<span className="muted" aria-hidden="true">↗</span></a>
    : <div className="item lc-item">{inner}</div>;
}

export function LocalsPage() {
  const { area, locating, locateMe } = useArea();
  const [typed, setTyped] = useState('');
  const [query, setQuery] = useState('');
  const lat = area ? round(area.center.lat) : 0;
  const lng = area ? round(area.center.lng) : 0;
  const todayKey = localDayKey();

  const offers = useQuery({ queryKey: ['rewards', 'locals', 'offers', lat, lng], queryFn: () => nearbyOffers(lat, lng), enabled: !!area });
  const feed = useQuery({ queryKey: ['rewards', 'locals', 'events', lat, lng], queryFn: () => nearbyEvents(lat, lng), enabled: !!area });
  const found = useQuery({
    queryKey: ['rewards', 'locals', 'search', query, lat, lng],
    queryFn: () => searchEvents(query, lat, lng),
    enabled: !!area && query.length > 0
  });

  const stores = storeDeals(offers.data?.venues);
  const searching = query.length > 0;
  const events = searching ? found.data?.events || [] : feed.data?.events || [];
  const markets = searching ? [] : feed.data?.markets || [];
  const attribution = searching ? found.data?.attribution || feed.data?.attribution : feed.data?.attribution;

  const submit = (event: FormEvent) => {
    event.preventDefault();
    setQuery(typed.trim().slice(0, 80));
  };

  return (
    <>
      <Head title="Locals" lead>
        <Link className="icon-btn" to="/rewards">🎁 Rewards</Link>
      </Head>
      <main className="page">
        <div className="card lc-area">
          <p className="small grow">{area ? areaLine(area.source) : 'Finding what’s near you…'}</p>
          {area && area.source !== 'device' ? (
            <button className="btn small soft" onClick={locateMe} disabled={locating}>{locating ? 'Finding you…' : 'Use my location'}</button>
          ) : null}
        </div>

        {!area ? <Spinner /> : null}

        {area && !searching ? (
          <section className="rw-section">
            <h2>Store specials &amp; rewards</h2>
            {offers.isPending ? <Spinner /> : null}
            {offers.isError ? <LoadError message={messageOf(offers.error)} retry={() => offers.refetch()} /> : null}
            {offers.data && stores.length === 0 ? (
              <p className="card rw-card small muted">No store deals nearby right now. Deals from places on your map and nearby show up here.</p>
            ) : null}
            {stores.map(({ venue, deals }) => {
              const target = storeTarget(venue);
              const to = target && target.kind === 'rewards'
                ? storeRewardsPath(target.venueId, target.globalPlaceId)
                : target ? `/place/${encodeURIComponent(target.globalPlaceId)}` : '/rewards';
              const meta = storeMeta(venue);
              return (
                <Link key={venue.venueId} className="card rw-card rw-link lc-store" to={to}>
                  <div className="row" style={{ alignItems: 'flex-start' }}>
                    <Thumb src={venue.photoUrl || venue.coverPhotoUrl} mark="🏬" />
                    <div className="grow" style={{ minWidth: 0 }}>
                      <h3 className="clip">{venue.venueName}</h3>
                      {meta ? <p className="small muted">{meta}</p> : null}
                      {venue.earnRate ? <p className="small muted">Earn {venue.earnRate} points per purchase</p> : null}
                    </div>
                  </div>
                  <ul className="lc-deals">
                    {deals.slice(0, SHOWN_DEALS).map((deal) => (
                      <li key={deal.key}><span aria-hidden="true">{deal.kind === 'offer' ? '🎁' : deal.announcement.event ? '📅' : '📣'}</span>{dealLine(deal)}</li>
                    ))}
                  </ul>
                  <p className="rw-more">{deals.length > SHOWN_DEALS ? `${deals.length - SHOWN_DEALS} more at ${venue.venueName} ›` : 'See the store ›'}</p>
                </Link>
              );
            })}
          </section>
        ) : null}

        {area ? (
          <section className="rw-section">
            <h2>{searching ? 'Events' : 'Happening nearby'}</h2>
            <form className="lc-search" onSubmit={submit} role="search">
              <input className="input" type="search" placeholder="Search events, teams, shows" value={typed} maxLength={80}
                onChange={(e) => { setTyped(e.target.value); if (!e.target.value) setQuery(''); }} aria-label="Search events" />
              {searching ? <button type="button" className="btn small plain" onClick={() => { setTyped(''); setQuery(''); }}>Clear</button> : null}
            </form>
            {searching && found.data && !found.data.nearby && events.length > 0 ? (
              <p className="small muted" style={{ margin: '8px 2px 0' }}>Nothing within 100 miles. These are happening elsewhere.</p>
            ) : null}
            {(searching ? found.isPending : feed.isPending) ? <Spinner /> : null}
            {!searching && feed.isError ? <LoadError message={messageOf(feed.error)} retry={() => feed.refetch()} /> : null}
            {searching && found.isError ? <LoadError message={messageOf(found.error)} retry={() => found.refetch()} /> : null}
            {(searching ? found.data : feed.data) && events.length === 0 ? (
              <p className="card rw-card small muted">
                {searching ? `Nothing matches “${query}”. Try a team, artist or venue.` : 'No events found near here for the next two weeks.'}
              </p>
            ) : null}
            {events.length > 0 ? (
              <ul className="list card" style={{ marginTop: 12, overflow: 'hidden' }}>
                {events.map((event) => <li key={event.id}><EventRow event={event} todayKey={todayKey} /></li>)}
              </ul>
            ) : null}
          </section>
        ) : null}

        {area && !searching && feed.data ? (
          <section className="rw-section">
            <h2>Farmers markets</h2>
            {markets.length === 0 ? (
              <p className="card rw-card small muted">No farmers markets listed near here.</p>
            ) : (
              <ul className="list card" style={{ marginTop: 12, overflow: 'hidden' }}>
                {markets.map((market) => {
                  const site = safeLink(market.website);
                  const directions = directionsLink(market.lat, market.lng);
                  const line = marketLine(market);
                  return (
                    <li key={market.id} className="item lc-item lc-market">
                      <Thumb src={market.photoUrl} mark="🥕" />
                      <span className="grow" style={{ minWidth: 0 }}>
                        <span className="lc-title">{market.name}</span>
                        {market.address ? <span className="small muted clip" style={{ display: 'block' }}>{market.address}</span> : null}
                        {line ? <span className="small lc-when">{line}</span> : null}
                        <span className="lc-links">
                          {directions ? <a href={directions} target="_blank" rel="noopener noreferrer">Directions ↗</a> : null}
                          {site ? <a href={site} target="_blank" rel="noopener noreferrer">Website ↗</a> : null}
                        </span>
                      </span>
                    </li>
                  );
                })}
              </ul>
            )}
          </section>
        ) : null}

        {attribution ? <p className="small muted lc-credit">{attribution}</p> : null}

        {area ? <Link className="btn block soft" style={{ marginTop: 20 }} to="/rewards">🎁 My rewards</Link> : null}
      </main>
    </>
  );
}
