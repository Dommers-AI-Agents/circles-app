#!/bin/bash
# build.sh — assemble the share-extension demo (v8). Captions/rings/cards are
# HTML→Chrome→PNG overlays (this ffmpeg has no drawtext/freetype), narration
# beats placed at the driver's marks without overlapping, dead space
# auto-cut, logo intro card (frame 0 is the poster — no fade-in) and a
# sign-up outro card wrapped around the walkthrough.
# Outputs: out/favcircles-<NAME>.mp4 (1080x2340) and
#          out/favcircles-<NAME>-ig.mp4 (1080x1920 Reels-safe blurred pad).
set -eu
DIR=$(cd "$(dirname "$0")" && pwd)
OUT="$DIR/out"
LEAD=${LEAD:-1.0}
NAME=${NAME:-share-demo}
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

python3 - "$DIR" "$OUT" "$LEAD" "$CHROME" "$NAME" <<'PY'
import subprocess, sys, os, json, html as htmlmod

DIR, OUT, LEAD, CHROME = sys.argv[1], sys.argv[2], float(sys.argv[3]), sys.argv[4]
NAME = sys.argv[5]

marks = {}
for line in open(f"{OUT}/actions.log"):
    t, name = line.split()
    marks.setdefault(name, float(t))

def dur(path):
    return float(subprocess.check_output(
        ["ffprobe","-v","quiet","-show_entries","format=duration","-of","csv=p=0",path]).strip())

# simctl recordVideo is VFR (frames only on screen change) — static holds
# collapse when trimmed, desyncing picture from the mark-based audio
# schedule. Normalize to CFR 30 first; all timing math runs on the result.
subprocess.run(["ffmpeg","-y","-v","error","-i",f"{OUT}/walk_raw.mp4",
    "-vf","fps=30","-c:v","libx264","-preset","fast","-crf","18",
    "-pix_fmt","yuv420p", f"{OUT}/walk_norm.mp4"], check=True)
raw_total = dur(f"{OUT}/walk_norm.mp4")
# ...and the recorder stops emitting frames once the screen goes static, so a
# take that ENDS on a hold (the ring sequence) comes back shorter than the
# mark timeline. Clone the last frame out to the "end" mark.
need = marks["end"] + LEAD + 0.4
if raw_total < need - 0.05:
    subprocess.run(["ffmpeg","-y","-v","error","-i",f"{OUT}/walk_norm.mp4",
        "-vf",f"tpad=stop_mode=clone:stop_duration={need-raw_total:.2f}",
        "-c:v","libx264","-preset","fast","-crf","18","-pix_fmt","yuv420p",
        f"{OUT}/walk_pad.mp4"], check=True)
    os.replace(f"{OUT}/walk_pad.mp4", f"{OUT}/walk_norm.mp4")
    print(f"padded static tail {need-raw_total:.1f}s")
    raw_total = dur(f"{OUT}/walk_norm.mp4")

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
    "app-launch": (0.3, 2.8), "done-a": (2.3, 1.0),
    "me-tab": (0.4, 2.2), "open-circle": (0.4, 2.6),
    "open-place": (0.5, 2.2), "chips-scroll": (0.3, 1.4),
    "hl-start": (0.3, 0.5), "end": (2.6, 0.0),
}
SCROLL_PROTECT = (0.15, 0.75)          # list flicks: keep them brisk
DEFAULT_PROTECT = (0.35, 1.2)
protected = []
for name, t in vt.items():
    if name.startswith("audio-"): continue
    pre, post = SCROLL_PROTECT if name.startswith("scroll-") or name == "nudge" else PROTECT.get(name, DEFAULT_PROTECT)
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
    subprocess.run(["ffmpeg","-y","-v","error","-i",f"{OUT}/walk_norm.mp4",
        "-filter_complex",";".join(fc),"-map","[vcut]",
        "-c:v","libx264","-preset","medium","-crf","18","-pix_fmt","yuv420p",
        f"{OUT}/walk_cut.mp4"], check=True)
    src = f"{OUT}/walk_cut.mp4"
    print(f"cut {sum(e-s for s,e in cuts):.1f}s of dead time ({len(cuts)} cuts)")
else:
    src = f"{OUT}/walk_norm.mp4"

vt = {k: shift(v) for k, v in vt.items()}
total = dur(src)
print("CUTS:", [(round(s,2), round(e,2)) for s,e in cuts])
for k, v in sorted(vt.items(), key=lambda x: x[1]):
    print(f"  shifted {v:6.2f}  {k}")

