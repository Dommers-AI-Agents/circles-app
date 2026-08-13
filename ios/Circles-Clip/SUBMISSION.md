# App Clip — Submission Checklist

Everything code-side is done, deployed, and E2E-verified (see git log on
`feature/app-clip`). What remains is App Store Connect configuration, done
once, at/after the first build upload that contains the clip.

## Already live / verified

- [x] Backend deployed: AASA `appclips` key, `/api/clip/*`, signup attribution,
      funnel counters (`clipScans` → `clipSignups` → `clipInstalls` on
      stickerVenues stats + owner dashboard headline)
- [x] Full flow verified against production in simulator: scan URL → offer →
      email signup → 100 pts → SKOverlay → full app installs → launches
      logged in (App Group mailbox handoff), conversion counted exactly once
- [x] Clip bundle ~4.5MB debug — far under the 15MB limit

## Before/with the next submission

1. **Version alignment (every submission)**: the clip's `MARKETING_VERSION`
   and `CURRENT_PROJECT_VERSION` must equal the app's. They're set per-target
   in project.pbxproj (currently 1.2.4 / 22, matching the app). When you bump
   the app for a release, bump the `Circles-Clip` target the same way
   (Xcode > project > each target > General, or edit both build configs).
2. **Portal** (Xcode automatic signing usually does all of this on the first
   device build/archive — verify in developer.apple.com > Identifiers):
   - App ID `com.favcircles.circles.Clip` with: App Clip (parent
     `com.favcircles.circles`), Sign in with Apple, Associated Domains,
     App Groups (`group.com.favcircles.circles`)
   - Parent App ID `com.favcircles.circles` gains App Groups
     (`group.com.favcircles.circles`)
3. **Upload the build** (archive from this branch; the clip embeds
   automatically — check the archive's contents show Circles-Clip.app under
   AppClips).
4. **ASC → app version → App Clip section**:
   - Header image 1800×1200 px, no transparency (shown on the clip card).
   - Subtitle: e.g. "Earn rewards at your favorite spots"
   - Action verb: **Open**
5. **ASC → Advanced App Clip Experiences** (this is what makes CAMERA/QR
   scans of the printed stickers open the clip — the default experience only
   covers Safari/Messages):
   - URL prefix: `https://api.favcircles.com/s/`
   - Bundle ID: com.favcircles.circles.Clip
6. **App Review notes** (paste into the version's review notes):

   > This build adds an App Clip for in-store signup. Stores display QR codes
   > that encode URLs like https://api.favcircles.com/s/5IRJ9M
   > (that exact code is a live demo venue, "Demo Cafe (App Review)",
   > maintained for review). Scanning with the Camera opens the App Clip,
   > which shows the store and a 100-point signup offer. Account creation is
   > the core purpose of the clip: a new customer standing at the register
   > signs up (Sign in with Apple or email/password) and immediately receives
   > 100 loyalty points for that store, spendable at the counter. The clip
   > then offers the full app; after install, the session carries over and
   > the user is already signed in.
   > Demo flow: scan or open https://api.favcircles.com/s/5IRJ9M → sign up
   > with any email → points confirmation → "Get the full app".

7. **Physical-device smoke test before submitting** (TestFlight or dev build):
   - Settings > Developer > App Clips Testing > Local Experiences: register
     `https://api.favcircles.com/s/5IRJ9M` → scan a printed QR of that URL
     with the Camera → clip card appears → full flow.
   - If associated-domain validation lags (Apple CDN), add `?mode=developer`
     to the domain entry in the clip's entitlements while testing.
   - Existing-user check: update an installed, logged-in build to this one —
     session must survive (expected: nothing changes; the keychain
     entitlement edit was reverted, only an App Group was added).

## Known accepted behaviors

- 100-pt signup bonus is once per user ever, at the first store scanned
  (`signup:<userId>` idempotency) — a second store's QR won't re-award.
- `clipScans` counts preview fetches (relaunches/retries inflate it slightly);
  directional metric by design.
- If the user dismisses SKOverlay and installs days later after iOS purges
  clip data, they see the login screen instead of auto-login — sign-in works
  normally; nothing double-awards.

## Test-data note (2026-08-13)

E2E testing created three throwaway accounts (`clip-test-0813@…`,
`normal-test-0813@…`, `ui-test-0813@favcircles-testing.example.com` — the
last one auto-follows Wes and holds 100 Demo Cafe points) and bumped Demo
Cafe's stats (clipScans/clipSignups/clipInstalls = 2, +1 scan/signup). Leave
or clean up at your leisure.
