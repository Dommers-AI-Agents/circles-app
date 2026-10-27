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
| `App Previews (iPhone Duo)/01-folded-886x1920.mp4` | **iPhone Duo → App Previews** | 886 × 1920 portrait, folded footage |
| `App Previews (iPhone Duo)/02-unfolded-1920x886.mp4` | **iPhone Duo → App Previews** | 1920 × 886 landscape, unfolded footage |

The slides reuse the September headlines (map, friends, postcards, circles, place, rewards, widgets,
privacy) so the Duo page reads the same as the iPhone page. Duo previews are accepted only at the
regular iPhone preview sizes, so the folded footage sits in a Duo frame on the brand background with
captions, and the unfolded footage in a landscape frame.

## Status

**2026-10-27: nothing here is upload-ready.** The app does not yet keep its controls inside the Duo's
safe area (iOS 27.1 lays the status bar, navigation buttons and tab bar out as a vertical rail on the
right edge, and the app's Add button, filter chips, Add to My Circle and Add Photo sit under it). The
`DRAFT …` folders show the problem on the actual slides; re-capture after the layout fix.

- [x] Capture harness, slide canvases and preview framing built and smoke-tested (2026-10-27).
- [ ] Captures on Wes's account (the sim must be signed in first, see below).
- [ ] Slides rendered and checked.
- [ ] Previews recorded, framed and checked.

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
4. **Previews**: record with `xcrun simctl io <udid> recordVideo --display=1` (folded) or `--display=3`
   (unfolded) while driving the app, then
   `source/build-preview-duo.sh outer footage.mov captions.json out.mp4` (or `inner`). The script frames
   the footage, overlays timed captions and writes H.264 High 4.0, 30 fps, silent stereo AAC 256k.

Simulator facts: udid `886F26D1-1279-4744-B932-2DD907E47A22`; only one display is lit at a time; the
inner display captures landscape (2853 × 2007); DeviceHub replaced Simulator.app in Xcode 27.
