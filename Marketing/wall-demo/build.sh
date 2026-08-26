#!/bin/bash
# build.sh — assemble the Wall Township demo: walkthrough (intro title card overlaid on the
# live map + narration + captions + filter-pill ring pulses) + outro (shared with the
# Charlotte demo). Reads beat timing from out/actions.log (written by driver.sh) and cuts
# the silent middle of each variable-length OCR person-hunt (Salvatore, Margie, Amanda).
# LEAD = video time of the driver's T0 inside walk_raw.mp4.
set -eu
DIR=$(cd "$(dirname "$0")" && pwd)
OUT="$DIR/out"
LEAD=${LEAD:-1.0}

python3 - "$DIR" "$OUT" "$LEAD" <<'PY'
import subprocess, sys
DIR, OUT, LEAD = sys.argv[1], sys.argv[2], float(sys.argv[3])
marks = {}
for line in open(f"{OUT}/actions.log"):
    t, name = line.split()
    marks.setdefault(name, float(t))

# ---- cut the silent middle of each OCR person-hunt (durations vary 6-19s) ----
cuts = []
def addcut(a, b):
    if b - a > 0.5: cuts.append((a, b))
addcut(marks["sal-start"] + 1.0,    marks["sal-done"] - 1.5)
addcut(marks["audio-b10b"] + 3.9,   marks["margie-done"] - 1.5)   # keep the b10b line + scroll tail
addcut(marks["amanda-start"] + 0.9, marks["amanda-done"] - 1.5)
# static banner hold before the b12 line (catfix verification time) — safe to trim
addcut(marks["outdoors"] + 1.5, marks["audio-b12"] - 0.3)
cuts.sort()
def shift(t):
    out = t
    for a, b in cuts:
        if t >= b: out -= (b - a)
        elif t > a: out -= (t - a)
    return out
marks = {k: shift(t) for k, t in marks.items()}

A = {k[6:]: v for k, v in marks.items() if k.startswith("audio-")}
beats = {
 "b00":"00_intro",
 "b01":"01_avatar","b02":"02_expand","b03":"03_everyone","b04":"04_coffee",
 "b05":"05_shopping","b06":"06_food","b07a":"07a_friend","b07b":"07b_sal",
 "b08":"08_zoomout","b09":"09_zoomin","b10":"10_margie","b10b":"10b_list",
 "b11":"11_amanda","b11a":"11a_next","b12":"12_jump","b13":"13_mine",
}
end = marks.get("end", 110.0)
caps = [
 ("c01", A["b01"],       A["b01"]+4.9),
 ("c02", A["b02"],       A["b03"]+6.0),
 ("c04", A["b04"],       A["b04"]+2.7),
 ("c05", A["b05"],       A["b05"]+4.7),
 ("c06", A["b06"],       A["b06"]+3.5),
 ("c07", A["b07b"]-0.2,  A["b07b"]+3.7),
 ("c08", A["b08"],       A["b08"]+4.4),
 ("c10", A["b10"]-0.2,   A["b10"]+4.0),
 ("c11", A["b11"]-0.2,   A["b11"]+4.0),
 ("c12", A["b12"],       A["b12"]+5.5),
 ("c13", marks.get("my-places", A["b13"]+1.5)-0.3, A["b13"]+4.8),
]

# ---- filter-pill ring pulses (person pill @ (160,174), category pill @ (449,174)) ----
# ring PNGs are 400x160 with the ring centered; overlay top-left = center - (200,80)
RING_XY = {"person": (-40, 94), "cat": (249, 94)}
ring_events = []   # (start, pos)
for m, pos, off in [("everyone","person",0.5),("coffee","cat",0.5),("shopping","cat",0.5),
                    ("food","cat",0.5),("all-categories","cat",0.5),("coffee2","cat",0.5),
                    ("outdoors","cat",0.5),("my-places","person",0.5),
                    ("sal-done","person",0.2),("margie-done","person",0.2),
                    ("amanda-done","person",0.2)]:
    if m in marks: ring_events.append((marks[m]+off, pos))
CYC = 0.72
PHASE = {1: (0.0,0.22), 2: (0.22,0.44), 3: (0.44,0.72)}   # expanding ripple, 2 cycles

