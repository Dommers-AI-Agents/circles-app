#!/bin/bash
# driver.sh — Google Maps LIST → FavCircles circle. The simulator has no Google
# Maps app, so the list is the real Google Maps web page in Safari (title,
# author, 31 places, in-page Share). Share → FavCircles list card → Save →
# open the app → Profile → scroll to the new circle → open it, flick through
# the places → back to the profile grid. OCR-driven; marks logged for
# build.sh (which auto-cuts all dead space). Brand cards come from build.sh.
set -u
UDID=46A04FA2-CEB7-4194-A1EF-A2CCC9DC88AA
DIR=$(cd "$(dirname "$0")" && pwd)
TOOLS="$DIR/../charlotte-demo/take2/tools"
OUT="$DIR/out"; mkdir -p "$OUT"
LOG="$OUT/actions.log"; : > "$LOG"
LIST_URL="https://goo.gl/maps/RtwSMUSaDyizyFL96"     # "The best Paris coffee & brunch spots" (31)
GROUP=$(xcrun simctl get_app_container $UDID com.favcircles.circles group.com.favcircles.circles 2>/dev/null)

read CFOX CFOY CFW CFH < <("$TOOLS/frame.sh")
export CFOX CFOY CFW CFH
echo "frame: $CFOX $CFOY $CFW $CFH   group: $GROUP"

shot() { xcrun simctl io $UDID screenshot "$1" >/dev/null 2>&1; }
find_txt() {  # find_txt <png> <needle> -> "x y" (px) or ""
  local R=$("$TOOLS/ocrfind" "$1" "$2")
  if [ "$R" != "NOTFOUND" ] && [ "$R" != "ERR" ]; then echo "$R"; fi
}

# ---- pristine stage ----
xcrun simctl location $UDID set 35.2271,-80.8431
xcrun simctl terminate $UDID com.favcircles.circles 2>/dev/null
xcrun simctl terminate $UDID com.apple.Maps 2>/dev/null
xcrun simctl terminate $UDID com.apple.mobilesafari 2>/dev/null
rm -f "$GROUP/pending-open-place.json" "$GROUP/pending-open-circle.json"
osascript -e 'tell application "Simulator" to activate'; sleep 0.5
# Home screen first so Safari's status bar doesn't carry a "◀ FavCircles" breadcrumb.
osascript -e 'tell application "System Events" to keystroke "h" using {command down, shift down}'; sleep 1.2
xcrun simctl launch $UDID com.apple.mobilesafari >/dev/null 2>&1; sleep 2
xcrun simctl openurl $UDID "$LIST_URL"
PAGE_READY=0
for i in $(seq 1 25); do
  shot /tmp/_ld_pre.png
  [ -n "$(find_txt /tmp/_ld_pre.png "31 places")" ] && { PAGE_READY=1; break; }
  # Google sometimes interposes "Looks like you already have Google Maps
  # app installed" — take the "Stay on web" link.
  SW=$(find_txt /tmp/_ld_pre.png "Stay on web")
  if [ -n "$SW" ]; then "$TOOLS/tap.sh" $(($(echo $SW | cut -d' ' -f1)/3)) $(($(echo $SW | cut -d' ' -f2)/3)); echo "dismissed Open-app interstitial"; sleep 2; fi
  sleep 1
done
if [ "$PAGE_READY" != "1" ]; then echo "PRE-LOAD FAILED: list page never rendered" >&2; exit 1; fi
sleep 2   # hero + first card images
xcrun simctl status_bar $UDID override --time "9:41" --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularMode active --cellularBars 4 2>/dev/null
sleep 1.0
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
    shot /tmp/_ld_ocr.png
    local R=$(find_txt /tmp/_ld_ocr.png "$TXT")
    if [ -n "$R" ]; then
      "$TOOLS/tap.sh" $(($(echo $R | cut -d' ' -f1)/3)) $(($(echo $R | cut -d' ' -f2)/3 + DY))
      mark "$NAME"; return 0
    fi
    sleep 0.8
  done
  die "$NAME"
}
wait_txt() {  # wait_txt <needle> <tries>
  for i in $(seq 1 "$2"); do
    shot /tmp/_ld_ocr.png
    [ -n "$(find_txt /tmp/_ld_ocr.png "$1")" ] && return 0
    sleep 0.8
  done
  return 1
}

# ============ Segment 1: the list in Google Maps (Safari) → share ============
at  0.5  "audio-b00"
sleep 4.2                                          # b00 (3.9s) over the list page
ocr_tap "Share" "page-share" 6                     # Google's in-page Share button
sleep 1.2
rel 0 "audio-b01"
for i in 1 2 3; do
  FOUND=0
  for j in $(seq 1 8); do
    shot /tmp/_ld_ocr.png
    [ -n "$(find_txt /tmp/_ld_ocr.png FavCircles)" ] && { FOUND=1; break; }
    if [ "$j" -ge 3 ] && [ -z "$(find_txt /tmp/_ld_ocr.png Copy)" ]; then break; fi   # no sheet up
    sleep 1.2
  done
  [ "$FOUND" = "1" ] && break
  ocr_tap "Share" "retap-share" 4; sleep 1.8
