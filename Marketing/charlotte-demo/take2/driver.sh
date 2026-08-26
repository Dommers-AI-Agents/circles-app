#!/bin/bash
# driver.sh — records the Charlotte demo walkthrough with actions timed to the narration beats.
# Beats 1-10 run on an absolute clock; everything after the James OCR-scroll is scheduled
# relative to its actual completion and logged, and build.sh places the audio from the log.
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

at  1.0  "audio-b01";     true
at  2.2  "tap-bill-avatar";  "$DIR/tools/tap.sh" 72 213
at  6.2  "audio-b02";     true
at  6.9  "tap-expand";    "$DIR/tools/tap.sh" 413 364
at  9.0  "audio-b03";     true
at  9.4  "person-dd";     "$DIR/tools/tap.sh" 78 85
at 10.9  "everyone";      "$DIR/tools/tap.sh" 143 100
at 15.2  "audio-b04";     true
at 15.5  "cat-dd";        "$DIR/tools/tap.sh" 219 85
at 16.9  "coffee";        "$DIR/tools/tap.sh" 219 185
at 18.6  "audio-b05";     true
at 18.8  "cat-dd";        "$DIR/tools/tap.sh" 219 85
at 19.9  "drinks";        "$DIR/tools/tap.sh" 219 227
at 21.6  "pin-vbgb";      "$DIR/tools/tap.sh" 211 383
at 23.6  "audio-b06";     true
at 23.7  "cat-dd";        "$DIR/tools/tap.sh" 219 85
at 24.8  "food";          "$DIR/tools/tap.sh" 219 143
at 26.1  "pin-optimist";  "$DIR/tools/tap.sh" 290 419
at 27.4  "audio-b07";     true
at 28.6  "person-dd";     "$DIR/tools/tap.sh" 78 85
at 29.9  "bill";          "$DIR/tools/tap.sh" 143 352
at 33.8  "audio-b08";     true
at 34.1  "pinch-out";     "$DIR/tools/pinch.sh" out
at 38.5  "audio-b09";     true
at 38.7  "pinch-in";      "$DIR/tools/pinch.sh" in
at 41.3  "audio-b10";     true
at 41.4  "cat-dd";        "$DIR/tools/tap.sh" 219 85
at 42.4  "all-categories"; "$DIR/tools/tap.sh" 219 101
at 43.3  "person-dd";     "$DIR/tools/tap.sh" 78 85
at 44.2  "james-start";   true   # (b10b filler audio is fixed at 45.8 in build.sh)
if ! "$DIR/tools/james.sh"; then
  mark "JAMES-FAIL"
  kill -INT $RECPID; wait $RECPID 2>/dev/null
  echo "ABORT: james selection failed"; exit 1
fi
mark "james-done"
rel 2.0  "audio-b11"
rel 0.3  "person-dd";     "$DIR/tools/tap.sh" 78 85
rel 1.2  "brittany";      "$DIR/tools/tap.sh" 143 394
rel 0.9  "cat-dd";        "$DIR/tools/tap.sh" 219 85
rel 1.0  "shopping";      "$DIR/tools/tap.sh" 219 269
rel 1.0  "audio-b12";     true
rel 2.2  "banner-link";   "$DIR/tools/tap.sh" 195 163
rel 3.5  "audio-b13";     true
rel 0.4  "person-dd";     "$DIR/tools/tap.sh" 78 85
rel 1.1  "my-places";     "$DIR/tools/tap.sh" 143 185
rel 4.9  "end";           true

kill -INT $RECPID
wait $RECPID 2>/dev/null
echo "recorded: $OUT/walk_raw.mp4"
cat "$LOG"
