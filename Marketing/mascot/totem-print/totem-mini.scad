// FavCircles Mini Totem (Wes, 2026-11-25: "a mini totem 3d print that is all one piece ...
// I still want engraving. You could do less though.")
// About half the Totem's size, printed upright in ONE piece: no glue, no dowels, no supports.
// The ring grows out of the base; the heart is fused to the ring at its tip and at both lobes.
// Still takes the 1½ in "TAP OR SCAN" label on top and a 38 mm NFC sticker in the pocket underneath.
// Engraving, less of it and none smaller than the full Totem's pen-filled lettering:
//   the map pin on both faces of the heart, FAVCIRCLES across the base front,
//   the FavCircles mark under the base (left unpainted).
// Shapes come from totem.scad (heart outline, pin, lettering font); this file only sets sizes.
//   part="mini"      the print (upright, as it stands on the counter)
//   part="painted"   preview: the engraving filled with gold paint
include <totem.scad>
part = "none";           // totem.scad draws nothing; this file does
mini = "mini";

// ---- sizes (these replace totem.scad's) ----
RING_OUT = 30; RING_IN = 22; RING_D = 10; RING_R = 1.5; RING_CH = 0.8;
HEART_S = 17; HEART_EDGE = 5.6;   // 45 mm wide: 0.6 mm into the ring at each lobe
HEART_DY = -3;                    // the tip ends 3.6 mm inside the ring's bottom
HALF_T = 5.5; DOME_R = 3.5;       // 11 mm thick, a hair proud of the ring
BASE_W = 76; BASE_D = 62; BASE_H = 12; BASE_CORNER = 10; BASE_R = 2;
SINK = 4;                         // the ring stands this deep in the base
RING_BACK = 21;                   // ring centre behind the base centre
LABEL_Y = -8.7;                   // label 3 mm from the front edge, 3.7 mm clear of the heart
ENGRAVE_DEPTH = 0.7;
BASE_TEXT = "FAVCIRCLES"; BASE_TEXT_SIZE = 5.6; BASE_TEXT_Z = 5.4;
DESIGN_SCALE = (HEART_S + HEART_EDGE) / 34;   // the pin, sized to this heart (1.6 mm strokes)
MARK_D = 13;

// a new name: re-assigning totem.scad's RING_CY would be evaluated up there, before SINK exists
MINI_CY = BASE_H - SINK + RING_OUT;

module mini_heart_cut() {     // the pin, cut into one curved face (heart-local, face up)
  intersection() {
    translate([0, 0, -1]) linear_extrude(HALF_T + 2) scale(DESIGN_SCALE) heart_design();
    difference() { heart_body(); translate([0, 0, -ENGRAVE_DEPTH]) heart_body(); }
  }
}
module mini_heart(cut = true) {
  for (m = [0, 1]) mirror([0, 0, m]) difference() { heart_body(); if (cut) mini_heart_cut(); }
}
// upright: ring-local z → -y (the customer), ring-local y → up
module upright() { translate([0, RING_BACK, MINI_CY]) rotate([90, 0, 0]) children(); }

module mini_base() {
  difference() {
    union() {
      linear_extrude(BASE_H - BASE_R) base2d();
      translate([0, 0, BASE_H - BASE_R - 0.01]) domed(BASE_R, BASE_R) base2d();
    }
    translate([0, LABEL_Y, BASE_H - LABEL_T]) cylinder(d = LABEL_D, h = 5, $fn = 128);
    translate([0, LABEL_Y, -1]) cylinder(d = TAG_D, h = 1 + BASE_H - LABEL_T - TAG_COVER, $fn = 128);
    translate([0, -BASE_D / 2 + ENGRAVE_DEPTH, BASE_TEXT_Z]) rotate([90, 0, 0]) linear_extrude(3)
      text(BASE_TEXT, size = BASE_TEXT_SIZE, font = FONT, halign = "center", valign = "center", spacing = 1.12);
    // the mark, under the base behind the NFC pocket (reads right when tipped over toward you)
    translate([0, 21.5, -1]) linear_extrude(1 + 0.6) mirror([0, 1, 0]) logo2d(MARK_D);
  }
}
// where the ring leaves the base it would hang at 30 degrees: a foot carries it up at 45
module ring_foot() {
  k = RING_OUT * sqrt(0.5); top = MINI_CY - k; out = k + (top - BASE_H);
  difference() {
    translate([0, RING_BACK + RING_D / 2 - RING_CH, 0]) rotate([90, 0, 0]) linear_extrude(RING_D - 2 * RING_CH)
      polygon([[-out, BASE_H - 1], [out, BASE_H - 1], [out, BASE_H], [k, top], [-k, top]]);
    upright() cylinder(r = RING_IN + 0.01, h = RING_D + 2, center = true, $fn = 200);
  }
}
module mini_totem() {
  union() {
    mini_base();
    upright() translate([0, 0, -RING_D / 2]) rotate_extrude($fn = 200) ring_profile();
    ring_foot();
    upright() translate([0, HEART_DY, 0]) mini_heart();
  }
}
module mini_paint() {         // what the paint pen fills
  upright() translate([0, HEART_DY, 0]) for (m = [0, 1]) mirror([0, 0, m]) mini_heart_cut();
  translate([0, -BASE_D / 2 + ENGRAVE_DEPTH, BASE_TEXT_Z]) rotate([90, 0, 0]) linear_extrude(ENGRAVE_DEPTH)
    text(BASE_TEXT, size = BASE_TEXT_SIZE, font = FONT, halign = "center", valign = "center", spacing = 1.12);
}

if (mini == "mini") mini_totem();
else if (mini == "painted") { color("#1f3a6e") mini_totem(); color("#d9a520") mini_paint(); }
