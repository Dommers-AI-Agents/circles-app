// Store characters: the three store badges again as standing figures, the size of the cactus and the
// mini Totem (Wes, 2026-11-26: "can we make a new version of these three but make them more of a
// character larger like the cactus and the mini totem").
// Each one stands on the same base: the store's 1½ in "TAP OR SCAN" label in the recess at the front,
// a 38 mm NFC sticker in the pocket underneath, the store's name cut into the front, SAVE US ON
// FAVCIRCLES round the label (an invitation, never points), place categories on both sides, the
// FavCircles stamp (mark, FAVCIRCLES, CHARLOTTE · EST. 2026) on the back, the mark underneath. Nothing leans over the label, so a phone can reach it.
// One piece, printed upright, no supports: everything leaves at 45 degrees or steeper.
// Lettering and faces are engraved (fill with a paint pen). Two colours (Wes, 2026-11-26: "I like two
// colors"): the base is one filament and the figure another, split flat at z = K_H (12 mm), so the
// printer swaps filament once. piece="base" and piece="figure" are the two halves of the same print.
//   character="monkee"     Fresh Monkee: the monkey crouched over a smoothie     (window code JKI750)
//   character="caffeena"   Caffeena Coffee House: a race car driven by a coffee cup   (FHVMPK)
//   character="port"       Port Coffee: the ship riding in a cup                (4HOA4V)
//   character="show"       preview of all three, in each store's colours
// The figures follow each store's logo and theme; they don't copy the logo.
include <../totem-print/totem.scad>
part = "none";            // totem.scad draws nothing: it lends the lettering font, icons, mark and domed()
character = "show";
piece = "whole";          // "whole", or "base" / "figure": the print cut at the top of the base, one colour each

// ---- the shared base (new names: totem.scad's own would be evaluated before these exist) ----
K_W = 78; K_D = 94; K_H = 12; K_CORNER = 12; K_R = 2;
K_LABEL_Y = -K_D / 2 + 3 + LABEL_D / 2;    // label 3 mm from the front edge
K_CY = 24;                                 // where the figure stands, behind the label
K_CUT = 0.8;                               // engraving depth
K_NAME_MAX = 5.4; K_NAME_W = 52;
K_TAG = "SAVE US ON FAVCIRCLES";
K_ICONS = [["coffee", "food", "drink"], ["shop", "music", "park"]];

function k_name_size(t) = min(K_NAME_MAX, K_NAME_W / ((cwsum(t, len(t)) + 0.12 * (len(t) - 1)) * 1.38));
module kbase2d() { offset(r = K_CORNER) square([K_W - 2 * K_CORNER, K_D - 2 * K_CORNER], center = true); }
module k_name2d(name) { text(name, size = k_name_size(name), font = FONT, halign = "center", valign = "center", spacing = 1.12); }
module k_tag2d() { translate([0, K_LABEL_Y]) arc_text2d(K_TAG, LABEL_D / 2 + 4.4, 4, 0.14); }   // 4 mm caps: a paint pen fills them
module k_side_icons(cut) {       // three categories on each side face
  for (si = [0, 1]) for (i = [0:2])
    translate([(si == 0 ? -1 : 1) * (K_W / 2 - K_CUT), (si == 0 ? 1 : -1) * (i - 1) * 15, K_H / 2 - 0.4])
      rotate([90, 0, si == 0 ? -90 : 90]) linear_extrude(cut) ring_icon(K_ICONS[si][i]);
}
// the stamp on the back: the mark, FAVCIRCLES, the city and year in a rounded frame, as on the Totem's
// base (Wes, 2026-11-26: "add the Favcircles Charlotte est 2026 stamp with the heart in a circle on the
// back base like the last larger base design"). Sized to this base's 54 mm of flat back.
K_CITY = "CHARLOTTE";
module k_stamp2d() {
  difference() { offset(r = 2.5) square([47.5, 4.6], center = true); offset(r = 1.8) square([47.5, 4.6], center = true); }
  translate([-20.6, 0]) logo2d(7.8);
  translate([-15, 1.75]) text("FAVCIRCLES", size = 3.0, font = FONT, halign = "left", valign = "center", spacing = 1.12);
  translate([-15, -2.35]) text(str(K_CITY, " · EST. 2026"), size = 2.0, font = FONT, halign = "left", valign = "center", spacing = 1.12);
}
module kbase(name) {
  difference() {
    union() {
      linear_extrude(K_H - K_R) kbase2d();
      translate([0, 0, K_H - K_R - 0.01]) domed(K_R, K_R) kbase2d();
    }
    translate([0, K_LABEL_Y, K_H - LABEL_T]) cylinder(d = LABEL_D, h = 5, $fn = 128);
    translate([0, K_LABEL_Y, -1]) cylinder(d = TAG_D, h = 1 + K_H - LABEL_T - TAG_COVER, $fn = 128);
    translate([0, -K_D / 2 + K_CUT, K_H / 2 - 0.3]) rotate([90, 0, 0]) linear_extrude(3) k_name2d(name);
    translate([0, 0, K_H - K_CUT]) linear_extrude(3) k_tag2d();
    k_side_icons(3);
    translate([0, K_D / 2 - K_CUT, K_H / 2 - 1]) rotate([90, 0, 180]) linear_extrude(3) k_stamp2d();
    translate([0, 26, -1]) linear_extrude(1 + 0.6) mirror([0, 1, 0]) logo2d(13);
  }
}
module k_label() { color("#fffdf7") translate([0, K_LABEL_Y, K_H - LABEL_T]) cylinder(d = LABEL_D - 0.6, h = 0.3, $fn = 96); }

