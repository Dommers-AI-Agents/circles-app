#!/bin/bash
# build.sh — assemble the Postcard teaser: normalize the simctl take, cut dead
# space around the driver's marks, overlay captions timed to the narration,
# and wrap it in the house-style brand cards (frame 0 is the poster).
# Outputs: out/favcircles-postcard.mp4 (1080x2340) + -ig.mp4 (1080x1920).
set -eu
DIR=$(cd "$(dirname "$0")" && pwd)
OUT="$DIR/out"
LEAD=${LEAD:-1.0}
NAME=${NAME:-postcard}
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

python3 - "$DIR" "$OUT" "$LEAD" "$CHROME" "$NAME" <<'PY'
import subprocess, sys, os, html as htmlmod
DIR, OUT, LEAD, CHROME, NAME = sys.argv[1], sys.argv[2], float(sys.argv[3]), sys.argv[4], sys.argv[5]

marks = {}
for line in open(f"{OUT}/actions.log"):
    t, name = line.split()
    marks.setdefault(name, float(t))

def dur(path):
    return float(subprocess.check_output(["ffprobe","-v","quiet","-show_entries","format=duration","-of","csv=p=0",path]).strip())

# VFR take -> CFR 30, then clone the last frame out to the "end" mark
subprocess.run(["ffmpeg","-y","-v","error","-i",f"{OUT}/walk_raw.mp4","-vf","fps=30",
    "-c:v","libx264","-preset","fast","-crf","18","-pix_fmt","yuv420p",f"{OUT}/walk_norm.mp4"], check=True)
raw_total = dur(f"{OUT}/walk_norm.mp4")
need = marks["end"] + LEAD + 0.4
if raw_total < need - 0.05:
    subprocess.run(["ffmpeg","-y","-v","error","-i",f"{OUT}/walk_norm.mp4",
        "-vf",f"tpad=stop_mode=clone:stop_duration={need-raw_total:.2f}",
        "-c:v","libx264","-preset","fast","-crf","18","-pix_fmt","yuv420p",f"{OUT}/walk_pad.mp4"], check=True)
    os.replace(f"{OUT}/walk_pad.mp4", f"{OUT}/walk_norm.mp4")
    raw_total = dur(f"{OUT}/walk_norm.mp4")

# ---- auto-cut dead space (no narration, outside a mark's window) ----
vt = {k: v + LEAD for k, v in marks.items()}
beats_pre = [k[6:] for k, v in sorted(vt.items(), key=lambda x: x[1]) if k.startswith("audio-")]
pre_sched, pe = [], 0.0
for b in beats_pre:
    d = dur(f"{DIR}/beats/{b}.mp3"); s = max(vt[f"audio-{b}"], pe + 0.25)
    pre_sched.append((s, s + d)); pe = s + d
PROTECT = {"tab-widgets": (0.25, 0.45), "scroll-to-postcard": (0.15, 0.3), "open-postcard": (0.2, 0.6),
           "choose-photo": (0.15, 0.9), "scroll-to-deliver": (0.15, 0.3),
           "open-recipients": (0.15, 0.6), "toggle-mail": (0.2, 1.1),
           "back": (0.4, 1.6), "end": (1.0, 0.0)}
DEFAULT_PROTECT = (0.2, 0.6)
protected = [(t - PROTECT.get(n, DEFAULT_PROTECT)[0], t + PROTECT.get(n, DEFAULT_PROTECT)[1])
             for n, t in vt.items() if not n.startswith("audio-")]
merged = []
for s, e in sorted(pre_sched + protected):
    if merged and s <= merged[-1][1] + 0.05: merged[-1][1] = max(merged[-1][1], e)
    else: merged.append([s, e])
cuts, pos = [], 0.0
for s, e in merged:
    if s - pos > 0.35: cuts.append((pos + 0.05, s - 0.05))
    pos = max(pos, e)
if raw_total - pos > 0.8: cuts.append((pos + 0.1, raw_total - 0.3))
cuts = sorted((s, e) for s, e in cuts if e - s > 0.4 and s > 0.2)
def shift(t):
    out = t
    for s, e in cuts:
        if t >= e: out -= (e - s)
        elif t > s: out -= (t - s)
    return out
if cuts:
    segs, p, fc = [], 0.0, []
    for s, e in cuts: segs.append((p, s)); p = e
    segs.append((p, raw_total))
    for i, (s, e) in enumerate(segs): fc.append(f"[0:v]trim={s:.2f}:{e:.2f},setpts=PTS-STARTPTS[s{i}]")
    fc.append("".join(f"[s{i}]" for i in range(len(segs))) + f"concat=n={len(segs)}:v=1:a=0[vcut]")
    subprocess.run(["ffmpeg","-y","-v","error","-i",f"{OUT}/walk_norm.mp4","-filter_complex",";".join(fc),
        "-map","[vcut]","-c:v","libx264","-preset","medium","-crf","18","-pix_fmt","yuv420p",f"{OUT}/walk_cut.mp4"], check=True)
    src = f"{OUT}/walk_cut.mp4"; print(f"cut {sum(e-s for s,e in cuts):.1f}s dead time ({len(cuts)} cuts)")
