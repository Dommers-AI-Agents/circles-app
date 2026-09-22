# Low / no-signal checklist

Run on a device before each App Review submission. Nothing in the automated
suites exercises a dead or weak connection; the pure rules are unit-tested,
the plumbing is not.

Set up: Settings → Developer → Network Link Conditioner (profiles below), or
Airplane Mode for "no signal".

## No signal (Airplane Mode)

- [ ] **Cached cold launch** — sign in online, kill the app, go airplane, launch.
      Home installs immediately with circles, feed and your pins; the pins
      *stay* (they used to paint from disk and vanish a second later). Banner
      "You're offline — showing saved data" is under the status bar.
- [ ] **Uncached cold launch** — sign out, sign in online, kill the app before
      Home paints, go airplane, launch. Splash → alert says "Can't reach
      FavCircles. Check your connection and try again." with Retry; never a
      sign-out.
- [ ] **Widget edits survive a kill** — Widgets tab → Water, log 3 cups in
      airplane; the card shows the warning badge. Kill the app. Come back
      online, open the Widgets tab: the 3 cups are there and the badge clears
      within a couple of seconds (pending save retried).
- [ ] **"Log a cup" from the reminder, offline** — the cup is there when the
      Water widget opens (kept as a pending edit).
- [ ] **Home-screen widget keeps its rows** — background the app while in
      airplane; the FavCircles widget on the Home Screen still shows the rows
      it had (it used to blank).
- [ ] **Banner clears** — leave airplane mode; the banner slides away and the
      map/feed refresh on their own.

## Weak signal (NLC "Very Bad Network" or "3G")

- [ ] Home loads with skeletons, no "Request failed: The request timed out"
      alerts; anything that does fail says to check the connection.
- [ ] Widgets tab: Quotes / Fridge Mail / How Are You spinners give up within
      ~30 s with a "Try again", not a full minute.
- [ ] Sending a postcard: the Apple Pay sheet is never dismissed by the app —
      no timeout there, ever.

## Known limits (deliberate, tracked)

- Check-ins, likes, comments and place saves are **not** queued offline; they
  fail with a connection message and must be redone. (Outbox + Idempotency-Key
  is the deferred Tier 3.)
- Quotes, Fridge Mail, How Are You, NextBar and the workout feed hold nothing
  on disk; they render empty offline.
- `APIService` sends request-side `Cache-Control: no-cache`, so the URLCache
  never serves a stale body offline; the app's own disk caches are what carry
  the cached launch.
