// Favvy register buddy, print version (Wes, 2026-11-19: "He can't be fragile").
// Printed as ONE solid piece: the heart sits right on the base, the feet are
// half sunk into it and the short, thick arms grow out of the body, so nothing
// floats and nothing is glued. The sloped front carries a real QR code; the NFC
// tag is sealed under it (print pause). Four colors, one AMS. Units mm. part = body|limbs|eyes|sparkle|cheeks|mouth|tongue|base|qr|text|all
include <qr.scad>
part = "all";
$fn = 72;

lobe_r = 20; lobe_x = 15; lobe_z = 52; tip_z = 21; tip_r = 13; depth = 0.72;
eye_z = 43; eye_x = 9.6;
HX = 0; HY = 12; HZ = 5;          // heart tip sunk 1 mm into the plinth top (z 14)

module heart(g = 0) {
    scale([1, depth, 1]) union() {
        hull() { translate([-lobe_x, 0, lobe_z]) sphere(lobe_r + g); translate([0, 0, tip_z]) sphere(tip_r + g); }
        hull() { translate([ lobe_x, 0, lobe_z]) sphere(lobe_r + g); translate([0, 0, tip_z]) sphere(tip_r + g); }
    }
}
module decal(g0, g1) { intersection() { difference() { heart(g1); heart(g0); } rotate([90, 0, 0]) linear_extrude(height = 80) children(); } }
module oval(x, z, rx, rz) { translate([x, z]) scale([rx, rz]) circle(1); }
module capsule(a, b, r1, r2) { hull() { translate(a) sphere(r1); translate(b) sphere(r2); } }

module eyes()    decal(0, 1.1) { oval(-eye_x, eye_z, 4.6, 6); oval(eye_x, eye_z, 4.6, 6); }
module sparkle() decal(1.0, 1.6) { for (s = [-1, 1]) { oval(s * eye_x + 1.7, eye_z + 2.4, 1.9, 1.9); oval(s * eye_x - 1.6, eye_z - 2.4, 0.8, 0.8); } }
module cheeks()  decal(0, 0.7) { oval(-18, 35.5, 5.2, 3.0); oval(18, 35.5, 5.2, 3.0); }
module mouth()   decal(0, 0.9) intersection() { translate([0, 36.5]) circle(5.2); translate([-7, 29]) square([14, 7.5]); }
module tongue()  decal(0.8, 1.2) oval(0, 32.6, 2.2, 1.4);
// short and thick, rooted deep inside the body, under 40 degrees from vertical so they print without supports
module arms() for (s = [-1, 1]) capsule([s * 22, 0, 40], [s * 37, -2, 59], 7.5, 8);
// half sunk into the plinth (world z 16 centre, 4.9 mm half height)
module feet() for (s = [-1, 1]) translate([s * 12, -8, 11]) scale([1.5, 2.0, 0.75]) sphere(6.5);
module limbs() { arms(); feet(); }

// plinth: flat top behind, sloped front for the QR
// The one-color figure (mono, 2026-11-20) has a deeper front so a 38 mm label + NFC sticker fit the slope
MONO = part == "mono" || part == "mono_all";
BX = 46; BF = MONO ? -52 : -40; BT = 30; BR = 9; FRONT_H = 6; TOP_H = 14; SLOPE_Y = -6;
module rr(y0, y1, h, z) { hull() for (x = [-BX + BR, BX - BR], y = [y0 + BR, y1 - BR]) translate([x, y, z]) cylinder(r = BR, h = h); }
module plinth() { hull() { rr(BF, BT, FRONT_H, 0); rr(SLOPE_Y, BT, 0.01, TOP_H - 0.01); translate([0,0,0]) rr(BF, BT, 0.01, 0); } }
slope_a = atan((TOP_H - FRONT_H) / (SLOPE_Y - BR - BF + BR));
module on_slope() {
    yc = (BF + SLOPE_Y) / 2; zc = (FRONT_H + TOP_H) / 2;
    translate([0, yc, zc]) rotate([slope_a, 0, 0]) children();
}
M = 29 / qr_n; QW = qr_n * M;   // the code is always 29 mm square
module qr_modules() on_slope() translate([-QW / 2, -QW / 2, -0.01])
    for (r = [0 : qr_n - 1], c = [0 : qr_n - 1]) if (qr[r][c] == 1) translate([c * M, (qr_n - 1 - r) * M, 0]) cube([M + 0.001, M + 0.001, 0.6]);