// a ball that can start in mid-air: a 45 degree cone underneath it
module drop(r) { hull() { sphere(r); translate([0, 0, -r * sqrt(2) + 0.3]) sphere(0.3, $fn = 12); } }
// engrave a drawing into the side of a solid that faces the customer:
//   children(0) the drawing, x across and y up;  children(1) the solid
// (the tool starts in front of the solid, so no face of it lies on the solid's own surface)
module front_cut(depth = K_CUT) {
  difference() {
    rotate([90, 0, 0]) linear_extrude(150) children(0);
    translate([0, depth, 0]) children(1);
  }
}
// figures are drawn standing on z = 0, centred on their own spot
module on_base() { translate([0, K_CY, K_H - 0.01]) children(); }

// ---------- Fresh Monkee: the monkey crouched over a smoothie ----------
// In profile across the back of the base, head turned to the customer, both hands round a smoothie
// that grows out of the base (so it prints in the base's green; the monkey is the second colour),
// the tail curling up and out past the base's edge (Wes, 2026-11-27: "get rid of the pole he's
// holding. Have him turn sideways and a bit crouched with both hands holding the smoothie. This way
// the smoothie is green and is built from the base. The monkey stays brown. His tail is curvy and can
// hang off the base. make full use of the width of the rear of the base").
// Colour here is by PART, not by height: every layer of the cup costs a filament change.
MK_S = 1.12;
MK_HX = -3; MK_HZ = 54;         // head centre
MK_CUP = [21, 0];
function mk_cup_r(z) = 8.5 + 3 * z / 26;
// engrave from the +x side: children(0) the drawing (x = across, y = up), children(1) the solid
module side_cut(depth = K_CUT) { rotate([0, 0, 90]) front_cut(depth) { children(0); rotate([0, 0, -90]) children(1); } }

// --- the smoothie (green) ---
module mk_cup_plain() {
  translate([MK_CUP[0], MK_CUP[1], 0]) {
    cylinder(r1 = mk_cup_r(0), r2 = mk_cup_r(26), h = 26.01, $fn = 128);
    translate([0, 0, 26]) cylinder(r1 = 11.5, r2 = 12.3, h = 0.81, $fn = 128);                       // the lid's rim
    translate([0, 0, 26.8]) cylinder(r = 12.3, h = 1.61, $fn = 128);
    translate([0, 0, 28.4]) scale([1, 1, 5 / 11.3]) intersection() { sphere(11.3, $fn = 96); translate([-12, -12, 0]) cube(24); }   // the dome
  }
}
module mk_leaf2d() {            // a leaf with its rib, on the cup's outer side
  translate([0, 11]) rotate(-18) difference() {
    intersection() { translate([-3.4, 0]) circle(7, $fn = 64); translate([3.4, 0]) circle(7, $fn = 64); }
    square([1.3, 9], center = true);
    for (y = [-2.5, 0.5, 3.5]) for (m = [0, 1]) mirror([m, 0]) translate([0, y]) rotate(-38) translate([0, -0.6]) square([3.4, 1.2]);
  }
}
module mk_cup() {
  difference() {
    mk_cup_plain();
    translate([MK_CUP[0], MK_CUP[1], 0]) for (z = [2.6, 19.4])               // the sleeve's two edges
      translate([0, 0, z]) difference() { cylinder(r = 14, h = 1.3, $fn = 128); translate([0, 0, -0.01]) cylinder(r1 = mk_cup_r(z) - K_CUT, r2 = mk_cup_r(z) - K_CUT + 1.32, h = 1.32, $fn = 128); }   // roofed at 45 degrees
    side_cut() { mk_leaf2d(); mk_cup_plain(); }
  }
}

