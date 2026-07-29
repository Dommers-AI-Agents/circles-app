import qrcode, random
from reportlab.pdfgen import canvas
from reportlab.lib.colors import HexColor
from reportlab.lib.units import inch
from reportlab.lib.utils import ImageReader

APPURL = "https://apps.apple.com/us/app/favcircles/id6746807095"
ICON   = "iOS_App_Icon_1024x1024_Transparent.png"

TRIM_W, TRIM_H = 3.5*inch, 2.0*inch
BLEED = 0.125*inch
W, H  = TRIM_W + 2*BLEED, TRIM_H + 2*BLEED     # 3.75 x 2.25 in
SAFE  = BLEED + 0.125*inch

BLUE   = HexColor("#1F6DC4")     # sampled from the app icon
DARK   = HexColor("#12233D")
GREY   = HexColor("#57687F")
BASE   = HexColor("#F2F6FC")
BLOCK  = HexColor("#E1EAF6")
STREET = HexColor("#FFFFFF")
PARK   = HexColor("#D9EBDD")
WATER  = HexColor("#CFE2F7")
PINS   = [HexColor("#E8503A"), HexColor("#F2A33C"), HexColor("#4CAF6D"), HexColor("#1F6DC4")]

def map_bg(c, seed=7):
    rnd = random.Random(seed)
    c.setFillColor(BASE); c.rect(0,0,W,H, stroke=0, fill=1)
    c.setFillColor(WATER)
    p = c.beginPath(); p.moveTo(W, H*0.72); p.curveTo(W*0.80,H*0.80, W*0.78,H*1.02, W*0.62,H)
    p.lineTo(W,H); p.close(); c.drawPath(p, stroke=0, fill=1)
    c.setFillColor(PARK); c.roundRect(W*0.06, H*0.10, W*0.20, H*0.22, 4, stroke=0, fill=1)
    c.setFillColor(BLOCK)
    for _ in range(16):
        c.rect(rnd.uniform(-0.05,0.95)*W, rnd.uniform(-0.05,0.95)*H,
               rnd.uniform(0.10,0.22)*W, rnd.uniform(0.12,0.26)*H, stroke=0, fill=1)
    c.setStrokeColor(STREET); c.setLineCap(1)
    for i in range(7):
        c.setLineWidth(rnd.choice([1.6,2.4,3.2])); c.line(-2, H*(i/6.0)+rnd.uniform(-4,4), W+2, H*(i/6.0)+rnd.uniform(-4,4))
    for i in range(9):
        x = W*(i/8.0)+rnd.uniform(-4,4)
        c.setLineWidth(rnd.choice([1.4,2.2,3.0])); c.line(x, -2, x, H+2)
    c.setLineWidth(4.2); c.line(-4, H*0.16, W+4, H*0.86)
    c.setStrokeColor(HexColor("#FBD98A")); c.setLineWidth(1.6); c.line(-4, H*0.16, W+4, H*0.86)

def pin(c, x, y, color, r=5.2):
    c.setFillColor(color); c.setStrokeColor(HexColor("#FFFFFF")); c.setLineWidth(1.1)
    c.circle(x, y, r, stroke=1, fill=1)
    p = c.beginPath(); p.moveTo(x-r*0.62, y-r*0.62); p.lineTo(x, y-r*1.95); p.lineTo(x+r*0.62, y-r*0.62); p.close()
    c.drawPath(p, stroke=0, fill=1)
    c.setFillColor(HexColor("#FFFFFF")); c.circle(x, y, r*0.36, stroke=0, fill=1)

def qr_vector(c, data, x, y, size):
    q = qrcode.QRCode(error_correction=qrcode.constants.ERROR_CORRECT_Q, box_size=10, border=0)
    q.add_data(data); q.make(fit=True)
    m = q.get_matrix(); n = len(m); s = size/float(n)
    c.setFillColor(HexColor("#FFFFFF")); c.roundRect(x-6, y-6, size+12, size+12, 5, stroke=0, fill=1)
    c.setFillColor(DARK)
    for r,row in enumerate(m):
        for col,v in enumerate(row):
            if v: c.rect(x+col*s, y+size-(r+1)*s, s*1.02, s*1.02, stroke=0, fill=1)

icon = ImageReader(ICON)
c = canvas.Canvas("favcircles_business_card.pdf", pagesize=(W,H))

# ---------------- FRONT ----------------
map_bg(c, seed=11)
c.setFillColor(HexColor("#FFFFFF")); c.setFillAlpha(0.94)
c.roundRect(SAFE-6, H*0.17, W-2*(SAFE-6), H*0.66, 7, stroke=0, fill=1)
c.setFillAlpha(1)
pin(c, W*0.115, H*0.895, PINS[0]); pin(c, W*0.885, H*0.895, PINS[2])
pin(c, W*0.16,  H*0.095, PINS[1]); pin(c, W*0.845, H*0.095, PINS[3])

# logo left, text right
ISZ = 64
ix, iy = 30, (H-ISZ)/2.0
c.drawImage(icon, ix, iy, ISZ, ISZ, mask='auto')

tx = ix + ISZ + 15
c.setFillColor(DARK); c.setFont("Helvetica-Bold", 17)
c.drawString(tx, H*0.545, "FavCircles")
c.setFillColor(GREY); c.setFont("Helvetica", 6.6)
c.drawString(tx, H*0.435, "A better way to save and organize")
c.drawString(tx, H*0.360, "the places you love.")
c.showPage()

# ---------------- BACK ----------------  (logo + QR only, no words)
map_bg(c, seed=23)
c.setFillColor(HexColor("#FFFFFF")); c.setFillAlpha(0.95)
c.roundRect(SAFE-6, SAFE-6, W-2*(SAFE-6), H-2*(SAFE-6), 7, stroke=0, fill=1)
c.setFillAlpha(1)

SZ  = 76                      # logo and QR identical size
GAP = 26
x0  = (W - (SZ + GAP + SZ))/2.0
yb  = 48.5                    # shared top/bottom alignment

c.drawImage(icon, x0, yb, SZ, SZ, mask='auto')
c.setFillColor(DARK); c.setFont("Helvetica-Bold", 11)
c.drawCentredString(x0 + SZ/2.0, yb - 12.5, "FavCircles")

qr_vector(c, APPURL, x0 + SZ + GAP, yb, SZ)

c.showPage(); c.save()
print("ok")
