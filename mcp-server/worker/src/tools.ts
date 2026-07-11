/**
 * Tool registration — Worker port of ../src/server.ts's tool set.
 *
 * buildServer() is called per request with the already-validated AuthInfo, so
 * every tool handler closes over the authenticated user. Stateless by design:
 * an McpServer instance is cheap to construct and nothing persists between
 * requests.
 *
 * ChatGPT Apps SDK compatibility: every tool declares title, outputSchema,
 * annotations (readOnlyHint/destructiveHint/idempotentHint/openWorldHint —
 * reviewed at App Directory submission), and openai/toolInvocation status
 * strings. Results carry structuredContent (validated against outputSchema by
 * the SDK) alongside a text narration. Error results are exempt from output
 * validation, so err() stays text-only.
 */

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";
import { AuthError, AuthInfo } from "./auth";
import {
  Backend,
  BackendError,
  Circle,
  NetworkCircle,
  NetworkPlace,
  Place,
  UserProfile,
  docId,
} from "./backend";

// Backend enums (from backend/models/FirestoreModels.js validators)
const PLACE_CATEGORIES = [
  "restaurant", "cafe", "bar", "hotel", "retail", "service", "attraction",
  "entertainment", "healthcare", "fitness", "education", "outdoor",
  "transport", "finance", "home", "work", "other",
] as const;
const CIRCLE_CATEGORIES = [
  "travel", "food", "services", "shopping", "healthcare", "entertainment", "other",
] as const;
const PRIVACY_LEVELS = ["public", "myNetwork", "private"] as const;

// ---- structured output shapes ----------------------------------------------

const CIRCLE_OUT = z.object({
  id: z.string(),
  name: z.string(),
  category: z.string(),
  privacy: z.string(),
  placesCount: z.number().nullable(),
  description: z.string().nullable(),
});
type CircleOut = z.infer<typeof CIRCLE_OUT>;

const PLACE_OUT = z.object({
  id: z.string(),
  name: z.string(),
  category: z.string().nullable(),
  address: z.string().nullable(),
  circleId: z.string().nullable(),
  circleName: z.string().nullable(),
  notes: z.string().nullable(),
  rating: z.number().nullable(),
  website: z.string().nullable(),
  phone: z.string().nullable(),
  latitude: z.number().nullable(),
  longitude: z.number().nullable(),
});
type PlaceOut = z.infer<typeof PLACE_OUT>;

function circleStruct(c: Circle): CircleOut {
  return {
    id: docId(c),
    name: c.name,
    category: c.category || "other",
    privacy: c.privacy || "myNetwork",
    placesCount: c.placesCount ?? null,
    description: c.description || null,
  };
}

function placeStruct(p: Place, circleName?: string): PlaceOut {
  const [lng, lat] = p.location?.coordinates ?? [null, null];
  return {
    id: docId(p),
    name: p.name,
    category: p.category || null,
    address: p.address || null,
    circleId: p.circleId || null,
    circleName: circleName ?? null,
    notes: p.publicNotes || p.notes || null,
    rating: p.rating ?? null,
    website: p.website || null,
    phone: p.phone || null,
    latitude: lat,
    longitude: lng,
  };
}

const RECOMMENDATION_OUT = z.object({
  id: z.string(),
  name: z.string(),
  category: z.string().nullable(),
  address: z.string().nullable(),
  notes: z.string().nullable(),
  rating: z.number().nullable(),
  latitude: z.number().nullable(),
  longitude: z.number().nullable(),
  circleName: z.string().nullable(),
  recommendedById: z.string().nullable(),
  recommendedByName: z.string().nullable(),
});
type RecommendationOut = z.infer<typeof RECOMMENDATION_OUT>;

/** User `location` can be a string or a loose object — flatten to display text. */
function locationText(loc: unknown): string | null {
  if (typeof loc === "string" && loc.trim()) return loc;
  if (loc && typeof loc === "object" && !Array.isArray(loc)) {
    const parts = ["city", "state", "country"]
      .map((k) => (loc as Record<string, unknown>)[k])
      .filter((v): v is string => typeof v === "string" && v.trim().length > 0);
    if (parts.length > 0) return parts.join(", ");
  }
  return null;
}

/** Loose place-identity key for cross-user overlap matching. */
function placeKey(name: string): string {
  return name.toLowerCase().replace(/[^a-z0-9]/g, "");
}

function distanceMeters(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R = 6371000;
  const toRad = (d: number) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) ** 2 + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
}

// ---- tool annotations (reviewed at ChatGPT App Directory submission) --------

const READ = { readOnlyHint: true, openWorldHint: false };
const CREATE = { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false };
const UPDATE = { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false };
const DESTRUCTIVE = { readOnlyHint: false, destructiveHint: true, idempotentHint: true, openWorldHint: false };

/** ChatGPT invocation status strings (≤64 chars each). Ignored by other hosts. */
function inv(invoking: string, invoked: string): Record<string, unknown> {
  return {
    "openai/toolInvocation/invoking": invoking,
    "openai/toolInvocation/invoked": invoked,
  };
}

// ---- result helpers ---------------------------------------------------------

type ToolResult = {
  content: { type: "text"; text: string }[];
  structuredContent?: Record<string, unknown>;
  isError?: boolean;
};

function ok(text: string, structured?: Record<string, unknown>): ToolResult {
  return { content: [{ type: "text", text }], ...(structured ? { structuredContent: structured } : {}) };
}

function err(e: unknown): ToolResult {
  const message = e instanceof Error ? e.message : String(e);
  const prefix = e instanceof AuthError ? "Auth error" : "Error";
  return { content: [{ type: "text", text: `${prefix}: ${message}` }], isError: true };
}

function formatCircle(c: Circle): string {
  const parts = [
    `- ${c.name} (id: ${docId(c)})`,
    `  category: ${c.category || "other"} | privacy: ${c.privacy || "myNetwork"} | places: ${c.placesCount ?? "?"}`,
  ];
  if (c.description) parts.push(`  description: ${c.description}`);
  return parts.join("\n");
}

function formatPlace(p: Place): string {
  const bits: string[] = [`- ${p.name} (id: ${docId(p)})`];
  const meta = [p.category, p.address].filter(Boolean).join(" | ");
  if (meta) bits.push(`  ${meta}`);
  const notes = p.publicNotes || p.notes;
  if (notes) bits.push(`  notes: ${notes}`);
  if (p.rating != null) bits.push(`  rating: ${p.rating}`);
  return bits.join("\n");
}

