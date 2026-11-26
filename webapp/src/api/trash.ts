import { del, get, post } from './client';
import type { Circle, Place } from './types';

export interface Trash {
  circles: (Circle & { deletedAt?: string })[];
  places: (Place & { deletedAt?: string })[];
}

export const trash = () => get<Trash>('/trash').then((r) => ({ circles: r.circles || [], places: r.places || [] }));
/** Brings a circle back with the places that went to the trash with it. */
export const restoreCircle = (id: string) => post(`/trash/circles/${encodeURIComponent(id)}/restore`);
export const restorePlace = (id: string) => post(`/trash/places/${encodeURIComponent(id)}/restore`);
export const deleteCircleForever = (id: string) => del(`/trash/circles/${encodeURIComponent(id)}`);
export const deletePlaceForever = (id: string) => del(`/trash/places/${encodeURIComponent(id)}`);
