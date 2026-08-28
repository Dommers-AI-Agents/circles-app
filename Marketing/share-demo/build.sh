#!/bin/bash
# build.sh — assemble the share-extension demo. Captions are HTML→Chrome→PNG
# overlays (this ffmpeg has no drawtext/freetype), narration beats placed at
# the driver's marks without overlapping, brand outro card appended.
# Outputs: out/favcircles-share-demo.mp4 (1080x2340) and
#          out/favcircles-share-demo-ig.mp4 (1080x1920 Reels-safe blurred pad).
set -eu
DIR=$(cd "$(dirname "$0")" && pwd)
OUT="$DIR/out"
LEAD=${LEAD:-1.0}
NAME=${NAME:-share-demo}
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

python3 - "$DIR" "$OUT" "$LEAD" "$CHROME" "$NAME" <<'PY'
import subprocess, sys, os, html as htmlmod

DIR, OUT, LEAD, CHROME = sys.argv[1], sys.argv[2], float(sys.argv[3]), sys.argv[4]
NAME = sys.argv[5]

marks = {}
for line in open(f"{OUT}/actions.log"):
    t, name = line.split()
    marks.setdefault(name, float(t))

def dur(path):
    return float(subprocess.check_output(
        ["ffprobe","-v","quiet","-show_entries","format=duration","-of","csv=p=0",path]).strip())

raw_total = dur(f"{OUT}/walk_raw.mp4")

# ---- auto-cut ALL dead space ----
# Dead = no narration playing AND not within the protected window around an
# action mark. Every such stretch is excised, so pacing is tight no matter
# how slow the network or OCR retries were on a given take.
vt = {k: v + LEAD for k, v in marks.items()}

beats_pre = [k[6:] for k, v in sorted(vt.items(), key=lambda x: x[1]) if k.startswith("audio-")]
pre_sched, pe = [], 0.0
for b in beats_pre:
    d = dur(f"{DIR}/beats/{b}.mp3")
    s = max(vt[f"audio-{b}"], pe + 0.25)
    pre_sched.append((s, s + d))
    pe = s + d

# Per-mark protection (pre, post) seconds — how much surrounding video an
# action needs to read on screen.
PROTECT = {
    "flourish-up": (0.2, 1.7), "flourish-down": (0.2, 1.7),
    "maps-open": (0.3, 2.2), "app-launch": (0.3, 2.8),
    "done-a": (2.3, 1.0), "done-b": (2.3, 1.0),
    "end": (2.6, 0.0),
}
DEFAULT_PROTECT = (0.35, 1.2)
protected = []
for name, t in vt.items():
    if name.startswith("audio-"): continue
    pre, post = PROTECT.get(name, DEFAULT_PROTECT)
    protected.append((t - pre, t + post))

busy = sorted(pre_sched + protected)
merged = []
for s, e in busy:
    if merged and s <= merged[-1][1] + 0.05:
        merged[-1][1] = max(merged[-1][1], e)
    else:
        merged.append([s, e])

cuts, pos = [], 0.0
for s, e in merged:
    if s - pos > 0.6:
        cuts.append((pos + 0.1, s - 0.1))
    pos = max(pos, e)
if raw_total - pos > 0.8:
    cuts.append((pos + 0.1, raw_total - 0.3))
cuts = [(s, e) for s, e in cuts if e - s > 0.4 and s > 0.2]
cuts.sort()

def shift(t):
    out = t
    for s, e in cuts:
        if t >= e: out -= (e - s)
        elif t > s: out -= (t - s)
    return out

if cuts:
    segs, pos, fc, idx = [], 0.0, [], 0
    for s, e in cuts:
        segs.append((pos, s)); pos = e
    segs.append((pos, raw_total))
    for i, (s, e) in enumerate(segs):
        fc.append(f"[0:v]trim={s:.2f}:{e:.2f},setpts=PTS-STARTPTS[s{i}]")
    fc.append("".join(f"[s{i}]" for i in range(len(segs))) + f"concat=n={len(segs)}:v=1:a=0[vcut]")
    subprocess.run(["ffmpeg","-y","-v","error","-i",f"{OUT}/walk_raw.mp4",
        "-filter_complex",";".join(fc),"-map","[vcut]",
        "-c:v","libx264","-preset","medium","-crf","18","-pix_fmt","yuv420p",
        f"{OUT}/walk_cut.mp4"], check=True)
    src = f"{OUT}/walk_cut.mp4"
    print(f"cut {sum(e-s for s,e in cuts):.1f}s of dead time ({len(cuts)} cuts)")
else:
    src = f"{OUT}/walk_raw.mp4"

vt = {k: shift(v) for k, v in vt.items()}
total = dur(src)

beats = [k[6:] for k, v in sorted(vt.items(), key=lambda x: x[1]) if k.startswith("audio-")]
events, prev_end = [], 0.0
for b in beats:
    mp3 = f"{DIR}/beats/{b}.mp3"
    d = dur(mp3)
    start = max(vt[f"audio-{b}"], prev_end + 0.25)
    events.append((b, mp3, start, d))
    prev_end = start + d
capdir = f"{OUT}/caps"; os.makedirs(capdir, exist_ok=True)

