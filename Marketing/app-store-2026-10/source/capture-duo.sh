#!/bin/zsh
# capture.sh <Closed|Open> <outdir> [--no-fold]
# Mac-driven App Store capture on the iPhone Duo simulator: folds the device
# (DeviceHub must be visible: Mac unlocked), starts the tap-servant UI test,
# navigates with simctl openurl, screenshots the live display with simctl.
set -u
POSTURE=$1; OUT=$2; FOLD=${3:-fold}; mkdir -p "$OUT"
UD=886F26D1-1279-4744-B932-2DD907E47A22
DD=~/Library/Developer/Xcode/DerivedData/Circles-iOS-cqbpbazqlbrshmfnktptqwdithlm
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

# fresh servant: clear any previous handshake folder
for d in ~/Library/Developer/CoreSimulator/Devices/$UD/data/Containers/Data/Application/*/tmp/duo-capture(N); do rm -rf "$d"; done
xcrun simctl terminate $UD com.favcircles.circles 2>/dev/null
( cd /Users/wesleysgroi/circles-app/ios && xcodebuild test-without-building \
    -project Circles-iOS.xcodeproj -scheme Circles-iOS -derivedDataPath "$DD" \
    -destination "platform=iOS Simulator,id=$UD" -parallel-testing-enabled NO \
    -only-testing:Circles-iOSUITests/DuoAppStoreCaptureUITests/testServeCommands \
    > "$OUT/xcodebuild-$POSTURE.log" 2>&1 ) &
TEST=$!

HS=""
for i in {1..240}; do
  for d in ~/Library/Developer/CoreSimulator/Devices/$UD/data/Containers/Data/Application/*/tmp/duo-capture(N); do [[ -e "$d/launched" ]] && HS=$d; done
  [[ -n $HS ]] && break; sleep 1
done
[[ -z $HS ]] && { echo "servant never launched"; kill $TEST; exit 1; }
echo "servant up: $HS"

shot() { sleep ${2:-2}; xcrun simctl io $UD screenshot --display=$DISP "$OUT/$1.png" >/dev/null 2>&1; echo "captured $1 ($(sips -g pixelWidth -g pixelHeight "$OUT/$1.png" | tail -2 | awk '{print $2}' | paste -sd x -))"; }
cmd()  { echo "$1" > "$HS/cmd"; for i in {1..600}; do [[ -e "$HS/$1.done" ]] && { rm -f "$HS/$1.done"; return 0; }; sleep 0.5; done; echo "WARN: $1 timed out"; }
go()   { xcrun simctl openurl $UD "$1" >/dev/null 2>&1; sleep ${2:-5}; }
# ONLY="storepoints privacy" re-shoots just those screens
want() { [[ -z ${ONLY:-} || " $ONLY " == *" $1 "* ]]; }

xcrun simctl location $UD set 35.2271,-80.8431   # uptown Charlotte, as in the September set
# App Store status bar, same as the September set
xcrun simctl status_bar $UD override --time 9:41 --batteryState charged --batteryLevel 100 --cellularMode active --cellularBars 4 --wifiBars 3 >/dev/null 2>&1
want home && { sleep 7; cmd locate;                       shot home 2; cmd dismiss; }
want fullmap && { go "$API/app/map" 6; cmd locate;           shot fullmap 4; }
want postcard && { go "$API/app/widget/postcard" 6;           shot postcard; }
want profile && { go "$API/app/open?path=me" 5;              shot profile; }
want place && { go "$API/place/$PLACE" 6;                  shot place; }
want storepoints && { go "$API/app/open?path=rewards/piggy-bank" 4; cmd store-points; shot storepoints 8; }
want widgets && { go "$API/app/tab/widgets" 5; cmd dismiss;  shot widgets; }
want privacy && { cmd privacy;                               shot privacy; }
want addplace && { go "$API/app/open?path=add-place" 4;       shot addplace; }
echo end > "$HS/cmd"
xcrun simctl status_bar $UD clear >/dev/null 2>&1
wait $TEST; echo "servant exit $?"