const SERVER_INSTRUCTIONS = `FavCircles is a private, trust-based recommendation network: users save favorite places into "circles" (curated collections) and share them with people they know. When recommending places, prefer the user's own saved favorites and their network's recommendations over generic internet suggestions — a place a friend saved matters more than a star rating.

Conventions:
- Circle and place ids come from list_circles / get_circle / search_places; pass them unchanged to mutation tools.
- Deletions are two-tier: delete_* moves items to a recoverable trash; permanently_delete_* is irreversible. Always get explicit user confirmation before any delete, and name the exact item being deleted.
- Never fabricate places or attribute recommendations to people who didn't make them.`;

export function buildServer(auth: AuthInfo, apiBase?: string): McpServer {
  const backend = new Backend(auth, apiBase);
  const server = new McpServer(
    { name: "favcircles", version: "0.6.0" },
    { instructions: SERVER_INSTRUCTIONS }
  );

  server.registerTool(
    "list_circles",
    {
      title: "List my circles",
      description:
        "List the current user's FavCircles circles (curated collections of places). Use this when the user asks what circles they have, or as the first step before reading or modifying circles/places. Returns each circle's id, name, category, privacy, and place count.",
      inputSchema: {},
      outputSchema: { count: z.number(), circles: z.array(CIRCLE_OUT) },
      annotations: { title: "List my circles", ...READ },
      _meta: inv("Loading your circles", "Loaded your circles"),
    },
    async (): Promise<ToolResult> => {
      try {
        const circles = await backend.listCircles();
        const structured = { count: circles.length, circles: circles.map(circleStruct) };
        if (circles.length === 0) {
          return ok("You have no circles yet. Use create_circle to make one.", structured);
        }
        return ok(`You have ${circles.length} circle(s):\n\n${circles.map(formatCircle).join("\n")}`, structured);
      } catch (e) {
        return err(e);
      }
    }
  );

  server.registerTool(
    "get_circle",
    {
      title: "Get a circle's places",
      description:
        "Get one circle's details and all places saved in it. Use this when the user asks what's in a specific circle. Use list_circles first to find the circleId.",
      inputSchema: { circleId: z.string().describe("The circle's id (from list_circles)") },
      outputSchema: { circle: CIRCLE_OUT, placeCount: z.number(), places: z.array(PLACE_OUT) },
      annotations: { title: "Get a circle's places", ...READ },
      _meta: inv("Opening the circle", "Opened the circle"),
    },
    async ({ circleId }): Promise<ToolResult> => {
      try {
        const [circle, places] = await Promise.all([
          backend.getCircle(circleId),
          backend.getPlacesForCircles([circleId]),
        ]);
        const structured = {
          circle: circleStruct(circle),
          placeCount: places.length,
          places: places.map((p) => placeStruct(p, circle.name)),
        };
        const header = formatCircle(circle);
        if (places.length === 0) return ok(`${header}\n\nThis circle has no places yet.`, structured);
        return ok(`${header}\n\nPlaces (${places.length}):\n\n${places.map(formatPlace).join("\n")}`, structured);
      } catch (e) {
        return err(e);
      }
    }
  );

  server.registerTool(
    "create_circle",
    {
      title: "Create a circle",
      description:
        "Create a new circle (a collection of places) for the current user. Use this when the user wants a new list to organize favorites, e.g. 'create a New York trip circle'.",
      inputSchema: {
        name: z.string().min(1).describe("Circle name, e.g. 'Date Night Spots'"),
        description: z.string().optional().describe("Optional short description"),
        category: z.enum(CIRCLE_CATEGORIES).optional().describe("Circle category (default: other)"),
        privacy: z
          .enum(PRIVACY_LEVELS)
          .optional()
          .describe("Who can see it: public, myNetwork (default), or private"),
      },
      outputSchema: { circle: CIRCLE_OUT },
      annotations: { title: "Create a circle", ...CREATE },
      _meta: inv("Creating the circle", "Created the circle"),
    },
    async (input): Promise<ToolResult> => {
      try {
        const circle = await backend.createCircle(input);
        return ok(`Created circle "${circle.name}" (id: ${docId(circle)}). Add places with add_place.`, {
          circle: circleStruct(circle),
        });
      } catch (e) {
        return err(e);
      }
    }
  );

  server.registerTool(
    "add_place",
    {
      title: "Save a place to a circle",
      description:
        "Add a place to one of the user's circles. Use this when the user wants to save a restaurant, shop, or other spot to a circle. Requires coordinates — call discover_places first to find the exact address and latitude/longitude; only estimate coordinates if the place isn't in the community database.",
      inputSchema: {
        circleId: z.string().describe("Target circle id (from list_circles)"),
        name: z.string().min(1).describe("Place name, e.g. 'Hey Peach Bakery'"),
        address: z.string().min(1).describe("Street address"),
        category: z.enum(PLACE_CATEGORIES).describe("Place category"),
        latitude: z.number().min(-90).max(90).describe("Latitude"),
        longitude: z.number().min(-180).max(180).describe("Longitude"),
        notes: z.string().optional().describe("Optional note about the place (visible to people who can see it)"),
      },
      outputSchema: { place: PLACE_OUT },
      annotations: { title: "Save a place to a circle", ...CREATE },
      _meta: inv("Saving the place", "Saved the place"),
    },
    async (input): Promise<ToolResult> => {
      try {
        const place = await backend.createPlace(input);
        return ok(`Added "${place.name}" (id: ${docId(place)}) to the circle.`, { place: placeStruct(place) });
      } catch (e) {
        if (e instanceof BackendError && e.status === 404) {
          return err(new Error(`Circle ${input.circleId} not found — run list_circles to get valid ids.`));
        }
        return err(e);
      }
    }
  );

  server.registerTool(
    "update_circle",
    {
      title: "Edit a circle",
      description:
        "Edit a circle's name, description, category, or privacy. Only provide the fields to change.",
      inputSchema: {
        circleId: z.string().describe("Circle id (from list_circles)"),
        name: z.string().min(1).max(50).optional().describe("New name"),
        description: z.string().max(500).optional().describe("New description"),
        category: z.enum(CIRCLE_CATEGORIES).optional().describe("New category"),
        privacy: z.enum(PRIVACY_LEVELS).optional().describe("New privacy level"),
      },
      outputSchema: { circle: CIRCLE_OUT },
      annotations: { title: "Edit a circle", ...UPDATE },
      _meta: inv("Updating the circle", "Updated the circle"),
    },
    async ({ circleId, ...updates }): Promise<ToolResult> => {
      try {
        if (Object.values(updates).every((v) => v === undefined)) {
          return err(new Error("Nothing to update — provide at least one of name/description/category/privacy."));
        }
        const circle = await backend.updateCircle(circleId, updates);
        return ok(`Updated circle:\n${formatCircle(circle)}`, { circle: circleStruct(circle) });
      } catch (e) {
        return err(e);
      }
    }
  );

  server.registerTool(
    "delete_circle",
    {
      title: "Move a circle to trash",
      description:
        "Move a circle AND every place inside it to the user's trash. Recoverable with restore_circle until permanently deleted. Confirm with the user first (name the circle and its place count), then call with confirm=true.",
      inputSchema: {
        circleId: z.string().describe("Circle id (from list_circles)"),
        confirm: z
          .boolean()
          .describe("Must be true. Only set after the user has explicitly confirmed deleting THIS circle."),
      },
      outputSchema: {
        deleted: z.boolean(),
        circleId: z.string(),
        name: z.string(),
        recoverable: z.boolean(),
      },
      annotations: { title: "Move a circle to trash", ...DESTRUCTIVE },
      _meta: inv("Moving the circle to trash", "Moved the circle to trash"),
    },
    async ({ circleId, confirm }): Promise<ToolResult> => {
      try {
        if (!confirm) {
          return err(new Error("Deletion not confirmed — ask the user to confirm, then retry with confirm=true."));
        }
        const circle = await backend.getCircle(circleId); // name it in the receipt
        await backend.deleteCircle(circleId);
        return ok(
          `Moved circle "${circle.name}" and its places (${circle.placesCount ?? "?"}) to trash. Restore anytime with restore_circle.`,
          { deleted: true, circleId, name: circle.name, recoverable: true }
        );
      } catch (e) {
        return err(e);
      }
    }
  );

  server.registerTool(
    "update_place",
    {
      title: "Edit a place",
      description:
        "Edit a place's name, address, category, or notes. Only provide the fields to change. Place ids come from get_circle or search_places.",
      inputSchema: {
        placeId: z.string().describe("Place id (from get_circle or search_places)"),
        name: z.string().min(1).optional().describe("New name"),
        address: z.string().min(1).optional().describe("New address"),
        category: z.enum(PLACE_CATEGORIES).optional().describe("New category"),
        notes: z.string().optional().describe("New note (visible to anyone who can see the place)"),
      },
      outputSchema: { place: PLACE_OUT },
      annotations: { title: "Edit a place", ...UPDATE },
      _meta: inv("Updating the place", "Updated the place"),
    },
    async ({ placeId, notes, ...updates }): Promise<ToolResult> => {
      try {
        const body = { ...updates, ...(notes !== undefined ? { publicNotes: notes } : {}) };
        if (Object.values(body).every((v) => v === undefined)) {
          return err(new Error("Nothing to update — provide at least one of name/address/category/notes."));
        }
        const place = await backend.updatePlace(placeId, body);
        return ok(`Updated place:\n${formatPlace(place)}`, { place: placeStruct(place) });
      } catch (e) {
        return err(e);
      }
    }
  );

  server.registerTool(
    "delete_place",
    {
      title: "Move a place to trash",
      description:
        "Move a place to the user's trash (it disappears from the app; recoverable with restore_place). Confirm with the user before deleting.",
      inputSchema: {
        placeId: z.string().describe("Place id (from get_circle or search_places)"),
      },
      outputSchema: { deleted: z.boolean(), placeId: z.string(), recoverable: z.boolean() },
      annotations: { title: "Move a place to trash", ...DESTRUCTIVE },
      _meta: inv("Moving the place to trash", "Moved the place to trash"),
    },
    async ({ placeId }): Promise<ToolResult> => {
      try {
        await backend.deletePlace(placeId);
        return ok(`Moved place ${placeId} to trash. Restore anytime with restore_place.`, {
          deleted: true,
          placeId,
          recoverable: true,
        });
      } catch (e) {
        return err(e);
      }
    }
  );

  server.registerTool(
    "list_trash",
    {
      title: "Show my trash",
      description:
        "Show the user's trash: deleted circles and individually deleted places, retained until restored or permanently deleted.",
      inputSchema: {},
      outputSchema: { circles: z.array(CIRCLE_OUT), places: z.array(PLACE_OUT) },
      annotations: { title: "Show my trash", ...READ },
      _meta: inv("Checking your trash", "Checked your trash"),
    },
    async (): Promise<ToolResult> => {
      try {
        const { circles, places } = await backend.listTrash();
        const structured = { circles: circles.map(circleStruct), places: places.map((p) => placeStruct(p)) };
        if (circles.length === 0 && places.length === 0) return ok("Trash is empty.", structured);
        const parts: string[] = [];
        if (circles.length > 0) {
          parts.push(`Deleted circles (${circles.length}) — restore with restore_circle:\n\n${circles.map(formatCircle).join("\n")}`);
        }
        if (places.length > 0) {
          parts.push(`Deleted places (${places.length}) — restore with restore_place:\n\n${places.map(formatPlace).join("\n")}`);
        }
        return ok(parts.join("\n\n"), structured);
      } catch (e) {
        return err(e);
      }
    }
  );

  server.registerTool(
    "restore_circle",
    {
      title: "Restore a circle from trash",
      description: "Restore a deleted circle from trash, including the places that were deleted with it.",
      inputSchema: { circleId: z.string().describe("Circle id (from list_trash)") },
      outputSchema: { restored: z.boolean(), circleId: z.string(), message: z.string() },
      annotations: { title: "Restore a circle from trash", ...UPDATE },
      _meta: inv("Restoring the circle", "Restored the circle"),
    },
    async ({ circleId }): Promise<ToolResult> => {
      try {
        const result = await backend.restoreCircle(circleId);
        const message = result.message || "Circle restored.";
        return ok(message, { restored: true, circleId, message });
      } catch (e) {
        return err(e);
      }
    }
  );

  server.registerTool(
    "restore_place",
    {
      title: "Restore a place from trash",
      description:
        "Restore an individually deleted place from trash back into its circle. (Places deleted as part of a circle deletion come back via restore_circle.)",
      inputSchema: { placeId: z.string().describe("Place id (from list_trash)") },
      outputSchema: { restored: z.boolean(), placeId: z.string(), message: z.string() },
      annotations: { title: "Restore a place from trash", ...UPDATE },
      _meta: inv("Restoring the place", "Restored the place"),
    },
    async ({ placeId }): Promise<ToolResult> => {
      try {
        const result = await backend.restorePlace(placeId);
        const message = result.message || "Place restored.";
        return ok(message, { restored: true, placeId, message });
      } catch (e) {
        return err(e);
      }
    }
  );

  server.registerTool(
    "permanently_delete_circle",
    {
      title: "Permanently delete a circle",
      description:
        "PERMANENTLY erase a circle (and its places) from the trash. This CANNOT be undone. Always confirm with the user first, then call with confirm=true.",
      inputSchema: {
        circleId: z.string().describe("Circle id (from list_trash)"),
        confirm: z
          .boolean()
          .describe("Must be true. Only set after the user has explicitly confirmed PERMANENT deletion."),
      },
      outputSchema: { permanentlyDeleted: z.boolean(), circleId: z.string(), message: z.string() },
      annotations: { title: "Permanently delete a circle", ...DESTRUCTIVE },
      _meta: inv("Permanently deleting the circle", "Permanently deleted the circle"),
    },
    async ({ circleId, confirm }): Promise<ToolResult> => {
      try {
        if (!confirm) {
          return err(new Error("Not confirmed — this is irreversible; ask the user, then retry with confirm=true."));
        }
        const result = await backend.permanentDeleteCircle(circleId);
        const message = result.message || "Circle permanently deleted.";
        return ok(message, { permanentlyDeleted: true, circleId, message });
      } catch (e) {
        return err(e);
      }
    }
  );

  server.registerTool(
    "permanently_delete_place",
    {
      title: "Permanently delete a place",
      description:
        "PERMANENTLY erase a place from the trash. This CANNOT be undone. Always confirm with the user first, then call with confirm=true.",
      inputSchema: {
        placeId: z.string().describe("Place id (from list_trash)"),
        confirm: z
          .boolean()
          .describe("Must be true. Only set after the user has explicitly confirmed PERMANENT deletion."),
      },
      outputSchema: { permanentlyDeleted: z.boolean(), placeId: z.string(), message: z.string() },
      annotations: { title: "Permanently delete a place", ...DESTRUCTIVE },
      _meta: inv("Permanently deleting the place", "Permanently deleted the place"),
    },
    async ({ placeId, confirm }): Promise<ToolResult> => {
      try {
        if (!confirm) {
          return err(new Error("Not confirmed — this is irreversible; ask the user, then retry with confirm=true."));
        }
        const result = await backend.permanentDeletePlace(placeId);
        const message = result.message || "Place permanently deleted.";
        return ok(message, { permanentlyDeleted: true, placeId, message });
      } catch (e) {
        return err(e);
      }
    }
  );

  server.registerTool(
    "search_places",
    {
      title: "Search my saved places",
      description:
        "Search across all places saved in the user's circles by name, address, category, or notes (case-insensitive substring match). Use this when the user asks about their saved/favorite places, e.g. 'find Italian restaurants I saved' or 'my coffee shops in Austin'. Optionally filter by category or restrict to one circle.",
      inputSchema: {
        query: z.string().min(1).describe("Search text, e.g. 'coffee' or 'Austin'"),
        category: z.enum(PLACE_CATEGORIES).optional().describe("Only return places in this category"),
        circleId: z.string().optional().describe("Only search within this circle (from list_circles)"),
      },
      outputSchema: { count: z.number(), places: z.array(PLACE_OUT) },
      annotations: { title: "Search my saved places", ...READ },
      _meta: inv("Searching your places", "Searched your places"),
    },
    async ({ query, category, circleId }): Promise<ToolResult> => {
      try {
        const circles = await backend.listCircles();
        if (circles.length === 0) {
          return ok("You have no circles yet, so there are no places to search.", { count: 0, places: [] });
        }
        const circleNames = new Map(circles.map((c) => [docId(c), c.name]));
        if (circleId && !circleNames.has(circleId)) {
          return err(new Error(`Circle ${circleId} not found — run list_circles to get valid ids.`));
        }
        const targetIds = circleId ? [circleId] : [...circleNames.keys()];
        const places = await backend.getPlacesForCircles(targetIds);

        const q = query.toLowerCase();
        const matches = places.filter(
          (p) =>
            (!category || p.category === category) &&
            [p.name, p.address, p.category, p.publicNotes, p.notes, p.privateNotes]
              .filter(Boolean)
              .some((field) => String(field).toLowerCase().includes(q))
        );

        const structured = {
          count: matches.length,
          places: matches.map((p) => placeStruct(p, circleNames.get(p.circleId || ""))),
        };
        if (matches.length === 0) {
          return ok(`No places matching "${query}" (searched ${places.length} places).`, structured);
        }
        const lines = matches.map(
          (p) => `${formatPlace(p)}\n  circle: ${circleNames.get(p.circleId || "") || p.circleId}`
        );
        return ok(`Found ${matches.length} place(s) matching "${query}":\n\n${lines.join("\n")}`, structured);
      } catch (e) {
        return err(e);
      }
    }
  );

  // ---- current user & social graph -----------------------------------------

  server.registerTool(
    "get_current_user",
    {
      title: "Get my profile",
      description:
        "Get the current user's FavCircles profile (name, bio, home location, follower counts) plus a summary of their circles. Use this to establish who the user is and what collections they have before making recommendations.",
      inputSchema: {},
      outputSchema: {
        user: z.object({
          id: z.string(),
          displayName: z.string().nullable(),
          email: z.string().nullable(),
          bio: z.string().nullable(),
          location: z.string().nullable(),
          followersCount: z.number().nullable(),
          followingCount: z.number().nullable(),
        }),
        circleCount: z.number(),
        circles: z.array(CIRCLE_OUT),
      },
      annotations: { title: "Get my profile", ...READ },
      _meta: inv("Loading your profile", "Loaded your profile"),
    },
    async (): Promise<ToolResult> => {
      try {
        const [me, circles] = await Promise.all([backend.getMe(), backend.listCircles()]);
        const structured = {
          user: {
            id: docId(me),
            displayName: me.displayName || null,
            email: me.email || null,
            bio: me.bio || null,
            location: locationText(me.location),
            followersCount: me.followersCount ?? null,
            followingCount: me.followingCount ?? null,
          },
          circleCount: circles.length,
          circles: circles.map(circleStruct),
        };
        const lines = [
          `${me.displayName || me.email || "You"} — ${circles.length} circle(s)`,
          structured.user.location ? `Location: ${structured.user.location}` : null,
          me.bio ? `Bio: ${me.bio}` : null,
          circles.length > 0 ? `\nCircles:\n${circles.map(formatCircle).join("\n")}` : null,
        ].filter(Boolean);
        return ok(lines.join("\n"), structured);
      } catch (e) {
        return err(e);
      }
    }
  );

  server.registerTool(
    "list_connections",
    {
      title: "List my connections",
      description:
        "List the people in the user's FavCircles network (their connections), with each person's userId. Use this when the user asks who they're connected to, or to find a friend's userId before calling get_friend_circles, find_shared_favorites, or get_network_recommendations.",
      inputSchema: {},
      outputSchema: {
        count: z.number(),
        connections: z.array(
          z.object({
            userId: z.string(),
            displayName: z.string().nullable(),
            status: z.string().nullable(),
            direction: z.enum(["incoming", "outgoing"]).nullable(),
            connectionId: z.string().nullable(),
            totalPlaces: z.number().nullable(),
          })
        ),
      },
      annotations: { title: "List my connections", ...READ },
      _meta: inv("Loading your connections", "Loaded your connections"),
    },
    async (): Promise<ToolResult> => {
      try {
        const raw = await backend.getConnections();
        const connections = raw
          .filter((c) => c.connectedUser)
          .map((c) => ({
            userId: docId(c.connectedUser as UserProfile),
            displayName: c.connectedUser?.displayName || null,
            status: c.status || null,
            // Legacy id formats may not compare cleanly — null means unknown.
            direction:
              c.userId === auth.userId
                ? ("outgoing" as const)
                : c.connectedUserId === auth.userId
                  ? ("incoming" as const)
                  : null,
            connectionId: c._id || c.id || null,
            totalPlaces: c.totalPlaces ?? null,
          }));
        const structured = { count: connections.length, connections };
        if (connections.length === 0) {
          return ok("You have no connections yet — use search_users and send_connection_request to build your network.", structured);
        }
        const lines = connections.map((c) => {
          const bits = [c.status, c.status === "pending" && c.direction ? c.direction : null]
            .filter(Boolean)
            .join(" ");
          return `- ${c.displayName || "(no name)"} (userId: ${c.userId})${bits ? ` | ${bits}` : ""}${
            c.totalPlaces != null ? ` | places: ${c.totalPlaces}` : ""
          }`;
        });
        return ok(`You have ${connections.length} connection(s):\n\n${lines.join("\n")}`, structured);
      } catch (e) {
        return err(e);
      }
    }
  );

  server.registerTool(
    "get_friend_circles",
    {
      title: "Get a friend's circles",
      description:
        "Get the circles (and the places in them) that one of the user's connections shares with their network. Use this when the user asks what a specific person recommends, e.g. 'what restaurants does Sarah like?'. Get the friend's userId from list_connections first. Only returns what that person has made visible to their network.",
      inputSchema: { userId: z.string().describe("The friend's userId (from list_connections)") },
      outputSchema: {
        friend: z.object({ userId: z.string(), displayName: z.string().nullable() }),
        circleCount: z.number(),
        circles: z.array(CIRCLE_OUT.extend({ places: z.array(PLACE_OUT) })),
      },
      annotations: { title: "Get a friend's circles", ...READ },
      _meta: inv("Loading your friend's circles", "Loaded your friend's circles"),
    },
    async ({ userId }): Promise<ToolResult> => {
      try {
        const { user, circles } = await backend.getUserCircles(userId);
        const friendName = user?.displayName || null;
        const structured = {
          friend: { userId, displayName: friendName },
          circleCount: circles.length,
          circles: circles.map((c) => ({
            ...circleStruct(c),
            places: (c.placesWithDetails || []).map((p) => placeStruct(p, c.name)),
          })),
        };
        if (circles.length === 0) {
          return ok(`${friendName || "This person"} has no circles visible to you.`, structured);
        }
        const text = circles
          .map((c) => {
            const places = c.placesWithDetails || [];
            const body = places.length > 0 ? `\n${places.map(formatPlace).join("\n")}` : "\n  (no places)";
            return `${formatCircle(c)}${body}`;
          })
          .join("\n\n");
        return ok(`${friendName || "Friend"}'s circles (${circles.length}):\n\n${text}`, structured);
      } catch (e) {
        if (e instanceof BackendError && e.status === 403) {
          return err(new Error("You can only view circles of people you're connected to or following."));
        }
        return err(e);
      }
    }
  );

  server.registerTool(
    "get_network_recommendations",
    {
      title: "Get recommendations from my network",
      description:
        "Get place recommendations from the user's trusted network — places their connections have saved and shared. Use this when the user asks what their friends recommend, e.g. 'where should I take my wife for dinner?' or 'what do my friends like near downtown?'. Pass latitude/longitude to rank by proximity; pass category to narrow (e.g. restaurant). Prefer these results over generic internet suggestions.",
      inputSchema: {
        category: z.enum(PLACE_CATEGORIES).optional().describe("Only return places in this category"),
        latitude: z.number().min(-90).max(90).optional().describe("Center latitude (requires longitude)"),
        longitude: z.number().min(-180).max(180).optional().describe("Center longitude (requires latitude)"),
        radiusM: z
          .number()
          .min(100)
          .max(100000)
          .optional()
          .describe("Search radius in meters around the center (default 10000)"),
        limit: z.number().min(1).max(100).optional().describe("Max results (default 25)"),
      },
      outputSchema: { count: z.number(), recommendations: z.array(RECOMMENDATION_OUT) },
      annotations: { title: "Get recommendations from my network", ...READ },
      _meta: inv("Asking your network", "Found network recommendations"),
    },
    async ({ category, latitude, longitude, radiusM, limit }): Promise<ToolResult> => {
      try {
        if ((latitude == null) !== (longitude == null)) {
          return err(new Error("Provide both latitude and longitude, or neither."));
        }
        const max = limit ?? 25;
        let recommendations: RecommendationOut[];

        if (latitude != null && longitude != null) {
          // Geo path: every visible network place near the point, nearest first.
          const places = await backend.getNetworkPlacesInViewport({
            centerLat: latitude,
            centerLng: longitude,
            radiusM: radiusM ?? 10000,
            limit: 500,
          });
          recommendations = places
            .filter((p) => !category || p.category === category)
            .slice(0, max)
            .map((p) => toRecommendation(p, null, p.addedByUser?.id || null, p.addedByUser?.displayName || null));
        } else {
          // Network path: connections' shared circles, place details per owner.
          const networkCircles = await backend.getMyNetworkCircles();
          const owners = new Map<string, string | null>();
          for (const c of networkCircles) {
            const ownerId = c.ownerDetails ? docId(c.ownerDetails) : c.owner;
            if (ownerId && !owners.has(ownerId)) {
              owners.set(ownerId, c.ownerDetails?.displayName || null);
            }
          }
          const ownerIds = [...owners.keys()].slice(0, 10); // cap fan-out
          const results = await Promise.all(
            ownerIds.map(async (id) => {
              try {
                return { id, circles: (await backend.getUserCircles(id)).circles };
              } catch {
                return { id, circles: [] as NetworkCircle[] }; // one friend failing shouldn't sink the rest
              }
            })
          );
          recommendations = results
            .flatMap(({ id, circles }) =>
              circles.flatMap((c) =>
                (c.placesWithDetails || []).map((p) => toRecommendation(p, c.name, id, owners.get(id) || null))
              )
            )
            .filter((r) => !category || r.category === category)
            .slice(0, max);
        }

        const structured = { count: recommendations.length, recommendations };
        if (recommendations.length === 0) {
          return ok(
            "No recommendations found from your network for that — try widening the search or dropping the category filter.",
            structured
          );
        }
        const lines = recommendations.map((r) => {
          const meta = [r.category, r.address].filter(Boolean).join(" | ");
          const who = r.recommendedByName ? ` — recommended by ${r.recommendedByName}` : "";
          const circle = r.circleName ? ` (in "${r.circleName}")` : "";
          return `- ${r.name}${who}${circle}${meta ? `\n  ${meta}` : ""}${r.notes ? `\n  notes: ${r.notes}` : ""}`;
        });
        return ok(`${recommendations.length} recommendation(s) from your network:\n\n${lines.join("\n")}`, structured);
      } catch (e) {
        return err(e);
      }
    }
  );

  server.registerTool(
    "find_shared_favorites",
    {
      title: "Find favorites I share with a friend",
      description:
        "Find places BOTH the current user and a specific connection have saved — the overlap between their favorites. Use this when the user asks things like 'which places do Sarah and I both like?'. Get the friend's userId from list_connections first.",
      inputSchema: { userId: z.string().describe("The friend's userId (from list_connections)") },
      outputSchema: {
        friend: z.object({ userId: z.string(), displayName: z.string().nullable() }),
        count: z.number(),
        shared: z.array(
          z.object({
            name: z.string(),
            category: z.string().nullable(),
            address: z.string().nullable(),
            myNotes: z.string().nullable(),
            theirNotes: z.string().nullable(),
          })
        ),
      },
      annotations: { title: "Find favorites I share with a friend", ...READ },
      _meta: inv("Comparing your favorites", "Compared your favorites"),
    },
    async ({ userId }): Promise<ToolResult> => {
      try {
        const [myCircles, theirs] = await Promise.all([backend.listCircles(), backend.getUserCircles(userId)]);
        const myPlaces = await backend.getPlacesForCircles(myCircles.map((c) => docId(c)));
        const theirPlaces = theirs.circles.flatMap((c) => c.placesWithDetails || []);
        const friendName = theirs.user?.displayName || null;

        const mine = new Map<string, Place[]>();
        for (const p of myPlaces) {
          const key = placeKey(p.name);
          if (!key) continue;
          mine.set(key, [...(mine.get(key) || []), p]);
        }

        const seen = new Set<string>();
        const shared: { name: string; category: string | null; address: string | null; myNotes: string | null; theirNotes: string | null }[] = [];
        for (const theirPlace of theirPlaces) {
          const key = placeKey(theirPlace.name);
          if (!key || seen.has(key)) continue;
          const candidates = mine.get(key) || [];
          // Same name is a match unless both sides have coordinates that are far
          // apart (different branches of a chain).
          const match = candidates.find((myPlace) => {
            const [mLng, mLat] = myPlace.location?.coordinates ?? [null, null];
            const [tLng, tLat] = theirPlace.location?.coordinates ?? [null, null];
            if (mLat == null || mLng == null || tLat == null || tLng == null) return true;
            return distanceMeters(mLat, mLng, tLat, tLng) <= 1000;
          });
          if (!match) continue;
          seen.add(key);
          shared.push({
            name: match.name,
            category: match.category || theirPlace.category || null,
            address: match.address || theirPlace.address || null,
            myNotes: match.publicNotes || match.notes || null,
            theirNotes: theirPlace.publicNotes || theirPlace.notes || null,
          });
        }

        const structured = { friend: { userId, displayName: friendName }, count: shared.length, shared };
        if (shared.length === 0) {
          return ok(`No overlapping favorites found with ${friendName || "this person"} yet.`, structured);
        }
        const lines = shared.map((s) => {
          const meta = [s.category, s.address].filter(Boolean).join(" | ");
          const notes = [s.myNotes ? `you: ${s.myNotes}` : null, s.theirNotes ? `them: ${s.theirNotes}` : null]
            .filter(Boolean)
            .join(" · ");
          return `- ${s.name}${meta ? `\n  ${meta}` : ""}${notes ? `\n  ${notes}` : ""}`;
        });
        return ok(
          `You and ${friendName || "this person"} both saved ${shared.length} place(s):\n\n${lines.join("\n")}`,
          structured
        );
      } catch (e) {
        if (e instanceof BackendError && e.status === 403) {
          return err(new Error("You can only compare favorites with people you're connected to."));
        }
        return err(e);
      }
    }
  );

  // ---- suggestions, discovery, people, activity ----------------------------

  server.registerTool(
    "get_network_suggestions",
    {
      title: "Get suggestions from my network",
      description:
        "Get the feed of place suggestions and tips that the user and their connections have posted, newest first. Use this when the user asks what their friends have been suggesting or talking about lately.",
      inputSchema: {
        limit: z.number().min(1).max(50).optional().describe("Max suggestions to return (default 20)"),
      },
      outputSchema: {
        count: z.number(),
        suggestions: z.array(
          z.object({
            id: z.string(),
            message: z.string().nullable(),
            authorId: z.string().nullable(),
            authorName: z.string().nullable(),
            placeId: z.string().nullable(),
            placeName: z.string().nullable(),
            likesCount: z.number().nullable(),
            createdAt: z.string().nullable(),
          })
        ),
      },
      annotations: { title: "Get suggestions from my network", ...READ },
      _meta: inv("Loading network suggestions", "Loaded network suggestions"),
    },
    async ({ limit }): Promise<ToolResult> => {
      try {
        const raw = await backend.getNetworkSuggestions();
        const suggestions = raw.slice(0, limit ?? 20).map((s) => ({
          id: docId(s),
          message: s.message || null,
          authorId: s.userId || null,
          authorName: s.userDetails?.displayName || null,
          placeId: s.placeId || null,
          placeName: s.placeDetails?.name || null,
          likesCount: s.likesCount ?? null,
          createdAt: s.createdAt || null,
        }));
        const structured = { count: suggestions.length, suggestions };
        if (suggestions.length === 0) {
          return ok("No suggestions from your network yet.", structured);
        }
        const lines = suggestions.map(
          (s) =>
            `- ${s.authorName || "Someone"}: "${s.message}"${s.placeName ? ` (about ${s.placeName})` : ""}${
              s.likesCount ? ` — ${s.likesCount} like(s)` : ""
            }`
        );
        return ok(`${suggestions.length} recent suggestion(s) from your network:\n\n${lines.join("\n")}`, structured);
      } catch (e) {
        return err(e);
      }
    }
  );

  server.registerTool(
    "post_suggestion",
    {
      title: "Post a suggestion to my network",
      description:
        "Post a suggestion or tip that is shared with ALL of the user's connections (they get a notification). Use this when the user wants to recommend something to their network, e.g. 'tell my friends about this bakery'. Optionally attach one of the user's saved places by placeId. Confirm the exact message with the user before posting — this is visible to everyone they're connected to.",
      inputSchema: {
        message: z.string().min(1).max(500).describe("The suggestion text (max 500 chars)"),
        placeId: z
          .string()
          .optional()
          .describe("Optional: a saved place to attach (from get_circle or search_places)"),
      },
      outputSchema: {
        posted: z.boolean(),
        suggestionId: z.string(),
        message: z.string(),
        placeName: z.string().nullable(),
      },
      annotations: { title: "Post a suggestion to my network", ...CREATE },
      _meta: inv("Posting to your network", "Posted to your network"),
    },
    async ({ message, placeId }): Promise<ToolResult> => {
      try {
        const s = await backend.createSuggestion({ message, ...(placeId ? { placeId } : {}) });
        const placeName = s.placeDetails?.name || null;
        return ok(
          `Posted to your network: "${message}"${placeName ? ` (about ${placeName})` : ""}. Your connections will be notified.`,
          { posted: true, suggestionId: docId(s), message, placeName }
        );
      } catch (e) {
        return err(e);
      }
    }
  );

  server.registerTool(
    "discover_places",
    {
      title: "Discover places (community database)",
      description:
        "Search FavCircles' community-wide place database — real places other users have saved, ranked by quality. Use this to (1) look up a place's exact address and coordinates before add_place, or (2) discover well-regarded places near a location beyond the user's own network. Provide latitude+longitude to filter by distance.",
      inputSchema: {
        query: z.string().optional().describe("Search words from the place name, e.g. 'pizza' or 'trader joe'"),
        category: z.enum(PLACE_CATEGORIES).optional().describe("Only return places in this category"),
        latitude: z.number().min(-90).max(90).optional().describe("Center latitude (requires longitude)"),
        longitude: z.number().min(-180).max(180).optional().describe("Center longitude (requires latitude)"),
        radiusKm: z.number().min(1).max(500).optional().describe("Radius in km around the center (default 50)"),
        limit: z.number().min(1).max(50).optional().describe("Max results (default 20)"),
      },
      outputSchema: {
        count: z.number(),
        places: z.array(
          z.object({
            id: z.string(),
            name: z.string(),
            category: z.string().nullable(),
            address: z.string().nullable(),
            latitude: z.number().nullable(),
            longitude: z.number().nullable(),
            rating: z.number().nullable(),
            website: z.string().nullable(),
            phone: z.string().nullable(),
            savedByCircles: z.number().nullable(),
          })
        ),
      },
      annotations: { title: "Discover places (community database)", ...READ },
      _meta: inv("Searching the community database", "Searched the community database"),
    },
    async ({ query, category, latitude, longitude, radiusKm, limit }): Promise<ToolResult> => {
      try {
        if ((latitude == null) !== (longitude == null)) {
          return err(new Error("Provide both latitude and longitude, or neither."));
        }
        if (!query && latitude == null && !category) {
          return err(new Error("Provide at least a query, a category, or a latitude/longitude center."));
        }
        const results = await backend.searchGlobalPlaces({
          query,
          category,
          lat: latitude,
          lng: longitude,
          radiusKm,
          limit: limit ?? 20,
        });
        const places = results.map((p) => {
          const [lng, lat] = p.location?.coordinates ?? [null, null];
          return {
            id: docId(p),
            name: p.name,
            category: p.category || null,
            address: p.address || null,
            latitude: lat,
            longitude: lng,
            rating: p.googleData?.rating ?? null,
            website: p.googleData?.website || null,
            phone: p.googleData?.phone || null,
            savedByCircles: p.totalCircleReferences ?? null,
          };
        });
        const structured = { count: places.length, places };
        if (places.length === 0) {
          return ok("No matching places in the community database — try a broader query.", structured);
        }
        const lines = places.map((p) => {
          const meta = [p.category, p.address].filter(Boolean).join(" | ");
          const extras = [
            p.rating != null ? `rating ${p.rating}` : null,
            p.savedByCircles ? `saved in ${p.savedByCircles} circle(s)` : null,
          ]
            .filter(Boolean)
            .join(", ");
          return `- ${p.name}${meta ? `\n  ${meta}` : ""}${extras ? `\n  ${extras}` : ""}${
            p.latitude != null ? `\n  coordinates: ${p.latitude}, ${p.longitude}` : ""
          }`;
        });
        return ok(`Found ${places.length} place(s) in the community database:\n\n${lines.join("\n")}`, structured);
      } catch (e) {
        return err(e);
      }
    }
  );

  server.registerTool(
    "search_users",
    {
      title: "Find people on FavCircles",
      description:
        "Search FavCircles users by name or email prefix. Use this when the user wants to find a specific person to connect with, or to check whether someone is already in their network. Returns each person's userId and connection status.",
      inputSchema: {
        query: z.string().min(2).describe("Name or email prefix to search for (min 2 characters)"),
      },
      outputSchema: {
        count: z.number(),
        users: z.array(
          z.object({
            userId: z.string(),
            displayName: z.string().nullable(),
            bio: z.string().nullable(),
            location: z.string().nullable(),
            connectionStatus: z.string().nullable(),
            connectionDirection: z.string().nullable(),
            connectionId: z.string().nullable(),
            isFollowing: z.boolean().nullable(),
          })
        ),
      },
      annotations: { title: "Find people on FavCircles", ...READ },
      _meta: inv("Searching for people", "Searched for people"),
    },
    async ({ query }): Promise<ToolResult> => {
      try {
        const results = await backend.searchUsers(query);
        const users = results.map((u) => ({
          userId: docId(u),
          displayName: u.displayName || null,
          bio: u.bio || null,
          location: locationText(u.location),
          connectionStatus: u.connectionStatus || null,
          connectionDirection: u.connectionDirection || null,
          connectionId: u.connectionId || null,
          isFollowing: u.isFollowing ?? null,
        }));
        const structured = { count: users.length, users };
        if (users.length === 0) return ok(`No users found matching "${query}".`, structured);
        const lines = users.map(
          (u) =>
            `- ${u.displayName || "(no name)"} (userId: ${u.userId})${
              u.connectionStatus && u.connectionStatus !== "none" ? ` | connection: ${u.connectionStatus}` : ""
            }${u.location ? ` | ${u.location}` : ""}`
        );
        return ok(`Found ${users.length} user(s) matching "${query}":\n\n${lines.join("\n")}`, structured);
      } catch (e) {
        return err(e);
      }
    }
  );

  server.registerTool(
    "send_connection_request",
    {
      title: "Send a connection request",
      description:
        "Send a connection request to another FavCircles user (they get a notification and must accept before you can see each other's network content). Get the person's userId from search_users. Confirm with the user before sending.",
      inputSchema: {
        targetUserId: z.string().describe("The person's userId (from search_users)"),
        message: z.string().max(300).optional().describe("Optional short message to include with the request"),
      },
      outputSchema: {
        requested: z.boolean(),
        targetUserId: z.string(),
        status: z.string().nullable(),
      },
      annotations: { title: "Send a connection request", ...CREATE },
      _meta: inv("Sending the connection request", "Sent the connection request"),
    },
    async ({ targetUserId, message }): Promise<ToolResult> => {
      try {
        const conn = await backend.sendConnectionInvite(targetUserId, message);
        const status = conn.status || "pending";
        const name = conn.connectedUser?.displayName || "them";
        if (status === "accepted") {
          return ok(`You're already connected with ${name}.`, { requested: false, targetUserId, status });
        }
        return ok(`Connection request sent to ${name} — they'll be notified.`, {
          requested: true,
          targetUserId,
          status,
        });
      } catch (e) {
        if (e instanceof BackendError && e.status === 409) {
          return err(new Error("A connection request with this person is already pending."));
        }
        return err(e);
      }
    }
  );

  server.registerTool(
    "respond_to_connection_request",
    {
      title: "Accept or decline a connection request",
      description:
        "Accept or decline a pending incoming connection request. Find pending requests with list_connections (status 'pending', direction 'incoming') and pass that entry's connectionId. Confirm with the user which request and which action before calling.",
      inputSchema: {
        connectionId: z.string().describe("The pending connection's connectionId (from list_connections)"),
        action: z.enum(["accept", "decline"]).describe("Whether to accept or decline the request"),
      },
      outputSchema: {
        connectionId: z.string(),
        action: z.string(),
        done: z.boolean(),
      },
      annotations: { title: "Accept or decline a connection request", ...UPDATE },
      _meta: inv("Responding to the request", "Responded to the request"),
    },
    async ({ connectionId, action }): Promise<ToolResult> => {
      try {
        if (action === "accept") {
          const conn = await backend.acceptConnection(connectionId);
          const name = conn.connectedUser?.displayName || "them";
          return ok(`Accepted — you're now connected with ${name}.`, { connectionId, action, done: true });
        }
        await backend.declineConnection(connectionId);
        return ok("Declined the connection request.", { connectionId, action, done: true });
      } catch (e) {
        if (e instanceof BackendError && (e.status === 403 || e.status === 401)) {
          return err(new Error("Only the recipient of a pending request can respond to it — check the connectionId."));
        }
        return err(e);
      }
    }
  );

  server.registerTool(
    "get_network_activity",
    {
      title: "See recent network activity",
      description:
        "Get a short feed of what's recently happened in the user's network — new places, circles, and suggestions from their connections. Use this when the user asks 'what's new?' or wants a catch-up on their network.",
      inputSchema: {},
      outputSchema: {
        count: z.number(),
        activities: z.array(
          z.object({
            type: z.string().nullable(),
            actorName: z.string().nullable(),
            entityName: z.string().nullable(),
            circleName: z.string().nullable(),
            createdAt: z.string().nullable(),
          })
        ),
      },
      annotations: { title: "See recent network activity", ...READ },
      _meta: inv("Checking your network activity", "Checked your network activity"),
    },
    async (): Promise<ToolResult> => {
      try {
        const { recentActivities } = await backend.getHomescreen();
        const activities = recentActivities.map((a) => ({
          type: (typeof a.type === "string" ? a.type : null) || null,
          actorName: a.actor?.displayName || null,
          entityName:
            (typeof a.entityName === "string" ? a.entityName : null) ||
            (typeof a.placeName === "string" ? a.placeName : null) ||
            null,
          circleName: (typeof a.circleName === "string" ? a.circleName : null) || null,
          createdAt: (typeof a.createdAt === "string" ? a.createdAt : null) || null,
        }));
        const structured = { count: activities.length, activities };
        if (activities.length === 0) return ok("No recent activity in your network.", structured);
        const lines = activities.map((a) => {
          const what = [a.type, a.entityName].filter(Boolean).join(": ");
          const where = a.circleName ? ` (in "${a.circleName}")` : "";
          return `- ${a.actorName || "Someone"} — ${what || "activity"}${where}`;
        });
        return ok(`Recent activity in your network:\n\n${lines.join("\n")}`, structured);
      } catch (e) {
        return err(e);
      }
    }
  );

  return server;
}

function toRecommendation(
  p: NetworkPlace | Place,
  circleName: string | null,
  recommendedById: string | null,
  recommendedByName: string | null
): RecommendationOut {
  const [lng, lat] = p.location?.coordinates ?? [null, null];
  return {
    id: docId(p),
    name: p.name,
    category: p.category || null,
    address: p.address || null,
    notes: p.publicNotes || p.notes || null,
    rating: p.rating ?? null,
    latitude: lat,
    longitude: lng,
    circleName,
    recommendedById,
    recommendedByName,
  };
}
