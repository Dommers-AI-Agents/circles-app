#!/bin/zsh
# record-preview-duo.sh <Closed|Open> <out.mov> [--no-fold]
# Records the App Preview storyboard on the iPhone Duo simulator: a deep-link tour
# (home → full map → place → profile → widgets → postcard) on the live display.
# Timings below match captions-duo.json. Frame it with build-preview-duo.sh.
set -u
POSTURE=$1; OUT=$2; FOLD=${3:-fold}
UD=886F26D1-1279-4744-B932-2DD907E47A22
API=https://api.favcircles.com
PLACE=${CAPTURE_PLACE_ID:-JyJDDivPtjm1XZBUteSp}
PANE='group 3 of splitter group 1 of group 1 of splitter group 1 of group 1 of front window'
case $POSTURE in Closed) DISP=1;; Open) DISP=3;; *) echo "posture?"; exit 2;; esac
lit() { xcrun simctl io $UD screenshot --display=$DISP /tmp/duo-lit.png >/dev/null 2>&1; [[ $(ffmpeg -v error -i /tmp/duo-lit.png -vf scale=1:1,format=gray -f rawvideo - 2>/dev/null | od -An -tu1 | tr -d ' ') -gt 8 ]]; }
if [[ $FOLD == fold ]]; then
  for try in 1 2 3; do
    osascript -e "tell application \"System Events\" to tell process \"DeviceHub\"
click (first button of $PANE whose help is \"$POSTURE\")
end tell" >/dev/null 2>&1 || echo "WARN: could not click $POSTURE in DeviceHub"
    sleep 6
    lit && break
    echo "display $DISP not lit after $POSTURE click (try $try)"
  done
  lit || { echo "ABORT: $POSTURE display never lit"; exit 1; }
fi
xcrun simctl location $UD set 35.2271,-80.8431
xcrun simctl status_bar $UD override --time 9:41 --batteryState charged --batteryLevel 100 --cellularMode active --cellularBars 4 --wifiBars 3 >/dev/null 2>&1
xcrun simctl terminate $UD com.favcircles.circles 2>/dev/null; sleep 2
# Warm start: the cold launch shows a blank screen for ~12 s, which is not footage.
xcrun simctl launch $UD com.favcircles.circles >/dev/null; sleep 14
xcrun simctl io $UD recordVideo --display=$DISP --codec h264 -f "$OUT" >/dev/null 2>&1 & REC=$!
sleep 5                                                                          # home
xcrun simctl openurl $UD "$API/place/$PLACE" >/dev/null;             sleep 7    # place
xcrun simctl openurl $UD "$API/app/open?path=me" >/dev/null;         sleep 5    # profile
xcrun simctl openurl $UD "$API/app/tab/widgets" >/dev/null;          sleep 5    # widgets
xcrun simctl openurl $UD "$API/app/map" >/dev/null;                  sleep 7    # full map (modal, so last: place/me links don't show over it)
kill -INT $REC; wait $REC 2>/dev/null
xcrun simctl status_bar $UD clear >/dev/null 2>&1
ffprobe -v error -show_entries format=duration -of csv=p=0 "$OUT"
