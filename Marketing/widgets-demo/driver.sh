#!/bin/bash
# driver.sh — Widgets tab teaser (~15s): live home screen -> tap the Widgets
# segment -> cards -> open Water and log a glass -> back to the cards.
# OCR-driven taps; marks logged for build.sh (which auto-cuts dead space and
# wraps the take in the house-style intro/outro cards).
set -u
UDID=$(cat /private/tmp/claude-501/demo_udid)
DIR=$(cd "$(dirname "$0")" && pwd)
TOOLS="$DIR/../charlotte-demo/take2/tools"
OUT="$DIR/out"; mkdir -p "$OUT"
LOG="$OUT/actions.log"; : > "$LOG"

read CFOX CFOY CFW CFH < <("$TOOLS/frame.sh")
export CFOX CFOY CFW CFH
echo "frame: $CFOX $CFOY $CFW $CFH"

shot() { xcrun simctl io $UDID screenshot "$1" >/dev/null 2>&1; }
find_txt() { local R=$("$TOOLS/ocrfind" "$1" "$2"); [ "$R" != "NOTFOUND" ] && [ "$R" != "ERR" ] && echo "$R"; }

# ---- pristine stage: cold relaunch on the Activity tab ----
xcrun simctl location $UDID set 40.1706,-74.0654
xcrun simctl terminate $UDID com.favcircles.circles 2>/dev/null
xcrun simctl status_bar $UDID override --time "9:41" --batteryState charged --batteryLevel 100 --wifiBars 3 --cellularMode active --cellularBars 4 2>/dev/null
osascript -e 'tell application "Simulator" to activate'; sleep 0.5
xcrun simctl launch $UDID com.favcircles.circles >/dev/null 2>&1
for i in $(seq 1 20); do shot /tmp/_wd.png; [ -n "$(find_txt /tmp/_wd.png "Recent Activity")" ] && break; sleep 1; done
sleep 4                                            # avatars + pins settle

rm -f "$OUT/walk_raw.mp4"
xcrun simctl io $UDID recordVideo --codec h264 --force "$OUT/walk_raw.mp4" &
RECPID=$!
sleep 1.0

T0=$(python3 -c "import time; print(time.time())")
mark() { python3 -c "import time; print('%0.2f  %s' % (time.time()-$T0, '$1'))" >> "$LOG"; }
rel()  { python3 -c "import time; time.sleep(max(0,$1))"; mark "$2"; }
die() { mark "FAIL-$1"; kill -INT $RECPID 2>/dev/null; wait $RECPID 2>/dev/null; echo "DRIVER FAILED: $1" >&2; exit 1; }

ocr_tap() {  # ocr_tap <needle> <mark> [tries] [dy pts]
  local TXT="$1" NAME="$2" TRIES="${3:-8}" DY="${4:-0}"
  for i in $(seq 1 "$TRIES"); do
    shot /tmp/_wd.png
    local R=$(find_txt /tmp/_wd.png "$TXT")
    if [ -n "$R" ]; then
      "$TOOLS/tap.sh" $(($(echo $R | cut -d' ' -f1)/3)) $(($(echo $R | cut -d' ' -f2)/3 + DY))
      mark "$NAME"; return 0
    fi
    sleep 0.6
  done
  die "$NAME"
}

try_tap() {  # like ocr_tap but a miss is not fatal
  local TXT="$1" NAME="$2" TRIES="${3:-4}"
  for i in $(seq 1 "$TRIES"); do
    shot /tmp/_wd.png
    local R=$(find_txt /tmp/_wd.png "$TXT")
    if [ -n "$R" ]; then "$TOOLS/tap.sh" $(($(echo $R | cut -d' ' -f1)/3)) $(($(echo $R | cut -d' ' -f2)/3)); mark "$NAME"; return 0; fi
    sleep 0.5
  done
  echo "skip: $TXT not on screen"; return 0
}

# ---- choreography ----
rel 0.4 "audio-b01"
sleep 0.9
ocr_tap "Widgets" "tab-widgets" 8                  # home segment control
sleep 2.4                                          # cards land
rel 0 "audio-b02"
ocr_tap "Water" "open-water" 8                     # card -> full page
sleep 1.8
try_tap "Log a glass" "log-glass" 4                # if the page has a one-tap logger
sleep 1.6
ocr_tap "Widgets" "back" 6                         # nav back button reads "Widgets"
sleep 1.6
rel 0 "end"
sleep 0.6
kill -INT $RECPID; wait $RECPID 2>/dev/null
echo "take done"; cat "$LOG"
