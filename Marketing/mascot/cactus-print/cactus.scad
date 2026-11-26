// Counter cactus (Wes, 2026-11-25: "something completely different. Like a cactus plant. Completely
// unrelated to the theme, but just cool and also have a spot for a small QR code and nfc sticker.")
// A saguaro in a pot on a saucer that reaches forward into a round pad: a 1 in round QR label sits in
// the pad's recess, a 25 mm NFC sticker in the pocket underneath, so one spot says tap or scan.
// One piece, printed upright, no supports: every arm leaves at 45 degrees and every top is a dome.
//   part="cactus"   the whole print
//   part="pot"      saucer, pad and pot only   } the same print split at the soil line, for two colours:
//   part="plant"    the cactus only            } one filament change, at z = SOIL_Z
// Sizes in mm. About 89 mm front to back, 58 mm wide, 105 mm tall.
part = "cactus";
$fn = 96;

// ---- saucer + pad ----
SAUCER_R = 29; BASE_T = 6; BASE_R = 1.6;
PAD_R = 17; PAD_Y = -43;              // pad centre in front of the pot
LABEL_D = 25.9; LABEL_T = 0.4;        // 1 in (25.4 mm) round label
TAG_D = 26; TAG_COVER = 1.2;          // 25 mm NFC sticker, on the pocket's ceiling right under the label
// ---- pot ----
POT_R1 = 19; POT_R2 = 23.5; POT_H = 34; RIM_H = 6; RIM_OUT = 2;
SOIL_Z = BASE_T + POT_H;              // the pot's flat top: where the colour changes
// ---- cactus ----
MAIN_R = 11; MAIN_H = 54; MAIN_RIBS = 10;
//        side  leaves the trunk at  reach  radius  height above the elbow  ribs
ARMS = [[-1,    16,                  17,    6.5,    24,                     8],
        [ 1,    27,                  15.5,  6.0,    13,                     8]];
RIB = 0.13;                           // how deep the valleys are, as a share of the radius

// a slab with a rounded top edge (flat underneath)
module domed(h, r) {
  minkowski() {
    linear_extrude(0.01) offset(delta = -r) children();
    scale([r, r, h]) intersection() { sphere(1, $fn = 32); translate([-1, -1, 0]) cube(2); }
  }
}
module base2d() { hull() { circle(SAUCER_R); translate([0, PAD_Y]) circle(PAD_R); } }
module base() {
  difference() {
    union() {
      linear_extrude(BASE_T - BASE_R) base2d();
      translate([0, 0, BASE_T - BASE_R - 0.01]) domed(BASE_R, BASE_R) base2d();
    }
    translate([0, PAD_Y, BASE_T - LABEL_T]) cylinder(d = LABEL_D, h = 3, $fn = 128);
    translate([0, PAD_Y, -1]) cylinder(d = TAG_D, h = 1 + BASE_T - LABEL_T - TAG_COVER, $fn = 128);
  }
}
module pot() {
  translate([0, 0, BASE_T - 0.01]) {
    cylinder(r1 = POT_R1, r2 = POT_R2, h = POT_H + 0.01);
    rim_r = POT_R2 + RIM_OUT;
    // the rim: a flare a little steeper than 45 degrees, up to a straight band
    flare = RIM_OUT + 1.4;
    translate([0, 0, POT_H - RIM_H - flare]) cylinder(r1 = rim_r - flare + 0.15, r2 = rim_r, h = flare);
    translate([0, 0, POT_H - RIM_H - 0.01]) cylinder(r = rim_r, h = RIM_H + 0.01);
  }
}

// the cactus's cross-section: round ribs with sharp valleys
module ribs2d(r, n) {
  polygon([for (i = [0:n * 16 - 1]) let(a = i * 360 / (n * 16))
    r * (1 - RIB + RIB * abs(cos(n * a / 2))) * [cos(a), sin(a)]]);
}
// a ribbed column from z = 0, h tall to the start of its dome, the dome r tall
module column(r, h, n, slices = 14) {
  linear_extrude(h) ribs2d(r, n);
  for (i = [0:slices - 1]) let(f0 = sqrt(1 - pow(i / slices, 2)), f1 = sqrt(1 - pow((i + 1) / slices, 2)))
    translate([0, 0, h + r * i / slices - 0.005]) linear_extrude(r / slices + 0.01, scale = max(f1, 0.02) / f0) scale(f0) ribs2d(r, n);
}
// an arm: out and up at 45 degrees from inside the trunk, then straight up
module arm(side, z0, reach, r, h, n) {
  elbow = [side * reach, 0, z0 + reach];
  hull() { translate([0, 0, z0]) sphere(r, $fn = 48); translate(elbow) sphere(r, $fn = 48); }
  // under the elbow: a 45 degree cone, so nothing hangs flatter than the arm itself
  hull() { translate(elbow) sphere(r, $fn = 48); translate(elbow - [0, 0, r * sqrt(2) - 0.4]) sphere(0.4, $fn = 16); }
  translate(elbow) rotate(360 / n / 2) column(r, h, n);
}
// a flower on top: six petals opening at 45 degrees
module bloom() {
  linear_extrude(3.2, scale = 2.2) for (i = [0:5]) rotate(i * 60) translate([1.5, 0]) scale([1.4, 0.85]) circle(1.3, $fn = 24);
  translate([0, 0, 3.1]) scale([1, 1, 0.6]) sphere(2.6, $fn = 32);
}
module plant() {
  translate([0, 0, SOIL_Z - 0.01]) {
    rotate(360 / MAIN_RIBS / 2 + 90) column(MAIN_R, MAIN_H, MAIN_RIBS);
    for (a = ARMS) arm(a[0], a[1], a[2], a[3], a[4], a[5]);
    translate([2.5, -1.5, MAIN_H + MAIN_R - 1.6]) bloom();
  }
}

if (part == "pot") { base(); pot(); }
else if (part == "plant") plant();
else if (part == "preview") { color("#c96a3a") { base(); pot(); } color("#3f8f45") plant(); }
else union() { base(); pot(); plant(); }