else:
    src = f"{OUT}/walk_norm.mp4"
vt = {k: shift(v) for k, v in vt.items()}

# ---- speed the walk (narration stays at normal speed) ----
# The take is mostly waiting for the app: taps, a picker, a scroll. At 1.0 the
# cut still runs ~12s against 6s of narration, which pushes the whole thing to
# 22s. Speeding only the picture keeps both halves of the feature and the
# house-style cards inside 15s, and reads as a teaser rather than a tutorial.
SPEED = float(os.environ.get("SPEED", "1.0"))
if SPEED != 1.0:
    subprocess.run(["ffmpeg","-y","-v","error","-i",src,"-filter_complex",
        f"[0:v]setpts=PTS/{SPEED},fps=30[v]","-map","[v]",
        "-c:v","libx264","-preset","medium","-crf","18","-pix_fmt","yuv420p",f"{OUT}/walk_fast.mp4"], check=True)
    src = f"{OUT}/walk_fast.mp4"
    vt = {k: v / SPEED for k, v in vt.items()}
    print(f"walk sped {SPEED}x -> {dur(src):.1f}s")

total = dur(src)
for k, v in sorted(vt.items(), key=lambda x: x[1]): print(f"  {v:6.2f}  {k}")

beats = [k[6:] for k, v in sorted(vt.items(), key=lambda x: x[1]) if k.startswith("audio-")]
events, prev_end = [], 0.0
for b in beats:
    mp3 = f"{DIR}/beats/{b}.mp3"; d = dur(mp3)
    start = max(vt[f"audio-{b}"], prev_end + 0.25)
    events.append((b, mp3, start, d)); prev_end = start + d

