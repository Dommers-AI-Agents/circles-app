// Add a place: find it (FavCircles' own places first, then OpenStreetMap),
// or type it in and drop a pin; then pick the circle, the kind of place, who
// can see it, notes and a rating, and save. ?circle=<id> starts on that circle.
import { useEffect, useMemo, useRef, useState, type FormEvent } from 'react';
import { Link, useNavigate, useSearchParams } from 'react-router-dom';
import { keepPreviousData, useQuery, useQueryClient, type UseQueryResult } from '@tanstack/react-query';
import { myCircles } from '../api/circles';
import { ApiError, messageOf } from '../api/client';
import { savePlace, searchVenues, type MapPin, type VenueSearch } from '../api/mapPlaces';
import type { Circle, PlacePrivacy } from '../api/types';
import { useAuth } from '../auth/AuthContext';
import {
  buildSaveBody, duplicateOf, handProblem, initialCircle, knownCategory, middleOf, MIN_VENUE_QUERY, outcomeOf, venueQueryOf,
  type Duplicate, type PickedVenue
} from '../logic/addPlace';
import { DEFAULT_CENTER, distanceMeters, distanceText, type LatLng } from '../logic/geo';
import { CATEGORIES, categoryOf, plural, PRIVACY, privacyMark, privacyName } from '../logic/labels';
import { LAST_CIRCLE_KEY, ratingWord, saveTargets } from '../logic/placeSave';
import type { VenueResult } from '../logic/venueResults';
import { HandMap } from '../map/HandMap';
import { askPosition, quietPosition } from '../map/location';
import { CircleEditSheet } from '../ui/CircleEditSheet';
import { Empty, Head, LoadError, Sheet, Spinner, Thumb, toast } from '../ui/kit';
import '../ui/circles.css';
import './addPlace.css';

type Step = 'find' | 'hand' | 'details';

const readLastCircle = (): string | null => {
  try { return localStorage.getItem(LAST_CIRCLE_KEY); } catch { return null; }
};
const writeLastCircle = (id: string) => {
  try { localStorage.setItem(LAST_CIRCLE_KEY, id); } catch { /* private window: nothing to remember */ }
};

const SOURCE_WORDS: Record<PickedVenue['source'], string> = {
  catalog: 'On FavCircles',
  osm: 'From OpenStreetMap',
  hand: 'Added by hand'
};