beats = [k[6:] for k, v in sorted(vt.items(), key=lambda x: x[1]) if k.startswith("audio-")]
events, prev_end = [], 0.0
for b in beats:
    mp3 = f"{DIR}/beats/{b}.mp3"
    d = dur(mp3)
    start = max(vt[f"audio-{b}"], prev_end + 0.25)
    events.append((b, mp3, start, d))
    prev_end = start + d
capdir = f"{OUT}/caps"; os.makedirs(capdir, exist_ok=True)

FONT = '-apple-system,"SF Pro Display","Helvetica Neue",Arial,sans-serif'
CAP_CSS = """*{margin:0;padding:0;box-sizing:border-box}
html,body{width:1080px;height:2340px;background:transparent}
body{font-family:%s;display:flex;align-items:flex-end;justify-content:center}
.cap{margin-bottom:250px;background:rgba(14,42,71,.93);color:#fff;font-size:52px;
font-weight:700;padding:30px 54px;border-radius:28px;
border:2px solid rgba(79,209,197,.55);max-width:940px;text-align:center;
line-height:1.3;box-shadow:0 10px 40px rgba(0,0,0,.4)}
body.top{align-items:flex-start}.top .cap{margin-top:540px}""" % FONT

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

# Captions ride at the bottom, except over the action row (b04) where the
# rings live — that one sits up over the hero photo.
TOP_CAPS = {"b04"}
cap_pngs = []
for b, mp3, start, d in events:
    text = htmlmod.escape(open(f"{DIR}/beats/{b}.txt").read().strip())
    cls = ' class=top' if b in TOP_CAPS else ''
    cap_pngs.append(render(b, f'<body{cls}><div class=cap>{text}</div>', CAP_CSS))

# ---- highlight rings: OCR'd button centers (screenshot px 1320x2868) ----
# -> video px (1080x2340); one ring PNG per button, shown on the spoken word.
SX, SY = 1080/1320, 2340/2868
hl = {}
if os.path.exists(f"{OUT}/hl.log"):
    for line in open(f"{OUT}/hl.log"):
        p = line.split()
        if len(p) == 3: hl[p[0]] = (float(p[1])*SX, float(p[2])*SY)
RING_CSS = """*{margin:0;padding:0;box-sizing:border-box}
html,body{width:1080px;height:2340px;background:transparent;position:relative}
.ring{position:absolute;width:356px;height:134px;border-radius:34px;
border:7px solid #4FD1C5;background:rgba(79,209,197,.16);
box-shadow:0 0 0 6px rgba(14,42,71,.55),0 0 46px 10px rgba(79,209,197,.75)}"""
def ring_png(name, keys):
    divs = "".join(f'<div class=ring style="left:{hl[k][0]-178:.0f}px;top:{hl[k][1]-67:.0f}px"></div>'
                   for k in keys if k in hl)
    return render(f"ring-{name}", divs, RING_CSS)
# word -> button, timed from edge-tts word boundaries of b04
WORDS = json.load(open(f"{DIR}/beats/b04.words.json")) if os.path.exists(f"{DIR}/beats/b04.words.json") else []
def wtime(w):
    for x in WORDS:
        if x["w"].lower().strip(".,—") == w: return x["t"]
    return None
SEQ = [("Navigate","Directions"), ("Call","Call"), ("Reserve","Reserve"),
       ("DoorDash","Delivery"), ("Uber","Ride")]
ring_events = []   # (png, rel_start, rel_end) relative to b04 start
b04 = next(((s, d) for b, m, s, d in events if b == "b04"), None)
if b04 and hl:
    ts = [(btn, wtime(w.lower())) for w, btn in SEQ]
    t_all = wtime("all") or (b04[1] - 1.3)
    for i, (btn, t) in enumerate(ts):
        if t is None or btn not in hl: continue
        nxt = next((t2 for _, t2 in ts[i+1:] if t2 is not None), t_all)
        ring_events.append((ring_png(btn, [btn]), t - 0.05, nxt - 0.05))
    ring_events.append((ring_png("all", [b for _, b in SEQ]), t_all - 0.05, b04[1] + 1.2))
    print("rings:", [(os.path.basename(p), round(s,2), round(e,2)) for p, s, e in ring_events])

# ---- brand cards (house style, per Wes 2026-08-29) ----
# A frozen home-screen frame sits dimmed behind a centered navy card: 4-dot
# logo, "Fav"(teal)+"Circles"(white), tagline. The intro card then lifts to
# reveal the live home screen before the walkthrough; the outro reverses it.
HOME = f"{DIR}/home_frame.png"        # clean 1320x2868 home-screen capture (checked in)
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
    '<div class=note><div class=pill>Sign up at favcircles.com</div>'
    '<div class=sub>Never forget a place.</div></div></div>', CARD_CSS)

