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

# ---- normalize the draft before rolling ----
# The composer keeps a server-side draft, so the previous take leaves the mail
# switch on and a photo attached. The address fields only exist while mail is
# ON, which makes them a reliable read of the switch without inspecting pixels.
normalize() {
  local R
  for i in $(seq 1 4); do
    shot /tmp/_pc.png
    [ -n "$(find_txt /tmp/_pc.png "Postcard")" ] && break
    "$TOOLS/flick.sh" 220 780 300; sleep 0.5
  done
  R=$("$TOOLS/ocrfind" /tmp/_pc.png "Widgets") ; [ "$R" = "NOTFOUND" ] && return 0
  shot /tmp/_pc.png
  R=$(find_txt /tmp/_pc.png "New") || return 0
  "$TOOLS/tap.sh" $(($(echo $R | cut -d' ' -f1)/3)) $(($(echo $R | cut -d' ' -f2)/3))
  sleep 2.2
  for i in $(seq 1 4); do
    shot /tmp/_pc.png
    [ -n "$(find_txt /tmp/_pc.png "Mail a printed postcard")" ] && break
    "$TOOLS/flick.sh" 220 780 300; sleep 0.5
  done
  shot /tmp/_pc.png
  if [ -n "$(find_txt /tmp/_pc.png "ZIP")" ]; then    # form showing => switch is ON
    R=$(find_txt /tmp/_pc.png "Mail a printed postcard")
    [ -n "$R" ] && "$TOOLS/tap.sh" $(($(echo $R | cut -d' ' -f1)/3)) $(($(echo $R | cut -d' ' -f2)/3))
    sleep 1.4
    echo "normalize: mail switch turned off"
  fi
  # back to the home screen for a clean start
  "$TOOLS/tap.sh" 42 114; sleep 2.0
}
# Reach the Widgets tab first so normalize can find the card.
for i in $(seq 1 8); do
  shot /tmp/_pc.png
  R=$(find_txt /tmp/_pc.png "Widgets") && { "$TOOLS/tap.sh" $(($(echo $R | cut -d' ' -f1)/3)) $(($(echo $R | cut -d' ' -f2)/3)); break; }
  sleep 0.6
done
sleep 1.6
normalize
# Cold relaunch, then park on the Widgets tab with the Postcard card in view:
# the cut opens there, so none of this navigation is on camera.
xcrun simctl terminate $UDID com.favcircles.circles 2>/dev/null
sleep 1.5
xcrun simctl launch $UDID com.favcircles.circles >/dev/null 2>&1
for i in $(seq 1 20); do shot /tmp/_pc.png; [ -n "$(find_txt /tmp/_pc.png "Recent Activity")" ] && break; sleep 1; done
sleep 3
for i in $(seq 1 8); do
  shot /tmp/_pc.png
  R=$(find_txt /tmp/_pc.png "Widgets") && { "$TOOLS/tap.sh" $(($(echo $R | cut -d' ' -f1)/3)) $(($(echo $R | cut -d' ' -f2)/3)); break; }
  sleep 0.6
done
sleep 2.0
for i in 1 2 3 4 5; do
  shot /tmp/_pc.png
  [ -n "$(find_txt /tmp/_pc.png "Postcard")" ] && break
  "$TOOLS/flick.sh" 220 780 300; sleep 0.6
done
sleep 1.2
# Where the card sits, so build.sh can ring it. Device points.
shot /tmp/_pc.png
CARD=$(find_txt /tmp/_pc.png "Postcard" || true)
if [ -n "${CARD:-}" ]; then
  echo "$(($(echo $CARD | cut -d' ' -f1)/3)) $(($(echo $CARD | cut -d' ' -f2)/3))" > "$OUT/card_xy.txt"
  echo "card at $(cat "$OUT/card_xy.txt")"
fi

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

ocr_tap_soft() {  # ocr_tap that returns 1 instead of dying
  local TXT="$1" NAME="$2" TRIES="${3:-4}"
  for i in $(seq 1 "$TRIES"); do
    shot /tmp/_pc.png
    local R=$(find_txt /tmp/_pc.png "$TXT")
    if [ -n "$R" ]; then
      "$TOOLS/tap.sh" $(($(echo $R | cut -d' ' -f1)/3)) $(($(echo $R | cut -d' ' -f2)/3))
      mark "$NAME"; return 0
    fi
    sleep 0.5
  done
  return 1
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
# Opens on the Widgets tab with the Postcard card already showing; build.sh
# rings the card over this first beat.
rel 0.4 "audio-b01"
sleep 1.6
mark "ring-card"
sleep 0.5

# The card's TITLE eats taps — "+ New" is the control that opens a fresh card.
ocr_tap "New" "open-postcard" 8
sleep 1.8

# Photo: the library picker, then the waterfall in the top row.
if ! ocr_tap_soft "Choose photo" "choose-photo" 4; then
  ocr_tap "Change photo" "choose-photo" 4
fi
sleep 2.2
"$TOOLS/tap.sh" 220 388                            # top row, middle thumbnail
sleep 2.2                                          # picker dismisses, card renders

rel 0 "audio-b02"
# Caption: the place name is its own field inside "Greetings from ___".
#
# Anchor on the section HEADER, not on the words "Greetings from" — those also
# appear printed across the postcard preview above, and OCR finds the preview
# first, which sends the tap to an image and the typing to whatever field still
# had focus. Cmd-A before typing replaces what is there instead of appending.
shot /tmp/_pc.png
CAP=$(find_txt /tmp/_pc.png "CAPTION ON THE CARD" || true)
if [ -n "${CAP:-}" ]; then
  "$TOOLS/tap.sh" 250 $(($(echo $CAP | cut -d' ' -f2)/3 + 40))
  sleep 1.2
  cliclick kd:cmd t:a ku:cmd
  sleep 0.3
  cliclick t:"Waterfalls"
  mark "type-caption"
  sleep 1.6
else
  die "type-caption"
fi

# Message: type a short line so the card reads like someone's, not a template.
shot /tmp/_pc.png
MSG=$(find_txt /tmp/_pc.png "MESSAGE" || true)
if [ -n "${MSG:-}" ]; then
  "$TOOLS/tap.sh" 220 $(($(echo $MSG | cut -d' ' -f2)/3 + 40))
  sleep 1.0
  cliclick kd:cmd t:a ku:cmd
  sleep 0.3
  cliclick t:"Found this one on the way home."
  mark "type-message"
  sleep 1.4
  "$TOOLS/tap.sh" 220 120                          # dismiss the keyboard
  sleep 0.8
fi

rel 0 "audio-b03"
# Both ways to send, side by side: a connection for the digital card, and the
# printed option underneath it.
for i in 1 2 3 4; do
  shot /tmp/_pc.png
  [ -n "$(find_txt /tmp/_pc.png "Mail a printed postcard")" ] && break
  "$TOOLS/flick.sh" 220 780 300; sleep 0.55
done
mark "scroll-to-deliver"
sleep 2.6

rel 0 "end"
sleep 1.0
kill -INT $RECPID; wait $RECPID 2>/dev/null
echo "take done"; cat "$LOG"
