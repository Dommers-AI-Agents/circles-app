// A place, circle or location shared in a chat: what the sender puts in the
// message, and what a bubble reads back to draw a tappable card. The same
// content and metadata as the iOS app builds
// (ios/Circles-iOS-UIKit/Logic/MessageShareCard.swift), so a card sent from
// the web opens on a phone and the other way round.

export type ShareInput =
  | { kind: 'place'; placeId?: string | null; placeName: string; address?: string | null; photoUrl?: string | null; lat?: number | null; lng?: number | null }
  | { kind: 'circle'; circleId: string; circleName: string; placeCount?: number | null; coverUrl?: string | null };

export interface OutgoingShare {
  type: 'place_share' | 'circle_share';
  /** The line the chat list and the push show */
  content: string;
  metadata: Record<string, string | number>;
}

const isCoordinate = (lat: unknown, lng: unknown): boolean =>
  typeof lat === 'number' && typeof lng === 'number' && Number.isFinite(lat) && Number.isFinite(lng)
  && lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;

export function outgoingShare(share: ShareInput): OutgoingShare {
  if (share.kind === 'place') {
    const metadata: Record<string, string | number> = { placeName: share.placeName };
    if (share.placeId) metadata.placeId = share.placeId;
    if (share.address) metadata.address = share.address;
    if (share.photoUrl) metadata.photoUrl = share.photoUrl;
    if (isCoordinate(share.lat, share.lng)) { metadata.lat = share.lat as number; metadata.lng = share.lng as number; }
    return { type: 'place_share', content: `📍 ${share.placeName}`, metadata };
  }
  const metadata: Record<string, string | number> = { circleId: share.circleId, circleName: share.circleName };
  if (typeof share.placeCount === 'number' && Number.isFinite(share.placeCount)) metadata.placeCount = share.placeCount;
  if (share.coverUrl) metadata.coverUrl = share.coverUrl;
  return { type: 'circle_share', content: `⭕️ ${share.circleName}`, metadata };
}

export interface ShareCard {
  kind: 'place' | 'circle' | 'location';
  title: string;
  subtitle?: string;
  imageUrl?: string;
  /** "📍" / "⭕️" / "📌" */
  symbol: string;
  /** A page in this app */
  path?: string;
  /** A map elsewhere, when there is no page to open (or for a location) */
  mapUrl?: string;
}

const text = (value: unknown): string | undefined => (typeof value === 'string' && value.trim() ? value : undefined);
const numberOf = (value: unknown): number | undefined => {
  if (typeof value === 'number') return Number.isFinite(value) ? value : undefined;
  if (typeof value === 'string' && value.trim() !== '') { const n = Number(value); return Number.isFinite(n) ? n : undefined; }
  return undefined;
};

/** A map anyone can open (most people here are on Android): Google Maps at the pin */
export function mapLink(lat: number, lng: number): string {
  return `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(`${lat},${lng}`)}`;
}

/** The card a received message draws; null when the message isn't a share (or is missing what a card needs). */
export function shareCard(type: string, metadata: Record<string, unknown> | null | undefined): ShareCard | null {
  const m = metadata || {};
  const lat = numberOf(m.lat);
  const lng = numberOf(m.lng);
  const mapUrl = lat !== undefined && lng !== undefined && isCoordinate(lat, lng) ? mapLink(lat, lng) : undefined;
  if (type === 'place_share') {
    const name = text(m.placeName);
    if (!name) return null;
    const id = text(m.placeId);
    return {
      kind: 'place', title: name, subtitle: text(m.address), imageUrl: text(m.photoUrl), symbol: '📍',
      path: id ? `/place/${encodeURIComponent(id)}` : undefined, mapUrl
    };
  }
  if (type === 'circle_share') {
    const id = text(m.circleId);
    const name = text(m.circleName);
    if (!id || !name) return null;
    const count = numberOf(m.placeCount);
    return {
      kind: 'circle', title: name, subtitle: count !== undefined ? `${Math.trunc(count)} ${Math.trunc(count) === 1 ? 'place' : 'places'}` : undefined,
      imageUrl: text(m.coverUrl), symbol: '⭕️', path: `/circle/${encodeURIComponent(id)}`
    };
  }
  if (type === 'location') {
    if (!mapUrl) return null;
    return { kind: 'location', title: 'My location', subtitle: text(m.address), symbol: '📌', mapUrl };
  }
  return null;
}
