# Apple featuring nomination — App Launch (2026-11-09)

Wes's call: pitch FavCircles as an **App Launch** built on the core features, using his problem framing
(memory `app-pitch-positioning`). One nomination. Created as a DRAFT through the App Store Connect API
(`POST /v1/nominations`). It goes to Apple only after Wes's OK (`PATCH submitted: true`). The type can't be
changed after submitting.

- **Name:** FavCircles: your map of favorite places, and your friends' (Apple limits: name 60 chars, description 1000)
- **Type:** APP_LAUNCH
- **Publish window:** 2026-12-01 → 2026-12-31 (Apple wants 3+ weeks of lead time)
- **Devices:** iPhone, iPad · **Locale:** en-US
- **Supplemental URLs:** https://favcircles.com/ · https://favcircles.com/watch.html ·
  https://apps.apple.com/us/app/favcircles/id6746807095 · videos/user-tour.mp4 · videos/charlotte-demo.mp4
- **ASC nomination id:** 5699c752-7ed2-47af-ac52-8b37a8eb93a8 (SUBMITTED 2026-11-10 00:05 UTC)

## Description

There was no well-organized way to save your favorite places. FavCircles fixes that.

Your own personal map: every place you love goes on your map, and once it's saved you'll never forget it.

Organized your way: places live in Circles that make sense to you ("Date Night", "Best Pizza", "Lisbon Trip"), each public, shared with your network, Inner Circle or private.

Your friends' and family's maps: see the personal maps of the people you know, wherever you are. Skip reviews by strangers and get recommendations from people you trust.

Also: Moments (photos and videos tied to places), Locals (nearby specials and events), Widgets (everyday mini-apps built in) and Rewards (local stores give points through an App Clip and NFC stickers).

The holidays are when people visit family and ask "where should we go?" FavCircles answers with a shared map from people you trust. We're a small independent team in Charlotte, NC.

## Notes field

Purpose and priority: our first featuring nomination, introducing FavCircles to App Store editors. The core experience (personal map, Circles, friends' maps) is the priority. We're happy to provide artwork, a TestFlight build or a demo on request.

## If Apple's editors ask for artwork

Requests go to App Store Connect users with the Admin, App Manager or Marketing role. sgroiwes@gmail.com is the Account Holder and Admin. brittanyvans@ and salasgroi@ have the Marketing role, so they may get the email too.

Ready in `assets/`: `app-icon-1024.png` and iPhone screenshots (map, friends, circles, rewards).

The full sets live in place and aren't duplicated:
- `Marketing/app-store-2026-09/iPhone 6.9-inch/` (10 screenshots) and `iPad 13-inch/` (7)
- App Previews (886×1920): `Marketing/app-store-2026-09/App Previews (iPhone)/01-your-map`, `02-your-people`
- Demo cuts: `Marketing/app-store-previews/charlotte-30s-886x1920.mp4`

Apple's editorial art usually asks for layered, text-free key art. That means a new build from the source files when the request comes.

## Status
- 2026-11-09: draft created (`5699c752-7ed2-47af-ac52-8b37a8eb93a8`). Live listing: 1.5.0, 8 ratings, 5.0 average. Not submitted, waiting for Wes.
- Submit: `PATCH /v1/nominations/<id>` with `submitted: true`. The latest date that keeps 3 weeks of lead time for a Dec 1 start is **Nov 10**. After that, move the start date out.
- 2026-11-10 00:05 UTC: Wes said submit. Added the user-tour and Charlotte demo video links (5/5 URLs) and SUBMITTED. Type and related apps are now locked.
- 2026-11-11: Helpful Details (the API's `notes`, limit **500** chars) set to helpful-details-500.txt. The full story is in helpful-details.txt. US only, launch in select markets first = true. No store count, since none are signed up yet.
