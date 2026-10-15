#!/bin/bash
# Renders every post in posts.json to out/<id>.jpg (1080×1350) with headless
# Chrome via a local server (fetch() needs http, not file://).
set -e
cd "$(dirname "$0")"
mkdir -p out
PORT=8765
python3 -m http.server $PORT >/dev/null 2>&1 & SERVER=$!
trap 'kill $SERVER' EXIT
sleep 1
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
for id in $(python3 -c "import json; print(' '.join(p['id'] for p in json.load(open('posts.json'))['posts'] if p.get('ready')))"); do
  "$CHROME" --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 --window-size=1080,1350 \
    --virtual-time-budget=6000 --screenshot="$PWD/out/$id.png" "http://localhost:$PORT/card.html?id=$id" >/dev/null 2>&1
  sips -s format jpeg -s formatOptions 90 "out/$id.png" --out "out/$id.jpg" >/dev/null && rm "out/$id.png"
done
ls out | wc -l | xargs echo "rendered:"
