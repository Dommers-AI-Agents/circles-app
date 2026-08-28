#!/bin/bash
# driver.sh — records the share-extension demo: Google Maps (Safari web) share
# with inline circle creation, Apple Maps share with one-tap save, then the
# FavCircles auto-open finale. OCR-driven taps (venue card geometry varies);
# marks written to out/actions.log for build.sh audio/caption placement.
set -u
UDID=46A04FA2-CEB7-4194-A1EF-A2CCC9DC88AA
DIR=$(cd "$(dirname "$0")" && pwd)
TOOLS="$DIR/../charlotte-demo/take2/tools"
OUT="$DIR/out"; mkdir -p "$OUT"
LOG="$OUT/actions.log"; : > "$LOG"

CHARLOTTE_NC_CIRCLE="b8xjuYHHDNnUD4bH8Ijq"
# Full Google Maps URL (no redirector): loads Supperland's place panel with
# its photo flare, and the extension parses name straight from q=
GMAPS_URL="https://maps.google.com/?q=Supperland,+1212+The+Plaza,+Charlotte,+NC+28205"

read CFOX CFOY CFW CFH < <("$TOOLS/frame.sh")
export CFOX CFOY CFW CFH
echo "frame: $CFOX $CFOY $CFW $CFH"

# Pre-phase dialog sweep (no marks — recording hasn't started)
pre_dismiss() {
  local TXT="$1" TRIES="${2:-3}"
  for i in $(seq 1 "$TRIES"); do
    xcrun simctl io $UDID screenshot /tmp/_sd_pre.png >/dev/null 2>&1
    local R=$("$TOOLS/ocrfind" /tmp/_sd_pre.png "$TXT")
    if [ "$R" != "NOTFOUND" ] && [ "$R" != "ERR" ]; then
      "$TOOLS/tap.sh" $(($(echo $R | cut -d' ' -f1)/3)) $(($(echo $R | cut -d' ' -f2)/3))
      echo "pre-dismissed: $TXT"; sleep 1.0; return 0
    fi
    sleep 0.7
  done
  return 0
}

# ---- pristine stage ----
# simctl location set triggers an async "Allow widgets from Maps to use your
# location?" prompt ~11s later (killed two takes mid-recording). Set location
# FIRST, ride out the prompt window off-camera, sweep every dialog, THEN roll.
xcrun simctl location $UDID set 35.2271,-80.8431
xcrun simctl terminate $UDID com.favcircles.circles 2>/dev/null
xcrun simctl terminate $UDID com.apple.Maps 2>/dev/null
xcrun simctl terminate $UDID com.apple.mobilesafari 2>/dev/null
osascript -e 'tell application "Simulator" to activate'; sleep 0.5
xcrun simctl launch $UDID com.apple.Maps >/dev/null 2>&1
sleep 5
pre_dismiss "Allow While Using App" 2
pre_dismiss "Not Now" 2
pre_dismiss "Continue" 2
echo "riding out the widgets-location prompt window..."
sleep 10
pre_dismiss "Allow" 4
sleep 4
pre_dismiss "Allow" 3
xcrun simctl terminate $UDID com.apple.Maps 2>/dev/null
sleep 1

# Pre-load the Google Maps place page OFF-CAMERA: the recording must open on
# the rendered page — no black loading screen, and none of Google's app-nag
# interstitials (two known variants: "Go back to web" and "Stay on web").
# Verified visible via the place panel's "Office supply store" line before
# rolling; abort if it never appears.
xcrun simctl openurl $UDID "$GMAPS_URL"
sleep 6
PAGE_READY=0
for i in $(seq 1 14); do
  pre_dismiss "Stay on web" 1
  pre_dismiss "Go back to web" 1
  pre_dismiss "Continue" 1
  xcrun simctl io $UDID screenshot /tmp/_sd_pre.png >/dev/null 2>&1
  R=$("$TOOLS/ocrfind" /tmp/_sd_pre.png "Directions")
  if [ "$R" != "NOTFOUND" ] && [ "$R" != "ERR" ]; then PAGE_READY=1; break; fi
  sleep 1
done
if [ "$PAGE_READY" != "1" ]; then echo "PRE-LOAD FAILED: place page never rendered" >&2; exit 1; fi
sleep 1.5
xcrun simctl spawn $UDID defaults write group.com.favcircles.circles shareExt.lastCircleId -string "$CHARLOTTE_NC_CIRCLE" 2>/dev/null
xcrun simctl status_bar $UDID override --time "9:41" --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularMode active --cellularBars 4 2>/dev/null
sleep 2
osascript -e 'tell application "Simulator" to activate'; sleep 0.6

rm -f "$OUT/walk_raw.mp4"
xcrun simctl io $UDID recordVideo --codec h264 --force "$OUT/walk_raw.mp4" &
RECPID=$!
sleep 1.0

T0=$(python3 -c "import time; print(time.time())")
mark() { python3 -c "import time; print('%0.2f  %s' % (time.time()-$T0, '$1'))" >> "$LOG"; }
at()   { python3 -c "import time; time.sleep(max(0, $T0+$1-time.time()))"; mark "$2"; }
rel()  { python3 -c "import time; time.sleep(max(0,$1))"; mark "$2"; }

die() { mark "FAIL-$1"; kill -INT $RECPID 2>/dev/null; wait $RECPID 2>/dev/null; echo "DRIVER FAILED: $1" >&2; exit 1; }

