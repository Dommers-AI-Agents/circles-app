/**
 * FavCircles MCP server — Phase 2 (local stdio + token validation).
 *
 * Every tool call validates the bearer token (signature, expiry, audience —
 * see auth.ts) before touching the backend, and reads the user id from the
 * validated token. On stdio the token arrives via FAVCIRCLES_TOKEN; the
 * Phase 3 Worker will pass each HTTP request's Authorization header into the
 * same authenticate() seam instead.
 *
 * stdio discipline: stdout is the JSON-RPC channel — diagnostics go to stderr.
 */

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { AuthError, AuthInfo, MCP_AUDIENCE, verifyToken } from "./auth.js";
import {
  BackendError,
  Circle,
  Place,
  createCircle,
  createPlace,
  deleteCircle,
  deletePlace,
  docId,
  getCircle,
  getPlacesForCircles,
  listCircles,
  listTrash,
  permanentDeleteCircle,
  permanentDeletePlace,
  restoreCircle,
  restorePlace,
  updateCircle,
  updatePlace,
} from "./backend.js";

// Backend enums (from models/FirestoreModels.js validators)
const PLACE_CATEGORIES = [
  "restaurant", "cafe", "bar", "hotel", "retail", "service", "attraction",
  "entertainment", "healthcare", "fitness", "education", "outdoor",
  "transport", "finance", "home", "work", "other",
] as const;
const CIRCLE_CATEGORIES = [
  "travel", "food", "services", "shopping", "healthcare", "entertainment", "other",
] as const;
const PRIVACY_LEVELS = ["public", "myNetwork", "private"] as const;

const server = new McpServer({ name: "favcircles", version: "0.4.0" });

// ---- auth seam ----

/**
 * Validate the caller's token and return AuthInfo. On stdio the token comes
 * from the environment; the Phase 3 Worker calls verifyToken() with the
 * per-request Authorization header instead.
 */
async function authenticate(): Promise<AuthInfo> {
  return verifyToken(process.env.FAVCIRCLES_TOKEN);
}

// ---- formatting helpers ----

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

type ToolResult = { content: { type: "text"; text: string }[]; isError?: boolean };

function ok(text: string): ToolResult {
  return { content: [{ type: "text", text }] };
}

function err(e: unknown): ToolResult {
  const message = e instanceof Error ? e.message : String(e);
  const prefix = e instanceof AuthError ? "Auth error" : "Error";
  return { content: [{ type: "text", text: `${prefix}: ${message}` }], isError: true };
}

// ---- tools ----

server.registerTool(
  "list_circles",
  {
    description:
      "List the current user's FavCircles circles (curated collections of places). Returns each circle's name, id, category, privacy, and place count.",
    inputSchema: {},
  },
  async (): Promise<ToolResult> => {
    try {
      const auth = await authenticate();
      const circles = await listCircles(auth);
      if (circles.length === 0) return ok("You have no circles yet. Use create_circle to make one.");
      return ok(`You have ${circles.length} circle(s):\n\n${circles.map(formatCircle).join("\n")}`);
    } catch (e) {
      return err(e);
    }
  }
);

server.registerTool(
  "get_circle",
  {
    description:
      "Get one circle's details and all places in it. Use list_circles first to find the circleId.",
    inputSchema: { circleId: z.string().describe("The circle's id (from list_circles)") },
  },
  async ({ circleId }): Promise<ToolResult> => {
    try {
      const auth = await authenticate();
      const [circle, places] = await Promise.all([
        getCircle(auth, circleId),
        getPlacesForCircles(auth, [circleId]),
      ]);
      const header = formatCircle(circle);
      if (places.length === 0) return ok(`${header}\n\nThis circle has no places yet.`);
      return ok(`${header}\n\nPlaces (${places.length}):\n\n${places.map(formatPlace).join("\n")}`);
    } catch (e) {
      return err(e);
    }
  }
);

server.registerTool(
  "create_circle",
  {
    description: "Create a new circle (a collection of places) for the current user.",
    inputSchema: {
      name: z.string().min(1).describe("Circle name, e.g. 'Date Night Spots'"),
      description: z.string().optional().describe("Optional short description"),
      category: z.enum(CIRCLE_CATEGORIES).optional().describe("Circle category (default: other)"),
      privacy: z
        .enum(PRIVACY_LEVELS)
        .optional()
        .describe("Who can see it: public, myNetwork (default), or private"),
    },
  },
  async (input): Promise<ToolResult> => {
    try {
      const auth = await authenticate();
      const circle = await createCircle(auth, input);
      return ok(`Created circle "${circle.name}" (id: ${docId(circle)}). Add places with add_place.`);
    } catch (e) {
      return err(e);
    }
  }
);

