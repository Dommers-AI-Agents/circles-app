#!/usr/bin/env python3
"""build.py — assemble the 2026-11 app tutorial (the in-app "Watch the video").

Inputs: out/take.mov + out/marks.txt from record.sh, beats/*.mp3/*.txt from
beats/gen.py (edge-tts Ava, same voice as the other tutorials).
Each walkthrough step becomes one clip: the take from its mark, as long as
its narration needs (capped, so waits for the network never show), with the
narration and a caption. House-style brand cards open and close it (navy card
over a dimmed home frame; see memory demo-video-brand-card-opener).
Output: out/favcircles-tutorial.mp4 (1080x2340, H.264/AAC).
"""
import html, json, os, subprocess

DIR = os.path.dirname(os.path.abspath(__file__))
OUT = f"{DIR}/out"
CAPS = f"{OUT}/caps"
os.makedirs(CAPS, exist_ok=True)
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
FONT = '-apple-system,"SF Pro Display","Helvetica Neue",Arial,sans-serif'

# step -> the most video it may use (seconds)
STEPS = [("home", 5.5), ("person", 6.5), ("activity", 4.6), ("place", 9.5), ("add", 8.5), ("add-form", 14.0),
         ("moments", 5.6), ("locals", 5.6), ("widgets", 5.8), ("checkin", 6.5),
         ("rewards", 5.6), ("profile", 4.6), ("circle", 6.2)]


def run(args):
    subprocess.run(args, check=True)


def dur(path):
    return float(subprocess.check_output(
        ["ffprobe", "-v", "quiet", "-show_entries", "format=duration", "-of", "csv=p=0", path]).strip())


