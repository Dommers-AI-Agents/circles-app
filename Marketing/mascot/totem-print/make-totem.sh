#!/bin/zsh
# Rebuild the FavCircles Totem print files (Wes, 2026-11-20; per-store maker's mark 2026-11-22).
#   ./make-totem.sh
#       → stl/*.stl and bambu/*.3mf (P1S, 0.16 mm Fine): plate 1 ring + base in Dark Blue PLA Matte,
#         plate 2 both heart halves in Red PLA Basic. The maker's mark under the base says No. 0001.
#   ./make-totem.sh <windowCode> [tag] ["Store Name"] [number]
#       → stores/<code>-<tag>/: the store's QR label sheet (Avery 8293): "TAP OR SCAN" round the top, the
#         store's name round the bottom (FAVCIRCLES when no name is given). With a name it also builds that
#         store's own ring + base plate, its maker's mark reading "MADE FOR <NAME>" and "No. <number>".
#       (tag = the base's NFC sticker, default "totem": Store Admin → NFC stickers → + → Points → "Totem")
set -e
HERE=${0:A:h}; cd $HERE
P=$HERE/../favvy-print/presets; B=/Applications/BambuStudio.app/Contents/MacOS/BambuStudio
BLUE="$P/filament-pla-matte-darkblue.json"; RED="$P/filament-pla-basic-red.json"
slice() { local out=$1 name=$2 fil=$3; shift 3
  $B --load-settings "$P/machine-P1S-0.4.json;$P/process-0.16-fine-3walls.json" --load-filaments "$fil" \
    --arrange 1 --orient 0 --slice 1 --outputdir "$out" --export-3mf "$name.3mf" "$@" >/dev/null 2>&1
  rm -f "$out/plate_1.gcode" "$out/result.json"
}
if [[ -n $1 ]]; then
  TAG=${2:-totem}; OUT=$HERE/stores/$1-$TAG
  node $HERE/../favvy-print/make-label.js "https://api.favcircles.com/s/$1?t=$TAG" $OUT "${3:-}"
  if [[ -n $3 ]] && ! command -v openscad >/dev/null; then
    echo "openscad is not on this Mac: made the label only (the store's own base plate needs openscad)"
  elif [[ -n $3 ]]; then
    NAME=${(U)3}; NO=${4:-0001}
    openscad --backend Manifold -D 'part="base"' -D "MAKER_FOR=\"$NAME\"" -D "MAKER_NO=\"$NO\"" --export-format binstl -o $OUT/base.stl totem.scad >/dev/null 2>&1
    [[ -f stl/ring.stl ]] || openscad --backend Manifold -D 'part="ring"' --export-format binstl -o stl/ring.stl totem.scad >/dev/null 2>&1
    slice $OUT "Totem 1 - ring + base ($3 No. $NO)" $BLUE $HERE/stl/ring.stl $OUT/base.stl
    echo "Plate 1 for $3: $OUT; plate 2 (heart) is the same for every store: bambu/Totem 2 - heart halves.3mf"
  fi
  echo "Print $OUT/sheet.pdf on Avery 8293 at Actual size"; exit 0
fi
mkdir -p stl bambu
for p in ring base heart_front heart_back; do
  openscad --backend Manifold -D "part=\"$p\"" --export-format binstl -o stl/$p.stl totem.scad >/dev/null 2>&1
done
slice $HERE/bambu "Totem 1 - ring + base" $BLUE $HERE/stl/ring.stl $HERE/stl/base.stl
slice $HERE/bambu "Totem 2 - heart halves" $RED $HERE/stl/heart_front.stl $HERE/stl/heart_back.stl
echo "Done: $HERE/bambu"
