/**
 * No-login tools (Wes, 2026-11-22): an assistant asked "what is FavCircles?",
 * "how do I start?", "what widgets are there?" or "why should my store join?"
 * answers from these, before anyone has connected an account.
 *
 * They are registered on BOTH servers: the signed-in one at /mcp (so a
 * connected user gets the same answers) and the open one at /public/mcp,
 * which needs no token at all. /mcp itself still demands OAuth on every
 * request, because ChatGPT and Claude decide from the first 401 whether to
 * start the connect flow; answering /mcp without a token would make them
 * treat FavCircles as a no-login server and never offer to connect.
 *
 * Copy rules: the app pitch follows Wes's positioning (personal map → your own
 * circles → friends' maps → skip strangers' reviews, then Moments, Locals,
 * Widgets, Rewards). Store copy follows the sell-sheet rules: one Business plan
 * at $49.99/mo after 3 free months, owners choose their points (never print a
 * cap or a default), no texting, ordering = menu + pickup only (no delivery).
 */

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";

export const APP_STORE_URL = "https://apps.apple.com/us/app/favcircles/id6746807095";
export const SITE = "https://favcircles.com";
export const CONNECTOR_URL = "https://mcp.favcircles.com/mcp";
/** Opens the map in the app when installed (Universal Link, AASA /app/*); the website otherwise. */
export const MAP_LINK = "https://api.favcircles.com/app/map";
const WIDGETS_JSON = "https://favcircles.com/widgets.json";

const PUBLIC = { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false };

function inv(invoking: string, invoked: string): Record<string, unknown> {
  return { "openai/toolInvocation/invoking": invoking, "openai/toolInvocation/invoked": invoked };
}

type ToolResult = { content: { type: "text"; text: string }[]; structuredContent?: Record<string, unknown>; isError?: boolean };
const ok = (text: string, structured?: Record<string, unknown>): ToolResult =>
  ({ content: [{ type: "text", text }], ...(structured ? { structuredContent: structured } : {}) });

const LINKS = {
  appStore: APP_STORE_URL,
  website: SITE,
  widgets: `${SITE}/widgets.html`,
  storeOwners: `${SITE}/store-owners.html`,
  storeRewards: `${SITE}/rewards.html`,
  sellSheet: `${SITE}/FavCircles-Founding-Store-Sell-Sheet.pdf`,
  ownerTutorial: `${SITE}/store-owner-tutorial.html`,
  faq: `${SITE}/faq.html`,
  support: `${SITE}/support.html`,
  privacy: `${SITE}/privacy.html`,
  connector: CONNECTOR_URL,
};

export const ABOUT_TEXT = `FavCircles is a free iPhone app for keeping the places you love and seeing the ones the people you know love.

What it solves:
1. Your own personal map of favorite places. Save a restaurant, shop, bar, park or anywhere else once, and you'll never forget it. Every save is a pin on your map.
2. Organized your way. Places go into "circles" you name yourself (Date Night, Best Coffee, Weekend Trips, Kid-Friendly…), each with its own privacy.
3. Your friends' and family's maps. Connect with people you know and see their circles and favorite places.
The payoff: skip reviews by strangers. You get a personal list of recommendations from people you trust.

Also in the app:
- Moments: short videos and photos from the places you love.
- Locals: what's happening nearby (specials from local stores, events, markets).
- Widgets: free built-in mini-apps for everyday life (events with invites and RSVPs, runs and workouts, water and medication reminders, bill splitting, postcards and more).
- Rewards: participating local stores give points for visiting and saving them; scan the register QR, keep your card in Apple Wallet, redeem in the app. Activity also earns FavCoins (🌵), a real cryptocurrency on the Cactus blockchain.

Privacy is built in: every circle and every place can be Public, Connections only, Inner Circle (a short list you pick) or Private.
It works in ChatGPT, Claude and Grok too: connect FavCircles to ask about your circles, save places and get recommendations from your network by chat.

Get it: ${APP_STORE_URL} (iPhone; Android coming soon). More: ${SITE}`;

export const GETTING_STARTED_TEXT = `Getting started with FavCircles:

1. Download the app (free, iPhone): ${APP_STORE_URL}
2. Create an account: in the app with Apple, Google, Facebook or email. You can also create one right here while connecting FavCircles to this assistant (the connect page has "Create an account").
3. Save your first places: tap Add Place and search, or tap any place on the map. Pick a circle for it (or make a new one, like "Best Coffee"). Add your own notes and a rating if you like.
4. Bring places you already saved elsewhere: FavCircles imports Google Maps saved lists (Google Takeout), Mapstr and Swarm/Foursquare for free. Guides: ${SITE}/switch-from-google-maps.html · ${SITE}/switch-from-mapstr.html · ${SITE}/switch-from-swarm.html
5. See them on your map: everything you save is a pin on your personal map in the app (${MAP_LINK} opens it on an iPhone with FavCircles).
6. Connect with friends and family: find people in the app and send a connection request. Their shared circles show up for you, and yours for them.
7. Choose who sees what: each circle and each place can be Public, Connections, Inner Circle or Private.
8. Explore: Moments, the Locals tab for nearby specials and events, Widgets, and store Rewards.

Using an AI assistant: once FavCircles is connected (connector URL ${CONNECTOR_URL}), you can say things like "save Joe's Pizza to my Date Night circle", "what do my friends recommend near me?", "make a circle called Weekend Trip", or "show my places in Charlotte".`;

