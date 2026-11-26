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
//   character="monkee"     Fresh Monkee: a seated, winking monkey               (window code JKI750)
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

// ---------- Fresh Monkee: a seated monkey, winking ----------
MK_HEAD_DZ = -4;                // the head sits low, so the muzzle rests on the chest
module mk_head() { translate([0, 0, MK_HEAD_DZ]) mk_head0(); }
module mk_head0() {
  translate([0, -1, 47]) scale([1.08, 0.96, 1]) drop(21);
  // ears: each leaves the head at 45 degrees
  for (s = [-1, 1]) hull() { translate([s * 23, -1, 52]) scale([1, 0.45, 1]) sphere(8.5); translate([s * 19, -1, 36]) sphere(1, $fn = 16); }
  // the muzzle, with a jaw that carries it down to the chest
  hull() { translate([0, -14.5, 40]) scale([13.5, 8.5, 9]) sphere(1); translate([0, -13.5, 28]) scale([8.5, 2.5, 2]) sphere(1, $fn = 32); }
}
// the face: a shallow step, the way the monkey's lighter face sits in its fur
module mk_mask2d() { translate([0, MK_HEAD_DZ]) mk_mask02d(); }
module mk_face2d() { translate([0, MK_HEAD_DZ]) mk_face02d(); }
module mk_mask02d() {
  hull() for (s = [-1, 1]) translate([s * 8.3, 54.5]) circle(9, $fn = 64);
  translate([0, 41]) scale([16, 11.5]) circle(1, $fn = 96);
  for (s = [-1, 1]) translate([s * 24.4, 52]) circle(4.6, $fn = 48);              // inner ears
}
module mk_face02d() {
  translate([-8, 55]) scale([2.8, 3.7]) circle(1, $fn = 32);                      // open eye
  translate([8.2, 53]) arc2d(4, 20, 160, 1.9);                                    // the wink
  for (s = [-1, 1]) translate([s * 2.4, 44.4]) circle(1.1, $fn = 20);             // nostrils
  translate([0, 45.6]) arc2d(10.2, 215, 325, 1.7);                                // smile
}
function mk_tail(i) = i < 0 ? [14 * cos(75), 14 * sin(75)]
  : i <= 16 ? 20 * [cos(60 - 5 * i), sin(60 - 5 * i)]
  : let(j = i - 16, a = 160 + 14 * j, r = 5.2 - 0.11 * j) 25.2 * [cos(-20), sin(-20)] + r * [cos(a), sin(a)];
module mk_tail() {              // lies on the base, round the right side, and curls
  for (i = [-1:37]) hull() for (p = [mk_tail(i), mk_tail(i + 1)]) translate([p[0], p[1], 1.6]) sphere(3.4, $fn = 32);
}
module monkee() {
  difference() {
    union() {
      translate([0, 0, 13]) scale([1.05, 0.95, 1]) sphere(19);                    // body
      mk_head();
      for (s = [-1, 1]) {
        hull() { translate([s * 17, -4, 26]) sphere(6, $fn = 48); translate([s * 14.5, -13, 10]) sphere(5.6, $fn = 48); }   // arms, hands on the feet
        translate([s * 11, -15, 5]) sphere(8, $fn = 64);                          // feet
      }
      mk_tail();
      // the tuft
      translate([0, 0, MK_HEAD_DZ]) {
        hull() { translate([0.5, -1, 66]) sphere(3.5, $fn = 32); translate([4.5, -1, 73.5]) sphere(1.6, $fn = 24); }
        hull() { translate([-1, -1, 66]) sphere(3, $fn = 32); translate([-4.5, -1, 71]) sphere(1.5, $fn = 24); }
      }
    }
    front_cut() { mk_mask2d(); mk_head(); }
    front_cut(3 * K_CUT) { mk_face2d(); mk_head(); }      // eyes and smile: deep enough to read unpainted
  }
}

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
module port() {
  difference() {
    union() {
      cylinder(r = 21.5, h = 2, $fn = 160); translate([0, 0, 1.99]) cylinder(r1 = 21.5, r2 = 20, h = 1.5, $fn = 160);   // saucer
      difference() { port_cup(); translate([0, 0, PORT_SEA]) cylinder(r = 18.4, h = 5, $fn = 160); }
      port_handle();
      port_ship();
    }
    front_cut() { port_cup2d(); port_cup(); }
    front_cut() { port_ship2d(); port_ship(); }
  }
}

// ---------- parts ----------
module figure(c) { on_base() { if (c == "monkee") monkee(); else if (c == "caffeena") caffeena(); else port(); } }
function store_name(c) = c == "monkee" ? "FRESH MONKEE" : c == "caffeena" ? "CAFFEENA" : "PORT COFFEE";
module whole(c) { union() { kbase(store_name(c)); figure(c); } }

if (character == "show") {
  translate([-95, 0, 0]) { color("#39b54a") render() kbase(store_name("monkee")); color("#6b4226") render() figure("monkee"); k_label(); }
  translate([0, 0, 0]) { color("#2b1707") render() kbase(store_name("caffeena")); color("#d49c60") render() figure("caffeena"); k_label(); }
  translate([95, 0, 0]) { color("#272b4a") render() kbase(store_name("port")); color("#f4f1ea") render() figure("port"); k_label(); }
}
else if (piece == "base") intersection() { whole(character); translate([-100, -100, -1]) cube([200, 200, K_H + 1]); }
else if (piece == "figure") intersection() { whole(character); translate([-100, -100, K_H]) cube([200, 200, 200]); }
else whole(character);
