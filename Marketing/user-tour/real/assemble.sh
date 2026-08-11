#!/bin/bash
# Assemble the real-footage user tour:
# title cards + per-beat composites (bg plate + simulator clip inside bezel + VO), concatenated.
# Footage: tour-raw.mov (scripted XCUITest run on the booted simulator).
set -euo pipefail
cd "$(dirname "$0")"
RAW=tour-raw.mov
FADE=0.3
PAD=0.6
mkdir -p seg
rm -f seg/*.mp4

dur_of() { ffprobe -v error -show_entries format=duration -of csv=p=0 "$1"; }

# --- static title-card segments (image + VO) ---
static_seg() { # name image vo skip_fadein
  local name=$1 img=$2 vo=$3 nofadein=${4:-0}
  local vod dur fadeout fin
  vod=$(dur_of "$vo"); dur=$(echo "$vod + $PAD" | bc); fadeout=$(echo "$dur - $FADE" | bc)
  if [ "$nofadein" = "1" ]; then fin=""; else fin="fade=t=in:st=0:d=$FADE,"; fi
  ffmpeg -y -v error -loop 1 -framerate 30 -i "$img" -i "$vo" \
    -filter_complex "[0:v]scale=1920:1080,${fin}fade=t=out:st=$fadeout:d=$FADE[v];[1:a]apad=pad_dur=$PAD,atrim=0:$dur,asetpts=N/SR/TB[a]" \
    -map "[v]" -map "[a]" -t "$dur" -r 30 \
    -c:v libx264 -pix_fmt yuv420p -preset medium -crf 18 -c:a aac -b:a 192k -ar 44100 \
    "seg/$name.mp4"
  echo "seg $name: ${dur}s (static)"
}

# --- real-footage beat segments (bg + clip in bezel + VO) ---
beat_seg() { # name bg vo start
  local name=$1 bg=$2 vo=$3 start=$4
  local vod dur fadeout
  vod=$(dur_of "$vo"); dur=$(echo "$vod + $PAD" | bc); fadeout=$(echo "$dur - $FADE" | bc)
  ffmpeg -y -v error \
    -loop 1 -framerate 30 -i "$bg" \
    -ss "$start" -t "$dur" -i "$RAW" \
    -loop 1 -framerate 30 -i bezel.png \
    -i "$vo" \
    -filter_complex "\
[1:v]scale=433:941,setpts=PTS-STARTPTS,tpad=stop_mode=clone:stop_duration=5[dev];\
[2:v]colorkey=0x00FF00:0.3:0.1[bez];\
[0:v]scale=1920:1080[bgv];\
[bgv][dev]overlay=1363:69:shortest=0[t1];\
[t1][bez]overlay=0:0,fade=t=in:st=0:d=$FADE,fade=t=out:st=$fadeout:d=$FADE[v];\
[3:a]apad=pad_dur=$PAD,atrim=0:$dur,asetpts=N/SR/TB[a]" \
    -map "[v]" -map "[a]" -t "$dur" -r 30 \
    -c:v libx264 -pix_fmt yuv420p -preset medium -crf 18 -c:a aac -b:a 192k -ar 44100 \
    "seg/$name.mp4"
  echo "seg $name: ${dur}s (clip @${start}s)"
}

static_seg 01-intro    ../out/01-intro.png vo/01-intro.mp3 1
beat_seg   02-home     bg/02-home.png     vo/02-home.mp3     23.0
beat_seg   03-addplace bg/03-addplace.png vo/03-addplace.mp3 30.5
beat_seg   04-filter   bg/04-filter.png   vo/04-filter.mp3   44.0
beat_seg   05-canopy   bg/05-canopy.png   vo/05-canopy.mp3   67.0
beat_seg   06-me       bg/07-me.png       vo/07-me.mp3       124.5
beat_seg   07-piggy    bg/08-piggy.png    vo/08-piggy.mp3    146.0
beat_seg   08-specials bg/09-specials.png vo/09-specials.mp3 160.0
static_seg 09-outro    ../out/99-outro.png vo/10-outro.mp3

# --- concat with the concat FILTER so both streams start at exactly 0 ---
inputs=(); fc=""; n=0
for f in seg/01-intro.mp4 seg/02-home.mp4 seg/03-addplace.mp4 seg/04-filter.mp4 seg/05-canopy.mp4 seg/06-me.mp4 seg/07-piggy.mp4 seg/08-specials.mp4 seg/09-outro.mp4; do
  inputs+=(-i "$f"); fc+="[$n:v][$n:a]"; n=$((n+1))
done
ffmpeg -y -v error "${inputs[@]}" \
  -filter_complex "${fc}concat=n=$n:v=1:a=1[v][a]" -map "[v]" -map "[a]" \
  -c:v libx264 -pix_fmt yuv420p -preset medium -crf 18 -c:a aac -b:a 192k \
  -movflags +faststart user-tour-real.mp4
ffmpeg -y -v error -i user-tour-real.mp4 -c:v libx264 -preset slow -crf 26 -pix_fmt yuv420p -c:a aac -b:a 128k -movflags +faststart user-tour-real-web.mp4
ffmpeg -y -v error -i user-tour-real-web.mp4 -frames:v 1 -q:v 2 user-tour-real-poster.jpg
echo DONE
ls -lh user-tour-real.mp4 user-tour-real-web.mp4