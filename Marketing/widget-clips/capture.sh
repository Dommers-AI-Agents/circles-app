#!/bin/bash
# Records each widget's full page in the simulator (signed in) for the
# per-widget Instagram clips. Usage: ./capture.sh [widgetId ...]
set -u
D=D65678AE-EDB9-4BFA-B3ED-2CDED836E3F3
OUT="$(cd "$(dirname "$0")" && pwd)/raw"
mkdir -p "$OUT"
IDS=("$@")
[ ${#IDS[@]} -eq 0 ] && IDS=(motivation workouts run water habits calories heartbeat sleepsounds quotes whattoeat drink nextbar postcard fridgemail billsplit stocks events howareyou)
xcrun simctl status_bar $D override --time 9:41 --batteryState charged --batteryLevel 100 --cellularBars 4 --wifiBars 3 --dataNetwork 5g >/dev/null 2>&1
osascript -e 'tell application "Simulator" to activate' >/dev/null 2>&1; sleep 1
frame() { osascript -e 'tell application "System Events" to tell process "Simulator" to get {position, size} of (first UI element of window 1 whose role is "AXGroup")' 2>/dev/null; }
F=$(frame); X=$(echo $F | cut -d, -f1 | tr -d ' '); Y=$(echo $F | cut -d, -f2 | tr -d ' '); W=$(echo $F | cut -d, -f3 | tr -d ' ')
pt() { python3 -c "print(f'{round($X+$1*$W/440)},{round($Y+$2*$W/440)}')"; }

# Fresh home frame for the brand cards
xcrun simctl terminate $D com.favcircles.circles >/dev/null 2>&1
xcrun simctl launch $D com.favcircles.circles >/dev/null; sleep 16
xcrun simctl io $D screenshot "$OUT/home_frame.png" >/dev/null 2>&1

for id in "${IDS[@]}"; do
  echo "== $id"
  xcrun simctl openurl $D "circles://widget/$id"; sleep 4
  rm -f "$OUT/$id.mov"
  xcrun simctl io $D recordVideo --codec h264 --force "$OUT/$id.mov" >/dev/null 2>&1 &
  REC=$!
  sleep 5.5
  kill -INT $REC; wait $REC 2>/dev/null; sleep 1
done
