#!/bin/bash
# Build tutorial video from scenes/NN-name/{frame.html,vo.txt}
# Each scene: screenshot HTML -> PNG, say vo.txt -> AIFF, combine with slow zoom, concat all.
set -euo pipefail
cd "$(dirname "$0")"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
VOICE="Samantha"
RATE=170
PAD=1.0          # seconds of silence after each VO
FADE=0.4         # per-scene fade in/out
W=1920; H=1080
mkdir -p out
rm -f out/concat.txt

for dir in scenes/*/; do
  name=$(basename "$dir")
  png="out/$name.png"
  aiff="out/$name.aiff"
  seg="out/$name.mp4"

  # inline shared.css so the screenshot has no external deps
  python3 -c "
import pathlib
html = pathlib.Path('$dir/frame.html').read_text()
css = pathlib.Path('shared.css').read_text()
html = html.replace('<link rel=\"stylesheet\" href=\"../../shared.css\">', '<style>' + css + '</style>')
pathlib.Path('out/render-$name.html').write_text(html)
"
  "$CHROME" --headless --disable-gpu --hide-scrollbars \
    --screenshot="$png" --window-size=$W,$H \
    --force-device-scale-factor=2 \
    "file://$PWD/out/render-$name.html" 2>/dev/null
  sips --resampleWidth $W "$png" >/dev/null

  say -v "$VOICE" -r $RATE -o "$aiff" -f "$dir/vo.txt"
  vodur=$(afinfo "$aiff" | awk '/estimated duration/ {print $3}')
  dur=$(echo "$vodur + $PAD" | bc)
  fadeout=$(echo "$dur - $FADE" | bc)
  frames=$(echo "$dur * 30 / 1" | bc)

  ffmpeg -y -loop 1 -framerate 30 -i "$png" -i "$aiff" \
    -filter_complex "\
[0:v]scale=8000:-1,zoompan=z='1+0.00012*on':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d=$frames:s=${W}x${H}:fps=30,fade=t=in:st=0:d=$FADE,fade=t=out:st=$fadeout:d=$FADE[v];\
[1:a]apad=pad_dur=$PAD,atrim=0:$dur,asetpts=N/SR/TB[a]" \
    -map "[v]" -map "[a]" -t "$dur" \
    -c:v libx264 -pix_fmt yuv420p -preset medium -crf 18 \
    -c:a aac -b:a 192k -ar 44100 \
    "$seg" 2>/dev/null
  echo "file '$name.mp4'" >> out/concat.txt
  echo "scene $name: vo=${vodur}s total=${dur}s"
done

ffmpeg -y -f concat -safe 0 -i out/concat.txt -c copy out/store-owner-tutorial.mp4 2>/dev/null
echo "DONE"
ls -lh out/store-owner-tutorial.mp4
