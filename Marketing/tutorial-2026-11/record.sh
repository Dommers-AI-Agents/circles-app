#!/bin/bash
# record.sh — film one take of the tutorial walkthrough on the recorder sim.
# Starts simctl recordVideo, runs the TutorialRecordingTour UI test (which
# prints TOURMARK lines), stops recording. Writes out/take.mov + out/marks.txt
# (seconds from the recording's start).
set -u
UDID=${UDID:-07629C59-9A22-4885-9063-CAE2EB6E1E2C}
DIR=$(cd "$(dirname "$0")" && pwd); OUT="$DIR/out"; mkdir -p "$OUT"
cd "$DIR/../../ios"
xcrun simctl status_bar $UDID override --time "9:41" --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3
rm -f "$OUT/take.mov"
xcrun simctl io $UDID recordVideo --codec=h264 --force "$OUT/take.mov" > "$OUT/rec.log" 2>&1 &
REC=$!
sleep 2
START=$(python3 -c 'import time; print(f"{time.time():.3f}")')
TEST_RUNNER_TOUR_RECORD=1 xcodebuild test -scheme Circles-iOS -destination "id=$UDID" \
  -only-testing:Circles-iOSUITests/TutorialRecordingTour -parallel-testing-enabled NO > "$OUT/test.log" 2>&1
kill -INT $REC; wait $REC 2>/dev/null
grep -o "TOURMARK [0-9.]* [a-z-]*" "$OUT/test.log" | awk -v s="$START" '{printf "%.2f %s\n", $2 - s + 2.0, $3}' > "$OUT/marks.txt"
grep -E "TEST (SUCCEEDED|FAILED)" "$OUT/test.log"; cat "$OUT/marks.txt"
