#!/bin/zsh
# render.sh — the Holiday favorites In-App Event images: ../event-card.jpg (1920x1080)
# and ../event-details.jpg (1080x1920), from compose.js
set -eu
cd "$(dirname "$0")"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
node compose.js out
for spec in card:1920,1080 details:1080,1920; do
  name=${spec%%:*}; size=${spec#*:}
  "$CHROME" --headless=new --hide-scrollbars --force-device-scale-factor=1 --window-size=$size --screenshot="out/$name.png" "file://$PWD/out/$name.html" >/dev/null 2>&1
  sips -s format jpeg -s formatOptions 92 "out/$name.png" --out "../event-$name.jpg" >/dev/null
  echo "event-$name.jpg $(sips -g pixelWidth -g pixelHeight "../event-$name.jpg" | tail -2 | awk '{print $2}' | paste -sd x -)"
done
