/**
 * Thin HTTP client for the FavCircles backend (Node/Express on Cloud Run).
 *
 * Every call takes the caller's validated AuthInfo (see auth.ts) and forwards
 * its bearer token — the backend's `protect` middleware re-verifies it and
 * scopes all queries to that user. Per-request tokens keep this module ready
 * for the Phase 3 Worker, where each HTTP request carries its own token.
 */

import type { AuthInfo } from "./auth.js";

const BASE_URL = (process.env.FAVCIRCLES_API || "https://api.favcircles.com/api").replace(/\/$/, "");

export class BackendError extends Error {
  constructor(
    message: string,
    public readonly status: number
  ) {
    super(message);
    this.name = "BackendError";
  }
}

async function request<T>(auth: AuthInfo, method: string, path: string, body?: unknown): Promise<T> {
  const res = await fetch(`${BASE_URL}${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${auth.token}`,
      "Content-Type": "application/json",
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });

  let json: any = {};
  try {
    json = await res.json();
  } catch {
    /* non-JSON error body */
  }

  if (!res.ok) {
    let message = json?.message || json?.error || `Backend returned HTTP ${res.status}`;
    if (Array.isArray(json?.errors) && json.errors.length > 0) {
      message += ` (${json.errors.join("; ")})`;
    }
    throw new BackendError(message, res.status);
  }
  return json as T;
}

// ---- Types (subset of backend fields the tools use) ----

export interface Circle {
  _id?: string;
  id?: string;
  name: string;
  description?: string | null;
  category?: string;
  privacy?: string;
  placesCount?: number;
  owner?: string;
  createdAt?: string;
}

export interface Place {
  _id?: string;
  id?: string;
  name: string;
  address?: string;
  category?: string;
  circleId?: string;
  notes?: string | null;
  publicNotes?: string | null;
  privateNotes?: string | null;
  rating?: number | null;
  website?: string | null;
  phone?: string | null;
  location?: { type: string; coordinates: [number, number] } | null;
}

export function docId(doc: { _id?: string; id?: string }): string {
  return doc._id || doc.id || "(no id)";
}

// ---- API calls (all verified against the deployed backend) ----

export async function listCircles(auth: AuthInfo): Promise<Circle[]> {
  const res = await request<{ success: boolean; circles?: Circle[]; data?: Circle[] }>(auth, "GET", "/circles");
  return res.circles || res.data || [];
}

export async function getCircle(auth: AuthInfo, circleId: string): Promise<Circle> {
  const res = await request<{ success: boolean; circle?: Circle; data?: Circle }>(
    auth,
    "GET",
    `/circles/${encodeURIComponent(circleId)}`
  );
  const circle = res.circle || res.data;
  if (!circle) throw new BackendError("Circle not found in response", 404);
  return circle;
}

export async function getPlacesForCircles(auth: AuthInfo, circleIds: string[]): Promise<Place[]> {
  if (circleIds.length === 0) return [];
  // The batch endpoint caps at 50 circleIds per request — chunk and merge.
  const chunks: string[][] = [];
  for (let i = 0; i < circleIds.length; i += 50) {
    chunks.push(circleIds.slice(i, i + 50));
  }
  const results = await Promise.all(
    chunks.map((chunk) =>
      request<{ success: boolean; places?: Place[]; data?: Place[] }>(auth, "POST", "/places/batch", {
        circleIds: chunk,
      })
    )
  );
  return results.flatMap((res) => res.places || res.data || []);
}

export async function createCircle(
  auth: AuthInfo,
  input: {
    name: string;
    description?: string;
    category?: string;
    privacy?: string;
  }
): Promise<Circle> {
  const res = await request<{ success: boolean; circle?: Circle; data?: Circle }>(auth, "POST", "/circles", input);
  const circle = res.circle || res.data;
  if (!circle) throw new BackendError("Circle create succeeded but no circle in response", 500);
  return circle;
}

export async function updateCircle(
  auth: AuthInfo,
  circleId: string,
  updates: { name?: string; description?: string; category?: string; privacy?: string }
): Promise<Circle> {
  const res = await request<{ circle?: Circle; data?: Circle }>(
    auth,
    "PUT",
    `/circles/${encodeURIComponent(circleId)}`,
    updates
  );
  const circle = res.circle || res.data;
  if (!circle) throw new BackendError("Circle update succeeded but no circle in response", 500);
  return circle;
}

/** Hard-deletes the circle AND every place in it (backend batch delete). */
export async function deleteCircle(auth: AuthInfo, circleId: string): Promise<void> {
  await request(auth, "DELETE", `/circles/${encodeURIComponent(circleId)}`);
}

export async function updatePlace(
  auth: AuthInfo,
  placeId: string,
  updates: { name?: string; address?: string; category?: string; publicNotes?: string; privateNotes?: string }
): Promise<Place> {
  const res = await request<{ place?: Place; data?: Place }>(
    auth,
    "PUT",
    `/places/${encodeURIComponent(placeId)}`,
    updates
  );
  const place = res.place || res.data;
  if (!place) throw new BackendError("Place update succeeded but no place in response", 500);
  return place;
}

/** Soft delete (deletedAt) — recoverable server-side, invisible in the app. */
export async function deletePlace(auth: AuthInfo, placeId: string): Promise<void> {
  await request(auth, "DELETE", `/places/${encodeURIComponent(placeId)}`);
}

// ---- trash (per-user; retained until permanently deleted) ----

export async function listTrash(auth: AuthInfo): Promise<{ circles: Circle[]; places: Place[] }> {
  const res = await request<{ circles?: Circle[]; places?: Place[] }>(auth, "GET", "/trash");
  return { circles: res.circles || [], places: res.places || [] };
}

export async function restoreCircle(auth: AuthInfo, circleId: string): Promise<{ message: string }> {
  return request(auth, "POST", `/trash/circles/${encodeURIComponent(circleId)}/restore`);
}

export async function permanentDeleteCircle(auth: AuthInfo, circleId: string): Promise<{ message: string }> {
  return request(auth, "DELETE", `/trash/circles/${encodeURIComponent(circleId)}`);
}

export async function restorePlace(auth: AuthInfo, placeId: string): Promise<{ message: string }> {
  return request(auth, "POST", `/trash/places/${encodeURIComponent(placeId)}/restore`);
}

export async function permanentDeletePlace(auth: AuthInfo, placeId: string): Promise<{ message: string }> {
  return request(auth, "DELETE", `/trash/places/${encodeURIComponent(placeId)}`);
}

export async function createPlace(
  auth: AuthInfo,
  input: {
    circleId: string;
    name: string;
    address: string;
    category: string;
    latitude: number;
    longitude: number;
    notes?: string;
  }
): Promise<Place> {
  const body = {
    circleId: input.circleId,
    name: input.name,
    address: input.address,
    category: input.category,
    location: { type: "Point", coordinates: [input.longitude, input.latitude] },
    ...(input.notes ? { publicNotes: input.notes } : {}),
  };
  const res = await request<{ success: boolean; place?: Place; data?: Place }>(auth, "POST", "/places", body);
  const place = res.place || res.data;
  if (!place) throw new BackendError("Place create succeeded but no place in response", 500);
  return place;
}
