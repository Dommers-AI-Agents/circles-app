// The home tab: every place I saved, on a map. Pins are tiered, never
// clustered (logic/pinTiers): only places in view are drawn, and crowded
// ones shrink to dots until you zoom in. "Friends" adds what my network
// saved in the area on screen.
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { keepPreviousData, useQuery } from '@tanstack/react-query';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';
import { myCircles } from '../api/circles';
import { messageOf } from '../api/client';
import { circlesOnMap, friendsPins, myMapPins, type MapPin } from '../api/mapPlaces';
import { useAuth } from '../auth/AuthContext';
import { DEFAULT_CENTER, distanceMeters, distanceText, type LatLng } from '../logic/geo';
import { categoryOf } from '../logic/labels';
import { planPins, type PinCandidate } from '../logic/pinTiers';
import { askPosition, lastPosition, quietPosition } from '../map/location';
import { meIcon, pinIcon, type PinOwner, type PinTier } from '../map/pins';
import { tileLayer } from '../map/tiles';
import { toast } from '../ui/kit';
import './map.css';

interface Drawn {
  marker: L.Marker;
  look: string;
}

interface View {
  center: LatLng;
  radiusM: number;
}

const round = (n: number, step: number) => Math.round(n / step) * step;

export function MapPage() {
  const { userId } = useAuth();
  const navigate = useNavigate();
  const holder = useRef<HTMLDivElement>(null);
  const mapRef = useRef<L.Map | null>(null);
  const drawn = useRef(new Map<string, Drawn>());
  const meMarker = useRef<L.Marker | null>(null);
  const framed = useRef(false);

  const [circleId, setCircleId] = useState<string | null>(null);
  const [friendsOn, setFriendsOn] = useState(false);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [me, setMe] = useState<LatLng | null>(lastPosition());
  const [locating, setLocating] = useState(false);
  const [view, setView] = useState<View | null>(null);
  const [moved, setMoved] = useState(0);
  const [quietDone, setQuietDone] = useState(false);

  const circles = useQuery({ queryKey: ['circles', 'mine'], queryFn: myCircles });
  const onMap = useMemo(() => circlesOnMap(circles.data || []), [circles.data]);
  const circleIds = useMemo(() => onMap.map((c) => c._id), [onMap]);
  const mine = useQuery({
    queryKey: ['map', 'mine', circleIds],
    queryFn: () => myMapPins(circleIds),
    enabled: circles.isSuccess
  });
  const friends = useQuery({
    queryKey: ['map', 'friends', view ? [round(view.center.lat, 0.002), round(view.center.lng, 0.002), round(view.radiusM, 50)] : null],
    queryFn: ({ signal }) => friendsPins(view!.center, view!.radiusM, signal),
    enabled: friendsOn && !!view,
    placeholderData: keepPreviousData,
    staleTime: 60000
  });

  const myPins = useMemo(() => mine.data || [], [mine.data]);
  const circleName = useCallback((id: string | null) => (id ? (onMap.find((c) => c._id === id) || { name: '' }).name : ''), [onMap]);
  // Chips: my circles that have a place on the map, in my own order
  const chips = useMemo(() => {
    const used = new Set(myPins.map((p) => p.circleId));
    return onMap.filter((c) => used.has(c._id));
  }, [onMap, myPins]);
  const shownMine = useMemo(() => (circleId ? myPins.filter((p) => p.circleId === circleId) : myPins), [myPins, circleId]);
  // The network's answer includes my own saves: those are already here
  const shownFriends = useMemo(() => {
    if (!friendsOn || !friends.data) return [];
    const own = new Set(myPins.map((p) => p.id));
    return friends.data.pins.filter((p) => p.addedBy !== userId && !own.has(p.id));
  }, [friendsOn, friends.data, myPins, userId]);

  const pins = useMemo(() => {
    const all = new Map<string, { pin: MapPin; owner: PinOwner }>();
    shownFriends.forEach((pin) => all.set(pin.id, { pin, owner: 'friend' }));
    shownMine.forEach((pin) => all.set(pin.id, { pin, owner: 'mine' }));
    return all;
  }, [shownMine, shownFriends]);
  const selected = selectedId ? pins.get(selectedId) || null : null;

  // ---- the map itself (made once)
  useEffect(() => {
    if (!holder.current || mapRef.current) return undefined;
    const map = L.map(holder.current, { zoomControl: false, attributionControl: true })
      .setView([DEFAULT_CENTER.lat, DEFAULT_CENTER.lng], 12);
    map.attributionControl.setPrefix(false);
    tileLayer().addTo(map);
    L.control.zoom({ position: 'topright' }).addTo(map);
    mapRef.current = map;
    let timer: ReturnType<typeof setTimeout> | undefined;
    const settled = () => {
      setMoved((n) => n + 1);
      // Friends' places are asked for once the map has been still for a moment
      clearTimeout(timer);
      timer = setTimeout(() => {
        const center = map.getCenter();
        const corner = map.getBounds().getNorthEast();
        setView({ center: { lat: center.lat, lng: center.lng }, radiusM: distanceMeters(center, corner) });
      }, 450);
    };
    map.on('moveend zoomend resize', settled);
    map.on('click', () => setSelectedId(null));
    const resize = new ResizeObserver(() => map.invalidateSize());
    resize.observe(holder.current);
    settled();
    const shown = drawn.current;
    return () => {
      clearTimeout(timer);
      resize.disconnect();
      map.remove();
      mapRef.current = null;
      shown.clear();
      meMarker.current = null;
    };
  }, []);

  // ---- where it opens: on me when location is already allowed, else on my
  // places, else on Charlotte (never a permission box on open)
  useEffect(() => {
    let live = true;
    quietPosition().then((position) => {
      if (!live) return;
      if (position) setMe(position);
      setQuietDone(true);
    });
    return () => { live = false; };
  }, []);

  const fit = useCallback((list: MapPin[]) => {
    const map = mapRef.current;
    if (!map || list.length === 0) return;
    map.fitBounds(L.latLngBounds(list.map((p) => [p.at.lat, p.at.lng] as [number, number])), { padding: [48, 48], maxZoom: 15, animate: false });
  }, []);

  useEffect(() => {
    const map = mapRef.current;
    if (!map || framed.current || !quietDone || !mine.isFetched) return;
    framed.current = true;
    if (me) map.setView([me.lat, me.lng], 14, { animate: false });
    else fit(myPins);
  }, [quietDone, mine.isFetched, me, myPins, fit]);

  // ---- my own position
  useEffect(() => {
    const map = mapRef.current;
    if (!map || !me) return;
    if (meMarker.current) meMarker.current.setLatLng([me.lat, me.lng]);
    else meMarker.current = L.marker([me.lat, me.lng], { icon: meIcon(), interactive: false, keyboard: false, zIndexOffset: -1000 }).addTo(map);
  }, [me]);

  // ---- pins: only the ones in view, crowded ones as dots
  useEffect(() => {
    const map = mapRef.current;
    if (!map) return;
    const size = map.getSize();
    const middle = { x: size.x / 2, y: size.y / 2 };
    const candidates: PinCandidate[] = [];
    pins.forEach(({ pin, owner }, id) => {
      const point = map.latLngToContainerPoint([pin.at.lat, pin.at.lng]);
      // Nearest the middle of the map first; my own places ahead of friends'
      const priority = Math.hypot(point.x - middle.x, point.y - middle.y) + (owner === 'friend' ? 100000 : 0);
      candidates.push({ id, x: point.x, y: point.y, priority });
    });
    const plan = planPins(candidates, { width: size.x, height: size.y }, { pinned: selectedId && pins.has(selectedId) ? [selectedId] : [] });
    const tiers = new Map<string, PinTier>();
    plan.dots.forEach((id) => tiers.set(id, 'dot'));
    plan.full.forEach((id) => tiers.set(id, 'full'));

    drawn.current.forEach((entry, id) => {
      if (!tiers.has(id)) {
        entry.marker.remove();
        drawn.current.delete(id);
      }
    });
    tiers.forEach((tier, id) => {
      const { pin, owner } = pins.get(id)!;
      const isSelected = id === selectedId;
      const look = `${tier}|${owner}|${isSelected}|${pin.category}`;
      const icon = pinIcon(pin.category, owner, tier, isSelected);
      const zIndexOffset = isSelected ? 2000 : tier === 'full' ? (owner === 'mine' ? 1000 : 500) : 0;
      const known = drawn.current.get(id);
      if (known) {
        if (known.look !== look) {
          known.marker.setIcon(icon);
          known.marker.setZIndexOffset(zIndexOffset);
          known.look = look;
        }
        return;
      }
      const marker = L.marker([pin.at.lat, pin.at.lng], { icon, title: pin.name, alt: pin.name, keyboard: true, zIndexOffset });
      marker.on('click', (event) => {
        L.DomEvent.stopPropagation(event);
        setSelectedId(id);
      });
      marker.addTo(map);
      drawn.current.set(id, { marker, look });
    });
  }, [pins, selectedId, moved]);

  // A place that is no longer shown (filter changed, friends off) can't stay selected
  useEffect(() => {
    if (selectedId && !pins.has(selectedId)) setSelectedId(null);
  }, [pins, selectedId]);

  const chooseCircle = (id: string | null) => {
    setCircleId(id);
    setSelectedId(null);
    fit(id ? myPins.filter((p) => p.circleId === id) : myPins);
  };

  const locate = async () => {
    setLocating(true);
    try {
      const position = await askPosition();
      setMe(position);
      mapRef.current?.setView([position.lat, position.lng], Math.max(mapRef.current.getZoom(), 15));
    } catch (error) {
      toast(messageOf(error));
    } finally {
      setLocating(false);
    }
  };

  const loading = circles.isPending || (circles.isSuccess && mine.isPending);
  const failed = circles.isError ? circles.error : mine.isError ? mine.error : null;
  const nothingYet = mine.isSuccess && myPins.length === 0;
  const category = selected ? categoryOf(selected.pin.category) : null;
  const away = selected && me ? distanceText(distanceMeters(me, selected.pin.at)) : '';

  return (
    <>
      <header className="head map-head">
        <h1 className="lead">Map</h1>
        <Link className="map-search" to="/search" role="search" aria-label="Search places and people">
          <span aria-hidden="true">🔎</span> Search places and people
        </Link>
      </header>
      <main className="map-main">
        <div className="map-chips" role="toolbar" aria-label="What the map shows">
          <button className={`map-chip friends${friendsOn ? ' on' : ''}`} aria-pressed={friendsOn} onClick={() => setFriendsOn((on) => !on)}>
            👥 Friends
          </button>
          {chips.length > 0 ? (
            <button className={`map-chip${circleId === null ? ' on' : ''}`} aria-pressed={circleId === null} onClick={() => chooseCircle(null)}>All my places</button>
          ) : null}
          {chips.map((c) => (
            <button key={c._id} className={`map-chip${circleId === c._id ? ' on' : ''}`} aria-pressed={circleId === c._id} onClick={() => chooseCircle(c._id)}>
              {c.name}
            </button>
          ))}
        </div>

        <div className="map-stage">
          <div ref={holder} className="map-canvas" aria-label="Map of saved places" />

          <div className="map-notes" aria-live="polite">
            {loading ? <span className="map-note"><span className="map-dot-spin" aria-hidden="true" /> Loading your places…</span> : null}
            {friendsOn && friends.isFetching ? <span className="map-note"><span className="map-dot-spin" aria-hidden="true" /> Looking for friends’ places…</span> : null}
            {friendsOn && friends.isError ? (
              <button className="map-note" onClick={() => friends.refetch()}>Friends’ places didn’t load. Tap to try again.</button>
            ) : null}
            {friendsOn && friends.isSuccess && !friends.isFetching && shownFriends.length === 0 ? (
              <span className="map-note">No friends’ places in this area yet</span>
            ) : null}
            {friendsOn && friends.isSuccess && !friends.isFetching && friends.data.hasMore ? (
              <span className="map-note">Zoom in to see more of your friends’ places</span>
            ) : null}
          </div>

          <div className="map-actions">
            <button className="map-fab plain" onClick={locate} disabled={locating} aria-label="Show where I am">
              {locating ? <span className="map-dot-spin" aria-hidden="true" /> : (
                <svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" aria-hidden="true">
                  <circle cx="12" cy="12" r="3.5" /><path d="M12 2v4m0 12v4M2 12h4m12 0h4" />
                </svg>
              )}
            </button>
            <button className="map-fab" onClick={() => navigate(circleId ? `/add?circle=${encodeURIComponent(circleId)}` : '/add')} aria-label="Add a place">+</button>
          </div>

          <div className="map-bottom">
            {failed ? (
              <div className="card map-card" role="alert">
                <strong>Your places didn’t load</strong>
                <p className="small muted">{messageOf(failed)}</p>
                <button className="btn soft small" onClick={() => (circles.isError ? circles.refetch() : mine.refetch())}>Try again</button>
              </div>
            ) : null}
            {selected && category ? (
              <div className="card map-card" role="dialog" aria-label={selected.pin.name}>
                <div className="row">
                  <span className={`map-card-mark ${selected.owner}`} aria-hidden="true">{category.mark}</span>
                  <div className="grow">
                    <strong className="clip" style={{ display: 'block' }}>{selected.pin.name}</strong>
                    <span className="small muted clip" style={{ display: 'block' }}>
                      {category.name}{away ? ` · ${away} away` : ''}
                    </span>
                  </div>
                  <button className="icon-btn" onClick={() => setSelectedId(null)} aria-label="Close">✕</button>
                </div>
                {selected.pin.address ? <p className="small muted map-card-line">{selected.pin.address}</p> : null}
                <p className="map-card-line">
                  {selected.owner === 'mine'
                    ? <span className="chip">{circleName(selected.pin.circleId) || 'My places'}</span>
                    : <span className="chip gold">Saved by a friend</span>}
                </p>
                <div className="row map-card-buttons">
                  <button className="btn grow" onClick={() => navigate(`/place/${selected.pin.id}`)}>Open</button>
                  <a className="btn soft grow" target="_blank" rel="noopener noreferrer"
                    href={`https://www.google.com/maps/dir/?api=1&destination=${selected.pin.at.lat},${selected.pin.at.lng}`}>Directions</a>
                </div>
              </div>
            ) : null}
            {!selected && !failed && nothingYet ? (
              <div className="card map-card map-first">
                <span className="map-first-mark" aria-hidden="true">📍</span>
                <div className="grow">
                  <strong>Add your first place</strong>
                  <p className="small muted">Save the spots you love and they show up here, on your own map.</p>
                </div>
                <button className="btn small" onClick={() => navigate('/add')}>Add a place</button>
              </div>
            ) : null}
          </div>
        </div>
      </main>
    </>
  );
}