# ---- overlays (HTML -> Chrome -> PNG) ----
capdir = f"{OUT}/caps"; os.makedirs(capdir, exist_ok=True)
FONT = '-apple-system,"SF Pro Display","Helvetica Neue",Arial,sans-serif'
CAP_CSS = """*{margin:0;padding:0;box-sizing:border-box}
html,body{width:1080px;height:2340px;background:transparent}
body{font-family:%s;display:flex;align-items:flex-end;justify-content:center}
.cap{margin-bottom:250px;background:rgba(14,42,71,.93);color:#fff;font-size:52px;
font-weight:700;padding:30px 54px;border-radius:28px;
border:2px solid rgba(79,209,197,.55);max-width:940px;text-align:center;
line-height:1.3;box-shadow:0 10px 40px rgba(0,0,0,.4)}""" % FONT
def render(name, body_html, css):
    ph, pp = f"{capdir}/{name}.html", f"{capdir}/{name}.png"
    open(ph, "w").write(f"<!doctype html><meta charset=utf8><style>{css}</style>{body_html}")
    subprocess.run([CHROME,"--headless","--disable-gpu","--hide-scrollbars",f"--screenshot={pp}",
                    "--window-size=1080,2340","--default-background-color=00000000",f"file://{ph}"],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return pp
cap_pngs = [render(b, f'<body><div class=cap>{htmlmod.escape(open(f"{DIR}/beats/{b}.txt").read().strip())}</div>', CAP_CSS)
            for b, _, _, _ in events]

# ---- brand cards (house style) ----
HOME = f"{DIR}/home_frame.png"
subprocess.run(["ffmpeg","-y","-v","error","-i",HOME,"-vf","scale=1080:2340",f"{OUT}/home_1080.png"], check=True)
CARD_CSS = """*{margin:0;padding:0;box-sizing:border-box}
html,body{width:1080px;height:2340px;background:rgba(6,14,26,.62)}
body{font-family:%s;display:flex;align-items:center;justify-content:center;color:#fff;text-align:center}
.card{width:920px;background:rgba(14,42,71,.96);border-radius:48px;padding:96px 56px 100px;
box-shadow:0 34px 100px rgba(0,0,0,.6);border:2px solid rgba(79,209,197,.28)}
.dots{display:grid;grid-template-columns:118px 118px;gap:26px;justify-content:center;margin-bottom:64px}
.dots i{width:118px;height:118px;border-radius:50%%;display:block}
.b{background:#3B8BD6}.t{background:#4FD1C5}
h1{font-size:150px;font-weight:800;letter-spacing:-3px;line-height:1}
h1 span{color:#4FD1C5}
p.tag{font-size:60px;font-weight:600;margin-top:34px;line-height:1.3;opacity:.96}
.note{margin-top:90px;display:flex;flex-direction:column;align-items:center;gap:26px}
.pill{background:#fff;color:#0E2A47;font-size:54px;font-weight:800;padding:28px 64px;border-radius:999px}
.sub{font-size:50px;font-weight:600;opacity:.92}""" % FONT
LOGO = '<div class=dots><i class=b></i><i class=t></i><i class=t></i><i class=b></i></div><h1><span>Fav</span>Circles</h1>'
intro_png = render("intro", f'<div class=card>{LOGO}<p class=tag>Never forget your favorite places.</p></div>', CARD_CSS)
outro_png = render("outro", f'<div class=card>{LOGO}<p class=tag>Never forget your favorite places.</p>'
    '<div class=note><div class=pill>Sign up at favcircles.com</div><div class=sub>Never forget a place.</div></div></div>', CARD_CSS)
def card_clip(png, mp3, out, lead, tail, reveal):
    d = dur(mp3) + lead + tail; ms = int(lead * 1000)
    ov = f"[1:v]format=rgba,fade=t=out:st={d-1.1:.2f}:d=0.6:alpha=1[ov]" if reveal else "[1:v]format=rgba,fade=t=in:st=0:d=0.6:alpha=1[ov]"
    post = "" if reveal else f",fade=t=out:st={d-0.6:.2f}:d=0.6"
    subprocess.run(["ffmpeg","-y","-v","error","-loop","1","-t",f"{d:.2f}","-framerate","30","-i",f"{OUT}/home_1080.png",
        "-loop","1","-t",f"{d:.2f}","-framerate","30","-i",png,"-i",mp3,
        "-filter_complex",f"{ov};[0:v][ov]overlay=0:0{post}[v];[2:a]adelay={ms}|{ms},apad,aresample=44100,aformat=sample_fmts=fltp:channel_layouts=stereo[a]",
        "-map","[v]","-map","[a]","-t",f"{d:.2f}","-c:v","libx264","-preset","medium","-crf","19","-pix_fmt","yuv420p",
        "-c:a","aac","-b:a","192k",out], check=True)
    return d
card_clip(intro_png, f"{DIR}/beats/s00.mp3", f"{OUT}/intro.mp4", 0.3, 0.7, True)
card_clip(outro_png, f"{DIR}/beats/s99.mp3", f"{OUT}/outro.mp4", 0.4, 0.8, False)

# ---- main pass ----
inputs = ["-i", src]
for _, mp3, _, _ in events: inputs += ["-i", mp3]
for png in cap_pngs: inputs += ["-i", png]
n = len(events); fc, mix = [], []
for i, (b, mp3, start, d) in enumerate(events):
    ms = int(start * 1000); fc.append(f"[{i+1}:a]adelay={ms}|{ms}[a{i}]"); mix.append(f"[a{i}]")
fc.append("".join(mix) + f"amix=inputs={len(mix)}:normalize=0,aresample=44100,aformat=sample_fmts=fltp:channel_layouts=stereo[aout]")
fc.append("[0:v]scale=1080:2340[v0]"); cur = "v0"
for i, (b, mp3, start, d) in enumerate(events):
    nxt = f"v{i+1}"; fc.append(f"[{cur}][{1+n+i}:v]overlay=0:0:enable='between(t,{start:.2f},{start+d+0.6:.2f})'[{nxt}]"); cur = nxt
fc.append(f"[{cur}]fade=t=in:st=0:d=0.3,fade=t=out:st={total-0.5:.2f}:d=0.5[vout]")
subprocess.run(["ffmpeg","-y","-v","error"] + inputs + ["-filter_complex",";".join(fc),"-map","[vout]","-map","[aout]",
    "-c:v","libx264","-preset","medium","-crf","19","-pix_fmt","yuv420p","-c:a","aac","-b:a","192k","-t",f"{total:.2f}",f"{OUT}/main.mp4"], check=True)
subprocess.run(["ffmpeg","-y","-v","error","-i",f"{OUT}/intro.mp4","-i",f"{OUT}/main.mp4","-i",f"{OUT}/outro.mp4","-filter_complex",
    "[0:a]aformat=sample_fmts=fltp:sample_rates=44100:channel_layouts=stereo[a0];[1:a]aformat=sample_fmts=fltp:sample_rates=44100:channel_layouts=stereo[a1];"
    "[2:a]aformat=sample_fmts=fltp:sample_rates=44100:channel_layouts=stereo[a2];[0:v][a0][1:v][a1][2:v][a2]concat=n=3:v=1:a=1[v][a]",
    "-map","[v]","-map","[a]","-c:v","libx264","-preset","medium","-crf","19","-pix_fmt","yuv420p","-c:a","aac","-b:a","192k",f"{OUT}/favcircles-{NAME}.mp4"], check=True)
subprocess.run(["ffmpeg","-y","-v","error","-i",f"{OUT}/favcircles-{NAME}.mp4","-filter_complex",
    "[0:v]split[fg][bg];[bg]scale=1080:1920,boxblur=40[bgb];[fg]scale=-2:1920[fgs];[bgb][fgs]overlay=(W-w)/2:0",
    "-c:v","libx264","-preset","medium","-crf","19","-pix_fmt","yuv420p","-c:a","copy",f"{OUT}/favcircles-{NAME}-ig.mp4"], check=True)
for f in [f"favcircles-{NAME}.mp4", f"favcircles-{NAME}-ig.mp4"]: print(" built", f, f"{dur(f'{OUT}/{f}'):.1f}s")
PY
