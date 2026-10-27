#!/bin/zsh
# landscape-check.sh <outdir> — folded Duo rotated right: home + place, then back to portrait.
set -u
OUT=$1; mkdir -p "$OUT"; UD=886F26D1-1279-4744-B932-2DD907E47A22; API=https://api.favcircles.com
PANE='group 3 of splitter group 1 of group 1 of splitter group 1 of group 1 of front window'
rot() { osascript -e "tell application \"System Events\" to tell process \"DeviceHub\"
click (first button of $PANE whose help is \"Rotate Right\")
end tell" >/dev/null 2>&1; sleep 4; }
xcrun simctl status_bar $UD override --time 9:41 --batteryState charged --batteryLevel 100 --cellularMode active --cellularBars 4 --wifiBars 3 >/dev/null 2>&1
rot
xcrun simctl terminate $UD com.favcircles.circles 2>/dev/null; xcrun simctl launch $UD com.favcircles.circles >/dev/null; sleep 8
xcrun simctl io $UD screenshot --display=1 "$OUT/landscape-home.png" >/dev/null 2>&1
xcrun simctl openurl $UD "$API/place/JyJDDivPtjm1XZBUteSp" >/dev/null; sleep 6
xcrun simctl io $UD screenshot --display=1 "$OUT/landscape-place.png" >/dev/null 2>&1
xcrun simctl openurl $UD "$API/app/map" >/dev/null; sleep 6
xcrun simctl io $UD screenshot --display=1 "$OUT/landscape-map.png" >/dev/null 2>&1
rot; rot; rot
xcrun simctl status_bar $UD clear >/dev/null 2>&1
for f in home place map; do echo "$f $(sips -g pixelWidth -g pixelHeight "$OUT/landscape-$f.png" | tail -2 | awk '{print $2}' | paste -sd x -)"; done
