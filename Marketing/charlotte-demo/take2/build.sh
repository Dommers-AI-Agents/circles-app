#!/bin/bash
# build.sh — assemble the Charlotte demo: new intro + narrated walkthrough (+captions) + outro.
# Reads beat timing from out/actions.log (written by driver.sh). LEAD = video time of the
# driver's T0 inside walk_raw.mp4.
set -eu
DIR=$(cd "$(dirname "$0")" && pwd)
OUT="$DIR/out"
LEAD=${LEAD:-1.0}

python3 - "$DIR" "$OUT" "$LEAD" <<'PY'
import subprocess, sys, os
DIR, OUT, LEAD = sys.argv[1], sys.argv[2], float(sys.argv[3])
marks = {}
for line in open(f"{OUT}/actions.log"):
    t, name = line.split()
    marks.setdefault(name, float(t))

A = {k[6:]: v for k, v in marks.items() if k.startswith("audio-")}
A["b10b"] = 45.8
beats = {
 "b01":"01_avatar","b02":"02_expand","b03":"03_everyone","b04":"04_coffee",
 "b05":"05_drinks","b06":"06_food","b07":"07_bill","b08":"08_zoomout",
 "b09":"09_zoomin","b10":"10_james","b10b":"10b_list","b11":"11_brittany",
 "b12":"12_jump","b13":"13_mine",
}
jd = marks.get("james-done", 52.7)
end = marks.get("end", 72.8)
caps = [
 ("c01", A["b01"],      A["b01"]+4.9),
 ("c02", A["b02"],      A["b03"]+5.6),
 ("c04", A["b04"],      A["b04"]+2.7),
 ("c05", A["b05"],      A["b05"]+4.7),
 ("c06", A["b06"],      A["b06"]+3.5),
 ("c07", marks.get("bill", A["b07"]+2.5)-0.3, A["b07"]+6.0),
 ("c08", A["b08"],      A["b08"]+4.4),
 ("c10", A["b10"],      jd),
 ("c11", A["b11"],      A["b11"]+4.8),
 ("c12", A["b12"],      A["b12"]+5.5),
 ("c13", marks.get("my-places", A["b13"]+1.5)-0.3, A["b13"]+4.8),
]

# ---- 1) intro (new narration) ----
intro_vo = f"{DIR}/beats/00_intro.mp3"
dur = 10.2
subprocess.run(["ffmpeg","-v","error","-y",
  "-loop","1","-framerate","30","-t",str(dur),"-i",f"{DIR}/../out/intro.png",
  "-i",intro_vo,
  "-filter_complex",
   f"[0:v]scale=1800:3912,zoompan=z='1+0.06*on/{int(dur*30)}':d=1:s=900x1956:fps=30,"
   f"fade=t=in:d=0.5,fade=t=out:st={dur-0.5}:d=0.5,format=yuv420p[v];"
   f"[1:a]adelay=600|600,apad,atrim=0:{dur},aformat=sample_rates=44100:channel_layouts=stereo[a]",
  "-map","[v]","-map","[a]","-c:v","libx264","-preset","medium","-crf","19",
  "-c:a","aac","-b:a","160k", f"{OUT}/intro_new.mp4"], check=True)

# ---- 2) walkthrough with captions + narration ----
wdur = round(end - 0.3, 2)
inputs = ["-ss", str(LEAD), "-i", f"{OUT}/walk_raw.mp4"]
for _, png in sorted((c[0], f"{DIR}/caps/{c[0]}.png") for c in caps):
    inputs += ["-i", png]
for b in sorted(beats):
    inputs += ["-i", f"{DIR}/beats/{beats[b]}.mp3"]

fc = f"[0:v]fps=30,scale=900:1956,setpts=PTS-STARTPTS[v0];"
cur = "v0"
for i, (name, s, e) in enumerate(caps):
    nxt = f"v{i+1}"
    fc += f"[{cur}][{i+1}:v]overlay=0:0:enable='between(t,{s:.2f},{e:.2f})'[{nxt}];"
    cur = nxt
fc += f"[{cur}]trim=0:{wdur},setpts=PTS-STARTPTS,fade=t=out:st={wdur-0.5}:d=0.5,format=yuv420p[vout];"
amixin = ""
nb = len(caps)
for j, b in enumerate(sorted(beats)):
    idx = 1 + nb + j
    ms = int(A[b]*1000)
    fc += f"[{idx}:a]aformat=sample_rates=44100:channel_layouts=stereo,adelay={ms}|{ms}[a{j}];"
    amixin += f"[a{j}]"
fc += f"{amixin}amix=inputs={len(beats)}:normalize=0,apad,atrim=0:{wdur}[aout]"

subprocess.run(["ffmpeg","-v","error","-y"]+inputs+[
  "-filter_complex",fc,"-map","[vout]","-map","[aout]",
  "-c:v","libx264","-preset","medium","-crf","19","-c:a","aac","-b:a","160k",
  f"{OUT}/walk_final.mp4"], check=True)

# ---- 3) concat with existing outro ----
subprocess.run(["ffmpeg","-v","error","-y",
  "-i",f"{OUT}/intro_new.mp4","-i",f"{OUT}/walk_final.mp4","-i",f"{DIR}/../out/outro2.mp4",
  "-filter_complex",
   "[0:v][0:a][1:v][1:a][2:v][2:a]concat=n=3:v=1:a=1[v][a]",
  "-map","[v]","-map","[a]","-c:v","libx264","-preset","medium","-crf","19",
  "-c:a","aac","-b:a","160k","-movflags","+faststart",
  f"{OUT}/favcircles-charlotte-demo.mp4"], check=True)
print("built", f"{OUT}/favcircles-charlotte-demo.mp4")
PY
