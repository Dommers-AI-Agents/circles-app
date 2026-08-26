#!/bin/bash
# driver.sh — records the Wall Township demo walkthrough (Joey, Salvatore, Margie, Amanda)
# with actions timed to the narration beats. Before recording starts, the home people row is
# scrolled until Joey's avatar is visible and its position stored (the row swallows the first
# drag after launch, so we retry). Beats through b07a run on an absolute clock; the three
# OCR person-hunts (Salvatore, Margie, Amanda) are variable-length, so everything after each
# hunt is scheduled relative to its actual completion. build.sh reads out/actions.log to
# place audio/captions and to cut the silent middle of each hunt.
set -u
UDID=46A04FA2-CEB7-4194-A1EF-A2CCC9DC88AA
DIR=$(cd "$(dirname "$0")" && pwd)
OUT="$DIR/out"; mkdir -p "$OUT"
LOG="$OUT/actions.log"; : > "$LOG"

read CFOX CFOY CFW CFH < <("$DIR/tools/frame.sh")
export CFOX CFOY CFW CFH
echo "frame: $CFOX $CFOY $CFW $CFH"

xcrun simctl location $UDID set 40.1659,-74.0958
xcrun simctl terminate $UDID com.favcircles.circles 2>/dev/null
sleep 2
xcrun simctl launch $UDID com.favcircles.circles >/dev/null
sleep 12
osascript -e 'tell application "Simulator" to activate'; sleep 0.8
sleep 2

# --- pre-record: scroll the people row until Joey's avatar is visible, store its position ---
JX=""; JY=""
for i in 1 2 3 4; do
  "$DIR/tools/drag.sh" 380 213 60 213 400; sleep 1.4
  xcrun simctl io booted screenshot /tmp/_wall_row.png >/dev/null 2>&1
  OUT2=$("$DIR/tools/ocrfind" /tmp/_wall_row.png "Joseph" "Jaime" "Geoff")
  J=$(echo "$OUT2" | sed -n 1p)
  if [ "$J" != "NOTFOUND" ] && [ "$J" != "ERR" ]; then
    JX=$(( $(echo $J | cut -d' ' -f1) / 3 )); JY=$(( $(( $(echo $J | cut -d' ' -f2) / 3 )) - 43 ))
    break
  fi
  # overshot past Joey (rightward drags get swallowed, so we can't recover) — abort cheaply pre-record
  if [ "$(echo "$OUT2" | sed -n 2p)" != "NOTFOUND" ] || [ "$(echo "$OUT2" | sed -n 3p)" != "NOTFOUND" ]; then
    echo "ABORT: people row overshot past Joey — rerun driver"; exit 1
  fi
done
if [ -z "$JX" ]; then echo "ABORT: Joey avatar not found in people row"; exit 1; fi
sleep 2   # let any residual row creep settle before recording
xcrun simctl io booted screenshot /tmp/_wall_row2.png >/dev/null 2>&1
J2=$("$DIR/tools/ocrfind" /tmp/_wall_row2.png "Joseph")
if [ "$J2" != "NOTFOUND" ] && [ "$J2" != "ERR" ]; then
  JX=$(( $(echo $J2 | cut -d' ' -f1) / 3 )); JY=$(( $(( $(echo $J2 | cut -d' ' -f2) / 3 )) - 43 ))
fi
echo "joey avatar at $JX,$JY"

rm -f "$OUT/walk_raw.mp4"
xcrun simctl io $UDID recordVideo --codec h264 --force "$OUT/walk_raw.mp4" &
RECPID=$!
sleep 1.0

T0=$(python3 -c "import time; print(time.time())")
mark() { python3 -c "import time; print('%0.2f  %s' % (time.time()-$T0, '$1'))" >> "$LOG"; }
at() { python3 -c "import time; time.sleep(max(0, $T0+$1-time.time()))"; mark "$2"; }
rel() { python3 -c "import time; time.sleep(max(0,$1))"; mark "$2"; }   # relative sleep then mark
die() { mark "$1"; kill -INT $RECPID; wait $RECPID 2>/dev/null; echo "ABORT: $1"; exit 1; }