export function AddPlacePage() {
  const { userId } = useAuth();
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const [params] = useSearchParams();
  const linkCircle = params.get('circle');
  const lastUsed = useMemo(readLastCircle, []);

  const [step, setStep] = useState<Step>('find');
  const [text, setText] = useState('');
  const [query, setQuery] = useState('');
  const [near, setNear] = useState<LatLng | null>(null);
  const [locating, setLocating] = useState(false);
  const [venue, setVenue] = useState<PickedVenue | null>(null);

  // "by hand"
  const [handName, setHandName] = useState('');
  const [handAddress, setHandAddress] = useState('');
  const [handPin, setHandPin] = useState<LatLng | null>(null);
  const [handError, setHandError] = useState('');

  // where it goes
  const [circleId, setCircleId] = useState<string | null>(null);
  const [madeCircle, setMadeCircle] = useState<Circle | null>(null);
  const [category, setCategory] = useState('other');
  const [privacy, setPrivacy] = useState<PlacePrivacy>('followCircle');
  const [notes, setNotes] = useState('');
  const [rating, setRating] = useState<number | null>(null);
  const [creating, setCreating] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [duplicate, setDuplicate] = useState<Duplicate | null>(null);
  const top = useRef<HTMLDivElement>(null);

  const circles = useQuery({ queryKey: ['circles', 'mine'], queryFn: myCircles });
  const targets = useMemo(() => saveTargets(circles.data || [], userId), [circles.data, userId]);
  useEffect(() => {
    if (circleId === null && targets.length > 0) setCircleId(initialCircle(targets, linkCircle, lastUsed));
  }, [targets, circleId, linkCircle, lastUsed]);
  const chosenCircle = targets.find((c) => c._id === circleId) || (madeCircle && madeCircle._id === circleId ? madeCircle : null);

  // Where to look: where I am when location is already allowed (never a
  // permission box on open), else the middle of my own places, else Charlotte
  useEffect(() => {
    let live = true;
    quietPosition().then((position) => { if (live && position) setNear(position); });
    return () => { live = false; };
  }, []);
  const placesMiddle = useMemo(() => {
    const lists = queryClient.getQueriesData<MapPin[]>({ queryKey: ['map', 'mine'] });
    return middleOf(lists.flatMap(([, pins]) => pins || []).map((pin) => pin.at));
  }, [queryClient]);
  const origin = near || placesMiddle;
  const bias = origin || DEFAULT_CENTER;

  useEffect(() => {
    const timer = setTimeout(() => setQuery(venueQueryOf(text)), 350);
    return () => clearTimeout(timer);
  }, [text]);
  const searching = query.length >= MIN_VENUE_QUERY;
  const results = useQuery({
    queryKey: ['addPlace', 'search', query, origin ? `${origin.lat.toFixed(2)},${origin.lng.toFixed(2)}` : 'anywhere'],
    queryFn: ({ signal }) => searchVenues(query, origin, bias, signal),
    enabled: searching,
    placeholderData: keepPreviousData,
    staleTime: 5 * 60 * 1000
  });

  const nearMe = async () => {
    setLocating(true);
    try {
      setNear(await askPosition());
    } catch (e) {
      toast(messageOf(e));
    } finally {
      setLocating(false);
    }
  };

  const toTop = () => { top.current?.scrollIntoView({ block: 'start' }); window.scrollTo({ top: 0 }); };

  const pick = (result: VenueResult) => {
    setVenue({
      name: result.name, address: result.address, at: result.at, category: knownCategory(result.category),
      source: result.source, globalPlaceId: result.globalPlaceId
    });
    setCategory(knownCategory(result.category));
    setError('');
    setStep('details');
    toTop();
  };

  const startHand = () => {
    if (!handName && text.trim()) setHandName(text.trim());
    setHandError('');
    setStep('hand');
    toTop();
  };

  const finishHand = (event: FormEvent) => {
    event.preventDefault();
    const problem = handProblem(handName, handPin);
    if (problem) { setHandError(problem); return; }
    setVenue({ name: handName, address: handAddress, at: handPin!, category: 'other', source: 'hand' });
    setCategory((current) => (venue && venue.source === 'hand' ? current : 'other'));
    setError('');
    setStep('details');
    toTop();
  };

  const change = () => {
    setStep(venue && venue.source === 'hand' ? 'hand' : 'find');
    setError('');
    toTop();
  };

  const save = async (force = false) => {
    if (!venue) return;
    if (!circleId) { setError('Pick the circle to save it to.'); return; }
    setSaving(true);
    setError('');
    const circleName = chosenCircle ? chosenCircle.name : null;
    try {
      const body = buildSaveBody(venue, { circleId, category, privacy, privateNotes: notes, userRating: rating }, { force });
      const place = await savePlace(body);
      const outcome = outcomeOf(place, circleName);
      writeLastCircle(circleId);
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: ['circles'] }),
        queryClient.invalidateQueries({ queryKey: ['circle', circleId] }),
        queryClient.invalidateQueries({ queryKey: ['map'] })
      ]);
      toast(outcome.toast);
      const id = place._id || place.id;
      navigate(id ? `/place/${encodeURIComponent(id)}` : '/', { replace: true });
    } catch (e) {
      setSaving(false);
      const body = e instanceof ApiError ? e.body : {};
      const dup = e instanceof ApiError ? duplicateOf(body, circleName) : null;
      if (dup) { setDuplicate(dup); return; }
      if (body.upgradeRequired) {
        setError(`This circle has reached the number of places your plan allows (${String(body.maxAllowed ?? '')}). Pick another circle.`);
        return;
      }
      const details = Array.isArray(body.errors) ? (body.errors as unknown[]).filter((x) => typeof x === 'string').join('. ') : '';
      setError(details ? `${details}.` : messageOf(e));
    }
  };

  const title = step === 'hand' ? 'Add it by hand' : step === 'details' ? 'Save the place' : 'Add a place';

  return (
    <>
      <Head title={title} back>
        {step !== 'find' ? <button className="icon-btn" onClick={() => { setStep('find'); toTop(); }}>Search</button> : null}
      </Head>
      <main className="page add-page">
        <div ref={top} />
        {step === 'find' ? (
          <FindStep
            text={text} setText={setText} query={query} searching={searching} results={results}
            near={near} locating={locating} nearMe={nearMe} onPick={pick} onHand={startHand}
          />
        ) : null}

        {step === 'hand' ? (
          <form onSubmit={finishHand} noValidate>
            <p className="add-lede">Type the place in and tap the map where it is. Good for a park bench, a friend’s porch or a spot no map knows.</p>
            <label className="field"><span>Name</span>
              <input type="text" maxLength={120} value={handName} onChange={(e) => setHandName(e.target.value)} placeholder="What do you call it?" autoFocus />
            </label>
            <label className="field"><span>Address (optional)</span>
              <input type="text" maxLength={300} value={handAddress} onChange={(e) => setHandAddress(e.target.value)} placeholder="Street, city" autoComplete="street-address" />
            </label>
            <div className="row add-map-head">
              <span className="grow small muted">{handPin ? 'Pin placed. Drag it or tap again to move it.' : 'Tap the map to put the pin down.'}</span>
              <button type="button" className="btn small soft" onClick={async () => {
                setLocating(true);
                try {
                  const here = await askPosition();
                  setNear(here);
                  setHandPin(here);
                } catch (e) {
                  toast(messageOf(e));
                } finally {
                  setLocating(false);
                }
              }} disabled={locating}>{locating ? 'Finding you…' : '📍 I’m here'}</button>
            </div>
            <div className="add-handmap-frame card">
              <HandMap start={handPin || bias} pin={handPin} onPin={(at) => { setHandPin(at); setHandError(''); }} />
            </div>
            <div className="card add-notice" role="note">
              <strong>Saved private until it’s checked</strong>
              <p className="small">We look for it among the businesses we know. If it’s not one of them, only you can see it until our team has reviewed it. Then it gets the privacy you pick.</p>
            </div>
            <p className="err" role="alert">{handError}</p>
            <button className="btn block" type="submit">Next</button>
          </form>
        ) : null}

        {step === 'details' && venue ? (
          <>
            <div className="card add-venue">
              <div className="row">
                <Thumb mark={categoryOf(category).mark} />
                <div className="grow">
                  <strong className="add-venue-name">{venue.name.trim() || 'Unnamed place'}</strong>
                  <span className="small muted add-venue-line">{venue.address.trim() || 'Pinned on the map'}</span>
                  <span className="chip gray add-venue-source">{SOURCE_WORDS[venue.source]}</span>
                </div>
                <button className="btn small soft" onClick={change}>Change</button>
              </div>
            </div>

            <p className="section-title">Save it to</p>
            <CirclePicker
              circles={circles} targets={targets} madeCircle={madeCircle} circleId={circleId} lastUsed={lastUsed}
              onPick={setCircleId} onNew={() => setCreating(true)}
            />

            <label className="field add-gap"><span>Kind of place</span>
              <select value={category} onChange={(e) => setCategory(e.target.value)}>
                {CATEGORIES.map((c) => <option key={c.id} value={c.id}>{c.mark} {c.name}</option>)}
              </select>
            </label>

            <p className="section-title">Who can see it</p>
            <div className="card add-options">
              <label className="radio" style={{ borderTop: 0 }}>
                <input type="radio" name="privacy" checked={privacy === 'followCircle'} onChange={() => setPrivacy('followCircle')} />
                <span>
                  <strong>Same as its circle</strong><br />
                  <span className="small muted">
                    {chosenCircle ? `${privacyMark(chosenCircle.privacy)} ${privacyName(chosenCircle.privacy)}, like ${chosenCircle.name}` : 'Whoever can see the circle'}
                  </span>
                </span>
              </label>
              {PRIVACY.map((tier) => (
                <label className="radio" key={tier.id}>
                  <input type="radio" name="privacy" checked={privacy === tier.id} onChange={() => setPrivacy(tier.id)} />
                  <span><strong>{tier.mark} {tier.name}</strong><br /><span className="small muted">{tier.detail}</span></span>
                </label>
              ))}
            </div>

            <label className="field add-gap"><span>Private notes (only you see these)</span>
              <textarea maxLength={2000} value={notes} onChange={(e) => setNotes(e.target.value)} placeholder="What to order, who to ask for, when to go…" />
            </label>

            <div className="card add-rating">
              {rating === null ? (
                <div className="row">
                  <span className="grow"><strong>Your rating</strong><br /><span className="small muted">Optional, 0 to 10</span></span>
                  <button className="btn small soft" onClick={() => setRating(8)}>Rate it</button>
                </div>
              ) : (
                <>
                  <div className="row">
                    <span className="grow"><strong>Your rating: {rating}</strong> <span className="small muted">· {ratingWord(rating)}</span></span>
                    <button className="btn small plain" onClick={() => setRating(null)}>Remove</button>
                  </div>
                  <input
                    className="add-range" type="range" min={0} max={10} step={1} value={rating}
                    onChange={(e) => setRating(Number(e.target.value))} aria-label="Your rating, 0 to 10"
                  />
                  <div className="add-range-ends small muted"><span>0</span><span>10</span></div>
                </>
              )}
            </div>

            {venue.source === 'hand' ? (
              <div className="card add-notice" role="note">
                <strong>Saved private until it’s checked</strong>
                <p className="small">If it isn’t a business we know, only you see it until our team reviews it.</p>
              </div>
            ) : null}

            <p className="err" role="alert">{error}</p>
            <button className="btn block add-save" onClick={() => save(false)} disabled={saving || !circleId}>
              {saving ? 'Saving…' : chosenCircle ? `Save to ${chosenCircle.name}` : 'Save'}
            </button>
          </>
        ) : null}
      </main>

      {creating ? (
        <CircleEditSheet onClose={() => setCreating(false)} onSaved={(made) => { setMadeCircle(made); setCircleId(made._id); }} />
      ) : null}

      {duplicate ? (
        <Sheet title={duplicate.title} onClose={() => setDuplicate(null)}>
          <p className="muted" style={{ marginBottom: 16 }}>{duplicate.message}</p>
          {duplicate.existingPlaceId ? (
            <button className="btn block" onClick={() => navigate(`/place/${encodeURIComponent(duplicate.existingPlaceId!)}`)}>Open it</button>
          ) : null}
          <button className="btn block soft add-sheet-gap" onClick={() => { setDuplicate(null); save(true); }}>Add anyway</button>
          <button className="btn block plain" onClick={() => setDuplicate(null)}>Cancel</button>
        </Sheet>
      ) : null}
    </>
  );
}

