// Add Place "by hand": a small map the person taps to put the place's pin.
// The pin can be dragged too. Same tiles and pin look as the map tab.
import { useEffect, useRef } from 'react';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';
import type { LatLng } from '../logic/geo';
import { dropIcon } from './pins';
import { tileLayer } from './tiles';

export function HandMap({ start, pin, onPin }: { start: LatLng; pin: LatLng | null; onPin: (at: LatLng) => void }) {
  const holder = useRef<HTMLDivElement>(null);
  const mapRef = useRef<L.Map | null>(null);
  const marker = useRef<L.Marker | null>(null);
  const report = useRef(onPin);
  report.current = onPin;

  useEffect(() => {
    if (!holder.current || mapRef.current) return undefined;
    const map = L.map(holder.current, { zoomControl: true, attributionControl: true })
      .setView([start.lat, start.lng], 16);
    map.attributionControl.setPrefix(false);
    tileLayer().addTo(map);
    map.on('click', (event: L.LeafletMouseEvent) => report.current({ lat: event.latlng.lat, lng: event.latlng.lng }));
    mapRef.current = map;
    const resize = new ResizeObserver(() => map.invalidateSize());
    resize.observe(holder.current);
    return () => {
      resize.disconnect();
      map.remove();
      mapRef.current = null;
      marker.current = null;
    };
    // The map is made once; a later start moves it (below)
  }, []);

  // A new starting point (the person allowed location) moves the map while no pin is down
  useEffect(() => {
    if (mapRef.current && !marker.current) mapRef.current.setView([start.lat, start.lng], Math.max(mapRef.current.getZoom(), 16));
  }, [start.lat, start.lng]);

  useEffect(() => {
    const map = mapRef.current;
    if (!map) return;
    if (!pin) {
      marker.current?.remove();
      marker.current = null;
      return;
    }
    if (marker.current) {
      marker.current.setLatLng([pin.lat, pin.lng]);
      return;
    }
    const placed = L.marker([pin.lat, pin.lng], { icon: dropIcon(), draggable: true, keyboard: false, title: 'The place' });
    placed.on('dragend', () => {
      const at = placed.getLatLng();
      report.current({ lat: at.lat, lng: at.lng });
    });
    placed.addTo(map);
    marker.current = placed;
  }, [pin]);

  return <div ref={holder} className="add-handmap" aria-label="Map: tap where the place is" />;
}