done
ocr_tap "FavCircles" "pick-favcircles" 8
# List mode: "Reading your list…" → card with the name/author/count and a
# "Save 31 places" button. Wait for the button before narrating the card.
wait_txt "Save 31" 20 || die "list-card-never-resolved"
sleep 0.6
rel 0 "audio-b02"
sleep 3.4                                          # "…named after your list. Tap Save."
ocr_tap "Save 31" "save-list" 6
# 31 places import: watch the button flip to Done.
wait_txt "Done" 40 || die "import-never-finished"
rel 2.4 "dwell-success"
ocr_tap "Done" "done-a" 6
sleep 0.8

# ---- OFF CAMERA (build.sh cuts this): give the new circle real photos ----
rm -f "$GROUP/pending-open-place.json" "$GROUP/pending-open-circle.json"
CID=""
for i in $(seq 1 10); do CID=$("$DIR/find-circle.sh"); [ -n "$CID" ] && break; sleep 1; done
echo "new circle: $CID"
if [ -n "$CID" ]; then
  ( cd "$DIR/../../backend" && node scripts/backfill-lookaround-photos.js --circle "$CID" 2>&1 | grep -v Firebase | tail -3 )
fi
mark "backfill-done"

# ============ Segment 2: FavCircles → Profile → the new circle ============
rel 0 "audio-b03"
xcrun simctl launch $UDID com.favcircles.circles >/dev/null; mark "app-launch"
wait_txt "Recent Activity" 30 || die "home-never-rendered"
sleep 1.5
rel 0 "audio-b03b"
sleep 0.4
for i in 1 2 3; do
  "$TOOLS/tap.sh" 362 900; mark "me-tab"
  wait_txt "Edit profile" 5 && break
done
sleep 1.8                                          # let the circle covers load
# The circle's mini-map fits its pins AND the user's location — from Charlotte
# that's a blank Atlantic. Stand in Paris for the circle view (home already rendered).
xcrun simctl location $UDID set 48.8566,2.3522
# New circles append at the END of the grid (circleOrder rule 2): flick down
# until OCR finds the list's name under a bubble.
LABEL_Y=""
for i in $(seq 1 14); do
  shot /tmp/_ld_ocr.png
  R=$(find_txt /tmp/_ld_ocr.png "Paris")
  if [ -n "$R" ]; then
    LABEL_Y=$(($(echo $R | cut -d' ' -f2)/3))
    if [ "$LABEL_Y" -gt 800 ]; then               # bubble/label tucked under the tab bar
      "$TOOLS/flick.sh" 220 700 420; mark "nudge"; sleep 0.9
      shot /tmp/_ld_ocr.png
      R=$(find_txt /tmp/_ld_ocr.png "Paris"); [ -n "$R" ] || continue
      LABEL_Y=$(($(echo $R | cut -d' ' -f2)/3))
    fi
    LABEL_X=$(($(echo $R | cut -d' ' -f1)/3))
    break
  fi
  "$TOOLS/flick.sh" 220 780 150; mark "scroll-$i"
  sleep 0.9
done
[ -n "$LABEL_Y" ] || die "new-circle-not-in-grid"
rel 0 "audio-b03c"
sleep 1.6
"$TOOLS/tap.sh" $LABEL_X $((LABEL_Y - 50)); mark "open-circle"   # the cover bubble above the label
wait_txt "All Categories" 12 || die "circle-never-opened"
sleep 2.6                                          # cover + first cards settle
rel 0 "audio-b04"
sleep 0.8
# Pan from the "Places" header, not the mini-map (that just pans the map).
shot /tmp/_ld_ocr.png; PH=$(find_txt /tmp/_ld_ocr.png "Places")
PY_=$(( ${PH:+$(echo $PH | cut -d' ' -f2)/3} )); [ "$PY_" -gt 0 ] || PY_=380
"$TOOLS/flick.sh" 60 $PY_ $((PY_ - 430)); mark "list-scroll-1"
sleep 1.7
"$TOOLS/flick.sh" 220 700 300; mark "list-scroll-2"   # cards fill the screen now
sleep 1.8

# ============ Segment 3: back to the profile grid ============
# Back chevron shares a row with "Edit" (header height varies) — locate it by OCR.
shot /tmp/_ld_ocr.png; ED=$(find_txt /tmp/_ld_ocr.png "Edit")
BY=$(( ${ED:+$(echo $ED | cut -d' ' -f2)/3} )); [ "$BY" -gt 0 ] || BY=63
sleep 0.8                                          # let the list settle so the tap isn't swallowed
"$TOOLS/tap.sh" 30 $BY; mark "back-to-profile"
wait_txt "Edit profile" 6 || { "$TOOLS/tap.sh" 30 $BY; mark "back-to-profile-retry"; }
sleep 1.2
rel 0 "audio-b05"
sleep 4.6
mark "end"

kill -INT $RECPID 2>/dev/null
wait $RECPID 2>/dev/null
xcrun simctl status_bar $UDID clear 2>/dev/null
echo "=== marks ==="; cat "$LOG"
echo "raw: $OUT/walk_raw.mp4"
