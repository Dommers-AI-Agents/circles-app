#!/usr/bin/env python3
"""Generate FavCircles table tents matching the winner window-sticker design.

Layout (flat, top to bottom): base flap / panel A (rotated 180) / apex fold /
panel B / base flap.  Panels are 4x6 in; flaps 0.75 in; 0.125 in bleed;
crop + fold marks in a 0.125 in slug area.  Units: 1/100 inch.
"""
import base64, os, re, subprocess

SCRATCH = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.expanduser('~/Desktop/FavCircles-Print-Assets/Table-Tents')
os.makedirs(OUT, exist_ok=True)

ICON_B64 = base64.b64encode(open(os.path.join(SCRATCH, 'app-icon.png'), 'rb').read()).decode()
QR_PATH = open(os.path.join(SCRATCH, 'qr-path.txt')).read().strip()

# ---- pin shape, normalized from the sticker's red pin (tip at origin, r=1) ----
RED_PIN_D = ("M112 444 C105.7504 433.3376 101.92 430.3136 101.92 426.08 "
             "C101.92 420.512816 106.432816 416 112 416 C117.567184 416 122.08 420.512816 122.08 426.08 "
             "C122.08 430.3136 118.2496 433.3376 112 444 Z "
             "M112 421.84639999999996 C114.3184 421.84639999999996 116.2336 423.7616 116.2336 426.08 "
             "C116.2336 428.3984 114.3184 430.3136 112 430.3136 "
             "C109.6816 430.3136 107.7664 428.3984 107.7664 426.08 "
             "C107.7664 423.7616 109.6816 421.84639999999996 112 421.84639999999996 Z")

def transform_path(d, fx, fy):
    """Apply (x,y)->(fx(x),fy(y)) to an absolute M/C path string."""
    out, nums = [], []
    tokens = re.findall(r'[MCZz]|-?[\d.]+', d)
    coords = []
    cmd = None
    for t in tokens:
        if t in 'MCZz':
            cmd = t
            out.append(t)
        else:
            coords.append(float(t))
            if len(coords) == 2:
                out.append(f"{fx(coords[0]):.3f} {fy(coords[1]):.3f}")
                coords = []
    return ' '.join(out)

# normalize: tip (112,444), r=10.08
PIN_UNIT = transform_path(RED_PIN_D, lambda x: (x - 112) / 10.08, lambda y: (y - 444) / 10.08)

def pin(x, y, r, color):
    d = transform_path(PIN_UNIT, lambda px: x + px * r, lambda py: y + py * r)
    return f'<path fill="{color}" fill-rule="evenodd" d="{d}"/>'

def touch_ring(x, y, r):
    return (f'<ellipse cx="{x}" cy="{y + 2}" rx="{r * 1.5:.1f}" ry="{r * 0.45:.1f}" '
            f'fill="none" stroke="#FFFFFF" stroke-width="1.2" opacity="0.4"/>')

# ---- colorways ----
VARIANTS = {
    'gunmetal': dict(grad=('#3A3F47', '#15171C'), flap='#15171C', qr='#1B1E24',
                     pin_start='#C8442F', pin_end='#6A8F3C', pin_mid='#D9A62E',
                     dots=('#D9A62E', '#B5652A')),
    'purple': dict(grad=('#667eea', '#764ba2'), flap='#59397e', qr='#23265F',
                   pin_start='#E8477E', pin_end='#61B946', pin_mid='#F2C94C',
                   dots=('#F2C94C', '#F09A38')),
}

PW, PH = 400, 600       # panel trim
FLAP = 75
BLEED = 12.5
MARK = 12.5             # slug for crop/fold marks
SERIF = "Georgia, 'DejaVu Serif', serif"
SANS = "'Helvetica Neue', Helvetica, Arial, sans-serif"

ROAD_D = "M70 545 C150 500 60 420 150 360 C240 300 160 220 260 165 C310 138 330 120 345 95"