def ring_enable(size, pos):
    p0, p1 = PHASE[size]
    terms = []
    for s, ep in ring_events:
        if ep != pos: continue
        for k in (0, 1):
            terms.append(f"between(t,{s+k*CYC+p0:.2f},{s+k*CYC+p1:.2f})")
    return "+".join(terms)

# ---- walkthrough: intro card overlay + captions + rings + narration ----
wdur = round(end - 0.3, 2)
inputs = ["-ss", str(LEAD), "-i", f"{OUT}/walk_raw.mp4",
          "-loop","1","-framerate","30","-t","10.5","-i", f"{DIR}/caps/intro_card.png"]
for _, png in sorted((c[0], f"{DIR}/caps/{c[0]}.png") for c in caps):
    inputs += ["-i", png]
for r in (1,2,3):
    inputs += ["-i", f"{DIR}/caps/ring{r}.png"]
for b in sorted(beats):
    inputs += ["-i", f"{DIR}/beats/{beats[b]}.mp3"]

fc = f"[0:v]fps=30,scale=900:1956,setpts=PTS-STARTPTS[vs];"
if cuts:
    n = len(cuts)
    fc += f"[vs]split={n+1}" + "".join(f"[s{i}]" for i in range(n+1)) + ";"
    bounds = [0.0] + [x for c in cuts for x in c] + [None]
    segs = [(bounds[2*i], bounds[2*i+1]) for i in range(n+1)]
    for i, (a, b) in enumerate(segs):
        tr = f"trim={a:.2f}" + (f":{b:.2f}" if b is not None else "")
        fc += f"[s{i}]{tr},setpts=PTS-STARTPTS[p{i}];"
    fc += "".join(f"[p{i}]" for i in range(n+1)) + f"concat=n={n+1}:v=1:a=0[v0];"
else:
    fc += "[vs]null[v0];"
# card fully visible from frame 1 so the share/poster thumbnail shows the branded map
fc += "[1:v]format=rgba,fade=t=out:st=8.0:d=0.7:alpha=1[card];"
fc += "[v0][card]overlay=0:0:enable='between(t,0,8.9)'[v1];"
cur, n = "v1", 2
for i, (name, s, e) in enumerate(caps):
    fc += f"[{cur}][{2+i}:v]overlay=0:0:enable='between(t,{s:.2f},{e:.2f})'[v{n}];"
    cur = f"v{n}"; n += 1
nring0 = 2 + len(caps)
for r in (1,2,3):
    for pos, (x, y) in RING_XY.items():
        en = ring_enable(r, pos)
        if not en: continue
        fc += f"[{cur}][{nring0+r-1}:v]overlay={x}:{y}:enable='{en}'[v{n}];"
        cur = f"v{n}"; n += 1
fc += (f"[{cur}]trim=0:{wdur},setpts=PTS-STARTPTS,"
       f"fade=t=out:st={wdur-0.5}:d=0.5,format=yuv420p[vout];")
amixin = ""
naud0 = nring0 + 3
for j, b in enumerate(sorted(beats)):
    ms = int(A[b]*1000)
    fc += f"[{naud0+j}:a]aformat=sample_rates=44100:channel_layouts=stereo,adelay={ms}|{ms}[a{j}];"
    amixin += f"[a{j}]"
fc += f"{amixin}amix=inputs={len(beats)}:normalize=0,apad,atrim=0:{wdur}[aout]"

subprocess.run(["ffmpeg","-v","error","-y"]+inputs+[
  "-filter_complex",fc,"-map","[vout]","-map","[aout]",
  "-c:v","libx264","-preset","medium","-crf","19","-c:a","aac","-b:a","160k",
  f"{OUT}/walk_final.mp4"], check=True)

# ---- concat with the shared outro ----
subprocess.run(["ffmpeg","-v","error","-y",
  "-i",f"{OUT}/walk_final.mp4","-i",f"{DIR}/../charlotte-demo/out/outro2.mp4",
  "-filter_complex",
   "[0:v][0:a][1:v][1:a]concat=n=2:v=1:a=1[v][a]",
  "-map","[v]","-map","[a]","-c:v","libx264","-preset","medium","-crf","19",
  "-c:a","aac","-b:a","160k","-movflags","+faststart",
  f"{OUT}/favcircles-wall-demo.mp4"], check=True)
print("built", f"{OUT}/favcircles-wall-demo.mp4")
PY
