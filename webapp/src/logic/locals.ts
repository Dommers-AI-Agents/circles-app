// Rules for the Locals tab: which area is shown and how it is said, a
// store's deals as one row, where a store or an event opens, and the small
// lines under an event and a market. Pure. Mirrors the iOS Locals tab
// (Controllers/Home/Tabs/HomeSpecialsViewController.swift).
import type { Announcement, LocalEvent, Market, NearbyVenue, Offer } from '../api/rewards';
import { distanceText } from './geo';
import { eventWhen, priceText } from './eventTime';

/** Where the list is centred: this browser, the account's last known spot, or Charlotte. */
export type AreaSource = 'device' | 'account' | 'default';

export function areaLine(source: AreaSource): string {
  switch (source) {
    case 'device': return 'Showing what’s near you.';
    case 'account': return 'Showing what’s near where you last used FavCircles.';
    default: return 'Showing Charlotte. Use your location to see what’s near you.';
  }
}

// ---- store specials

export type Deal =
  | { kind: 'offer'; key: string; title: string; offer: Offer }
  | { kind: 'announcement'; key: string; title: string; announcement: Announcement };

export interface StoreDeals {
  venue: NearbyVenue;
  deals: Deal[];
}

/**
 * One row per store, in the server's order (saved stores first, then the
 * nearest). A store's rewards first, cheapest first, then what it posted.
 * Stores with nothing to show are left out.
 */
export function storeDeals(venues: NearbyVenue[] | null | undefined): StoreDeals[] {
  return (venues || []).map((venue) => {
    const offers = (venue.offers || [])
      .filter((o) => o && o.title && Number.isFinite(o.pointsCost) && o.pointsCost > 0)
      .slice()
      .sort((a, b) => a.pointsCost - b.pointsCost)
      .map((offer, i): Deal => ({ kind: 'offer', key: `o:${offer.offerId || i}`, title: offer.title, offer }));
    const posts = (venue.announcements || [])
      .filter((a) => a && a.title)
      .map((announcement, i): Deal => ({ kind: 'announcement', key: `a:${announcement.announcementId || i}`, title: announcement.title, announcement }));
    return { venue, deals: [...offers, ...posts] };
  }).filter((row) => row.deals.length > 0);
}

/** "Free drip coffee · 100 points" or the post's title. */
export function dealLine(deal: Deal): string {
  return deal.kind === 'offer' ? `${deal.title} · ${deal.offer.pointsCost} points` : deal.title;
}

/** "Saved · 0.4 mi", "Online store", "1.2 mi" */
export function storeMeta(venue: Pick<NearbyVenue, 'savedByUser' | 'isVirtual' | 'distanceMeters' | 'category'>): string {
  const parts: string[] = [];
  if (venue.savedByUser) parts.push('On your map');
  if (venue.isVirtual) parts.push('Online store');
  else if (typeof venue.distanceMeters === 'number' && Number.isFinite(venue.distanceMeters)) parts.push(distanceText(venue.distanceMeters));
  return parts.join(' · ');
}

// ---- where a row opens

export type StoreTarget =
  | { kind: 'rewards'; venueId: string; globalPlaceId: string | null }
  | { kind: 'place'; globalPlaceId: string }
  | null;

/** An enrolled store opens its rewards; a place that isn't opens its place page. */
export function storeTarget(row: { venueId?: string | null; globalPlaceId?: string | null }): StoreTarget {
  if (row.venueId) return { kind: 'rewards', venueId: row.venueId, globalPlaceId: row.globalPlaceId || null };
  if (row.globalPlaceId) return { kind: 'place', globalPlaceId: row.globalPlaceId };
  return null;
}

/** Only http(s) links leave the app (a source's odd value never becomes a javascript: link). */
export function safeLink(url: string | null | undefined): string | null {
  const text = String(url || '').trim();
  if (!/^https?:\/\//i.test(text)) return null;
  try {
    return new URL(text).toString();
  } catch {
    return null;
  }
}

// ---- events and markets

/** "Today 7:00 PM · Free" */
export function eventWhenLine(event: Pick<LocalEvent, 'startLocalDate' | 'startLocalTime' | 'isFree' | 'priceMin' | 'priceMax' | 'currency'>, todayKey: string): string {
  return [eventWhen(event.startLocalDate, event.startLocalTime, todayKey), priceText(event)].filter(Boolean).join(' · ');
}

/** "ImaginOn · 0.3 mi" */
export function eventWhereLine(event: Pick<LocalEvent, 'venueName' | 'city' | 'distanceMeters'>): string {
  const place = event.venueName || event.city || '';
  const distance = typeof event.distanceMeters === 'number' && Number.isFinite(event.distanceMeters) ? distanceText(event.distanceMeters) : '';
  return [place, distance].filter(Boolean).join(' · ');
}

/** Store events are FavCircles' own; the rest come from a listing source. */
export const isStoreEvent = (event: Pick<LocalEvent, 'source' | 'venueId'>): boolean => event.source === 'store' || !!event.venueId;

/** "Sat 8 AM–12:30 PM · 0.4 mi · SNAP accepted" */
export function marketLine(market: Pick<Market, 'hoursSummary' | 'distanceMeters' | 'acceptsSnap' | 'organic'>): string {
  const parts: string[] = [];
  if (market.hoursSummary) parts.push(market.hoursSummary);
  if (typeof market.distanceMeters === 'number' && Number.isFinite(market.distanceMeters)) parts.push(distanceText(market.distanceMeters));
  if (market.acceptsSnap) parts.push('SNAP accepted');
  if (market.organic) parts.push('Organic');
  return parts.join(' · ');
}

/** A map link for directions: works on any phone, no app needed. */
export function directionsLink(lat: number, lng: number): string | null {
  if (!Number.isFinite(lat) || !Number.isFinite(lng) || (lat === 0 && lng === 0)) return null;
  return `https://www.google.com/maps/dir/?api=1&destination=${lat},${lng}`;
}