def panel(v, grad_id):
    """One panel in local coords (0,0)-(400,600), flap at y 600..675, bleed overdraw."""
    e = []
    # background: covers side bleed + a bit past the joins (overdrawn by neighbors harmlessly)
    e.append(f'<rect x="{-BLEED}" y="{-BLEED}" width="{PW + 2 * BLEED}" height="{PH + BLEED}" fill="url(#{grad_id})"/>')
    # base flap in solid dark + bleed below
    e.append(f'<rect x="{-BLEED}" y="{PH - 1}" width="{PW + 2 * BLEED}" height="{FLAP + BLEED + 1}" fill="{v["flap"]}"/>')
    e.append(f'<text x="{PW / 2}" y="{PH + FLAP / 2 + 4}" font-family="{SANS}" font-size="11" fill="#FFFFFF" '
             f'opacity="0.35" text-anchor="middle" letter-spacing="2">BASE FLAP — FOLD UNDER</text>')
    # inner hairline border (analog of the sticker's inner circle)
    e.append(f'<rect x="26" y="26" width="{PW - 52}" height="{PH - 52}" rx="20" fill="none" '
             f'stroke="#FFFFFF" stroke-width="1.4" opacity="0.6"/>')
    # ghost road + dashed centerline
    e.append(f'<path d="{ROAD_D}" fill="none" stroke="#FFFFFF" stroke-width="26" opacity="0.1" stroke-linecap="round"/>')
    e.append(f'<path d="{ROAD_D}" fill="none" stroke="#FFFFFF" stroke-width="2" opacity="0.4" '
             f'stroke-dasharray="8 7" stroke-linecap="round"/>')
    # road-end pins with touch-down rings
    e.append(touch_ring(70, 545, 9))
    e.append(pin(70, 545, 9, v['pin_start']))
    e.append(touch_ring(345, 97, 9))
    e.append(pin(345, 95, 9, v['pin_end']))
    # accent dots
    e.append(f'<circle cx="96" cy="128" r="4" fill="{v["dots"][0]}"/>')
    e.append(f'<circle cx="332" cy="428" r="4" fill="{v["dots"][1]}"/>')
    # app icon
    e.append(f'<clipPath id="ic-{grad_id}"><rect x="168" y="46" width="64" height="64" rx="14.4"/></clipPath>')
    e.append(f'<image x="168" y="46" width="64" height="64" clip-path="url(#ic-{grad_id})" '
             f'href="data:image/png;base64,{ICON_B64}"/>')
    # headline
    e.append(f'<text x="200" y="172" font-family="{SERIF}" font-weight="bold" font-size="37" '
             f'fill="#FFFFFF" text-anchor="middle">Every great place</text>')
    e.append(f'<text x="200" y="218" font-family="{SERIF}" font-weight="bold" font-size="37" '
             f'fill="#FFFFFF" text-anchor="middle">has a story.</text>')
    # divider with yellow pin
    e.append('<line x1="62" y1="252" x2="172" y2="252" stroke="#FFFFFF" stroke-width="1.6"/>')
    e.append('<line x1="228" y1="252" x2="338" y2="252" stroke="#FFFFFF" stroke-width="1.6"/>')
    e.append(pin(200, 263, 7.8, v['pin_mid']))
    # subline
    e.append(f'<text x="200" y="308" font-family="{SANS}" font-weight="400" font-size="24" '
             f'fill="#FFFFFF" text-anchor="middle">Remember yours.</text>')
    # QR block reused verbatim from the sticker (rect was 130 @ (210,332))
    k = 150 / 130
    tx, ty = 125 - 210 * k, 348 - 332 * k
    e.append(f'<g transform="translate({tx:.4f} {ty:.4f}) scale({k:.6f})">'
             f'<rect x="210" y="332" width="130" height="130" rx="11" fill="#FFFFFF"/>'
             f'<path d="{QR_PATH}" fill="{v["qr"]}"/></g>')
    # wordmark
    e.append(pin(133, 566, 7, '#FFFFFF'))
    e.append(f'<text x="148" y="566" font-family="{SANS}" font-weight="600" font-size="25" '
             f'fill="#FFFFFF" text-anchor="start">FavCircles</text>')
    return '\n'.join(e)