def render(name, body, css):
    page, png = f"{CAPS}/{name}.html", f"{CAPS}/{name}.png"
    open(page, "w").write(f"<!doctype html><meta charset=utf8><style>{css}</style>{body}")
    subprocess.run([CHROME, "--headless", "--disable-gpu", "--hide-scrollbars", f"--screenshot={png}",
                    "--window-size=1080,2340", "--default-background-color=00000000", f"file://{page}"],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return png


CAP_CSS = """*{margin:0;padding:0;box-sizing:border-box}
html,body{width:1080px;height:2340px;background:transparent}
body{font-family:%s;display:flex;align-items:flex-end;justify-content:center}
.cap{margin-bottom:270px;background:rgba(14,42,71,.93);color:#fff;font-size:50px;
font-weight:700;padding:30px 50px;border-radius:28px;border:2px solid rgba(79,209,197,.55);
max-width:960px;text-align:center;line-height:1.3;box-shadow:0 10px 40px rgba(0,0,0,.4)}""" % FONT

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

AUDIO = "aresample=44100,aformat=sample_fmts=fltp:channel_layouts=stereo"
VENC = ["-c:v", "libx264", "-preset", "medium", "-crf", "19", "-pix_fmt", "yuv420p", "-r", "30"]
AENC = ["-c:a", "aac", "-b:a", "192k"]

marks = {}
for line in open(f"{OUT}/marks.txt"):
    t, name = line.split()
    marks.setdefault(name, float(t))

# CFR 30 at 1080x2340 (recordVideo is variable-rate)
run(["ffmpeg", "-y", "-v", "error", "-i", f"{OUT}/take.mov", "-vf", "fps=30,scale=1080:2340",
     *VENC, f"{OUT}/take_norm.mp4"])
take_len = dur(f"{OUT}/take_norm.mp4")

# Home frame for the cards: Home a beat after it's on screen
run(["ffmpeg", "-y", "-v", "error", "-ss", f"{marks['home'] + 1.5:.2f}", "-i", f"{OUT}/take_norm.mp4",
     "-frames:v", "1", f"{OUT}/home_1080.png"])


def card_clip(png, mp3, out, lead, tail, reveal):
    d = dur(mp3) + lead + tail
    ms = int(lead * 1000)
    ov = (f"[1:v]format=rgba,fade=t=out:st={d - 1.1:.2f}:d=0.6:alpha=1[ov]" if reveal
          else "[1:v]format=rgba,fade=t=in:st=0:d=0.6:alpha=1[ov]")
    post = "" if reveal else f",fade=t=out:st={d - 0.6:.2f}:d=0.6"
    run(["ffmpeg", "-y", "-v", "error",
         "-loop", "1", "-t", f"{d:.2f}", "-framerate", "30", "-i", f"{OUT}/home_1080.png",
         "-loop", "1", "-t", f"{d:.2f}", "-framerate", "30", "-i", png, "-i", mp3,
         "-filter_complex", f"{ov};[0:v][ov]overlay=0:0{post}[v];[2:a]adelay={ms}|{ms},apad,{AUDIO}[a]",
         "-map", "[v]", "-map", "[a]", "-t", f"{d:.2f}", *VENC, *AENC, out])


intro = render("intro", f'<div class=card>{LOGO}<p class=tag>Never forget your favorite places.</p></div>', CARD_CSS)
outro = render("outro", f'<div class=card>{LOGO}<p class=tag>Never forget your favorite places.</p>'
               '<div class=note><div class=pill>Sign up at favcircles.com</div>'
               '<div class=sub>Never forget a place.</div></div></div>', CARD_CSS)
card_clip(intro, f"{DIR}/beats/s00.mp3", f"{OUT}/c_intro.mp4", 0.6, 1.4, True)
card_clip(outro, f"{DIR}/beats/s99.mp3", f"{OUT}/c_outro.mp4", 0.7, 1.8, False)

clips = [f"{OUT}/c_intro.mp4"]
order = [n for n, _ in STEPS]
for i, (name, cap) in enumerate(STEPS):
    start = marks[name]
    nxt = marks[order[i + 1]] if i + 1 < len(order) else marks.get("end", take_len)
    mp3 = f"{DIR}/beats/{name}.mp3"
    speech = dur(mp3)
    want = max(speech + 1.4, 3.0)
    # The step's own video (up to its cap), never shorter than its narration
    length = max(want, min(nxt - start, cap))
    available = max(0.5, min(nxt - start, take_len - start))
    pad = max(0.0, length - available)
    text = html.escape(open(f"{DIR}/beats/{name}.txt").read().strip())
    cap_png = render(name, f"<div class=cap>{text}</div>", CAP_CSS)
    out = f"{OUT}/c_{i:02d}_{name}.mp4"
    vf = f"trim={start:.2f}:{start + min(length, available):.2f},setpts=PTS-STARTPTS"
    if pad > 0:
        vf += f",tpad=stop_mode=clone:stop_duration={pad:.2f}"
    run(["ffmpeg", "-y", "-v", "error", "-i", f"{OUT}/take_norm.mp4", "-i", mp3,
         "-loop", "1", "-t", f"{length:.2f}", "-framerate", "30", "-i", cap_png,
         "-filter_complex",
         f"[0:v]{vf}[v0];[2:v]format=rgba,fade=t=in:st=0.2:d=0.25:alpha=1,"
         f"fade=t=out:st={min(length, speech + 0.9) - 0.3:.2f}:d=0.3:alpha=1[cap];"
         f"[v0][cap]overlay=0:0:enable='between(t,0.2,{min(length, speech + 0.9):.2f})'[v];"
         f"[1:a]adelay=300|300,apad,{AUDIO}[a]",
         "-map", "[v]", "-map", "[a]", "-t", f"{length:.2f}", *VENC, *AENC, out])
    clips.append(out)
    print(f"{name:9s} {length:5.1f}s  (speech {speech:.1f}s, room {available:.1f}s{', +pad' if pad else ''})")
clips.append(f"{OUT}/c_outro.mp4")

inputs, labels = [], []
for i, c in enumerate(clips):
    inputs += ["-i", c]
    labels.append(f"[{i}:v][{i}:a]")
run(["ffmpeg", "-y", "-v", "error", *inputs, "-filter_complex",
     "".join(labels) + f"concat=n={len(clips)}:v=1:a=1[v][a]",
     "-map", "[v]", "-map", "[a]", *VENC, *AENC, "-movflags", "+faststart", f"{OUT}/favcircles-tutorial.mp4"])
print(f"built out/favcircles-tutorial.mp4  {dur(f'{OUT}/favcircles-tutorial.mp4'):.1f}s")
