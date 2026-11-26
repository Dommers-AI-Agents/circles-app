import { del, get, post, put } from './client';
import type { Circle, Place, Privacy, User } from './types';

/** My circles, in the order I arranged them on my profile. Never re-sorted. */
export const myCircles = () => get<{ circles: Circle[] }>('/circles/me').then((r) => r.circles || []);

export const circle = (id: string) => get<{ circle: Circle }>(`/circles/${encodeURIComponent(id)}`).then((r) => r.circle);

/** A circle's places, in the circle's own order. */
export const circlePlaces = (id: string) =>
  get<{ places: Place[] }>(`/circles/${encodeURIComponent(id)}/places`).then((r) => r.places || []);

export interface CircleInput {
  name: string;
  description?: string;
  privacy: Privacy;
  category?: string;
  showOnMap?: boolean;
}

export const createCircle = (input: CircleInput) => post<{ circle: Circle }>('/circles', input).then((r) => r.circle);

/** Send only what the person changed: an untouched privacy must never be written back. */
export const updateCircle = (id: string, changes: Partial<CircleInput>) =>
  put<{ circle: Circle }>(`/circles/${encodeURIComponent(id)}`, changes).then((r) => r.circle);

/** Moves the circle to the trash (it can be restored from the app). */
export const deleteCircle = (id: string) => del<{ message: string }>(`/circles/${encodeURIComponent(id)}`);

/** Someone's profile: who they are and the circles this viewer may open or see locked. */
export const userProfile = (userId: string) =>
  get<{ data: { user: User; circles: Circle[] } }>(`/network/user-circles/${encodeURIComponent(userId)}`, { includeLocked: 1 })
    .then((r) => r.data);
