/**
 * Thin HTTP client for the FavCircles backend (Node/Express on Cloud Run).
 * Worker port of ../src/backend.ts — every call forwards the caller's
 * validated bearer token; the backend re-verifies and scopes to that user.
 */

import type { AuthInfo } from "./auth";

export const DEFAULT_API_BASE = "https://api.favcircles.com/api";

export class BackendError extends Error {
  constructor(
    message: string,
    public readonly status: number
  ) {
    super(message);
    this.name = "BackendError";
  }
}

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

export interface UserProfile {
  _id?: string;
  id?: string;
  email?: string;
  displayName?: string;
  firstName?: string;
  lastName?: string;
  profilePicture?: string | null;
  bio?: string | null;
  location?: unknown;
  followersCount?: number;
  followingCount?: number;
  createdAt?: string;
}

export interface Connection {
  _id?: string;
  id?: string;
  status?: string;
  totalPlaces?: number;
  connectedUser?: UserProfile;
  /** Initiator's user id — compare with the caller's to infer direction. */
  userId?: string;
  connectedUserId?: string;
}

export interface Suggestion {
  _id?: string;
  id?: string;
  userId?: string;
  message?: string;
  placeId?: string | null;
  placeDetails?: { name?: string; address?: string; category?: string } | null;
  likesCount?: number;
  createdAt?: string;
  userDetails?: UserProfile;
}

/** Community-wide place record (global_places collection). */
export interface GlobalPlace {
  _id?: string;
  id?: string;
  name: string;
  address?: string;
  category?: string;
  location?: { type: string; coordinates: [number, number] } | null;
  googleData?: { rating?: number; website?: string; phone?: string } | null;
  totalCircleReferences?: number;
  qualityScore?: number;
}

export interface SearchedUser extends UserProfile {
  connectionStatus?: string;
  connectionDirection?: string | null;
  connectionId?: string | null;
  isFollowing?: boolean;
}

export interface ActivityItem {
  type?: string;
  entityName?: string;
  circleName?: string;
  placeName?: string;
  createdAt?: string;
  actor?: { displayName?: string } | null;
  [key: string]: unknown;
}

/** Circle as returned by the network endpoints — enriched with owner/places. */
export interface NetworkCircle extends Circle {
  ownerDetails?: UserProfile;
  placesWithDetails?: Place[];
}

/** Place as returned by the viewport endpoint — enriched with adder info. */
export interface NetworkPlace extends Place {
  addedBy?: string;
  addedByUser?: { id?: string; displayName?: string } | null;
}

export function docId(doc: { _id?: string; id?: string }): string {
  return doc._id || doc.id || "(no id)";
}

export class Backend {
  constructor(
    private readonly auth: AuthInfo,
    private readonly baseUrl: string = DEFAULT_API_BASE
  ) {}

