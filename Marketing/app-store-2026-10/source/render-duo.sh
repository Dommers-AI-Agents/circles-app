#!/bin/zsh
# render-duo.sh  — composes the Duo slides and renders them to App Store JPEGs.
# usage: source/render-duo.sh outer|inner
set -eu
cd "$(dirname "$0")/.."
KIND=$1
case $KIND in outer) W=1398; H=2034; OUT="iPhone Duo outer 1398x2034";; inner) W=2853; H=2007; OUT="iPhone Duo inner 2853x2007";; *) exit 2;; esac
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
node ../app-store-2026-09/source/compose.js "source/duo-$KIND.json" "source/out-duo-$KIND"
mkdir -p "$OUT"
for html in source/out-duo-$KIND/*.html; do
  name=${html:t:r}
  "$CHROME" --headless=new --hide-scrollbars --force-device-scale-factor=1 --window-size=$W,$H --screenshot="source/out-duo-$KIND/$name.png" "file://$PWD/$html" >/dev/null 2>&1
  sips -s format jpeg -s formatOptions 92 "source/out-duo-$KIND/$name.png" --out "$OUT/$name.jpg" >/dev/null
  echo "$OUT/$name.jpg $(sips -g pixelWidth -g pixelHeight "$OUT/$name.jpg" | tail -2 | awk '{print $2}' | paste -sd x -)"
done
