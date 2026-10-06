#!/usr/bin/env python3
"""Themed widget clips for Instagram: brand card → 4 widgets → brand card.

Inputs come from capture.sh (raw/<id>.png screenshots, raw/motivation.mov,
raw/home_frame.png). House style per Wes 2026-08-29: the dimmed home screen
behind a navy FavCircles card opens and closes every video. Silent — add
audio in Instagram. Output: out/favcircles-widgets-<theme>-ig.mp4 (1080x1920).
"""
import os, subprocess, html

DIR = os.path.dirname(os.path.abspath(__file__))
RAW, OUT, TMP = f"{DIR}/raw", f"{DIR}/out", f"{DIR}/tmp"
os.makedirs(OUT, exist_ok=True); os.makedirs(TMP, exist_ok=True)
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
FONT = '-apple-system,"SF Pro Display","Helvetica Neue",Arial,sans-serif'
W, H, FPS = 1080, 2340, 30
SEG = 3.4          # seconds per widget
FADE = 0.35

WIDGETS = {
    "motivation": ("Motivation", "A coach who won't let you skip"),
    "workouts": ("Workouts", "Log sets, reps and PRs"),
    "run": ("Map My Run", "Track your runs on a map"),
    "heartbeat": ("Heartbeat", "Your pulse, from the camera"),
    "water": ("Water", "Tap to log each glass"),
    "habits": ("Habits", "Daily check-ins and streaks"),
    "calories": ("Calories", "Quick-add meals and macros"),
    "sleepsounds": ("Sleep Sounds", "Rain, ocean, fire — mix and drift off"),
    "whattoeat": ("What to Eat", "Can't decide? Spin for dinner"),
    "drink": ("Make Me a Drink", "A cocktail to order, and how to make it"),
    "nextbar": ("NextBar", "Your next bar, picked from your circles"),
    "billsplit": ("Bill Split", "Split the check, add the tip"),
    "howareyou": ("How Are You?", "Check on Mom or Dad, a few times a day"),
    "fridgemail": ("Fridge Mail", "Kids' drawings, mailed to Grandma"),
    "postcard": ("Postcard", "Send a real postcard from your trip"),
    "events": ("Events", "Photos and plans only your group sees"),
}
CLIPS = {
    "get-moving": ("Get moving", ["motivation", "workouts", "run", "heartbeat"]),
    "everyday": ("Every day, a little better", ["water", "habits", "calories", "sleepsounds"]),
    "going-out": ("Going out tonight", ["whattoeat", "drink", "nextbar", "billsplit"]),
    "your-people": ("For your people", ["howareyou", "fridgemail", "postcard", "events"]),
}
# Private details in the captures (screenshot px, 1320x2868): x, y, w, h
REDACT = {
    "howareyou": [(48, 1170, 1224, 246)],     # the person being checked on
    "fridgemail": [(48, 999, 1224, 195), (900, 1620, 380, 70), (0, 2800, 1320, 68)],    # grandparent's name + home address
}

def run(args): subprocess.run(args, check=True)