CAP_CSS = """*{margin:0;padding:0;box-sizing:border-box}
html,body{width:1080px;height:2340px;background:transparent}
body{font-family:-apple-system,"SF Pro Display","Helvetica Neue",Arial,sans-serif;
display:flex;align-items:flex-end;justify-content:center}
.cap{margin-bottom:250px;background:rgba(14,42,71,.93);color:#fff;font-size:52px;
font-weight:700;padding:30px 54px;border-radius:28px;
border:2px solid rgba(79,209,197,.55);max-width:940px;text-align:center;
line-height:1.3;box-shadow:0 10px 40px rgba(0,0,0,.4)}"""

def render(name, body_html, css):
    path_html = f"{capdir}/{name}.html"
    path_png = f"{capdir}/{name}.png"
    open(path_html, "w").write(f"<!doctype html><meta charset=utf8><style>{css}</style>{body_html}")
    subprocess.run([CHROME, "--headless", "--disable-gpu", "--hide-scrollbars",
                    f"--screenshot={path_png}", "--window-size=1080,2340",
                    "--default-background-color=00000000",
                    f"file://{path_html}"], check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return path_png

cap_pngs = []
for b, mp3, start, d in events:
    text = htmlmod.escape(open(f"{DIR}/beats/{b}.txt").read().strip())
    cap_pngs.append(render(b, f'<div class=cap>{text}</div>', CAP_CSS))

OUTRO_CSS = """*{margin:0;padding:0;box-sizing:border-box}
html,body{width:1080px;height:2340px;background:#3182CE}
body{font-family:-apple-system,"SF Pro Display","Helvetica Neue",Arial,sans-serif;
display:flex;flex-direction:column;align-items:center;justify-content:center;color:#fff}
h1{font-size:150px;font-weight:800;letter-spacing:-2px}
p{font-size:66px;font-weight:600;margin-top:34px;opacity:.94;text-align:center;line-height:1.35}"""
outro_png = render("outro", "<h1>FavCircles</h1><p>Save it. Share it.<br>Find it again.</p>", OUTRO_CSS)

# ---- main pass: scale + caption overlays + narration mix ----
inputs = ["-i", src]
for _, mp3, _, _ in events: inputs += ["-i", mp3]
n_audio = len(events)
for png in cap_pngs: inputs += ["-i", png]

fc = []
mix = []
for i, (b, mp3, start, d) in enumerate(events):
    ms = int(start * 1000)
    fc.append(f"[{i+1}:a]adelay={ms}|{ms}[a{i}]")
    mix.append(f"[a{i}]")
fc.append("".join(mix) + f"amix=inputs={len(mix)}:normalize=0[aout]")

fc.append("[0:v]scale=1080:2340[v0]")
cur = "v0"
for i, (b, mp3, start, d) in enumerate(events):
    idx = 1 + n_audio + i
    end = start + d + 0.7
    nxt = f"v{i+1}"
    fc.append(f"[{cur}][{idx}:v]overlay=0:0:enable='between(t,{start:.2f},{end:.2f})'[{nxt}]")
    cur = nxt
fc.append(f"[{cur}]fade=t=out:st={total-0.5:.2f}:d=0.5[vout]")

subprocess.run(["ffmpeg","-y","-v","error"] + inputs + [
    "-filter_complex", ";".join(fc),
    "-map","[vout]","-map","[aout]",
    "-c:v","libx264","-preset","medium","-crf","19","-pix_fmt","yuv420p",
    "-c:a","aac","-b:a","192k","-t",f"{total:.2f}",
    f"{OUT}/main.mp4"], check=True)

# ---- outro clip ----
subprocess.run(["ffmpeg","-y","-v","error",
    "-loop","1","-t","3.0","-framerate","30","-i", outro_png,
    "-f","lavfi","-t","3.0","-i","anullsrc=channel_layout=stereo:sample_rate=44100",
    "-filter_complex","[0:v]fade=t=in:st=0:d=0.4,fade=t=out:st=2.5:d=0.5[v]",
    "-map","[v]","-map","1:a",
    "-c:v","libx264","-preset","medium","-crf","19","-pix_fmt","yuv420p",
    "-c:a","aac","-shortest", f"{OUT}/outro.mp4"], check=True)

# concat FILTER (stream-copy concat inflated duration on mismatched timestamps)
subprocess.run(["ffmpeg","-y","-v","error",
    "-i",f"{OUT}/main.mp4","-i",f"{OUT}/outro.mp4",
    "-filter_complex","[0:v][0:a][1:v][1:a]concat=n=2:v=1:a=1[v][a]",
    "-map","[v]","-map","[a]",
    "-c:v","libx264","-preset","medium","-crf","19","-pix_fmt","yuv420p",
    "-c:a","aac","-b:a","192k", f"{OUT}/favcircles-{NAME}.mp4"], check=True)

# ---- Instagram 9:16 variant ----
subprocess.run(["ffmpeg","-y","-v","error","-i",f"{OUT}/favcircles-{NAME}.mp4",
    "-filter_complex",
    "[0:v]split[fg][bg];[bg]scale=1080:1920,boxblur=40[bgb];"
    "[fg]scale=-2:1920[fgs];[bgb][fgs]overlay=(W-w)/2:0",
    "-c:v","libx264","-preset","medium","-crf","19","-pix_fmt","yuv420p",
    "-c:a","copy", f"{OUT}/favcircles-{NAME}-ig.mp4"], check=True)

print("built:")
for f in [f"favcircles-{NAME}.mp4", f"favcircles-{NAME}-ig.mp4"]:
    print(" ", f, f"{dur(f'{OUT}/{f}'):.1f}s")
PY
