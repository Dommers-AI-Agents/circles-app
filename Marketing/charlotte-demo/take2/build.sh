#!/bin/bash
# build.sh — assemble the Charlotte demo: walkthrough (intro title card overlaid on the live
# map + narration + captions + filter-pill ring pulses) + outro.
# Reads beat timing from out/actions.log (written by driver.sh). LEAD = video time of the
# driver's T0 inside walk_raw.mp4.
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

# ---- cut the silent middle of the James OCR-scroll (its duration varies 6-19s) ----
# keep ~1.5s of scroll after the b10b line ends, and the last 2.5s before selection.
cutA = marks["audio-b10b"] + 5.3
cutB = marks["james-done"] - 2.5
CUT = round(cutB - cutA, 2) if cutB - cutA > 0.5 else 0.0
if CUT:
    marks = {k: (t if t <= cutA else max(cutA, t - CUT)) for k, t in marks.items()}

A = {k[6:]: v for k, v in marks.items() if k.startswith("audio-")}
beats = {
 "b00":"00_intro",
 "b01":"01_avatar","b02":"02_expand","b03":"03_everyone","b04":"04_coffee",
 "b05":"05_drinks","b06":"06_food","b07":"07_bill","b08":"08_zoomout",
 "b09":"09_zoomin","b10":"10_james","b10b":"10b_list","b11":"11_brittany",
 "b12":"12_jump","b13":"13_mine",
}
end = marks.get("end", 80.0)
caps = [
 ("c01", A["b01"],      A["b01"]+4.9),
 ("c02", A["b02"],      A["b03"]+6.2),
 ("c04", A["b04"],      A["b04"]+2.7),
 ("c05", A["b05"],      A["b05"]+4.7),
 ("c06", A["b06"],      A["b06"]+3.5),
 ("c07", marks.get("bill", A["b07"]+2.5)-0.3, A["b07"]+6.0),
 ("c08", A["b08"],      A["b08"]+4.4),
 ("c10", A["b10"]-0.2,  A["b10"]+4.1),
 ("c11", A["b11"],      A["b11"]+4.2),
 ("c12", A["b12"],      A["b12"]+5.5),
 ("c13", marks.get("my-places", A["b13"]+1.5)-0.3, A["b13"]+4.8),
]

# ---- filter-pill ring pulses (person pill @ (160,174), category pill @ (449,174)) ----
# ring PNGs are 400x160 with the ring centered; overlay top-left = center - (200,80)
RING_XY = {"person": (-40, 94), "cat": (249, 94)}
ring_events = []   # (start, pos)
for m, pos in [("everyone","person"),("bill","person"),("brittany","person"),
               ("my-places","person"),("coffee","cat"),("drinks","cat"),
               ("food","cat"),("all-categories","cat"),("shopping","cat")]:
    if m in marks: ring_events.append((marks[m]+0.5, pos))   # +0.5: let the dropdown-close animation finish first
if "james-done" in marks: ring_events.append((marks["james-done"]+0.2, "person"))
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
if CUT:
    fc += (f"[vs]split[s1][s2];[s1]trim=0:{cutA:.2f},setpts=PTS-STARTPTS[p1];"
           f"[s2]trim={cutA+CUT:.2f},setpts=PTS-STARTPTS[p2];[p1][p2]concat=n=2:v=1:a=0[v0];")
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

# ---- concat with existing outro ----
subprocess.run(["ffmpeg","-v","error","-y",
  "-i",f"{OUT}/walk_final.mp4","-i",f"{DIR}/../out/outro2.mp4",
  "-filter_complex",
   "[0:v][0:a][1:v][1:a]concat=n=2:v=1:a=1[v][a]",
  "-map","[v]","-map","[a]","-c:v","libx264","-preset","medium","-crf","19",
  "-c:a","aac","-b:a","160k","-movflags","+faststart",
  f"{OUT}/favcircles-charlotte-demo.mp4"], check=True)
print("built", f"{OUT}/favcircles-charlotte-demo.mp4")
PY
