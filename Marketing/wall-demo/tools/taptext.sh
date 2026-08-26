#!/bin/bash
# taptext.sh "text" [maxtries] — OCR-find text on screen and tap it; scrolls person menu between tries
DIR=$(dirname "$0")
TXT="$1"; TRIES=${2:-3}
for i in $(seq 1 $TRIES); do
  xcrun simctl io booted screenshot /tmp/_ocr_take2.png >/dev/null 2>&1
  R=$("$DIR/ocrfind" /tmp/_ocr_take2.png "$TXT")
  if [ "$R" != "NOTFOUND" ] && [ "$R" != "ERR" ]; then
    PX=$(echo $R | cut -d' ' -f1); PY=$(echo $R | cut -d' ' -f2)
    "$DIR/tap.sh" $((PX/3)) $((PY/3))
    exit 0
  fi
  "$DIR/drag.sh" 143 540 143 290 400
  sleep 0.8
done
echo "TAPTEXT-FAIL: $TXT" >&2; exit 1