# --- intro: title card over the live home map (overlay + VO placed by build.sh) ---
at  0.5  "audio-b00";     true
# --- walkthrough ---
at 10.3  "audio-b01";     true
at 11.6  "tap-joey-avatar";  "$DIR/tools/tap.sh" $JX $JY
at 13.6  "verify-joey";   true
xcrun simctl io booted screenshot /tmp/_wall_v.png >/dev/null 2>&1
[ "$("$DIR/tools/ocrfind" /tmp/_wall_v.png "Joseph D. Sgroi")" = "NOTFOUND" ] && die "JOEY-TAP-FAIL"
at 15.7  "audio-b02";     true
at 16.4  "tap-expand";    "$DIR/tools/tap.sh" 413 364
at 18.5  "audio-b03";     true
at 18.9  "person-dd";     "$DIR/tools/tap.sh" 78 85
at 20.4  "everyone";      "$DIR/tools/tap.sh" 143 100
at 25.2  "audio-b04";     true
at 25.5  "cat-dd";        "$DIR/tools/tap.sh" 219 85
at 26.9  "coffee";        "$DIR/tools/tap.sh" 219 185
at 28.6  "audio-b05";     true
at 28.8  "cat-dd";        "$DIR/tools/tap.sh" 219 85
at 30.0  "shopping";      "$DIR/tools/tap.sh" 219 271
at 31.7  "pin-sgroi";     "$DIR/tools/tap.sh" 165 148
at 33.7  "audio-b06";     true
at 33.75 "cat-dd";        "$DIR/tools/tap.sh" 219 85
at 34.9  "food";          "$DIR/tools/tap.sh" 219 144
at 36.2  "pin-scarborough"; "$DIR/tools/tap.sh" 329 630
at 37.5  "audio-b07a";    true
at 38.7  "person-dd";     "$DIR/tools/tap.sh" 78 85
at 39.5  "sal-start";     true
"$DIR/tools/pick.sh" "Salvatore" "Salvatore A Sgroi" 2 "Margie" "Chelsea" "James Suk" || die "SAL-FAIL"
mark "sal-done"
rel 0.3  "audio-b07b"     # narration lands as the map switches to Salvatore
rel 3.9  "audio-b08"
rel 0.35 "pinch-out";     "$DIR/tools/pinch.sh" out
rel 4.3  "audio-b09"
rel 0.2  "pinch-in";      "$DIR/tools/pinch.sh" in
rel 2.7  "cat-dd";        "$DIR/tools/tap.sh" 219 85
rel 1.05 "all-categories"; "$DIR/tools/tap.sh" 219 103
rel 0.9  "person-dd";     "$DIR/tools/tap.sh" 78 85
rel 0.3  "audio-b10b"     # "Everyone you follow is right here — let's scroll to Margie."
rel 0.7  "margie-start";  true
"$DIR/tools/pick.sh" "Margie" "Margie Eckhoff" 2 "Chelsea" "James Suk" "fritz" || die "MARGIE-FAIL"
mark "margie-done"
rel 0.3  "audio-b10"      # narration lands as the map switches to Margie
rel 4.1  "audio-b11a"     # "One more — Amanda."
rel 0.5  "person-dd";     "$DIR/tools/tap.sh" 78 85
rel 0.9  "amanda-start";  true
"$DIR/tools/pick.sh" "Amanda" "Amanda Agnello" 1 "Jaime Moore" "Linda Sgroi" || die "AMANDA-FAIL"
mark "amanda-done"
rel 0.4  "cat-dd";        "$DIR/tools/tap.sh" 219 85
rel 1.05 "coffee2";       "$DIR/tools/tap.sh" 219 185
rel 0.5  "audio-b11"
rel 4.0  "cat-dd";        "$DIR/tools/tap.sh" 219 85
rel 1.05 "outdoors";      "$DIR/tools/tap.sh" 219 270
rel 0.8  "audio-b12"
rel 2.4  "banner-link";   "$DIR/tools/tap.sh" 161 164
rel 3.6  "audio-b13"
rel 0.5  "person-dd";     "$DIR/tools/tap.sh" 78 85
rel 1.3  "my-places";     "$DIR/tools/tap.sh" 143 187
rel 5.2  "end";           true

kill -INT $RECPID
wait $RECPID 2>/dev/null
echo "recorded: $OUT/walk_raw.mp4"
cat "$LOG"