# Optional variant: tap if present, silently continue if not.
ocr_tap_opt() {
  local TXT="$1" NAME="$2" TRIES="${3:-4}"
  for i in $(seq 1 "$TRIES"); do
    xcrun simctl io $UDID screenshot /tmp/_sd_ocr.png >/dev/null 2>&1
    local R=$("$TOOLS/ocrfind" /tmp/_sd_ocr.png "$TXT")
    if [ "$R" != "NOTFOUND" ] && [ "$R" != "ERR" ]; then
      local PX=$(echo $R | cut -d' ' -f1) PY=$(echo $R | cut -d' ' -f2)
      "$TOOLS/tap.sh" $((PX/3)) $((PY/3))
      mark "$NAME"
      return 0
    fi
    sleep 0.8
  done
  mark "skip-$NAME"
  return 0
}

# The red guidance line contains the word "Save", which OCR matches before
# the button — so Save is tapped by GEOMETRY: find the circle-picker label,
# tap 59pts below it (12 spacing + half of each control).
tap_save_below() {
  local LABEL="$1" NAME="$2" TRIES="${3:-10}"
  for i in $(seq 1 "$TRIES"); do
    xcrun simctl io $UDID screenshot /tmp/_sd_ocr.png >/dev/null 2>&1
    local R=$("$TOOLS/ocrfind" /tmp/_sd_ocr.png "$LABEL")
    if [ "$R" != "NOTFOUND" ] && [ "$R" != "ERR" ]; then
      local PX=$(echo $R | cut -d' ' -f1) PY=$(echo $R | cut -d' ' -f2)
      "$TOOLS/tap.sh" $((PX/3)) $((PY/3 + 59))
      mark "$NAME"
      return 0
    fi
    sleep 0.8
  done
  die "$NAME"
}

# OCR-find "text", tap it, mark. Retries every 0.8s up to $3 tries.
ocr_tap() {
  local TXT="$1" NAME="$2" TRIES="${3:-8}"
  for i in $(seq 1 "$TRIES"); do
    xcrun simctl io $UDID screenshot /tmp/_sd_ocr.png >/dev/null 2>&1
    local R=$("$TOOLS/ocrfind" /tmp/_sd_ocr.png "$TXT")
    if [ "$R" != "NOTFOUND" ] && [ "$R" != "ERR" ]; then
      local PX=$(echo $R | cut -d' ' -f1) PY=$(echo $R | cut -d' ' -f2)
      "$TOOLS/tap.sh" $((PX/3)) $((PY/3))
      mark "$NAME"
      return 0
    fi
    sleep 0.8
  done
  die "$NAME"
}

# ================= Segment A: Google Maps (Safari) =================
# Page is already loaded and nag-free from the pre-phase — the video opens on
# the rendered Google Maps place page while the intro line plays, with a
# scroll flourish through the restaurant's photo panel for flare.
at  0.5  "audio-b00"
sleep 1.4
"$TOOLS/drag.sh" 220 720 220 400 600; mark "flourish-up"
sleep 1.6
"$TOOLS/drag.sh" 220 430 220 700 600; mark "flourish-down"
sleep 1.2
"$TOOLS/tap.sh" 380 895; mark "safari-menu"      # Safari ... menu
sleep 1.3
rel 0 "audio-b01"
ocr_tap "Share" "safari-share" 6
sleep 1.8
ocr_tap "FavCircles" "pick-favcircles" 8
rel 1.6 "audio-b02"                               # card resolving
# wait for resolution: the picker button label appears when circles load
ocr_tap "Charlotte NC" "open-picker" 14
rel 0.4 "audio-b03"
ocr_tap "New Circle" "new-circle" 8
sleep 1.2
cliclick t:"Date Nights"; mark "typed-name"
sleep 0.6
ocr_tap "Create" "create-circle" 6
sleep 2.2                                          # circle created, picker closes
rel 0 "audio-b04"
tap_save_below "Date Nights" "save-a" 10
sleep 3.4                                          # success card
rel 0.8 "dwell-success-a"
ocr_tap "Done" "done-a" 8
sleep 0.6

# ================= Segment B: Apple Maps (quick!) =================
rel 0 "audio-b05"
xcrun simctl openurl $UDID "maps://?q=The%20Crunkleton%20Charlotte"; mark "maps-open"
sleep 4.0
"$TOOLS/tap.sh" 44 568; mark "maps-share"          # place card share button
sleep 1.6
ocr_tap "FavCircles" "pick-favcircles-b" 8
sleep 4.0                                          # card resolves (Date Nights preselected)
rel 0 "audio-b06"
tap_save_below "Date Nights" "save-b" 12
sleep 3.2
rel 0.5 "dwell-success-b"
ocr_tap "Done" "done-b" 8
sleep 0.6

# ================= Segment C: open FavCircles =================
rel 0 "audio-b07"
xcrun simctl launch $UDID com.favcircles.circles >/dev/null; mark "app-launch"
sleep 6.5                                          # auto-navigate to Supperland
rel 0 "audio-b08"
sleep 4.0
mark "end"

kill -INT $RECPID 2>/dev/null
wait $RECPID 2>/dev/null
xcrun simctl status_bar $UDID clear 2>/dev/null
echo "=== marks ==="; cat "$LOG"
echo "raw: $OUT/walk_raw.mp4"