// ---- step 1: find it

type ResultsQuery = UseQueryResult<VenueSearch>;

function FindStep({ text, setText, query, searching, results, near, locating, nearMe, onPick, onHand }: {
  text: string; setText: (text: string) => void; query: string; searching: boolean; results: ResultsQuery;
  near: LatLng | null; locating: boolean; nearMe: () => void; onPick: (result: VenueResult) => void; onHand: () => void;
}) {
  const data = searching ? results.data : undefined;
  return (
    <>
      <form className="add-search" role="search" onSubmit={(e) => e.preventDefault()}>
        <input
          className="input" type="search" enterKeyHint="search" value={text} onChange={(e) => setText(e.target.value)}
          placeholder="Search for a place" aria-label="Search for a place" autoFocus autoComplete="off"
        />
        <button type="button" className={`btn small ${near ? '' : 'soft'}`} onClick={nearMe} disabled={locating} aria-pressed={!!near}>
          {locating ? 'Finding you…' : '📍 Near me'}
        </button>
      </form>
      <p className="small muted add-hint">
        {near ? 'Places near you come first.' : 'Tap “Near me” to see what’s around you first.'} Add a city to look further away.
      </p>

      {!searching ? (
        <div className="card add-start">
          <span className="add-start-mark" aria-hidden="true">🔎</span>
          <div className="grow">
            <strong>Find the place</strong>
            <p className="small muted">Type its name: a café, a shop, a park. At least {MIN_VENUE_QUERY} letters.</p>
          </div>
        </div>
      ) : null}

      {searching && results.isPending ? <Spinner /> : null}
      {searching && results.isError && !data ? <LoadError message={messageOf(results.error)} retry={() => results.refetch()} /> : null}
      {data && data.results.length === 0 && !results.isFetching ? (
        <Empty mark="🤷" title={`Nothing found for “${query}”`} action={<button className="btn" onClick={onHand}>Add it by hand</button>}>
          Check the spelling or add the city. Or put it on the map yourself.
        </Empty>
      ) : null}
      {data && data.results.length > 0 ? (
        <>
          <p className="section-title add-results-title">
            {plural(data.results.length, 'place')}{results.isFetching ? ' · updating…' : ''}
          </p>
          <ul className="list card add-results">
            {data.results.map((result) => {
              const away = near ? distanceText(distanceMeters(near, result.at)) : '';
              return (
                <li key={result.key}>
                  <button className="item" onClick={() => onPick(result)}>
                    <Thumb src={result.photo} mark={categoryOf(result.category).mark} />
                    <span className="grow">
                      <strong className="clip add-result-name">{result.name}</strong>
                      <span className="small muted clip add-result-line">{result.address || categoryOf(result.category).name}</span>
                      <span className="small add-result-meta">
                        {result.source === 'catalog' ? <span className="chip">On FavCircles</span> : <span className="chip gray">{categoryOf(result.category).name}</span>}
                        {away ? <span className="muted"> {away}</span> : null}
                      </span>
                    </span>
                  </button>
                </li>
              );
            })}
          </ul>
          {data.webFailed ? <p className="small muted add-foot">The wider search isn’t answering right now, so only places already on FavCircles are listed.</p> : null}
          {data.hasWebResults ? (
            <p className="small muted add-foot">
              Some results © <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noopener noreferrer">OpenStreetMap</a> contributors
            </p>
          ) : null}
        </>
      ) : null}

      <div className="card add-hand-cta">
        <div className="grow">
          <strong>Can’t find it?</strong>
          <p className="small muted">Type it in and drop a pin on the map.</p>
        </div>
        <button className="btn small soft" onClick={onHand}>Add it by hand</button>
      </div>
      <p className="small muted add-foot"><Link to="/">Back to the map</Link></p>
    </>
  );
}