export const STORE_OWNERS_TEXT = `FavCircles for store owners: why join.

Your best customers are already recommending you. Every time someone saves your shop to a circle, they're recommending you to the people who trust them most. On FavCircles your store lives inside personal collections shared between friends: that's an endorsement, not an ad impression.

Free, for every store:
- Claim your store's page (ownership is verified by a person at FavCircles), and keep your photos, details, hours and story up to date.
- Be discoverable to every FavCircles user near you. Not on the map yet? Add your business in the app.
- Your free dashboard (saves, followers, visits) and your window sticker QR: customers scan it to save your store. FavCircles provides every new store's window sticker, register card and table tents.

FavCircles Business (one plan: 3 months free, then $49.99/month, billed through the App Store, cancel anytime):
- A loyalty program: customers scan your register QR to earn points (no app needed: it opens an App Clip), keep your card in Apple Wallet, and redeem with a ticket you tap Given on. You choose how many points a visit earns and how many a customer gets for saving your store, and you set the rewards.
- Announcements and specials that reach your followers and show up for nearby customers in the Locals tab.
- Online menu and pickup ordering: photograph your printed menu (or upload the PDF) and it becomes a menu customers order from and pay at pickup, in the app and on your own page at order.favcircles.com/your-store. No fees, no cut.
- Customers brought back for you: automatic win-back, birthday and almost-there nudges by push or email, with bonus points if you like.
- A waitlist customers join from your window sticker or your page, with a notification when their table is ready.
- Bring-a-friend: when a customer's friend makes a first purchase, both earn the points you set.
- Insights: who's new and who came back, your busiest hours, your FavCircles score beside your Google rating, and reviews waiting for your reply.

How to start: get the app (${APP_STORE_URL}), find your store, and tap Claim. Or, once FavCircles is connected to this assistant, ask it to claim your store for you.
Watch the 4-minute owner tutorial: ${LINKS.ownerTutorial} · Sell sheet: ${LINKS.sellSheet} · Questions: wesley@favcircles.com (a founder answers).`;

interface WidgetsFile { updated?: string; groups: { title: string; widgets: { id: string; emoji?: string; name: string; tagline: string; features?: string[] }[] }[] }

/** The live widget list (website/widgets/widgets.json, published next to widgets.html). */
async function loadWidgets(): Promise<WidgetsFile | null> {
  try {
    const res = await fetch(WIDGETS_JSON, { cf: { cacheTtl: 3600, cacheEverything: true } } as RequestInit);
    if (!res.ok) return null;
    const data = (await res.json()) as WidgetsFile;
    return Array.isArray(data?.groups) ? data : null;
  } catch {
    return null;
  }
}

