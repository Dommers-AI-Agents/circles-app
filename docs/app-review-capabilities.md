# Capability → feature → where the reviewer taps

Every capability we declare is something App Review will look for and reject if
they cannot find it. Two of our rejections were exactly that: PassKit linked
with Apple Pay unreachable (2.1, Sept 17), and `audio` declared with Sleep
Sounds buried four taps deep (2.5.4, Sept 20).

**Paste the table into App Review Notes on every submission.** If a row has no
navigation path, the capability comes out of the plist — not into the notes.

Sources of truth that must agree:
- `ios/Circles-iOS-UIKit/Info.plist` (manual)
- `INFOPLIST_KEY_UIBackgroundModes` in `project.pbxproj` (generated half)

They are merged, so a value in only one of them is a drift waiting to surprise
us. Keep them identical.

## UIBackgroundModes

| Mode | Feature that justifies it | Where the reviewer taps |
|---|---|---|
| `audio` | Sleep Sounds — 12 synthesized ambient sounds, fading timer, lock-screen transport | Home tab → **Widgets** segment → **Sleep Sounds** → pick a sound → Play → press Home; audio continues, Now Playing shows on the Lock Screen |
| `remote-notification` | Push: check-in nudges, postcard status, care check-ins, quotes | Any push; Settings → Notifications |
| `fetch` | Background refresh of places/activity | — |
| `processing` | Import resolution queue, photo backfill | Circles → import a Google Maps list |
| `location` | Visit detection — significant-change monitoring that suggests places you stopped at | Me → Settings → **Visits**; `VisitDetectionService` sets `allowsBackgroundLocationUpdates` |

## Entitlements & frameworks

| Capability | Feature | Where the reviewer taps |
|---|---|---|
| Apple Pay (PassKit / Stripe) | Printed postcard mail; Fridge Mail packs + subscription | Home → **Widgets** → **Postcard** → add a photo → turn on **Mail a printed card** → fill the address → the **Apple Pay button** at the bottom |
| App Groups | Share Extension + Home Screen widget auth mirror | Share a link from Safari → FavCircles |
| Associated Domains | Passkeys (RP `favcircles.com`), universal links | Me → Settings → Set Up Passkey |

## Before every submission

1. Diff the two `UIBackgroundModes` sources; they must match.
2. For each row above, walk the path yourself on a **physical device**. A path
   you cannot walk is a rejection already written.
3. Any capability added since the last submission gets a fresh row **and** a
   screen recording attached to the notes if it is a background mode.
4. When a guideline is cited, read the **whole** guideline, not the sentence
   Apple quoted. 4.9 was rejected twice: once for Apple Pay being unreachable,
   then again for the button not being Apple's — both are in the same guideline.
