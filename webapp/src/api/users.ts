import { get, put } from './client';
import type { User } from './types';

export const me = () => get<{ user: User }>('/users/me').then((r) => r.user);

export interface ProfileChanges {
  displayName?: string;
  bio?: string;
  zipcode?: string;
  profilePicture?: string;
}
export const updateMe = (changes: ProfileChanges) => put<{ user?: User } & Partial<User>>('/users/me', changes);
