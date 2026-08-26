#!/bin/bash
# james.sh — scroll the open person menu to James Sukkert and select him.
# The menu list creeps for >1s after a drag (rubber-band), so we only tap once two
# consecutive OCR reads agree on his position; then verify the selection took.
DIR=$(cd "$(dirname "$0")" && pwd)
SHOT=/tmp/_james_ocr.png
bigdrag() { "$DIR/drag.sh" 143 560 143 200 300; }
nudge() {
  if [ "$1" = "down" ]; then "$DIR/drag.sh" 143 500 143 380 250; else "$DIR/drag.sh" 143 380 143 500 250; fi
}
scan() {
  xcrun simctl io booted screenshot "$SHOT" >/dev/null 2>&1
  local out; out=$("$DIR/ocrfind" "$SHOT" "James Sukkert" "Melinda" "Chelsea" "My Connections" "fritz" "Margie")
  J=$(echo "$out" | sed -n 1p)
  OPEN=0; BELOW=0
  [ "$(echo "$out" | sed -n 2p)" != "NOTFOUND" ] && { OPEN=1; BELOW=1; }
  [ "$(echo "$out" | sed -n 5p)" != "NOTFOUND" ] && { OPEN=1; BELOW=1; }
  for n in 3 4 6; do [ "$(echo "$out" | sed -n ${n}p)" != "NOTFOUND" ] && OPEN=1; done
}
jxy() { [ "$J" != "NOTFOUND" ] && [ "$J" != "ERR" ] && [ -n "$J" ]; }
bigdrag; sleep 0.4; bigdrag; sleep 1.2
PREVY=-999
for i in 1 2 3 4 5 6 7; do
  scan
  if jxy; then
    PX=$(( $(echo $J | cut -d' ' -f1) / 3 )); PY=$(( $(echo $J | cut -d' ' -f2) / 3 ))
    if [ $PY -gt 540 ]; then nudge down; sleep 1.1; PREVY=-999; continue; fi
    if [ $PY -lt 155 ]; then nudge up; sleep 1.1; PREVY=-999; continue; fi
    D=$((PY-PREVY)); [ $D -lt 0 ] && D=$((-D))
    if [ $D -gt 8 ]; then PREVY=$PY; sleep 0.5; continue; fi   # still settling — read again
    "$DIR/tap.sh" $PX $PY
    sleep 1.0
    scan
    if [ $OPEN -eq 0 ]; then
      P=$("$DIR/ocrfind" "$SHOT" "James Suk")
      [ "$P" != "NOTFOUND" ] && exit 0
      "$DIR/tap.sh" 78 85; sleep 1.1     # wrong row selected — reopen and retry
      bigdrag; sleep 0.4; bigdrag; sleep 1.2
      PREVY=-999; continue
    fi
    PREVY=-999; continue
  fi
  if [ $BELOW -eq 1 ]; then nudge up; else nudge down; fi
  sleep 1.1; PREVY=-999
done
echo "JAMES-FAIL" >&2; exit 1
