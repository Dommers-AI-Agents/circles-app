#!/bin/bash
# driver.sh — v8: Apple Maps save -> open FavCircles -> Profile -> Charlotte NC
# circle -> scroll to The Crunkleton -> place view, then hold on the action
# row while build.sh rings Directions / Call / Reserve / Delivery / Ride in
# sync with the narration. Logo intro/outro cards are added by build.sh.
# OCR-driven; marks logged for build.sh (which auto-cuts all dead space).
set -u
UDID=46A04FA2-CEB7-4194-A1EF-A2CCC9DC88AA
DIR=$(cd "$(dirname "$0")" && pwd)
TOOLS="$DIR/../charlotte-demo/take2/tools"
OUT="$DIR/out"; mkdir -p "$OUT"
LOG="$OUT/actions.log"; : > "$LOG"
HL="$OUT/hl.log"; : > "$HL"

CHARLOTTE_NC_CIRCLE="b8xjuYHHDNnUD4bH8Ijq"
GROUP=$(xcrun simctl get_app_container $UDID com.favcircles.circles group.com.favcircles.circles 2>/dev/null)

read CFOX CFOY CFW CFH < <("$TOOLS/frame.sh")
export CFOX CFOY CFW CFH
echo "frame: $CFOX $CFOY $CFW $CFH   group: $GROUP"

shot() { xcrun simctl io $UDID screenshot "$1" >/dev/null 2>&1; }
find_txt() {  # find_txt <png> <needle> -> "x y" (px) or ""
  local R=$("$TOOLS/ocrfind" "$1" "$2")
  if [ "$R" != "NOTFOUND" ] && [ "$R" != "ERR" ]; then echo "$R"; fi
}

pre_dismiss() {
  local TXT="$1" TRIES="${2:-3}"
  for i in $(seq 1 "$TRIES"); do
    shot /tmp/_sd_pre.png
    local R=$(find_txt /tmp/_sd_pre.png "$TXT")
    if [ -n "$R" ]; then
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
rm -f "$GROUP/pending-open-place.json"
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
  shot /tmp/_sd_pre.png
  [ -n "$(find_txt /tmp/_sd_pre.png Website)" ] && { PAGE_READY=1; break; }
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
  local TXT="$1" NAME="$2" TRIES="${3:-8}" DY="${4:-0}"
  for i in $(seq 1 "$TRIES"); do
    shot /tmp/_sd_ocr.png
    local R=$(find_txt /tmp/_sd_ocr.png "$TXT")
    if [ -n "$R" ]; then
      local PX=$(echo $R | cut -d' ' -f1) PY=$(echo $R | cut -d' ' -f2)
      "$TOOLS/tap.sh" $((PX/3)) $((PY/3 + DY))
      mark "$NAME"
      return 0
    fi
    sleep 0.8
  done
  die "$NAME"
}

wait_txt() {  # wait_txt <needle> <tries> — block until text is on screen
  for i in $(seq 1 "$2"); do
    shot /tmp/_sd_ocr.png
    [ -n "$(find_txt /tmp/_sd_ocr.png "$1")" ] && return 0
    sleep 0.8
  done
  return 1
}

# ============ Segment 1: Apple Maps save ============
at  0.5  "audio-b00"
sleep 5.4                                          # b00 (5.1s) over the card
"$TOOLS/tap.sh" 44 568; mark "maps-share"          # place card share button
sleep 1.4
rel 0 "audio-b01"
# The share tap occasionally doesn't register, and the sheet's app row can
# take several seconds to populate. Wait for FavCircles; only re-tap when
# no sheet is up at all (an eager retap dismisses the one it just opened).
for i in 1 2 3; do
  FOUND=0
  for j in $(seq 1 8); do
    shot /tmp/_sd_ocr.png
    [ -n "$(find_txt /tmp/_sd_ocr.png FavCircles)" ] && { FOUND=1; break; }
    if [ "$j" -ge 3 ] && [ -z "$(find_txt /tmp/_sd_ocr.png Copy)" ]; then break; fi   # no sheet
    sleep 1.2
  done
  if [ "$FOUND" = "1" ]; then break; fi
  "$TOOLS/tap.sh" 44 568; mark "retap-share"
  sleep 1.8
