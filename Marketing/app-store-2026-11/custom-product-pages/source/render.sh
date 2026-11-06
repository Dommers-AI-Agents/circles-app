#!/bin/zsh
# render.sh <page>  — composes one custom product page's widget slides (source/<page>.json)
# with the September compose.js and renders them to 1320x2868 JPEGs in <page>/.
set -eu
cd "$(dirname "$0")/.."
P=$1
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
node ../../app-store-2026-09/source/compose.js "source/$P.json" "source/out/$P"
mkdir -p "$P"
for html in source/out/$P/*.html; do
  name=${html:t:r}
  "$CHROME" --headless=new --hide-scrollbars --force-device-scale-factor=1 --window-size=1320,2868 --screenshot="source/out/$P/$name.png" "file://$PWD/$html" >/dev/null 2>&1
  sips -s format jpeg -s formatOptions 92 "source/out/$P/$name.png" --out "$P/$name.jpg" >/dev/null
  echo "$P/$name.jpg $(sips -g pixelWidth -g pixelHeight "$P/$name.jpg" | tail -2 | awk '{print $2}' | paste -sd x -)"
done