module front_text() translate([0, BF + 0.4, FRONT_H / 2]) rotate([90, 0, 0])
    linear_extrude(0.8) text("TAP OR SCAN", size = 3.6, font = "Liberation Sans:style=Bold", halign = "center", valign = "center", spacing = 1.15);

module at_heart() translate([HX, HY, HZ]) children();

if (part == "body")    at_heart() heart();
if (part == "arms")    at_heart() arms();
if (part == "feet")    at_heart() feet();
if (part == "eyes")    at_heart() eyes();
if (part == "sparkle") at_heart() sparkle();
if (part == "cheeks")  at_heart() cheeks();
if (part == "mouth")   at_heart() mouth();
if (part == "tongue")  at_heart() tongue();
if (part == "base")    plinth();
if (part == "qr")      qr_modules();
if (part == "text")    front_text();
if (part == "all") {
    color("#f4567f") at_heart() heart();
    color("#c8305e") at_heart() arms();
    color("#c8305e") at_heart() feet();
    color("#1d1b22") at_heart() eyes();
    color("#ffffff") at_heart() sparkle();
    color("#c8305e") at_heart() cheeks();
    color("#1d1b22") at_heart() mouth();
    color("#c8305e") at_heart() tongue();
    color("#f6f3ef") plinth();
    color("#1d1b22") qr_modules();
    color("#d8285f") front_text();
}

// ---- Bambu / AMS export: one non-overlapping STL per filament ----
// NFC pocket: flat, 26 mm x 0.64 mm (four Fine layers) for a 25 mm round NTAG
// sticker (Wes, 2026-11-19: use the 25 mm stickers he has), under the QR with
// 1.9-5 mm of plastic over it. Stick it to the pocket floor so it stays flat.
// The top sits on a layer line of Bambu's Fine profile (0.2 first layer + 29 x
// 0.16 = 4.84 mm): pause at 4.84 mm.
// Washer recess from below: 32.4 mm x 3.2 mm (1-1/4 in / 32 mm steel fender washer).
POCKET_TOP = 4.84;
module nfc_pocket() translate([0, -24, POCKET_TOP - 0.64]) cylinder(r = 13, h = 0.64);
module washer_recess() translate([0, 12, -0.01]) cylinder(r = 16.2, h = 3.2);
module heart_solid() at_heart() heart();
module deep_parts() { at_heart() { arms(); feet(); cheeks(); tongue(); } front_text(); }
module black_parts() { at_heart() { difference() { eyes(); sparkle(); } difference() { mouth(); tongue(); } } qr_modules(); }

if (part == "pink")  difference() { heart_solid(); at_heart() { arms(); feet(); } plinth(); }
if (part == "deep")  difference() { deep_parts(); plinth(); }
if (part == "white") union() { difference() { plinth(); heart_solid(); at_heart() feet(); nfc_pocket(); washer_recess(); } at_heart() sparkle(); }
if (part == "black") black_parts();
if (part == "face")  at_heart() { difference() { eyes(); sparkle(); } difference() { mouth(); tongue(); } }  // black minus the QR, for prints where the QR shares the base color

// ---- One-color figure + stickers (Wes, 2026-11-20) ----
// Print it in ONE filament (about 2 h, no pause, no color swaps). The QR is a
// laminated 1.5 in (38 mm) round sticker label (make-figure.sh writes it; a 1.5 in circle punch cuts it) laid over a
// 38 mm NFC sticker, both in a 40 mm x 0.6 mm round recess on the sloped
// front: the tag sits right under the label for strong taps, and a new label
// replaces the QR without reprinting. The face keeps its raised relief (fill
// it with a paint marker if wanted). Weight: two 1 in (25 mm) fender washers
// in side recesses underneath, away from the tag.
LABEL_D = 40; LABEL_DEPTH = 0.6;
module label_recess() on_slope() translate([0, 0, -LABEL_DEPTH]) cylinder(d = LABEL_D, h = LABEL_DEPTH + 2);
module side_washers() for (s = [-1, 1]) translate([s * 29, 12, -0.01]) cylinder(d = 25.8, h = 3.2);
module mono_body() {
    difference() {
        union() {
            plinth();
            at_heart() { heart(); arms(); feet(); eyes(); sparkle(); cheeks(); mouth(); tongue(); }
            front_text();
        }
        label_recess();
        side_washers();
    }
}
if (part == "mono") mono_body();
if (part == "mono_all") { color("#f26b1d") mono_body(); color("#ffffff") on_slope() translate([0, 0, -LABEL_DEPTH + 0.05]) cylinder(d = 38, h = 0.5); }
