#!/bin/bash
# driver.sh — Postcard teaser (~15s): live home screen -> Widgets segment ->
# Postcard widget -> pick a photo -> choose a connection (the free in-app send)
# -> switch on "Mail a printed postcard · $3.99" and fill a US address -> rest
# on "Send postcard".
#
# It deliberately STOPS before tapping Send. Two reasons: the Apple Pay sheet
# needs a card in Wallet, which a simulator does not have, and a real tap would
# create a real Lob order against the live account.
#
# OCR-driven taps; marks logged for build.sh (which auto-cuts dead space and
# wraps the take in the house-style intro/outro cards).
#
# Prerequisites (see README.md): Simulator window visible and the Mac unlocked,
# app signed in, at least one photo in the simulator's library, at least one
# connection on the account.
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
for i in $(seq 1 20); do shot /tmp/_pc.png; [ -n "$(find_txt /tmp/_pc.png "Recent Activity")" ] && break; sleep 1; done
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
    shot /tmp/_pc.png
    local R=$(find_txt /tmp/_pc.png "$TXT")
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
    shot /tmp/_pc.png
    local R=$(find_txt /tmp/_pc.png "$TXT")
    if [ -n "$R" ]; then "$TOOLS/tap.sh" $(($(echo $R | cut -d' ' -f1)/3)) $(($(echo $R | cut -d' ' -f2)/3)); mark "$NAME"; return 0; fi
    sleep 0.5
  done
  echo "skip: $TXT not on screen"; return 0
}

type_txt() { cliclick t:"$1"; }

# ---- choreography ----
rel 0.4 "audio-b01"
sleep 0.6
ocr_tap "Widgets" "tab-widgets" 8                  # home segment control
sleep 2.0                                          # cards land
ocr_tap "Postcard" "open-postcard" 8               # card -> full page
sleep 1.6

# Photo: the library picker. "Choose photo" reads "Change photo" once one is set.
ocr_tap "Choose photo" "choose-photo" 6
sleep 2.0
"$TOOLS/tap.sh" 110 300                            # first thumbnail, top-left grid cell
sleep 2.2                                          # picker dismiss + card renders

rel 0 "audio-b02"
# Digital send: pick a connection.
ocr_tap "Choose a connection" "open-recipients" 6
sleep 1.6
"$TOOLS/tap.sh" 220 250                            # first contact row
sleep 1.6

rel 0 "audio-b03"
# Physical send: the paid option, then a real US address.
ocr_tap "Mail a printed postcard" "toggle-mail" 6 0
sleep 1.4
ocr_tap "Street" "addr-street" 6
type_txt "1 Infinite Loop"; sleep 0.4
ocr_tap "City" "addr-city" 6
type_txt "Cupertino"; sleep 0.4
ocr_tap "State" "addr-state" 6
type_txt "CA"; sleep 0.4
ocr_tap "ZIP" "addr-zip" 6
type_txt "95014"; sleep 0.4
"$TOOLS/tap.sh" 220 120                            # dismiss the keyboard
sleep 2.4                                          # address verifies, price confirms

# Rest on the Send button WITHOUT tapping it — see the header.
rel 0 "end"
sleep 0.8
kill -INT $RECPID; wait $RECPID 2>/dev/null
echo "take done"; cat "$LOG"
