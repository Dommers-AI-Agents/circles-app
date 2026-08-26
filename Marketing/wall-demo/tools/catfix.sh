#!/bin/bash
# catfix.sh <label> — verify the category pill shows <label>; if a menu tap raced the
# open animation and selected the wrong row, correct it via OCR. Works from unknown
# menu state (open or closed). Exit 0 once the pill reads <label>.
DIR=$(cd "$(dirname "$0")" && pwd)
L="$1"
SHOT=/tmp/_catfix.png; PILL=/tmp/_catfix_pill.png; ROWS=/tmp/_catfix_rows.png
for i in 1 2 3; do
  xcrun simctl io booted screenshot "$SHOT" >/dev/null 2>&1
  # pill strip only (cat pill ~ x 155-290pt, y 70-105pt → px 465-870 / 210-315)
  ffmpeg -v error -y -i "$SHOT" -vf "crop=440:120:450:205" "$PILL" 2>/dev/null
  [ "$("$DIR/ocrfind" "$PILL" "$L")" != "NOTFOUND" ] && exit 0
  # wrong category — look for the target row in the (possibly open) menu region
  ffmpeg -v error -y -i "$SHOT" -vf "crop=760:1300:280:290" "$ROWS" 2>/dev/null
  R=$("$DIR/ocrfind" "$ROWS" "$L")
  if [ "$R" = "NOTFOUND" ]; then
    "$DIR/tap.sh" 219 85; sleep 1.2      # menu closed — open it
    xcrun simctl io booted screenshot "$SHOT" >/dev/null 2>&1
    ffmpeg -v error -y -i "$SHOT" -vf "crop=760:1300:280:290" "$ROWS" 2>/dev/null
    R=$("$DIR/ocrfind" "$ROWS" "$L")
  fi
  if [ "$R" != "NOTFOUND" ] && [ "$R" != "ERR" ]; then
    RX=$(( ( $(echo $R | cut -d' ' -f1) + 280 ) / 3 )); RY=$(( ( $(echo $R | cut -d' ' -f2) + 290 ) / 3 ))
    "$DIR/tap.sh" $RX $RY; sleep 1.1
  else
    sleep 0.8
  fi
done
echo "CATFIX-FAIL $L" >&2; exit 1
