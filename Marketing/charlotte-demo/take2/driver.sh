#!/bin/bash
# driver.sh — records the Charlotte demo walkthrough with actions timed to the narration beats.
# v3: intro plays OVER the live map (no separate cover segment) — the driver holds ~10s at the
# start while build.sh overlays the title card + intro VO. The James line (b10) now fires at
# james-done so the narration lands exactly when the map switches to James's places.
# Beats through b09 run on an absolute clock; everything after the James OCR-scroll is scheduled
# relative to its actual completion and logged, and build.sh places audio/captions from the log.
set -u
UDID=46A04FA2-CEB7-4194-A1EF-A2CCC9DC88AA
DIR=$(cd "$(dirname "$0")" && pwd)
OUT="$DIR/out"; mkdir -p "$OUT"
LOG="$OUT/actions.log"; : > "$LOG"

read CFOX CFOY CFW CFH < <("$DIR/tools/frame.sh")
export CFOX CFOY CFW CFH
echo "frame: $CFOX $CFOY $CFW $CFH"

xcrun simctl location $UDID set 35.2271,-80.8431
xcrun simctl terminate $UDID com.favcircles.circles 2>/dev/null
sleep 2
xcrun simctl launch $UDID com.favcircles.circles >/dev/null
sleep 12
osascript -e 'tell application "Simulator" to activate'; sleep 0.6

rm -f "$OUT/walk_raw.mp4"
xcrun simctl io $UDID recordVideo --codec h264 --force "$OUT/walk_raw.mp4" &
RECPID=$!
sleep 1.0

T0=$(python3 -c "import time; print(time.time())")
mark() { python3 -c "import time; print('%0.2f  %s' % (time.time()-$T0, '$1'))" >> "$LOG"; }
at() { python3 -c "import time; time.sleep(max(0, $T0+$1-time.time()))"; mark "$2"; }
rel() { python3 -c "import time; time.sleep(max(0,$1))"; mark "$2"; }   # relative sleep then mark

# --- intro: title card over the live home map (overlay + VO placed by build.sh) ---
at  0.5  "audio-b00";     true
# --- walkthrough ---
at 10.3  "audio-b01";     true
at 11.5  "tap-bill-avatar";  "$DIR/tools/tap.sh" 72 213
at 15.5  "audio-b02";     true
at 16.2  "tap-expand";    "$DIR/tools/tap.sh" 413 364
at 18.3  "audio-b03";     true
at 18.7  "person-dd";     "$DIR/tools/tap.sh" 78 85
at 20.2  "everyone";      "$DIR/tools/tap.sh" 143 100
at 25.15 "audio-b04";     true
at 25.45 "cat-dd";        "$DIR/tools/tap.sh" 219 85
at 26.85 "coffee";        "$DIR/tools/tap.sh" 219 185
at 28.55 "audio-b05";     true
at 28.75 "cat-dd";        "$DIR/tools/tap.sh" 219 85
at 29.9  "drinks";        "$DIR/tools/tap.sh" 219 227
at 31.55 "pin-vbgb";      "$DIR/tools/tap.sh" 211 383
at 33.6  "audio-b06";     true
at 33.65 "cat-dd";        "$DIR/tools/tap.sh" 219 85
at 34.8  "food";          "$DIR/tools/tap.sh" 219 143
at 36.1  "pin-optimist";  "$DIR/tools/tap.sh" 290 419
at 37.4  "audio-b07";     true
at 38.6  "person-dd";     "$DIR/tools/tap.sh" 78 85
at 39.9  "bill";          "$DIR/tools/tap.sh" 143 352
at 43.75 "audio-b08";     true
at 44.1  "pinch-out";     "$DIR/tools/pinch.sh" out
at 48.45 "audio-b09";     true
at 48.65 "pinch-in";      "$DIR/tools/pinch.sh" in
at 51.3  "cat-dd";        "$DIR/tools/tap.sh" 219 85
at 52.3  "all-categories"; "$DIR/tools/tap.sh" 219 101
at 53.2  "person-dd";     "$DIR/tools/tap.sh" 78 85
at 53.5  "audio-b10b";    true   # "Everyone you follow is right here — let's scroll down to James."
at 54.1  "james-start";   true
if ! "$DIR/tools/james.sh"; then
  mark "JAMES-FAIL"
  kill -INT $RECPID; wait $RECPID 2>/dev/null
  echo "ABORT: james selection failed"; exit 1
fi
mark "james-done"
rel 0.3  "audio-b10"      # narration lands as the map switches to James
rel 4.3  "audio-b11"
rel 0.4  "person-dd";     "$DIR/tools/tap.sh" 78 85
rel 1.4  "brittany";      "$DIR/tools/tap.sh" 143 394
rel 1.1  "cat-dd";        "$DIR/tools/tap.sh" 219 85
rel 1.2  "shopping";      "$DIR/tools/tap.sh" 219 269
rel 1.2  "audio-b12";     true
rel 2.3  "banner-link";   "$DIR/tools/tap.sh" 195 163
rel 3.7  "audio-b13";     true
rel 0.45 "person-dd";     "$DIR/tools/tap.sh" 78 85
rel 1.25 "my-places";     "$DIR/tools/tap.sh" 143 185
rel 5.1  "end";           true

kill -INT $RECPID
wait $RECPID 2>/dev/null
echo "recorded: $OUT/walk_raw.mp4"
cat "$LOG"