// --- the monkey (brown) ---
module mk_head() {
  translate([MK_HX, -1, MK_HZ]) scale([1.05, 0.95, 1]) drop(16);
  for (s = [-1, 1]) hull() { translate([MK_HX + s * 17.6, -1, MK_HZ + 1.5]) scale([1, 0.45, 1]) sphere(7.4); translate([MK_HX + s * 7.5, -1, MK_HZ - 13]) sphere(1, $fn = 16); }
  // a shallow muzzle, carried down to the chest by the jaw
  hull() { translate([MK_HX, -12.6, MK_HZ - 5]) scale([10.5, 5.2, 7.2]) sphere(1, $fn = 64); translate([MK_HX, -7.5, MK_HZ - 17]) sphere(1.5, $fn = 24); }
}
module mk_mask2d() {
  hull() for (s = [-1, 1]) translate([MK_HX + s * 6.4, MK_HZ + 3.6]) circle(7.4, $fn = 64);
  translate([MK_HX, MK_HZ - 5.6]) scale([12.6, 8.8]) circle(1, $fn = 96);
  for (s = [-1, 1]) translate([MK_HX + s * 19.4, MK_HZ + 1.8]) circle(3.5, $fn = 48);              // inner ears
}
module mk_face2d() {
  for (s = [-1, 1]) translate([MK_HX + s * 6.4, MK_HZ + 4.2]) arc2d(3.3, 10, 170, 1.7);            // eyes shut, smiling
  for (s = [-1, 1]) translate([MK_HX + s * 1.8, MK_HZ - 0.4]) circle(0.95, $fn = 20);              // nostrils
  translate([MK_HX, MK_HZ + 1.2]) arc2d(7.6, 212, 328, 1.5);                                       // the smile, cheek to cheek
  intersection() { translate([MK_HX, MK_HZ - 4.4]) circle(5, $fn = 64); translate([MK_HX - 8, MK_HZ - 18.2]) square([16, 12.6]); }   // open mouth
}
// the tail: an S in plan, always climbing better than 45 degrees, out past the base's edge and curling back
MK_TP = [[-18, 0], [-23, 3], [-28, 6], [-33, 6], [-37, 3], [-40, -1], [-41.5, -5], [-40.5, -9], [-37.5, -11], [-34.8, -9.4], [-34.6, -6.4]];
function mk_tz(i) = i == 0 ? 5 : mk_tz(i - 1) + 1.15 * norm(MK_TP[i] - MK_TP[i - 1]);
function mk_tr(i) = 3.7 - 1.3 * i / (len(MK_TP) - 1);
module mk_tail() {
  for (i = [0:len(MK_TP) - 2]) hull() for (j = [i, i + 1]) translate([MK_TP[j][0], MK_TP[j][1], mk_tz(j)]) sphere(mk_tr(j), $fn = 32);
}
// a finger joint lying on the cup's wall (cup-local, out along +x): it grows out of the wall at 45 degrees,
// so no layer of it starts in mid-air
module mk_knuckle(r, d) { hull() { translate([r, 0, 0]) sphere(d, $fn = 20); translate([r - 1.2, 0, -d * 2.2]) sphere(0.4, $fn = 12); } }
module mk_limbs(s) {            // one side: haunch, shin and foot, arm, hand and fingers
  hull() { translate([-13, s * 8, 9]) sphere(9, $fn = 64); translate([9, s * 10, 14]) sphere(6.5, $fn = 64); translate([8, s * 10, 3]) sphere(4, $fn = 32); }
  hull() { translate([8, s * 10, 2.6]) sphere(4.2, $fn = 32); translate([13.5, s * 12.5, 2]) scale([1, 1, 0.8]) sphere(3.8, $fn = 32); }
  for (dy = [-2.9, 0, 2.9]) translate([16.4, s * 12.5 + dy, 1.5]) sphere(1.9, $fn = 24);           // toes
  hull() { translate([-3, s * 11, 37]) sphere(5.5, $fn = 48); translate([7, s * 13.5, 21.5]) sphere(4.6, $fn = 48); }   // upper arm, elbow on the knee
  // forearm: it climbs from the knee to the cup, with a web down into the knee so its underside never starts in mid-air
  hull() { translate([7, s * 13.5, 21.5]) sphere(4.6, $fn = 48); translate([20.5, s * 12, 23]) sphere(4.2, $fn = 48); translate([12.5, s * 11.5, 15]) sphere(1, $fn = 16); }
  hull() { translate([20.5, s * 12, 23]) sphere(4.4, $fn = 48); translate([21, s * 8, 14.5]) sphere(1, $fn = 16); }    // the hand, grown from the cup's wall
  // four fingers round the cup
  for (k = [0:3]) let(z = 24.6 - 2.5 * k, r = mk_cup_r(z) + 0.5)
    hull() for (a = [78, 44 + 3 * k]) translate([MK_CUP[0], 0, z]) rotate(s * a) mk_knuckle(r, 1.45);
  hull() for (a = [100, 128]) translate([MK_CUP[0], 0, 23 + (a - 100) * 0.09]) rotate(s * a) mk_knuckle(mk_cup_r(23) + 0.5, 1.6);   // thumb
}
module mk_torso() { hull() { translate([-13, 0, 10]) sphere(12, $fn = 96); translate([-5, 0, 32]) sphere(11, $fn = 96); } }   // back and chest
module mk_pin2d() { translate([-13.5, 26.5]) difference() { mini_pin2d(10.5); translate([0, 2.05]) circle(1.35, $fn = 32); } }
module mk_body() {
  difference() {                // a map pin on the flank, behind the arm (Wes, 2026-11-27: "a small engraving near the back of the monkey of a map pin")
    mk_torso();
    front_cut(2 * K_CUT) { mk_pin2d(); mk_torso(); }
  }
  difference() {                // the face is cut into the head alone
    mk_head();
    front_cut() { mk_mask2d(); mk_head(); }
    front_cut(2.4 * K_CUT) { mk_face2d(); mk_head(); }
  }
  for (s = [-1, 1]) mk_limbs(s);
  mk_tail();
  // the tuft: three spikes
  for (t = [[0.8, 5.2, 9.4, 3.2], [-1.2, -4.6, 7.2, 2.8], [0, 0.6, 6.2, 2.6]])
    hull() { translate([MK_HX + t[0], -1, MK_HZ + 15]) sphere(t[3], $fn = 32); translate([MK_HX + t[1], -1, MK_HZ + 15 + t[2]]) sphere(1.4, $fn = 24); }
  // the straw, with its bend ring
  translate([MK_CUP[0] + 3.5, MK_CUP[1], 30]) { cylinder(r = 2, h = 15, $fn = 40); translate([0, 0, 11]) cylinder(r1 = 2, r2 = 2.6, h = 0.61, $fn = 40); translate([0, 0, 11.6]) cylinder(r = 2.6, h = 1.2, $fn = 40); }
}
module mk_green() { scale(MK_S) mk_cup(); }
module monkee() { difference() { scale(MK_S) mk_body(); scale(MK_S) mk_cup_plain(); } }

