// One way to call the API. Same origin as the page, so no CORS. Every call
// carries the sign-in and `X-FC-Inner-Circle: 1`: without that header the
// server relabels Inner Circle privacy as "private", and an edit that sent
// the label back would downgrade it.
import { getSession, setSession } from '../auth/session';

export class ApiError extends Error {
  status: number;
  code?: string;
  body: Record<string, unknown>;
  constructor(status: number, message: string, body: Record<string, unknown> = {}) {
    super(message);
    this.status = status;
    this.code = typeof body.code === 'string' ? body.code : undefined;
    this.body = body;
  }
}

type Query = Record<string, string | number | boolean | undefined | null>;

interface Options {
  query?: Query;
  body?: unknown;
  signal?: AbortSignal;
  /** Sign-in calls: a 401 is "wrong code", not "your sign-in ran out" */
  anonymous?: boolean;
}

const withQuery = (path: string, query?: Query): string => {
  if (!query) return path;
  const params = new URLSearchParams();
  Object.entries(query).forEach(([key, value]) => {
    if (value !== undefined && value !== null && value !== '') params.set(key, String(value));
  });
  const text = params.toString();
  return text ? `${path}?${text}` : path;
};

export const authHeaders = (): Record<string, string> => {
  const session = getSession();
  return session ? { Authorization: `Bearer ${session.token}` } : {};
};

export async function api<T = unknown>(method: string, path: string, options: Options = {}): Promise<T> {
  const headers: Record<string, string> = { 'X-FC-Inner-Circle': '1', ...(options.anonymous ? {} : authHeaders()) };
  if (options.body !== undefined) headers['Content-Type'] = 'application/json';
  let response: Response;
  try {
    response = await fetch(withQuery(`/api${path}`, options.query), {
      method,
      headers,
      body: options.body !== undefined ? JSON.stringify(options.body) : undefined,
      signal: options.signal
    });
  } catch (error) {
    if ((error as Error).name === 'AbortError') throw error;
    throw new ApiError(0, "You're offline. Check your connection and try again.");
  }
  let json: Record<string, unknown> = {};
  try {
    json = await response.json();
  } catch {
    json = {};
  }
  if (!response.ok || json.success === false) {
    // The 30-day sign-in ran out (or was revoked): back to the sign-in page
    if (response.status === 401 && !options.anonymous) setSession(null);
    const message = (json.message as string) || (json.error as string)
      || (response.status === 429 ? 'Too many tries. Wait a few minutes and try again.' : 'Something went wrong. Please try again.');
    throw new ApiError(response.status, message, json);
  }
  return json as T;
}

export const get = <T = unknown>(path: string, query?: Query, signal?: AbortSignal) => api<T>('GET', path, { query, signal });
export const post = <T = unknown>(path: string, body?: unknown) => api<T>('POST', path, { body: body === undefined ? {} : body });
export const put = <T = unknown>(path: string, body?: unknown) => api<T>('PUT', path, { body: body === undefined ? {} : body });
export const del = <T = unknown>(path: string, body?: unknown) => api<T>('DELETE', path, { body });

export const messageOf = (error: unknown): string =>
  error instanceof Error ? error.message : 'Something went wrong. Please try again.';
