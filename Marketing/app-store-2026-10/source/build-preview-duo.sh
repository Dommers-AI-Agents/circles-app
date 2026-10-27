#!/bin/zsh
# build-preview-duo.sh outer|inner <footage.mov> <captions.json> <out.mp4>
# Frames a simctl recording of the Duo (outer: --display=1 while Closed, inner: --display=3 while Open)
# into an App Store preview: outer → 886x1920 portrait, inner → 1920x886 landscape; H.264 High 4.0,
# 30 fps, silent stereo AAC 256k (Apple rejects mono/no audio). Captions: [{"text":"…","start":0,"end":4},…]
# NO_RING=1 leaves out the device bezel ring (footage on the brand background only).
set -eu
KIND=$1; SRC=$2; CAPS=$3; OUT=$4
HERE="$(cd "$(dirname "$0")" && pwd)"; WORK="$HERE/preview-work-$KIND"; mkdir -p "$WORK"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
G=$(node "$HERE/preview-frame.js" $KIND "$WORK")
W=$(echo $G | python3 -I -c 'import json,sys;print(json.load(sys.stdin)["w"])'); H=$(echo $G | python3 -I -c 'import json,sys;print(json.load(sys.stdin)["h"])')
FX=$(echo $G | python3 -I -c 'import json,sys;print(json.load(sys.stdin)["fx"])'); FY=$(echo $G | python3 -I -c 'import json,sys;print(json.load(sys.stdin)["fy"])'); FW=$(echo $G | python3 -I -c 'import json,sys;print(json.load(sys.stdin)["fw"])')
"$CHROME" --headless=new --hide-scrollbars --force-device-scale-factor=1 --window-size=$W,$H --screenshot="$WORK/bg.png" "file://$WORK/bg-$KIND.html" >/dev/null 2>&1
"$CHROME" --headless=new --hide-scrollbars --force-device-scale-factor=1 --default-background-color=00000000 --window-size=$W,$H --screenshot="$WORK/ring.png" "file://$WORK/ring-$KIND.html" >/dev/null 2>&1

# captions → transparent PNGs (same look as the Sept previews)
i=0; INPUTS=(-loop 1 -i "$WORK/bg.png" -i "$SRC" -loop 1 -i "$WORK/ring.png"); if [[ ${NO_RING:-0} == 1 ]]; then CHAIN="[1:v]fps=30,scale=${FW}:-2[f];[0:v][f]overlay=${FX}:${FY}[v0]"; else CHAIN="[1:v]fps=30,scale=${FW}:-2[f];[0:v][f]overlay=${FX}:${FY}[a];[a][2:v]overlay=0:0[v0]"; fi; LAST="v0"
if [[ $KIND == outer ]]; then CW=886; else CW=800; fi
python3 -I - "$CAPS" "$WORK" "$CW" <<'PY'
import json,sys
caps=json.load(open(sys.argv[1])); work=sys.argv[2]; cw=int(sys.argv[3])
for n,c in enumerate(caps):
    html=f'''<!doctype html><html><head><meta charset="utf-8"><link href="https://fonts.googleapis.com/css2?family=Inter:wght@800&display=swap" rel="stylesheet">
<style>html,body{{margin:0;background:transparent}}body{{width:{cw}px;height:200px;display:flex;align-items:center;justify-content:center}}
div{{font-family:Inter,Helvetica,Arial,sans-serif;font-weight:800;font-size:46px;color:#fff;background:rgba(15,30,58,.93);padding:22px 36px;border-radius:26px;max-width:{cw-100}px;text-align:center;line-height:1.15;box-shadow:0 10px 30px rgba(0,0,0,.35)}}
em{{font-style:normal;color:#4FD1C5}}</style></head><body><div>{c["text"]}</div></body></html>'''
    open(f"{work}/cap{n}.html","w").write(html)
PY
n=$(python3 -I -c 'import json,sys;print(len(json.load(open(sys.argv[1]))))' "$CAPS")
for ((k=0;k<n;k++)); do
  "$CHROME" --headless=new --hide-scrollbars --force-device-scale-factor=1 --default-background-color=00000000 --window-size=$CW,200 --screenshot="$WORK/cap$k.png" "file://$WORK/cap$k.html" >/dev/null 2>&1
  st=$(python3 -I -c 'import json,sys;print(json.load(open(sys.argv[1]))[int(sys.argv[2])]["start"])' "$CAPS" $k)
  en=$(python3 -I -c 'import json,sys;print(json.load(open(sys.argv[1]))[int(sys.argv[2])]["end"])' "$CAPS" $k)
  INPUTS+=(-loop 1 -i "$WORK/cap$k.png"); idx=$((3+k))
  if [[ $KIND == outer ]]; then POS="0:300"; else POS="60:343"; fi
  CHAIN="${CHAIN};[${LAST}][${idx}:v]overlay=${POS}:enable='between(t,${st},${en})'[v$((k+1))]"; LAST="v$((k+1))"
done
DUR=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$SRC")
DUR=$(python3 -I -c "print(min(float('$DUR'), 29.8))")   # App Store previews: 15–30 s
ffmpeg -y -v error "${INPUTS[@]}" -f lavfi -i anullsrc=channel_layout=stereo:sample_rate=48000 \
  -filter_complex "${CHAIN};[${LAST}]format=yuv420p[out]" -map "[out]" -map "$((3+n)):a" -t "$DUR" \
  -c:v libx264 -profile:v high -level 4.0 -pix_fmt yuv420p -r 30 -b:v 8M -c:a aac -b:a 256k -ar 48000 -ac 2 "$OUT"
ffprobe -v error -select_streams v -show_entries stream=width,height,r_frame_rate,duration -of csv=p=0 "$OUT"