def flat_svg(name, v, marks=True):
    W = PW + 2 * (BLEED + MARK)                  # 450
    H = 2 * PH + 2 * FLAP + 2 * (BLEED + MARK)   # 1400
    ox, oy = BLEED + MARK, BLEED + MARK          # trim origin (25,25)
    folds = [oy + FLAP, oy + FLAP + PH, oy + FLAP + 2 * PH]
    s = [f'<?xml version="1.0" encoding="UTF-8"?>',
         f'<svg xmlns="http://www.w3.org/2000/svg" width="{W / 100}in" height="{H / 100}in" viewBox="0 0 {W} {H}">',
         f'<!-- FavCircles table tent ({name}). Panels 4x6in, base flaps 0.75in, bleed 0.125in. -->',
         f'<defs><linearGradient id="gA-{name}" x1="0%" y1="0%" x2="100%" y2="100%">'
         f'<stop offset="0%" stop-color="{v["grad"][0]}"/><stop offset="100%" stop-color="{v["grad"][1]}"/></linearGradient>'
         f'<linearGradient id="gB-{name}" x1="0%" y1="0%" x2="100%" y2="100%">'
         f'<stop offset="0%" stop-color="{v["grad"][0]}"/><stop offset="100%" stop-color="{v["grad"][1]}"/></linearGradient></defs>',
         '<rect width="100%" height="100%" fill="#FFFFFF"/>']
    # panel A: rotated 180 so it reads upright once folded over the apex
    # rotation about the panel center maps local y 0..600 -> flat 700..100 and
    # the flap (local 600..675) -> flat 100..25, i.e. above the panel
    s.append(f'<g transform="translate({ox} {oy + FLAP}) rotate(180 {PW / 2} {PH / 2})">')
    s.append(panel(v, f'gA-{name}'))
    s.append('</g>')
    # panel B upright, its flap at the bottom
    s.append(f'<g transform="translate({ox} {oy + FLAP + PH})">')
    s.append(panel(v, f'gB-{name}'))
    s.append('</g>')
    if marks:
        m = []
        tl, tr = ox, ox + PW
        tt, tb = oy, oy + 2 * PH + 2 * FLAP
        L = 10
        for x, y, dx, dy in [(tl, tt, -1, -1), (tr, tt, 1, -1), (tl, tb, -1, 1), (tr, tb, 1, 1)]:
            m.append(f'<line x1="{x + dx * 3}" y1="{y}" x2="{x + dx * (3 + L)}" y2="{y}" stroke="#000" stroke-width="0.75"/>')
            m.append(f'<line x1="{x}" y1="{y + dy * 3}" x2="{x}" y2="{y + dy * (3 + L)}" stroke="#000" stroke-width="0.75"/>')
        for fy in folds:
            for x0, x1 in [(2, MARK + BLEED - 3), (W - MARK - BLEED + 3, W - 2)]:
                m.append(f'<line x1="{x0}" y1="{fy}" x2="{x1}" y2="{fy}" stroke="#000" stroke-width="0.75" stroke-dasharray="3 2"/>')
        m.append(f'<text x="{W - 4}" y="{folds[1] - 5}" font-family="{SANS}" font-size="8" fill="#888" '
                 f'text-anchor="end" transform="rotate(-90 {W - 4} {folds[1] - 5})"></text>')
        s.extend(m)
    s.append('</svg>')
    return '\n'.join(s)

