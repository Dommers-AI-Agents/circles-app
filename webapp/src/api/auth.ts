import { api } from './client';
import type { SessionResponse } from './types';

// Sign-in calls are `anonymous`: a 401 here means a wrong password or code,
// not a sign-in that ran out.
export const startEmailCode = (email: string) =>
  api<{ newAccount: boolean }>('POST', '/auth/email-code/start', { body: { email }, anonymous: true });

export const verifyEmailCode = (email: string, code: string, displayName?: string) =>
  api<SessionResponse>('POST', '/auth/email-code/verify', {
    body: { email, code, ...(displayName ? { displayName } : {}), signupSource: 'web_app' },
    anonymous: true
  });

export const passwordLogin = (email: string, password: string) =>
  api<SessionResponse>('POST', '/auth/login', { body: { email, password }, anonymous: true });

export const forgotPassword = (email: string) =>
  api<{ message?: string }>('POST', '/auth/forgot-password', { body: { email }, anonymous: true });
