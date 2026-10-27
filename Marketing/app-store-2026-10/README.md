# App Store assets, October 2026 — iPhone Duo

iPhone Duo screenshots and App Previews for the 1.4.1 submission, captured on the iPhone Duo
simulator (Xcode 27.1, iOS 27.1) on Wes's account in Charlotte. Apple takes Duo screenshots in two
sizes and shows an "optimized for iPhone Duo" badge on the product page once they're uploaded.
They're optional today and required from April 2027 for apps built with the iOS 27.1 SDK.

## Where each folder goes in App Store Connect

App Store Connect → FavCircles → the version you're preparing → **Previews and Screenshots** → iPhone Duo.

| Folder | Slot | Size |
|---|---|---|
| `iPhone Duo outer 1398x2034/` | **iPhone Duo, outer display** (folded) | 1398 × 2034 |
| `iPhone Duo inner 2853x2007/` | **iPhone Duo, inner display** (unfolded, landscape) | 2853 × 2007 |
| `App Previews (iPhone Duo)/01-folded-886x1920.mp4` | **iPhone Duo → App Previews** (1st) | 886 × 1920 portrait, folded footage, 29.5 s |
| `App Previews (iPhone Duo)/02-unfolded-1920x886.mp4` | **iPhone Duo → App Previews** (2nd) | 1920 × 886 landscape, unfolded footage, 29.3 s |

The slides reuse the September headlines (map, friends, postcards, circles, place, rewards, widgets,
privacy) so the Duo page reads the same as the iPhone page. Duo previews are accepted only at the
regular iPhone preview sizes, so the folded footage sits in a Duo frame on the brand background with
captions, and the unfolded footage in a landscape frame.

## Status (2026-10-27)

- [x] App-wide safe-area sweep so nothing sits under the Duo's vertical rail (840 constraints, 150 files),
      plus the map filter chips and the Add to My Circle title at the narrower folded width.
- [x] 8 folded slides, 8 unfolded slides, both captured on Wes's account after the sweep.
- [x] Two previews: folded 886×1920 (29.5 s) and unfolded 1920×886 (29.3 s), captions timed to the footage.
- [x] Folded landscape checked (place page and map).
- Upload with 1.4.1. Nearby offers on the Store Points slide shows "Test Bakery (Demo)"; re-shoot that one
  screen if a real store should be there.

## How it's made (`source/`)

1. **Sign the Duo sim in** (once per sim): drop a `clip-auth-handoff.json` session mailbox in the
   app's App Group container and launch the app (the recipe in the simulator-screenshot memory).
   The app must be built with normal simulator signing; `CODE_SIGNING_ALLOWED=NO` strips the App
   Group entitlement and the mailbox is never read.
2. **Capture** (Mac unlocked, DeviceHub showing the Duo window):
   `source/capture-duo.sh Closed source/raw-duo-outer` then `source/capture-duo.sh Open source/raw-duo-inner`.
   It folds the device through DeviceHub's Closed/Open buttons, runs the tap-servant UI test
   (`Circles-iOSUITests/DuoAppStoreCaptureUITests`), navigates with `simctl openurl` universal links and
   screenshots the live display with `simctl io screenshot --display=1|3`.
3. **Slides**: `source/render-duo.sh outer` and `source/render-duo.sh inner` (slide lists in
   `source/duo-outer.json` / `source/duo-inner.json`, canvases `duoOuter`/`duoInner` in the September
   `compose.js`, rendered with Chrome headless, converted to JPEG without alpha).
4. **Previews**: `source/record-preview-duo.sh Closed|Open out.mov` records a warm-start deep-link tour
   (home → place → profile → widgets → full map; the modal map goes last because place/profile links don't
   show over it). Check the scene times with a one-frame-per-second filmstrip, put them in
   `source/captions-folded.json` / `captions-unfolded.json`, then
   `source/build-preview-duo.sh outer|inner footage.mov captions.json out.mp4` frames the footage, overlays
   the captions and writes H.264 High 4.0, 30 fps, ≤29.8 s, silent stereo AAC 256k. Re-record if a chat
   banner or a home prompt (Log a workout, postcard nudge) lands in the take.
5. **Folded landscape**: `source/landscape-check.sh outdir` rotates the folded Duo and shoots home, place, map.

Simulator facts: udid `886F26D1-1279-4744-B932-2DD907E47A22`; only one display is lit at a time; the
inner display captures landscape (2853 × 2007); DeviceHub replaced Simulator.app in Xcode 27.
