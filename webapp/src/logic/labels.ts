// Words and marks for the server's ids: privacy tiers and place categories.
// Mirrors the iOS app (Models/Place.swift PlaceCategory, the privacy pickers).
import type { PlacePrivacy, Privacy } from '../api/types';

export const PRIVACY: { id: Privacy; name: string; detail: string; mark: string }[] = [
  { id: 'public', name: 'Public', detail: 'Anyone can see it', mark: '🌍' },
  { id: 'myNetwork', name: 'My Network', detail: 'Only people you are connected with', mark: '👥' },
  { id: 'innerCircle', name: 'Inner Circle', detail: 'Only the people on your Inner Circle list', mark: '💛' },
  { id: 'private', name: 'Private', detail: 'Only you', mark: '🔒' }
];

export const privacyName = (privacy: PlacePrivacy | undefined): string => {
  if (!privacy || privacy === 'followCircle') return "Same as its circle";
  return (PRIVACY.find((p) => p.id === privacy) || PRIVACY[0]).name;
};
export const privacyMark = (privacy: PlacePrivacy | undefined): string =>
  (PRIVACY.find((p) => p.id === privacy) || { mark: '' }).mark;

export const CATEGORIES: { id: string; name: string; mark: string }[] = [
  { id: 'restaurant', name: 'Restaurant', mark: '🍽️' },
  { id: 'cafe', name: 'Café', mark: '☕' },
  { id: 'bar', name: 'Bar', mark: '🍸' },
  { id: 'hotel', name: 'Hotel', mark: '🛏️' },
  { id: 'retail', name: 'Shop', mark: '🛍️' },
  { id: 'service', name: 'Service', mark: '🧰' },
  { id: 'attraction', name: 'Attraction', mark: '🎡' },
  { id: 'entertainment', name: 'Entertainment', mark: '🎭' },
  { id: 'healthcare', name: 'Healthcare', mark: '🩺' },
  { id: 'fitness', name: 'Fitness', mark: '🏋️' },
  { id: 'education', name: 'Education', mark: '🎓' },
  { id: 'outdoor', name: 'Outdoors', mark: '🌲' },
  { id: 'transport', name: 'Transport', mark: '🚉' },
  { id: 'finance', name: 'Finance', mark: '🏦' },
  { id: 'home', name: 'Home', mark: '🏠' },
  { id: 'work', name: 'Work', mark: '💼' },
  { id: 'other', name: 'Other', mark: '📍' }
];
const OTHER = CATEGORIES[CATEGORIES.length - 1];
export const categoryOf = (id: string | undefined | null) => CATEGORIES.find((c) => c.id === id) || OTHER;

export const plural = (n: number, one: string, many = `${one}s`): string => `${n} ${n === 1 ? one : many}`;

/** "2 min ago", "3 h ago", "Tue", "Nov 3" */
export function timeAgo(iso: string | undefined | null, now = Date.now()): string {
  const then = iso ? Date.parse(iso) : NaN;
  if (Number.isNaN(then)) return '';
  const seconds = Math.max(0, Math.round((now - then) / 1000));
  if (seconds < 60) return 'Just now';
  if (seconds < 3600) return `${Math.floor(seconds / 60)} min ago`;
  if (seconds < 86400) return `${Math.floor(seconds / 3600)} h ago`;
  const date = new Date(then);
  if (seconds < 6 * 86400) return date.toLocaleDateString(undefined, { weekday: 'short' });
  const sameYear = date.getFullYear() === new Date(now).getFullYear();
  return date.toLocaleDateString(undefined, sameYear ? { month: 'short', day: 'numeric' } : { month: 'short', day: 'numeric', year: 'numeric' });
}