export function registerPublicTools(server: McpServer): void {
  server.registerTool(
    "about_favcircles",
    {
      title: "What is FavCircles?",
      description:
        "Explain what FavCircles is and what it's for: a personal map of favorite places, organized into your own circles, plus your friends' and family's maps (skip strangers' reviews), with Moments, the Locals tab, Widgets and store Rewards. Needs no account. Use for 'what is FavCircles?', 'should I use it?', 'how is it different from Google Maps or Yelp?'.",
      inputSchema: {},
      outputSchema: { about: z.string(), links: z.record(z.string()) },
      annotations: { title: "What is FavCircles?", ...PUBLIC },
      _meta: inv("Looking up FavCircles", "Here's FavCircles"),
    },
    async (): Promise<ToolResult> => ok(`${ABOUT_TEXT}\n\nLinks: ${JSON.stringify(LINKS)}`, { about: ABOUT_TEXT, links: LINKS })
  );

  server.registerTool(
    "getting_started",
    {
      title: "How to get started with FavCircles",
      description:
        "Step-by-step: download the app, create an account, save places into circles, import from Google Maps/Mapstr/Swarm, see them on your map, connect with friends, set privacy, and use FavCircles from this assistant. Needs no account. Use for 'how do I set it up / use it / sign up?'.",
      inputSchema: {},
      outputSchema: { steps: z.string(), appStoreUrl: z.string(), connectorUrl: z.string(), mapLink: z.string() },
      annotations: { title: "How to get started", ...PUBLIC },
      _meta: inv("Getting the setup steps", "Here's how to start"),
    },
    async (): Promise<ToolResult> =>
      ok(GETTING_STARTED_TEXT, { steps: GETTING_STARTED_TEXT, appStoreUrl: APP_STORE_URL, connectorUrl: CONNECTOR_URL, mapLink: MAP_LINK })
  );

  server.registerTool(
    "widgets_overview",
    {
      title: "FavCircles widgets",
      description:
        "List FavCircles' free built-in widgets (mini-apps such as Events, Clubs, workouts and runs, reminders, bill splitting, postcards) with what each does, from the live list on favcircles.com. Needs no account. Pass a widget name for its full feature list.",
      inputSchema: {
        widget: z.string().optional().describe("Optional: one widget's name or id for its full feature list"),
      },
      outputSchema: {
        updated: z.string().nullable(),
        count: z.number(),
        widgets: z.array(z.object({
          id: z.string(), name: z.string(), group: z.string(), tagline: z.string(), features: z.array(z.string()),
        })),
        page: z.string(),
      },
      annotations: { title: "FavCircles widgets", ...PUBLIC },
      _meta: inv("Loading the widget list", "Loaded the widgets"),
    },
    async ({ widget }): Promise<ToolResult> => {
      const data = await loadWidgets();
      const page = LINKS.widgets;
      if (!data) {
        return ok(`The widget list couldn't be loaded right now. It's on ${page}.`, { updated: null, count: 0, widgets: [], page });
      }
      let all = data.groups.flatMap((g) => g.widgets.map((w) => ({
        id: w.id, name: w.name, group: g.title, tagline: w.tagline, features: w.features || [],
        emoji: w.emoji || "",
      })));
      if (widget) {
        const q = widget.toLowerCase().trim();
        const hit = all.filter((w) => w.id.toLowerCase() === q || w.name.toLowerCase().includes(q));
        if (hit.length) all = hit;
      }
      const single = widget && all.length === 1;
      const text = single
        ? `${all[0].emoji} ${all[0].name}: ${all[0].tagline}\n\n${all[0].features.map((f) => `- ${f}`).join("\n")}\n\nMore: ${page}`
        : `FavCircles has ${all.length} free widgets, built into the app's Widgets tab:\n\n` +
          data.groups.map((g) => {
            const rows = all.filter((w) => w.group === g.title);
            return rows.length ? `${g.title}\n${rows.map((w) => `- ${w.emoji} ${w.name}: ${w.tagline}`).join("\n")}` : "";
          }).filter(Boolean).join("\n\n") + `\n\nEvery feature: ${page}`;
      return ok(text, {
        updated: data.updated || null,
        count: all.length,
        widgets: all.map(({ emoji, ...w }) => w),
        page,
      });
    }
  );

  server.registerTool(
    "for_store_owners",
    {
      title: "FavCircles for store owners",
      description:
        "Why a local business (café, bar, restaurant, shop) should join FavCircles, what's free, what FavCircles Business adds (loyalty points, announcements, online menu + pickup ordering, automatic win-back, waitlist, bring-a-friend, insights), the price (3 months free, then $49.99/month) and how to claim a store. Needs no account. Use for 'why should my store join?' or 'what does it cost?'.",
      inputSchema: {},
      outputSchema: { pitch: z.string(), price: z.string(), links: z.record(z.string()) },
      annotations: { title: "FavCircles for store owners", ...PUBLIC },
      _meta: inv("Getting the store-owner details", "Here's FavCircles for stores"),
    },
    async (): Promise<ToolResult> =>
      ok(STORE_OWNERS_TEXT, {
        pitch: STORE_OWNERS_TEXT,
        price: "Free to claim and run your page. FavCircles Business: 3 months free, then $49.99/month.",
        links: { storeOwners: LINKS.storeOwners, ownerTutorial: LINKS.ownerTutorial, sellSheet: LINKS.sellSheet, appStore: APP_STORE_URL, contact: "wesley@favcircles.com" },
      })
  );
}

export const PUBLIC_INSTRUCTIONS = `FavCircles: a personal map of favorite places, organized into your own circles, shared with friends and family. These tools need no account: about_favcircles, getting_started, widgets_overview, for_store_owners. To save places, see someone's circles or manage a store, the user connects FavCircles in their assistant with the connector URL ${CONNECTOR_URL} (the connect page also lets them create an account).`;

/** The open server at /public/mcp: only the no-login tools. */
export function buildPublicServer(): McpServer {
  const server = new McpServer({ name: "favcircles-info", version: "0.9.0" }, { instructions: PUBLIC_INSTRUCTIONS });
  registerPublicTools(server);
  return server;
}