  private async request<T>(method: string, path: string, body?: unknown): Promise<T> {
    const res = await fetch(`${this.baseUrl}${path}`, {
      method,
      headers: {
        Authorization: `Bearer ${this.auth.token}`,
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

  async listCircles(): Promise<Circle[]> {
    const res = await this.request<{ circles?: Circle[]; data?: Circle[] }>("GET", "/circles");
    return res.circles || res.data || [];
  }

  async getCircle(circleId: string): Promise<Circle> {
    const res = await this.request<{ circle?: Circle; data?: Circle }>(
      "GET",
      `/circles/${encodeURIComponent(circleId)}`
    );
    const circle = res.circle || res.data;
    if (!circle) throw new BackendError("Circle not found in response", 404);
    return circle;
  }

  async getPlacesForCircles(circleIds: string[]): Promise<Place[]> {
    if (circleIds.length === 0) return [];
    // The batch endpoint caps at 50 circleIds per request — chunk and merge.
    const chunks: string[][] = [];
    for (let i = 0; i < circleIds.length; i += 50) {
      chunks.push(circleIds.slice(i, i + 50));
    }
    const results = await Promise.all(
      chunks.map((chunk) =>
        this.request<{ places?: Place[]; data?: Place[] }>("POST", "/places/batch", { circleIds: chunk })
      )
    );
    return results.flatMap((res) => res.places || res.data || []);
  }

  async createCircle(input: {
    name: string;
    description?: string;
    category?: string;
    privacy?: string;
  }): Promise<Circle> {
    const res = await this.request<{ circle?: Circle; data?: Circle }>("POST", "/circles", input);
    const circle = res.circle || res.data;
    if (!circle) throw new BackendError("Circle create succeeded but no circle in response", 500);
    return circle;
  }

  async updateCircle(
    circleId: string,
    updates: { name?: string; description?: string; category?: string; privacy?: string }
  ): Promise<Circle> {
    const res = await this.request<{ circle?: Circle; data?: Circle }>(
      "PUT",
      `/circles/${encodeURIComponent(circleId)}`,
      updates
    );
    const circle = res.circle || res.data;
    if (!circle) throw new BackendError("Circle update succeeded but no circle in response", 500);
    return circle;
  }

  /** Hard-deletes the circle AND every place in it (backend batch delete). */
  async deleteCircle(circleId: string): Promise<void> {
    await this.request("DELETE", `/circles/${encodeURIComponent(circleId)}`);
  }

  async updatePlace(
    placeId: string,
    updates: { name?: string; address?: string; category?: string; publicNotes?: string; privateNotes?: string }
  ): Promise<Place> {
    const res = await this.request<{ place?: Place; data?: Place }>(
      "PUT",
      `/places/${encodeURIComponent(placeId)}`,
      updates
    );
    const place = res.place || res.data;
    if (!place) throw new BackendError("Place update succeeded but no place in response", 500);
    return place;
  }

  /** Soft delete (deletedAt) — recoverable server-side, invisible in the app. */
  async deletePlace(placeId: string): Promise<void> {
    await this.request("DELETE", `/places/${encodeURIComponent(placeId)}`);
  }

  // ---- trash (per-user; retained until permanently deleted) ----

  async listTrash(): Promise<{ circles: Circle[]; places: Place[] }> {
    const res = await this.request<{ circles?: Circle[]; places?: Place[] }>("GET", "/trash");
    return { circles: res.circles || [], places: res.places || [] };
  }

  async restoreCircle(circleId: string): Promise<{ message: string; restoredPlaces?: number }> {
    return this.request("POST", `/trash/circles/${encodeURIComponent(circleId)}/restore`);
  }

  async permanentDeleteCircle(circleId: string): Promise<{ message: string }> {
    return this.request("DELETE", `/trash/circles/${encodeURIComponent(circleId)}`);
  }

  async restorePlace(placeId: string): Promise<{ message: string }> {
    return this.request("POST", `/trash/places/${encodeURIComponent(placeId)}/restore`);
  }

  async permanentDeletePlace(placeId: string): Promise<{ message: string }> {
    return this.request("DELETE", `/trash/places/${encodeURIComponent(placeId)}`);
  }

  // ---- current user & social graph (read-only network endpoints) ----

  async getMe(): Promise<UserProfile> {
    const res = await this.request<{ user?: UserProfile; data?: UserProfile }>("GET", "/auth/me");
    const user = res.user || res.data;
    if (!user) throw new BackendError("No user in /auth/me response", 500);
    return user;
  }

  async getConnections(): Promise<Connection[]> {
    const res = await this.request<{ connections?: Connection[]; data?: Connection[] }>("GET", "/connections");
    return res.connections || res.data || [];
  }

  /** Circles (public/myNetwork) owned by the user's accepted connections. No place details. */
  async getMyNetworkCircles(): Promise<NetworkCircle[]> {
    const res = await this.request<{ data?: NetworkCircle[]; circles?: NetworkCircle[] }>(
      "GET",
      "/network/my-network-circles"
    );
    return res.data || res.circles || [];
  }

  /** A connection's visible circles WITH place details. 403 if not connected/following. */
  async getUserCircles(userId: string): Promise<{ user?: UserProfile; circles: NetworkCircle[] }> {
    const res = await this.request<{ data?: { user?: UserProfile; circles?: NetworkCircle[] } }>(
      "GET",
      `/network/user-circles/${encodeURIComponent(userId)}`
    );
    return { user: res.data?.user, circles: res.data?.circles || [] };
  }

  /** Network places within a radius of a point, nearest first, with adder attribution. */
  async getNetworkPlacesInViewport(params: {
    centerLat: number;
    centerLng: number;
    radiusM: number;
    limit?: number;
  }): Promise<NetworkPlace[]> {
    const qs = new URLSearchParams({
      centerLat: String(params.centerLat),
      centerLng: String(params.centerLng),
      radiusM: String(params.radiusM),
      ...(params.limit ? { limit: String(params.limit) } : {}),
    });
    const res = await this.request<{ places?: NetworkPlace[] }>("GET", `/network/places/viewport?${qs}`);
    return res.places || [];
  }

  // ---- suggestions, discovery, people, activity ----

  /** Suggestions feed: the user's own + their accepted connections', newest first. */
  async getNetworkSuggestions(): Promise<Suggestion[]> {
    const res = await this.request<{ data?: Suggestion[] }>("GET", "/suggestions/network");
    return res.data || [];
  }

  /** Broadcast a suggestion to the user's whole network (notifies all connections). */
  async createSuggestion(input: { message: string; placeId?: string }): Promise<Suggestion> {
    const res = await this.request<{ data?: Suggestion }>("POST", "/suggestions", input);
    if (!res.data) throw new BackendError("Suggestion created but no data in response", 500);
    return res.data;
  }

  /** Search the community-wide global_places collection (quality-ranked, optional geo filter). */
  async searchGlobalPlaces(params: {
    query?: string;
    category?: string;
    lat?: number;
    lng?: number;
    radiusKm?: number;
    limit?: number;
  }): Promise<GlobalPlace[]> {
    const qs = new URLSearchParams();
    if (params.query) qs.set("query", params.query);
    if (params.category) qs.set("category", params.category);
    if (params.lat != null && params.lng != null) {
      qs.set("lat", String(params.lat));
      qs.set("lng", String(params.lng));
      if (params.radiusKm != null) qs.set("radius", String(params.radiusKm));
    }
    if (params.limit) qs.set("limit", String(params.limit));
    const res = await this.request<{ data?: GlobalPlace[] }>("GET", `/places/global/search?${qs}`);
    return res.data || [];
  }

  async searchUsers(query: string): Promise<SearchedUser[]> {
    const res = await this.request<{ users?: SearchedUser[] }>(
      "GET",
      `/users/search?query=${encodeURIComponent(query)}`
    );
    return res.users || [];
  }

  /** 201 on new request; backend returns 200 "Already connected" / 409 "already pending". */
  async sendConnectionInvite(targetUserId: string, message?: string): Promise<Connection> {
    const res = await this.request<{ data?: Connection }>("POST", "/connections/invite", {
      targetUserId,
      ...(message ? { message } : {}),
    });
    return res.data || {};
  }

  async acceptConnection(connectionId: string): Promise<Connection> {
    const res = await this.request<{ data?: Connection }>(
      "POST",
      `/connections/${encodeURIComponent(connectionId)}/accept`
    );
    return res.data || {};
  }

  async declineConnection(connectionId: string): Promise<void> {
    await this.request("DELETE", `/connections/${encodeURIComponent(connectionId)}/decline`);
  }

  /** Lightweight home feed: ≤10 recent network activities + online users. */
  async getHomescreen(): Promise<{ recentActivities: ActivityItem[]; userList: UserProfile[] }> {
    const res = await this.request<{
      data?: { recentActivities?: ActivityItem[]; userList?: UserProfile[] };
    }>("GET", "/home/homescreen");
    return { recentActivities: res.data?.recentActivities || [], userList: res.data?.userList || [] };
  }

  async createPlace(input: {
    circleId: string;
    name: string;
    address: string;
    category: string;
    latitude: number;
    longitude: number;
    notes?: string;
  }): Promise<Place> {
    const body = {
      circleId: input.circleId,
      name: input.name,
      address: input.address,
      category: input.category,
      location: { type: "Point", coordinates: [input.longitude, input.latitude] },
      ...(input.notes ? { publicNotes: input.notes } : {}),
    };
    const res = await this.request<{ place?: Place; data?: Place }>("POST", "/places", body);
    const place = res.place || res.data;
    if (!place) throw new BackendError("Place create succeeded but no place in response", 500);
    return place;
  }
}
