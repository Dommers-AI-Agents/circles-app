#!/bin/bash
# driver.sh — v5: Apple Maps only on camera (narration covers Google too).
# Save The Crunkleton from Apple Maps -> open FavCircles -> place view with
# the DoorDash/Reserve/Uber-Lyft partner chips -> finish on the home map.
# OCR-driven; marks logged for build.sh (which auto-cuts all dead space).
set -u
UDID=46A04FA2-CEB7-4194-A1EF-A2CCC9DC88AA
DIR=$(cd "$(dirname "$0")" && pwd)
TOOLS="$DIR/../charlotte-demo/take2/tools"
OUT="$DIR/out"; mkdir -p "$OUT"
LOG="$OUT/actions.log"; : > "$LOG"

CHARLOTTE_NC_CIRCLE="b8xjuYHHDNnUD4bH8Ijq"

read CFOX CFOY CFW CFH < <("$TOOLS/frame.sh")
export CFOX CFOY CFW CFH
echo "frame: $CFOX $CFOY $CFW $CFH"

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

# ---- pristine stage (widgets-location prompt ridden out off-camera) ----
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
# Pre-open the Crunkleton place card OFF-CAMERA so frame one is the loaded
# Apple Maps card, not a search animation.
xcrun simctl openurl $UDID "maps://?q=The%20Crunkleton%20Charlotte"
sleep 5
PAGE_READY=0
for i in $(seq 1 10); do
  xcrun simctl io $UDID screenshot /tmp/_sd_pre.png >/dev/null 2>&1
  R=$("$TOOLS/ocrfind" /tmp/_sd_pre.png "Website")
  if [ "$R" != "NOTFOUND" ] && [ "$R" != "ERR" ]; then PAGE_READY=1; break; fi
  sleep 1
done
if [ "$PAGE_READY" != "1" ]; then echo "PRE-LOAD FAILED: Maps card never rendered" >&2; exit 1; fi
xcrun simctl spawn $UDID defaults write group.com.favcircles.circles shareExt.lastCircleId -string "$CHARLOTTE_NC_CIRCLE" 2>/dev/null
xcrun simctl status_bar $UDID override --time "9:41" --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularMode active --cellularBars 4 2>/dev/null
sleep 1.5
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

# ============ Segment 1: Apple Maps save ============
at  0.5  "audio-b00"
sleep 8.3                                          # full intro line over the card
"$TOOLS/tap.sh" 44 568; mark "maps-share"          # place card share button
sleep 1.4
rel 0 "audio-b01"
# The first share tap occasionally doesn't register — but the sheet also
# takes ~2s to render the app row, so be PATIENT before re-tapping (an
# eager retap dismisses the sheet it just opened).
for i in 1 2 3; do
  FOUND=0
  for j in 1 2 3; do
    xcrun simctl io $UDID screenshot /tmp/_sd_ocr.png >/dev/null 2>&1
    R=$("$TOOLS/ocrfind" /tmp/_sd_ocr.png "FavCircles")
    if [ "$R" != "NOTFOUND" ] && [ "$R" != "ERR" ]; then FOUND=1; break; fi
    sleep 1.4
  done
  if [ "$FOUND" = "1" ]; then break; fi
  "$TOOLS/tap.sh" 44 568; mark "retap-share"
  sleep 1.8
done
ocr_tap "FavCircles" "pick-favcircles" 8
sleep 3.4                                          # card resolves
rel 0 "audio-b02"
sleep 2.2
tap_save_below "Charlotte NC" "save-a" 12
sleep 3.2                                          # success card (visual only)
rel 1.0 "dwell-success"
ocr_tap "Done" "done-a" 10
sleep 0.6

# ============ Segment 2: FavCircles place view + partner chips ============
rel 0 "audio-b03"
xcrun simctl launch $UDID com.favcircles.circles >/dev/null; mark "app-launch"
sleep 6.0                                          # auto-navigate to the place
# Verify the place view actually opened (cold-launch nav can lag); if not,
# give it a moment more, then relaunch once as a last resort.
PLACE_OK=0
for i in $(seq 1 6); do
  xcrun simctl io $UDID screenshot /tmp/_sd_ocr.png >/dev/null 2>&1
  R=$("$TOOLS/ocrfind" /tmp/_sd_ocr.png "Added by")
  if [ "$R" != "NOTFOUND" ] && [ "$R" != "ERR" ]; then PLACE_OK=1; break; fi
  sleep 1.0
done
if [ "$PLACE_OK" != "1" ]; then die "place-view-never-opened"; fi
"$TOOLS/drag.sh" 220 700 220 545 500; mark "chips-scroll"
rel 0.3 "audio-b04"
sleep 8.0    # dwell until the chips line has FULLY landed before leaving

# ============ Segment 3: My Places map ============
ocr_tap "Home" "back-to-home" 8                    # Home tab pops to the map
sleep 1.4
ocr_tap "Everyone" "open-person-filter" 8
sleep 1.4
ocr_tap "My Places" "pick-my-places" 8
sleep 1.0
rel 0 "audio-b05"
sleep 4.6                                          # dwell on the filtered map

# ============ Segment 4: profile circles finale ============
"$TOOLS/tap.sh" 362 900; mark "me-tab"
sleep 2.6
"$TOOLS/drag.sh" 220 700 220 520 500; mark "profile-scroll"
rel 0.3 "audio-b06"
sleep 6.0                                          # circles grid dwell
mark "end"

kill -INT $RECPID 2>/dev/null
wait $RECPID 2>/dev/null
xcrun simctl status_bar $UDID clear 2>/dev/null
echo "=== marks ==="; cat "$LOG"
echo "raw: $OUT/walk_raw.mp4"
