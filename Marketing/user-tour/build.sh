#!/bin/bash
# Build tutorial video from scenes/NN-name/{frame.html,vo.txt}
# Each scene: screenshot HTML -> PNG, edge-tts vo.txt -> MP3, combine with slow zoom, concat all.
# VO uses Microsoft edge-tts neural voices (pip3 install --user --break-system-packages edge-tts).
# "FavCircles" is spelled "FaveCircles" in vo.txt files so TTS says "Fave", not "Fav".
set -euo pipefail
cd "$(dirname "$0")"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
VOICE="en-US-AvaNeural"
PAD=0.6          # tighter cuts
FADE=0.3
W=1920; H=1080
mkdir -p out
rm -f out/concat.txt

first=1
for dir in scenes/*/; do
  name=$(basename "$dir")
  png="out/$name.png"
  mp3="out/$name.mp3"
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

  python3 -m edge_tts --voice "$VOICE" --rate=+8% --file "$dir/vo.txt" --write-media "$mp3" >/dev/null 2>&1
  vodur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$mp3")
  dur=$(echo "$vodur + $PAD" | bc)
  fadeout=$(echo "$dur - $FADE" | bc)
  frames=$(echo "$dur * 30 / 1" | bc)

  if [ $first -eq 1 ]; then
    fadein=""   # open directly on content — no black first frame
    first=0
  else
    fadein="fade=t=in:st=0:d=$FADE,"
  fi

  ffmpeg -y -loop 1 -framerate 30 -i "$png" -i "$mp3" \
    -filter_complex "\
[0:v]scale=8000:-1,zoompan=z='1+0.00012*on':x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':d=$frames:s=${W}x${H}:fps=30,${fadein}fade=t=out:st=$fadeout:d=$FADE[v];\
[1:a]apad=pad_dur=$PAD,atrim=0:$dur,asetpts=N/SR/TB[a]" \
    -map "[v]" -map "[a]" -t "$dur" \
    -c:v libx264 -pix_fmt yuv420p -preset medium -crf 18 \
    -c:a aac -b:a 192k -ar 44100 \
    "$seg" 2>/dev/null
  echo "file '$name.mp4'" >> out/concat.txt
  echo "scene $name: vo=${vodur}s total=${dur}s"
done

# concat FILTER (not demuxer stream-copy): resets timestamps so video+audio both
# start at exactly 0 — otherwise players show a black frame before the first scene
inputs=(); fc=""; n=0
while read -r line; do
  f="out/$(echo "$line" | sed "s/^file '//; s/'$//")"
  inputs+=(-i "$f"); fc+="[$n:v][$n:a]"; n=$((n+1))
done < out/concat.txt
ffmpeg -y -v error "${inputs[@]}" \
  -filter_complex "${fc}concat=n=$n:v=1:a=1[v][a]" -map "[v]" -map "[a]" \
  -c:v libx264 -pix_fmt yuv420p -preset medium -crf 18 -c:a aac -b:a 192k \
  -movflags +faststart out/user-tour.mp4
ffmpeg -y -v error -i out/user-tour.mp4 -c:v libx264 -preset slow -crf 26 -pix_fmt yuv420p -c:a aac -b:a 128k -movflags +faststart out/user-tour-web.mp4
# poster image for embeds (explicit poster = no black preview anywhere)
ffmpeg -y -v error -i out/user-tour-web.mp4 -frames:v 1 -q:v 2 out/user-tour-poster.jpg
echo "DONE"
ls -lh out/user-tour.mp4 out/user-tour-web.mp4