server.registerTool(
  "add_place",
  {
    description:
      "Add a place to one of the user's circles. Requires coordinates — if you only have an address, estimate the latitude/longitude as accurately as you can or ask the user.",
    inputSchema: {
      circleId: z.string().describe("Target circle id (from list_circles)"),
      name: z.string().min(1).describe("Place name, e.g. 'Hey Peach Bakery'"),
      address: z.string().min(1).describe("Street address"),
      category: z.enum(PLACE_CATEGORIES).describe("Place category"),
      latitude: z.number().min(-90).max(90).describe("Latitude"),
      longitude: z.number().min(-180).max(180).describe("Longitude"),
      notes: z.string().optional().describe("Optional note about the place (visible to people who can see it)"),
    },
  },
  async (input): Promise<ToolResult> => {
    try {
      const auth = await authenticate();
      const place = await createPlace(auth, input);
      return ok(`Added "${place.name}" (id: ${docId(place)}) to the circle.`);
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
    description:
      "Edit a circle's name, description, category, or privacy. Only provide the fields to change.",
    inputSchema: {
      circleId: z.string().describe("Circle id (from list_circles)"),
      name: z.string().min(1).max(50).optional().describe("New name"),
      description: z.string().max(500).optional().describe("New description"),
      category: z.enum(CIRCLE_CATEGORIES).optional().describe("New category"),
      privacy: z.enum(PRIVACY_LEVELS).optional().describe("New privacy level"),
    },
  },
  async ({ circleId, ...updates }): Promise<ToolResult> => {
    try {
      const auth = await authenticate();
      if (Object.values(updates).every((v) => v === undefined)) {
        return err(new Error("Nothing to update — provide at least one of name/description/category/privacy."));
      }
      const circle = await updateCircle(auth, circleId, updates);
      return ok(`Updated circle:\n${formatCircle(circle)}`);
    } catch (e) {
      return err(e);
    }
  }
);

server.registerTool(
  "delete_circle",
  {
    description:
      "Move a circle AND every place inside it to the user's trash. Recoverable with restore_circle until permanently deleted. Confirm with the user first (name the circle and its place count), then call with confirm=true.",
    inputSchema: {
      circleId: z.string().describe("Circle id (from list_circles)"),
      confirm: z
        .boolean()
        .describe("Must be true. Only set after the user has explicitly confirmed deleting THIS circle."),
    },
  },
  async ({ circleId, confirm }): Promise<ToolResult> => {
    try {
      const auth = await authenticate();
      if (!confirm) {
        return err(new Error("Deletion not confirmed — ask the user to confirm, then retry with confirm=true."));
      }
      const circle = await getCircle(auth, circleId); // name it in the receipt
      await deleteCircle(auth, circleId);
      return ok(`Moved circle "${circle.name}" and its places (${circle.placesCount ?? "?"}) to trash. Restore anytime with restore_circle.`);
    } catch (e) {
      return err(e);
    }
  }
);

server.registerTool(
  "update_place",
  {
    description:
      "Edit a place's name, address, category, or notes. Only provide the fields to change. Place ids come from get_circle or search_places.",
    inputSchema: {
      placeId: z.string().describe("Place id (from get_circle or search_places)"),
      name: z.string().min(1).optional().describe("New name"),
      address: z.string().min(1).optional().describe("New address"),
      category: z.enum(PLACE_CATEGORIES).optional().describe("New category"),
      notes: z.string().optional().describe("New note (visible to anyone who can see the place)"),
    },
  },
  async ({ placeId, notes, ...updates }): Promise<ToolResult> => {
    try {
      const auth = await authenticate();
      const body = { ...updates, ...(notes !== undefined ? { publicNotes: notes } : {}) };
      if (Object.values(body).every((v) => v === undefined)) {
        return err(new Error("Nothing to update — provide at least one of name/address/category/notes."));
      }
      const place = await updatePlace(auth, placeId, body);
      return ok(`Updated place:\n${formatPlace(place)}`);
    } catch (e) {
      return err(e);
    }
  }
);

server.registerTool(
  "delete_place",
  {
    description:
      "Move a place to the user's trash (it disappears from the app; recoverable with restore_place). Confirm with the user before deleting.",
    inputSchema: {
      placeId: z.string().describe("Place id (from get_circle or search_places)"),
    },
  },
  async ({ placeId }): Promise<ToolResult> => {
    try {
      const auth = await authenticate();
      await deletePlace(auth, placeId);
      return ok(`Moved place ${placeId} to trash. Restore anytime with restore_place.`);
    } catch (e) {
      return err(e);
    }
  }
);

server.registerTool(
  "list_trash",
  {
    description:
      "Show the user's trash: deleted circles and individually deleted places, retained until restored or permanently deleted.",
    inputSchema: {},
  },
  async (): Promise<ToolResult> => {
    try {
      const auth = await authenticate();
      const { circles, places } = await listTrash(auth);
      if (circles.length === 0 && places.length === 0) return ok("Trash is empty.");
      const parts: string[] = [];
      if (circles.length > 0) {
        parts.push(`Deleted circles (${circles.length}) — restore with restore_circle:\n\n${circles.map(formatCircle).join("\n")}`);
      }
      if (places.length > 0) {
        parts.push(`Deleted places (${places.length}) — restore with restore_place:\n\n${places.map(formatPlace).join("\n")}`);
      }
      return ok(parts.join("\n\n"));
    } catch (e) {
      return err(e);
    }
  }
);

server.registerTool(
  "restore_circle",
  {
    description: "Restore a deleted circle from trash, including the places that were deleted with it.",
    inputSchema: { circleId: z.string().describe("Circle id (from list_trash)") },
  },
  async ({ circleId }): Promise<ToolResult> => {
    try {
      const auth = await authenticate();
      const result = await restoreCircle(auth, circleId);
      return ok(result.message || "Circle restored.");
    } catch (e) {
      return err(e);
    }
  }
);

server.registerTool(
  "restore_place",
  {
    description:
      "Restore an individually deleted place from trash back into its circle. (Places deleted as part of a circle deletion come back via restore_circle.)",
    inputSchema: { placeId: z.string().describe("Place id (from list_trash)") },
  },
  async ({ placeId }): Promise<ToolResult> => {
    try {
      const auth = await authenticate();
      const result = await restorePlace(auth, placeId);
      return ok(result.message || "Place restored.");
    } catch (e) {
      return err(e);
    }
  }
);

server.registerTool(
  "permanently_delete_circle",
  {
    description:
      "PERMANENTLY erase a circle (and its places) from the trash. This CANNOT be undone. Always confirm with the user first, then call with confirm=true.",
    inputSchema: {
      circleId: z.string().describe("Circle id (from list_trash)"),
      confirm: z
        .boolean()
        .describe("Must be true. Only set after the user has explicitly confirmed PERMANENT deletion."),
    },
  },
  async ({ circleId, confirm }): Promise<ToolResult> => {
    try {
      const auth = await authenticate();
      if (!confirm) {
        return err(new Error("Not confirmed — this is irreversible; ask the user, then retry with confirm=true."));
      }
      const result = await permanentDeleteCircle(auth, circleId);
      return ok(result.message || "Circle permanently deleted.");
    } catch (e) {
      return err(e);
    }
  }
);

server.registerTool(
  "permanently_delete_place",
  {
    description:
      "PERMANENTLY erase a place from the trash. This CANNOT be undone. Always confirm with the user first, then call with confirm=true.",
    inputSchema: {
      placeId: z.string().describe("Place id (from list_trash)"),
      confirm: z
        .boolean()
        .describe("Must be true. Only set after the user has explicitly confirmed PERMANENT deletion."),
    },
  },
  async ({ placeId, confirm }): Promise<ToolResult> => {
    try {
      const auth = await authenticate();
      if (!confirm) {
        return err(new Error("Not confirmed — this is irreversible; ask the user, then retry with confirm=true."));
      }
      const result = await permanentDeletePlace(auth, placeId);
      return ok(result.message || "Place permanently deleted.");
    } catch (e) {
      return err(e);
    }
  }
);

server.registerTool(
  "search_places",
  {
    description:
      "Search across all places in the user's circles by name, address, category, or notes (case-insensitive substring match).",
    inputSchema: { query: z.string().min(1).describe("Search text, e.g. 'coffee' or 'Austin'") },
  },
  async ({ query }): Promise<ToolResult> => {
    try {
      const auth = await authenticate();
      const circles = await listCircles(auth);
      if (circles.length === 0) return ok("You have no circles yet, so there are no places to search.");
      const circleNames = new Map(circles.map((c) => [docId(c), c.name]));
      const places = await getPlacesForCircles(auth, [...circleNames.keys()]);

      const q = query.toLowerCase();
      const matches = places.filter((p) =>
        [p.name, p.address, p.category, p.publicNotes, p.notes, p.privateNotes]
          .filter(Boolean)
          .some((field) => String(field).toLowerCase().includes(q))
      );

      if (matches.length === 0) return ok(`No places matching "${query}" (searched ${places.length} places).`);
      const lines = matches.map(
        (p) => `${formatPlace(p)}\n  circle: ${circleNames.get(p.circleId || "") || p.circleId}`
      );
      return ok(`Found ${matches.length} place(s) matching "${query}":\n\n${lines.join("\n")}`);
    } catch (e) {
      return err(e);
    }
  }
);

// ---- start ----

const transport = new StdioServerTransport();
await server.connect(transport);
console.error(
  `favcircles MCP server v0.2 on stdio (backend: ${process.env.FAVCIRCLES_API || "https://api.favcircles.com/api"}, audience: ${MCP_AUDIENCE})`
);