// ---- step 2: which circle

function CirclePicker({ circles, targets, madeCircle, circleId, lastUsed, onPick, onNew }: {
  circles: { isPending: boolean; isError: boolean; error: unknown; refetch: () => unknown };
  targets: Circle[]; madeCircle: Circle | null; circleId: string | null; lastUsed: string | null;
  onPick: (id: string) => void; onNew: () => void;
}) {
  if (circles.isPending) return <Spinner />;
  if (circles.isError) return <LoadError message={messageOf(circles.error)} retry={() => circles.refetch()} />;
  // A circle made a moment ago shows at once, before the list refreshes
  const list = madeCircle && !targets.some((c) => c._id === madeCircle._id) ? [...targets, madeCircle] : targets;
  return (
    <div className="card add-options">
      {list.length === 0 ? (
        <p className="add-none">You don’t have a circle yet. Make one to save this place in, like “Coffee” or “Date night”.</p>
      ) : null}
      {list.map((c, index) => (
        <label className="radio" key={c._id} style={index === 0 ? { borderTop: 0 } : undefined}>
          <input type="radio" name="circle" checked={circleId === c._id} onChange={() => onPick(c._id)} />
          <span className="grow">
            <strong>{c.name}</strong>
            {c._id === lastUsed ? <span className="chip add-last">used last</span> : null}
            <br />
            <span className="small muted">
              {privacyMark(c.privacy)} {privacyName(c.privacy)}
              {typeof c.placesCount === 'number' ? ` · ${plural(c.placesCount, 'place')}` : ''}
            </span>
          </span>
        </label>
      ))}
      <button className="btn block plain add-new-circle" onClick={onNew}>＋ New circle</button>
    </div>
  );
}