// ---------- Caffeena: a race car, a coffee cup at the wheel ----------
CAR_CUP_X = -3;
CAR_WHEELS = [[-22, 11, 7.7], [24, 9.5, 6.7]];     // x, radius, axle height: big at the back
module car_body() {
  intersection() {
    // side view: a tall spoiler lip, a flat deck, a long hood down to the nose
    rotate([90, 0, 0]) linear_extrude(50, center = true)
      polygon([[-34, -1], [-34, 13], [-37, 16], [-37, 21], [-34, 21], [-30, 16.5], [10, 16.5], [34, 7.5], [36.5, 5.5], [36.5, -1]]);
    // from above: narrowing to the nose
    translate([0, 0, -2]) linear_extrude(40) offset(r = 4) offset(delta = -4) polygon([[-37, -15], [4, -15], [36.5, -8], [36.5, 8], [4, 15], [-37, 15]]);
    // from the front: round shoulders
    rotate([90, 0, 90]) linear_extrude(100, center = true) polygon([[-15, -2], [-15, 10], [-12.5, 15], [-8.5, 17.5], [-8.5, 30], [8.5, 30], [8.5, 17.5], [12.5, 15], [15, 10], [15, -2]]);
  }
  // the headrest fairing behind the driver, and a cowl in front
  hull() { translate([-12, 0, 16.4]) sphere(6.5, $fn = 48); translate([-29, 0, 16.4]) sphere(2.5, $fn = 32); }
  hull() { translate([9, 0, 15.6]) scale([1, 1.5, 1]) sphere(5, $fn = 48); translate([19, 0, 11.6]) sphere(2, $fn = 24); }
}
module car_wheels() {           // sunk into the base so only the printable part of each tyre shows
  for (w = CAR_WHEELS) for (s = [-1, 1]) translate([w[0], s * 15, w[2]]) rotate([90, 0, 0])
    hull() { cylinder(r = w[1], h = 7, center = true, $fn = 96); cylinder(r = w[1] - 1.4, h = 9, center = true, $fn = 96); }
}
module car_hubs() {
  for (w = CAR_WHEELS) for (s = [-1, 1]) translate([w[0], s * 19.5, w[2]]) rotate([90, 0, 0])
    linear_extrude(2 * K_CUT, center = true) { ring2d(w[1] - 4.2, 1.3); circle(2.2, $fn = 32); }
}
module car_stripes() {          // two racing stripes down the hood
  for (y = [-2.4, 2.4]) hull() for (x = [14.5, 33]) translate([x, y, 4]) cylinder(d = 2.2, h = 40, $fn = 24);
}
module car_cup() {
  translate([CAR_CUP_X, 0, 0]) {
    translate([0, 0, 12]) cylinder(r1 = 8.5, r2 = 10.5, h = 26.01);
    translate([0, 0, 38]) cylinder(r1 = 10.5, r2 = 11.6, h = 1.11);                // the lid
    translate([0, 0, 39.1]) cylinder(r = 11.6, h = 2.2);
    translate([0, 0, 41.29]) scale([1, 1, 0.45]) sphere(10.6);
    translate([0, -5.6, 44.4]) scale([1.5, 1, 1]) cylinder(r1 = 2.2, r2 = 1.6, h = 2.2, $fn = 32);   // the sip spout
  }
}
module car_cup_face2d() {
  for (s = [-1, 1]) translate([CAR_CUP_X + s * 3.9, 32]) scale([1.8, 2.5]) circle(1, $fn = 32);
  translate([CAR_CUP_X, 31.5]) arc2d(5.6, 222, 318, 1.6);
}
module car_door2d() { translate([1.5, 7.6]) { ring2d(5.4, 1.2); text("C", size = 5.2, font = FONT, halign = "center", valign = "center"); } }
module caffeena() {
  difference() {
    union() { car_body(); car_wheels(); car_cup(); }
    car_hubs();
    front_cut() { car_door2d(); car_body(); }
    front_cut() { car_cup_face2d(); car_cup(); }
    difference() { car_stripes(); translate([0, 0, -K_CUT]) car_body(); }
  }
}

