# FavCircles web app

FavCircles in a browser, at **app.favcircles.com**, for phones with no iOS app (there is no Android app). React + TypeScript, built with Vite into `backend/public/app`, which is **committed**: the Cloud Run image is built from `backend/` alone. The backend serves the page (`backend/routes/webAppRoutes.js`) and the API on the same origin.

## Run it
```
cd backend && PORT=8099 WEB_APP_HOSTS=localhost node server.js   # the API + the built app at http://localhost:8099
cd webapp && npm run dev -- --port 5173                          # live-reload dev server, proxies /api to :8099
npm run typecheck && npm test                                    # before every commit
npm run build                                                    # writes backend/public/app + build-info.json; commit both
```
A backend test (`routes/__tests__/webAppRoutes.test.js`) fails when the built files are missing or older than `src/`.

## Layout
- `src/api/` — one module per area. `client.ts` is the only place that calls `fetch` (`get/post/put/del`, `ApiError`, `messageOf`). `types.ts` holds the shared shapes (User, Place, Circle).
- `src/auth/` — the saved sign-in (`fc.store.session`, shared with the store web page `/s/<code>`), `useAuth()`.
- `src/logic/` — pure rules with a `*.test.ts` next to each (vitest). No React, no fetch.
- `src/ui/` — shared pieces: `kit.tsx` (Avatar, Thumb, Spinner, Empty, LoadError, Head, Sheet, ConfirmSheet, toast), `Layout.tsx` (tab bar), `PlaceRow`, `CircleCard`, `share.ts`.
- `src/pages/` — one file per screen (+ a small `.css` beside it when needed), routed in `App.tsx`.
- `src/realtime/` — tab-bar badges (`BADGE_KEYS`) and the live stream.
- `src/styles/base.css` — tokens (`--brand`, `--card`, `--line`, `--muted`…) and shared classes (`.card .btn .field .item .list .chip .row .grow .clip .section-title .empty`). Light and dark both come from the tokens: never hard-code a text or surface colour.

## Rules (the same ones the iOS app follows)
- **Data:** every screen loads with `useQuery` (TanStack Query) so what was loaded shows at once while it refreshes. After a write, `invalidateQueries` the keys it changed. Query keys start with the area: `['circles', …]`, `['circle', id, …]`, `['place', id]`, `['user', id]`, `['feed']`, `['messages', …]`, `['rewards', …]`.
- **Never a blank screen:** loading → `<Spinner/>`, failure → `<LoadError retry>`, nothing there → `<Empty>` with words and, where it helps, a button.
- **Privacy:** four tiers, `public | myNetwork | innerCircle | private` (a place may also be `followCircle`). `client.ts` sends `X-FC-Inner-Circle: 1` on every call. An edit sends **only the fields the person changed**; never write back a privacy value they did not touch.
- **Coordinates** are GeoJSON `[lng, lat]`; go through `logic/geo.ts` (`latLngOf`, `pointOf`).
- **Order:** circles and a circle's places keep the server's order. Never sort them alphabetically.
- **Removing a saved place is "unsave"**, never "delete": the venue stays.
- **Copy:** plain words, sentence case, no jargon. Errors say what happened and what to do.
- **No inline scripts, no third-party scripts or fetches:** the CSP is `script-src 'self'; connect-src 'self'`. Images from any https host are fine.
- **A new first path segment** must be added to `APP_PATHS` in `backend/routes/webAppRoutes.js` as well as `App.tsx`.
- Touch targets ≥ 40 px; the layout is phone-first and must hold up at 360 px wide and on a desktop.