def homeprint_svg(name, v):
    """Letter 8.5x11: tent scaled to 75%, cut/fold guides, assembly steps."""
    k = 0.75
    W, H = 850, 1100
    strip_w, strip_h = PW * k, (2 * PH + 2 * FLAP) * k
    sx, sy = 80, (H - strip_h) / 2
    folds = [FLAP * k, (FLAP + PH) * k, (FLAP + 2 * PH) * k]
    s = [f'<?xml version="1.0" encoding="UTF-8"?>',
         f'<svg xmlns="http://www.w3.org/2000/svg" width="8.5in" height="11in" viewBox="0 0 {W} {H}">',
         f'<defs><linearGradient id="gA-{name}" x1="0%" y1="0%" x2="100%" y2="100%">'
         f'<stop offset="0%" stop-color="{v["grad"][0]}"/><stop offset="100%" stop-color="{v["grad"][1]}"/></linearGradient>'
         f'<linearGradient id="gB-{name}" x1="0%" y1="0%" x2="100%" y2="100%">'
         f'<stop offset="0%" stop-color="{v["grad"][0]}"/><stop offset="100%" stop-color="{v["grad"][1]}"/></linearGradient>'
         f'<clipPath id="strip-{name}"><rect x="{sx}" y="{sy}" width="{strip_w}" height="{strip_h}"/></clipPath></defs>',
         '<rect width="100%" height="100%" fill="#FFFFFF"/>',
         f'<g clip-path="url(#strip-{name})">',
         f'<g transform="translate({sx} {sy}) scale({k})">',
         f'<g transform="translate(0 {FLAP}) rotate(180 {PW / 2} {PH / 2})">{panel(v, "gA-" + name)}</g>',
         f'<g transform="translate(0 {FLAP + PH})">{panel(v, "gB-" + name)}</g>',
         '</g></g>',
         f'<rect x="{sx}" y="{sy}" width="{strip_w}" height="{strip_h}" fill="none" stroke="#999" stroke-width="1"/>']
    for fy in folds:
        s.append(f'<line x1="{sx}" y1="{sy + fy}" x2="{sx + strip_w}" y2="{sy + fy}" '
                 f'stroke="#FFFFFF" stroke-width="1" stroke-dasharray="6 5" opacity="0.55"/>')
    tx = sx + strip_w + 60
    steps = [
        ('FavCircles Table Tent', 30, 700, '#222'),
        (f'{name.capitalize()} · prints at 3″ × 4.5″ panels', 15, 400, '#666'),
        ('', 13, 400, '#444'),
        ('1.  Cut along the solid grey outline.', 15, 400, '#333'),
        ('2.  Score + fold along each dashed line', 15, 400, '#333'),
        ('     (flap / apex / flap).', 15, 400, '#333'),
        ('3.  Fold into a triangle so both faces', 15, 400, '#333'),
        ('     stand upright.', 15, 400, '#333'),
        ('4.  Overlap the two base flaps and', 15, 400, '#333'),
        ('     tape or glue them underneath.', 15, 400, '#333'),
        ('', 13, 400, '#444'),
        ('Card stock (65–110 lb) recommended.', 13, 400, '#666'),
    ]
    ty = sy + 40
    for txt, fs, fw, col in steps:
        if txt:
            s.append(f'<text x="{tx}" y="{ty}" font-family="{SANS}" font-size="{fs}" '
                     f'font-weight="{fw}" fill="{col}">{txt}</text>')
        ty += fs * 1.9
    s.append('</svg>')
    return '\n'.join(s)

for name, v in VARIANTS.items():
    base = os.path.join(OUT, f'FavCircles-table-tent-{name}')
    svg = flat_svg(name, v)
    open(base + '.svg', 'w').write(svg)
    hp = homeprint_svg(name, v)
    open(base + '-letter-homeprint.svg', 'w').write(hp)
    subprocess.run(['rsvg-convert', '-f', 'pdf', '-o', base + '.pdf', base + '.svg'], check=True)
    subprocess.run(['rsvg-convert', '-w', '1350', '-o', base + '-300dpi.png', base + '.svg'], check=True)
    subprocess.run(['rsvg-convert', '-w', '400', '-o', base + '-preview.png', base + '.svg'], check=True)
    subprocess.run(['rsvg-convert', '-f', 'pdf', '-o', base + '-letter-homeprint.pdf', base + '-letter-homeprint.svg'], check=True)
    os.remove(base + '-letter-homeprint.svg')
    subprocess.run(['magick', base + '-300dpi.png', '-colorspace', 'CMYK', '-density', '300',
                    '-units', 'PixelsPerInch', base + '-CMYK.tiff'], check=True)
    print('built', name)
print('done ->', OUT)