// ---------- Port Coffee: the ship in the cup ----------
PORT_SEA = 29;                  // the coffee's surface
module port_cup() { translate([0, 0, 3]) cylinder(r1 = 13, r2 = 21, h = 28, $fn = 160); }
module port_handle() {          // a handle with 45 degree corners: it prints in mid-air without support
  rotate([90, 0, 0]) linear_extrude(6.4, center = true) offset(r = 0.8) offset(delta = -0.8) difference() {
    polygon([[13, 7], [27, 21], [27, 25], [21.5, 30.5], [13, 30.5]]);
    polygon([[13, 12.6], [22.5, 22.1], [22.5, 24], [19.5, 27], [13, 27]]);
  }
}
module port_ship() {
  translate([-1, 0, PORT_SEA]) {
    intersection() {            // the hull, bow to the right
      rotate([90, 0, 0]) linear_extrude(20, center = true) polygon([[-14, -1], [-16, 8], [19, 9.2], [10, -1]]);
      translate([0, 0, -2]) linear_extrude(15) offset(r = 1.5) offset(delta = -1.5) polygon([[-17, -5.5], [7, -5.5], [19.5, 0], [7, 5.5], [-17, 5.5]]);
    }
    rotate([90, 0, 0]) linear_extrude(8, center = true) polygon([[-12, 7.8], [-11, 13], [6, 13], [9, 8.4]]);
    rotate([90, 0, 0]) linear_extrude(6.4, center = true) polygon([[-8, 12.5], [-7.2, 17], [2, 17], [3.6, 12.5]]);
    translate([-3, 0, 16.5]) cylinder(r = 3.1, h = 8, $fn = 48);                   // the funnel, with its band
    translate([-3, 0, 22.4]) cylinder(r1 = 3.1, r2 = 3.9, h = 0.81, $fn = 48);
    translate([-3, 0, 23.2]) cylinder(r = 3.9, h = 2, $fn = 48);
  }
}
module port_ship2d() {
  for (x = [-9, -5, -1, 3]) translate([x - 1, PORT_SEA + 4.8]) circle(1.15, $fn = 24);                 // portholes
  for (x = [-7.5, -4, -0.5, 3]) translate([x - 1, PORT_SEA + 10.8]) square([1.9, 1.9], center = true); // cabin windows
}
module port_cup2d() {
  translate([0, 19]) text("PORT", size = 5.6, font = FONT, halign = "center", valign = "center", spacing = 1.1);
  for (i = [-2:2]) translate([i * 4.4, 9.4]) arc2d(2.2, 20, 160, 1.2);             // waves
}
// the cup, handle and ship are 35% larger than first drawn, the saucer is not (Wes, 2026-11-27: "make the
// white part a little bigger? perhaps not the white circle base it sits on, but taller and bigger.
// perhaps 35% larger"). Scaled from the cup's foot, so it still stands in the saucer.
PORT_GROW = 1.35;
module port() {
  cylinder(r = 21.5, h = 2, $fn = 160); translate([0, 0, 1.99]) cylinder(r1 = 21.5, r2 = 20, h = 1.5, $fn = 160);   // saucer
  translate([0, 0, 3]) scale(PORT_GROW) translate([0, 0, -3]) difference() {
    union() {
      difference() { port_cup(); translate([0, 0, PORT_SEA]) cylinder(r = 18.4, h = 5, $fn = 160); }
      port_handle();
      port_ship();
    }
    front_cut() { port_cup2d(); port_cup(); }
    front_cut() { port_ship2d(); port_ship(); }
  }
}

// ---------- parts ----------
// base(c): everything in the first colour.  figure(c): everything in the second.
// Caffeena and Port change colour at the top of the base; Fresh Monkee's smoothie is base-coloured too.
module figure(c) {
  intersection() {
    on_base() { if (c == "monkee") monkee(); else if (c == "caffeena") caffeena(); else port(); }
    translate([-150, -150, K_H]) cube([300, 300, 300]);
  }
}
function store_name(c) = c == "monkee" ? "FRESH MONKEE" : c == "caffeena" ? "CAFFEENA" : "PORT COFFEE";
module base(c) { union() { kbase(store_name(c)); if (c == "monkee") on_base() mk_green(); } }
module whole(c) { union() { base(c); figure(c); } }

if (character == "show") {
  translate([-95, 0, 0]) { color("#39b54a") render() base("monkee"); color("#6b4226") render() figure("monkee"); k_label(); }
  translate([0, 0, 0]) { color("#2b1707") render() base("caffeena"); color("#d49c60") render() figure("caffeena"); k_label(); }
  translate([95, 0, 0]) { color("#272b4a") render() base("port"); color("#f4f1ea") render() figure("port"); k_label(); }
}
else if (piece == "base") base(character);
else if (piece == "figure") figure(character);
else whole(character);
