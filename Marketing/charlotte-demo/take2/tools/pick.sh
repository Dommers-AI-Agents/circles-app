#!/bin/bash
# pick.sh <row-needle> <pill-verify-needle> <n-initial-bigdrags> <below-marker> [below-marker2 ...]
# Scroll the OPEN person menu to the row matching <row-needle> and select it.
# Same protocol as james.sh: only tap when two consecutive OCR reads agree (<8px),
# then verify the menu closed AND the pill shows <pill-verify-needle>; recover if a
# wrong row got selected. <below-marker>s are names known to sit BELOW the target —
# if one is visible but the target isn't, we scroll up, else down.
DIR=$(cd "$(dirname "$0")" && pwd)
NEEDLE="$1"; VERIFY="$2"; NDRAGS="$3"; shift 3
SHOT=/tmp/_pick_ocr.png
bigdrag() { "$DIR/drag.sh" 143 560 143 200 300; }
nudge() {
  if [ "$1" = "down" ]; then "$DIR/drag.sh" 143 500 143 380 250; else "$DIR/drag.sh" 143 380 143 500 250; fi
}
scan() {
  xcrun simctl io booted screenshot "$SHOT" >/dev/null 2>&1
  local out; out=$("$DIR/ocrfind" "$SHOT" "$NEEDLE" "My Connections" "$@")
  J=$(echo "$out" | sed -n 1p)
  OPEN=0; PAST=0
  [ "$(echo "$out" | sed -n 2p)" != "NOTFOUND" ] && OPEN=1                 # list top visible → target below
  local i=3
  for m in "$@"; do
    [ "$(echo "$out" | sed -n ${i}p)" != "NOTFOUND" ] && { OPEN=1; PAST=1; }  # below-marker visible → overshot
    i=$((i+1))
  done
}
jxy() { [ "$J" != "NOTFOUND" ] && [ "$J" != "ERR" ] && [ -n "$J" ]; }
for ((d=0; d<NDRAGS; d++)); do bigdrag; sleep 0.4; done
sleep 1.2
PREVY=-999
for i in 1 2 3 4 5 6 7 8; do
  scan "$@"
  if jxy; then
    PX=$(( $(echo $J | cut -d' ' -f1) / 3 )); PY=$(( $(echo $J | cut -d' ' -f2) / 3 ))
    if [ $PY -gt 540 ]; then nudge down; sleep 1.1; PREVY=-999; continue; fi
    if [ $PY -lt 155 ]; then nudge up; sleep 1.1; PREVY=-999; continue; fi
    D=$((PY-PREVY)); [ $D -lt 0 ] && D=$((-D))
    if [ $D -gt 8 ]; then PREVY=$PY; sleep 0.5; continue; fi   # still settling — read again
    "$DIR/tap.sh" $PX $PY
    sleep 1.0
    scan "$@"
    if [ $OPEN -eq 0 ]; then
      P=$("$DIR/ocrfind" "$SHOT" "$VERIFY")
      [ "$P" != "NOTFOUND" ] && exit 0
      "$DIR/tap.sh" 78 85; sleep 1.1     # wrong row selected — reopen and retry
      for ((d=0; d<NDRAGS; d++)); do bigdrag; sleep 0.4; done
      sleep 1.2
      PREVY=-999; continue
    fi
    PREVY=-999; continue
  fi
  if [ $PAST -eq 1 ]; then nudge up; else nudge down; fi
  sleep 1.1; PREVY=-999
done
echo "PICK-FAIL $NEEDLE" >&2; exit 1