done
ocr_tap "FavCircles" "pick-favcircles" 8
sleep 3.4                                          # card resolves
rel 0 "audio-b02"
sleep 2.2
ocr_tap "Charlotte NC" "save-a" 12 59              # Save button sits below the circle name
sleep 3.2                                          # success card (visual only)
rel 1.0 "dwell-success"
ocr_tap "Done" "done-a" 10
sleep 0.8
# The extension wrote the pending-open mailbox at save time; drop it so the
# app opens on Home and we navigate to the place BY HAND on camera.
rm -f "$GROUP/pending-open-place.json"

# ============ Segment 2: FavCircles -> Profile -> circle -> place ============
rel 0 "audio-b03"
xcrun simctl launch $UDID com.favcircles.circles >/dev/null; mark "app-launch"
# "Add Place" also matches the splash's "add places" copy — wait for the
# home feed header instead, which only exists once the tab bar is live.
wait_txt "Recent Activity" 30 || die "home-never-rendered"
sleep 1.5
rel 0 "audio-b03b"
sleep 0.4
for i in 1 2 3; do
  "$TOOLS/tap.sh" 362 900; mark "me-tab"
  wait_txt "Edit profile" 5 && break
done
sleep 1.8                                          # let the circle covers load
ocr_tap "Charlotte NC" "open-circle" 10 -50        # tap the cover bubble above the label
wait_txt "All Categories" 10 || die "circle-never-opened"   # profile also says "850 Places"
sleep 2.2                                          # cover photo + place cards render
# Firestore returns the circle's places in doc-id order, so the fresh save
# lands anywhere in the 74-place list: flick until OCR finds it.
PLACE_Y=""
for i in $(seq 1 16); do
  shot /tmp/_sd_ocr.png
  R=$(find_txt /tmp/_sd_ocr.png "Crunkleton")
  if [ -n "$R" ]; then
    PLACE_Y=$(($(echo $R | cut -d' ' -f2)/3))
    if [ "$PLACE_Y" -gt 820 ]; then                # tucked under the tab bar: nudge up
      "$TOOLS/flick.sh" 220 700 420; mark "nudge"; sleep 0.9
      shot /tmp/_sd_ocr.png
      R=$(find_txt /tmp/_sd_ocr.png "Crunkleton"); [ -n "$R" ] || continue
      PLACE_Y=$(($(echo $R | cut -d' ' -f2)/3))
    fi
    break
  fi
  "$TOOLS/flick.sh" 220 780 150; mark "scroll-$i"
  sleep 0.9
done
[ -n "$PLACE_Y" ] || die "crunkleton-not-in-list"
rel 0 "audio-b03c"
sleep 1.0
"$TOOLS/tap.sh" 70 $PLACE_Y; mark "open-place"     # the card photo (title label eats taps)
wait_txt "Added by" 10 || die "place-view-never-opened"
sleep 1.2

# ============ Segment 3: action row + highlights ============
sleep 0.6
# Log the on-screen button centers (screenshot px) for build.sh's rings.
shot "$OUT/hl_frame.png"
for L in Directions Call Website Delivery Reserve Ride; do
  R=$(find_txt "$OUT/hl_frame.png" "$L"); [ -n "$R" ] && echo "$L $R" >> "$HL"
done
if ! grep -q '^Call ' "$HL"; then                  # 4-letter label: OCR can miss it
  DX=$(grep '^Directions' "$HL" | cut -d' ' -f2); DY=$(grep '^Directions' "$HL" | cut -d' ' -f3)
  RX=$(grep '^Reserve' "$HL" | cut -d' ' -f2)
  [ -n "$DY" ] && [ -n "$RX" ] && echo "Call $RX $DY" >> "$HL"
fi
echo "hl: $(tr '\n' ';' < "$HL")"
mark "hl-start"
rel 0.2 "audio-b04"
sleep 9.0                                          # rings + "all from one place" dwell
mark "end"

kill -INT $RECPID 2>/dev/null
wait $RECPID 2>/dev/null
xcrun simctl status_bar $UDID clear 2>/dev/null
echo "=== marks ==="; cat "$LOG"
echo "raw: $OUT/walk_raw.mp4"
