#!/bin/zsh
# Build a store's Favvy figure (Wes, 2026-11-20: one color + a QR sticker label).
#   ./make-figure.sh <windowCode> [tag]
#   tag = the store's Points NFC sticker for this figure (Store Admin → NFC
#         stickers → add "Favvy", kind Points → tag "favvy"). With a tag, a tap
#         or scan pays the visit; without one it only saves the store.
# The link (QR label + NFC sticker): https://api.favcircles.com/s/<code>?t=<tag>
# Output in bambu/<code>[-<tag>]/:
#   favvy-mono.stl, Favvy <code>.3mf (P1S, 0.16 mm Fine, any one filament)
#   label/label.pdf|png (1.5 in round, for Sticker Mule) and label/sheet.pdf
#   (US Letter, 20 labels: print at 100%, laminate, 1.5 in circle punch)
# COLOR=1 also writes the old four-filament STLs (QR printed in plastic).
set -e
CODE=${1:?usage: make-figure.sh <windowCode> [tag]}
TAG=${2:-}
HERE=${0:A:h}
BACKEND=${HERE:h:h:h}/backend
URL="https://api.favcircles.com/s/$CODE${TAG:+?t=$TAG}"
OUT="$HERE/bambu/$CODE${TAG:+-$TAG}"
mkdir -p "$OUT"
node "$HERE/make-label.js" "$URL" "$OUT/label"
openscad -D 'part="mono"' --export-format binstl -o "$OUT/favvy-mono.stl" "$HERE/favvy-print.scad" >/dev/null 2>&1
BAMBU=/Applications/BambuStudio.app/Contents/MacOS/BambuStudio
if [[ -x $BAMBU ]]; then
  P="$HERE/presets"
  $BAMBU --load-settings "$P/machine-P1S-0.4.json;$P/process-0.16-fine-3walls.json" \
    --load-filaments "$P/filament-pla-basic.json" --outputdir "$OUT" \
    --export-3mf "Favvy $CODE.3mf" "$OUT/favvy-mono.stl" >/dev/null 2>&1 || echo "(Bambu project skipped; open favvy-mono.stl in Bambu Studio)"
fi
if [[ -n $COLOR ]]; then
  node -e "
const q=require('$BACKEND/node_modules/qrcode').create(process.argv[1],{errorCorrectionLevel:'M'});
const n=q.modules.size,d=q.modules.data,rows=[];
for(let y=0;y<n;y++){const r=[];for(let x=0;x<n;x++)r.push(d[y*n+x]?1:0);rows.push('['+r.join(',')+']');}
require('fs').writeFileSync('$HERE/qr.scad','// '+process.argv[1]+'\nqr_n='+n+';\nqr=['+rows.join(',\n')+'];\n');" "$URL"
  for p in pink deep white black; do
    openscad -D "part=\"$p\"" --export-format binstl -o "$OUT/favvy-$p.stl" "$HERE/favvy-print.scad" >/dev/null 2>&1
  done
fi
echo "Done: $OUT"
echo "Link for the NFC sticker: $URL"