def render(name, body, css):
    page, png = f"{TMP}/{name}.html", f"{TMP}/{name}.png"
    open(page, "w").write(f"<!doctype html><meta charset=utf8><style>{css}</style>{body}")
    subprocess.run([CHROME, "--headless", "--disable-gpu", "--hide-scrollbars", f"--screenshot={png}",
                    f"--window-size={W},{H}", "--default-background-color=00000000", f"file://{page}"],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return png

CARD_CSS = """*{margin:0;padding:0;box-sizing:border-box}
html,body{width:1080px;height:2340px;background:rgba(6,14,26,.62)}
body{font-family:%s;display:flex;align-items:center;justify-content:center;color:#fff;text-align:center}
.card{width:920px;background:rgba(14,42,71,.96);border-radius:48px;padding:90px 56px 96px;
box-shadow:0 34px 100px rgba(0,0,0,.6);border:2px solid rgba(79,209,197,.28)}
.dots{display:grid;grid-template-columns:96px 96px;gap:22px;justify-content:center;margin-bottom:52px}
.dots i{width:96px;height:96px;border-radius:50%%;display:block}
.b{background:#3B8BD6}.t{background:#4FD1C5}
h1{font-size:128px;font-weight:800;letter-spacing:-3px;line-height:1}
h1 span{color:#4FD1C5}
h2{font-size:78px;font-weight:800;margin-top:56px;line-height:1.1}
p.tag{font-size:50px;font-weight:600;margin-top:26px;line-height:1.35;opacity:.92}
.note{margin-top:70px;display:flex;flex-direction:column;align-items:center;gap:24px}
.pill{background:#fff;color:#0E2A47;font-size:52px;font-weight:800;padding:26px 60px;border-radius:999px}
.sub{font-size:46px;font-weight:600;opacity:.92}""" % FONT
LOGO = '<div class=dots><i class=b></i><i class=t></i><i class=t></i><i class=b></i></div><h1><span>Fav</span>Circles</h1>'
CAP_CSS = """*{margin:0;padding:0;box-sizing:border-box}
html,body{width:1080px;height:2340px;background:transparent}
body{font-family:%s;display:flex;align-items:flex-end;justify-content:center}
.cap{margin-bottom:230px;background:rgba(14,42,71,.94);color:#fff;text-align:center;
padding:30px 54px;border-radius:30px;border:2px solid rgba(79,209,197,.6);max-width:960px;
box-shadow:0 10px 40px rgba(0,0,0,.45)}
.cap b{display:block;font-size:64px;font-weight:800;color:#4FD1C5}
.cap span{display:block;font-size:46px;font-weight:600;margin-top:8px}""" % FONT

def card_clip(png, out, d, reveal):
    """Home frame under the dim+card overlay. reveal: the overlay lifts at the
    end (opener); otherwise it settles in and fades to black (closer)."""
    ov = (f"[1:v]format=rgba,fade=t=out:st={d-0.7:.2f}:d=0.6:alpha=1[ov]" if reveal
          else "[1:v]format=rgba,fade=t=in:st=0:d=0.5:alpha=1[ov]")
    post = "" if reveal else f",fade=t=out:st={d-0.5:.2f}:d=0.5"
    run(["ffmpeg", "-y", "-v", "error",
         "-loop", "1", "-t", f"{d}", "-framerate", f"{FPS}", "-i", f"{TMP}/home.png",
         "-loop", "1", "-t", f"{d}", "-framerate", f"{FPS}", "-i", png,
         "-filter_complex", f"{ov};[0:v][ov]overlay=0:0{post},format=yuv420p[v]",
         "-map", "[v]", "-t", f"{d}", "-c:v", "libx264", "-crf", "19", "-preset", "medium", out])

def redacted(wid):
    src = f"{RAW}/{wid}.png"
    if wid not in REDACT: return src
    out = f"{TMP}/{wid}-redacted.png"
    chain, cur = [], "0:v"
    for i, (x, y, w, h) in enumerate(REDACT[wid]):
        r = min(28, h // 4 - 1, w // 4 - 1)
        chain.append(f"[{cur}]split[m{i}][c{i}];[c{i}]crop={w}:{h}:{x}:{y},boxblur={r}:4[b{i}];[m{i}][b{i}]overlay={x}:{y}[r{i}]")
        cur = f"r{i}"
    run(["ffmpeg", "-y", "-v", "error", "-i", src, "-filter_complex", ";".join(chain), "-map", f"[{cur}]", out])
    return out

def segment(wid, out):
    title, line = WIDGETS[wid]
    cap = render(f"cap-{wid}", f"<div class=cap><b>{html.escape(title)}</b><span>{html.escape(line)}</span></div>", CAP_CSS)
    frames = int(SEG * FPS)
    if wid == "motivation" and os.path.exists(f"{RAW}/motivation.mov"):
        # The live coach: he shouts on screen
        base = ["-ss", "1", "-t", f"{SEG}", "-i", f"{RAW}/motivation.mov"]
        vf = f"[0:v]scale={W}:{H},fps={FPS}[s]"
    else:
        # A still page with a slow push-in so it doesn't sit frozen
        base = ["-loop", "1", "-t", f"{SEG}", "-framerate", f"{FPS}", "-i", redacted(wid)]
        vf = (f"[0:v]scale={W*2}:{H*2},zoompan=z='1+0.05*on/{frames}':x='iw/2-(iw/zoom/2)':y='0'"
              f":d={frames}:s={W}x{H}:fps={FPS}[s]")
    run(["ffmpeg", "-y", "-v", "error"] + base + ["-loop", "1", "-t", f"{SEG}", "-i", cap,
         "-filter_complex", f"{vf};[1:v]format=rgba,fade=t=in:st=0.15:d=0.35:alpha=1[c];[s][c]overlay=0:0,format=yuv420p[v]",
         "-map", "[v]", "-t", f"{SEG}", "-r", f"{FPS}", "-c:v", "libx264", "-crf", "19", "-preset", "medium", out])

def xfade_all(parts, out):
    """Crossfade the parts in order."""
    inputs, fc, durs = [], [], []
    for p in parts:
        inputs += ["-i", p]
        durs.append(float(subprocess.check_output(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                                                   "-of", "csv=p=0", p]).decode().strip()))
    cur, offset = "0:v", 0.0
    for i in range(1, len(parts)):
        offset += durs[i - 1] - FADE
        fc.append(f"[{cur}][{i}:v]xfade=transition=fade:duration={FADE}:offset={offset:.2f}[x{i}]")
        cur = f"x{i}"
    run(["ffmpeg", "-y", "-v", "error"] + inputs + ["-filter_complex", ";".join(fc), "-map", f"[{cur}]",
         "-c:v", "libx264", "-crf", "19", "-preset", "medium", "-pix_fmt", "yuv420p", out])

# Blurred: the home screen shows real friends' faces and check-ins, and
# these go on a public account
run(["ffmpeg", "-y", "-v", "error", "-i", f"{RAW}/home_frame.png", "-vf", f"scale={W}:{H},boxblur=22:3", f"{TMP}/home.png"])
outro_png = render("outro", f'<div class=card>{LOGO}<h2>Free widgets, one app.</h2>'
                   '<div class=note><div class=pill>Get it on the App Store</div>'
                   '<div class=sub>favcircles.com</div></div></div>', CARD_CSS)
card_clip(outro_png, f"{TMP}/outro.mp4", 2.6, False)

for slug, (theme, ids) in CLIPS.items():
    names = " · ".join(WIDGETS[i][0] for i in ids)
    intro_png = render(f"intro-{slug}", f'<div class=card>{LOGO}<h2>{html.escape(theme)}</h2>'
                       f'<p class=tag>{html.escape(names)}</p></div>', CARD_CSS)
    card_clip(intro_png, f"{TMP}/intro-{slug}.mp4", 2.4, True)
    segs = []
    for wid in ids:
        segment(wid, f"{TMP}/seg-{wid}.mp4")
        segs.append(f"{TMP}/seg-{wid}.mp4")
    full = f"{TMP}/full-{slug}.mp4"
    xfade_all([f"{TMP}/intro-{slug}.mp4"] + segs + [f"{TMP}/outro.mp4"], full)
    # Instagram 9:16: the phone-shaped video over a blurred copy of itself
    final = f"{OUT}/favcircles-widgets-{slug}-ig.mp4"
    run(["ffmpeg", "-y", "-v", "error", "-i", full, "-filter_complex",
         "[0:v]split[fg][bg];[bg]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,boxblur=40[bgb];"
         "[fg]scale=-2:1920[fgs];[bgb][fgs]overlay=(W-w)/2:0,format=yuv420p",
         "-c:v", "libx264", "-crf", "19", "-preset", "medium", "-movflags", "+faststart", final])
    print("built", final)