def card_clip(png, mp3, out, lead, tail, reveal):
    """Home frame under a dim+card overlay. reveal=True: the overlay lifts at
    the end (intro -> live home); reveal=False: it settles in at the start
    and the whole thing fades to black (outro)."""
    d = dur(mp3) + lead + tail
    ms = int(lead * 1000)
    if reveal:
        ov = f"[1:v]format=rgba,fade=t=out:st={d-1.1:.2f}:d=0.6:alpha=1[ov]"
        post = ""
    else:
        ov = "[1:v]format=rgba,fade=t=in:st=0:d=0.6:alpha=1[ov]"
        post = f",fade=t=out:st={d-0.6:.2f}:d=0.6"
    subprocess.run(["ffmpeg","-y","-v","error",
        "-loop","1","-t",f"{d:.2f}","-framerate","30","-i", f"{OUT}/home_1080.png",
        "-loop","1","-t",f"{d:.2f}","-framerate","30","-i", png, "-i", mp3,
        "-filter_complex",f"{ov};[0:v][ov]overlay=0:0{post}[v];"
        f"[2:a]adelay={ms}|{ms},apad,aresample=44100,aformat=sample_fmts=fltp:channel_layouts=stereo[a]",
        "-map","[v]","-map","[a]","-t",f"{d:.2f}",
        "-c:v","libx264","-preset","medium","-crf","19","-pix_fmt","yuv420p",
        "-c:a","aac","-b:a","192k", out], check=True)
    return d

# Intro: frame 0 IS the poster (dimmed home + card, no fade-in) so the
# paused/unplayed video shows the brand card over the app.
intro_d = card_clip(intro_png, f"{DIR}/beats/s00.mp3", f"{OUT}/intro.mp4", 0.6, 1.6, True)
outro_d = card_clip(outro_png, f"{DIR}/beats/s99.mp3", f"{OUT}/outro.mp4", 0.7, 1.8, False)

# ---- main pass: scale + caption/ring overlays + narration mix ----
inputs = ["-i", src]
for _, mp3, _, _ in events: inputs += ["-i", mp3]
n_audio = len(events)
for png in cap_pngs: inputs += ["-i", png]
for png, _, _ in ring_events: inputs += ["-i", png]

fc = []
mix = []
for i, (b, mp3, start, d) in enumerate(events):
    ms = int(start * 1000)
    fc.append(f"[{i+1}:a]adelay={ms}|{ms}[a{i}]")
    mix.append(f"[a{i}]")
fc.append("".join(mix) + f"amix=inputs={len(mix)}:normalize=0,aresample=44100,aformat=sample_fmts=fltp:channel_layouts=stereo[aout]")

fc.append("[0:v]scale=1080:2340[v0]")
cur = "v0"
for i, (b, mp3, start, d) in enumerate(events):
    idx = 1 + n_audio + i
    end = start + d + 0.7
    nxt = f"v{i+1}"
    fc.append(f"[{cur}][{idx}:v]overlay=0:0:enable='between(t,{start:.2f},{end:.2f})'[{nxt}]")
    cur = nxt
for j, (png, rs, re_) in enumerate(ring_events):
    idx = 1 + n_audio + len(cap_pngs) + j
    s, e = b04[0] + rs, b04[0] + re_
    nxt = f"r{j}"
    fc.append(f"[{cur}][{idx}:v]overlay=0:0:enable='between(t,{s:.2f},{e:.2f})'[{nxt}]")
    cur = nxt
fc.append(f"[{cur}]fade=t=in:st=0:d=0.3,fade=t=out:st={total-0.5:.2f}:d=0.5[vout]")

subprocess.run(["ffmpeg","-y","-v","error"] + inputs + [
    "-filter_complex", ";".join(fc),
    "-map","[vout]","-map","[aout]",
    "-c:v","libx264","-preset","medium","-crf","19","-pix_fmt","yuv420p",
    "-c:a","aac","-b:a","192k","-t",f"{total:.2f}",
    f"{OUT}/main.mp4"], check=True)

# concat FILTER (stream-copy concat inflated duration on mismatched timestamps)
subprocess.run(["ffmpeg","-y","-v","error",
    "-i",f"{OUT}/intro.mp4","-i",f"{OUT}/main.mp4","-i",f"{OUT}/outro.mp4",
    "-filter_complex",
    "[0:a]aformat=sample_fmts=fltp:sample_rates=44100:channel_layouts=stereo[a0];"
    "[1:a]aformat=sample_fmts=fltp:sample_rates=44100:channel_layouts=stereo[a1];"
    "[2:a]aformat=sample_fmts=fltp:sample_rates=44100:channel_layouts=stereo[a2];"
    "[0:v][a0][1:v][a1][2:v][a2]concat=n=3:v=1:a=1[v][a]",
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
