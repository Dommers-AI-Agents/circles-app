// FavCircles tap plaques (Wes, 2026-11-25, with a photo of a store's flat "We would appreciate your
// Google review! Tap to rate your experience" NFC tile: "3d prints design that are comparable to this
// but better and would invite a user to join FavCircles to save the store").
// What these do that the flat tile does not: raised lettering you can feel and read from the side,
// tap AND scan in one spot (the store's own 1½ in "TAP OR SCAN" label over an NFC sticker), and one
// that stands up and faces the customer. The words invite a save; they never promise points.
// Every design prints flat, face up, no supports. The base is one colour and everything raised is a
// second colour: ONE filament change, at z = BASE_T.
//   design="tile"    90 mm rounded square, lies flat on the counter
//   design="heart"   a heart-shaped tile, the label in the middle
//   design="sign"    the tile with a blank foot, to stand in the base below
//   design="stand"   the base: a slot that leans the sign back 15 degrees
//   design="show"    preview of all of them, in colour
include <../totem-print/totem.scad>
part = "none";            // totem.scad draws nothing: it lends the heart outline, the mark and arc text
design = "show";

STORE_NAME = "FAVCIRCLES";         // the bottom line: FavCircles for now, a store's own name later
// place categories either side of the label (Wes, 2026-11-26: "you can still fit some categories")
SIDE_ICONS = [["coffee", "food", "drink"], ["shop", "music", "park"]];
T_BASE = 3.2; T_RAISE = 0.8;          // plaque body, and how far the lettering stands up
T_W = 90; T_CORNER = 11; T_RIM = 1.8; T_RIM_IN = 2.2;
T_LABEL_D = 38.6; T_LABEL_T = 0.6;    // 1½ in round label with the NFC sticker under it
T_LABEL_Y = 3;
T_FOOT = 13;                          // sign only: the blank strip that goes into the stand
S_W = 100; S_D = 46; S_H = 15; S_LEAN = 15; S_SLOT = T_BASE + T_RAISE + 0.5; S_SLOT_Y = -6;
H_S = 50; H_EDGE = 9;                 // heart tile: 118 mm wide
H_LABEL_Y = 9;

module words(t, size, track = 1.1) { text(t, size = size, font = FONT, halign = "center", valign = "center", spacing = track); }
function fit(t, maxw, maxsize, track = 1.14) = min(maxsize, maxw / ((cwsum(t, len(t)) + (track - 1) * (len(t) - 1)) * 1.38));
module brand(size, maxw) {            // FavCircles gets its mark beside it; a store's name stands alone, as big as fits
  if (STORE_NAME == "FAVCIRCLES") { translate([-size * 5.6, 0]) logo2d(size * 2.2); translate([size * 1.6, 0]) words("FAVCIRCLES", size, 1.14); }
  else words(STORE_NAME, fit(STORE_NAME, maxw, size * 1.25), 1.14);
}
module side_icons2d(x, y0, step) {
  for (si = [0, 1]) for (i = [0:len(SIDE_ICONS[si]) - 1])
    translate([(si == 0 ? -1 : 1) * x, y0 - i * step]) ring_icon(SIDE_ICONS[si][i]);
}

// ---------- tile / sign ----------
module tile2d(foot = 0) {
  translate([0, -foot / 2]) offset(r = T_CORNER) square([T_W - 2 * T_CORNER, T_W + foot - 2 * T_CORNER], center = true);
}
module tile_raised2d(foot = 0) {
  // a rim just inside the edge
  difference() { offset(delta = -T_RIM_IN) tile2d(foot); offset(delta = -T_RIM_IN - T_RIM) tile2d(foot); }
  translate([0, 33.5]) words("LOVE THIS PLACE?", 5.4);
  translate([0, T_LABEL_Y]) ring2d(T_LABEL_D / 2 + 2.2, 1.4);     // a collar round the label
  translate([0, -26]) words("SAVE IT IN ONE TAP", 4.9);
  translate([0, -36.5]) brand(3.3, 70);
  side_icons2d(33.5, T_LABEL_Y + 11, 11);
}
// a plaque: the body with the label recess, and what stands up on it (the second colour)
module plaque_body(label_y) {
  difference() {
    linear_extrude(T_BASE) children();
    translate([0, label_y, T_BASE - T_LABEL_T]) cylinder(d = T_LABEL_D, h = 3, $fn = 128);
  }
}
module plaque_up() { translate([0, 0, T_BASE - 0.01]) linear_extrude(T_RAISE + 0.01) children(); }
module tile_body(foot = 0) { plaque_body(T_LABEL_Y) tile2d(foot); }
module tile_up(foot = 0) { plaque_up() tile_raised2d(foot); }
module tile(foot = 0) { tile_body(foot); tile_up(foot); }

// ---------- heart ----------
module heart_tile2d() { offset(r = H_EDGE) polygon(heart_pts(H_S)); }
module heart_raised2d() {
  difference() { offset(delta = -T_RIM_IN) heart_tile2d(); offset(delta = -T_RIM_IN - T_RIM) heart_tile2d(); }
  translate([0, H_LABEL_Y]) ring2d(T_LABEL_D / 2 + 2.2, 1.4);
  translate([0, H_LABEL_Y]) arc_text2d("LOVE IT HERE?", T_LABEL_D / 2 + 9.6, 5.0);
  translate([0, -22]) words("SAVE THIS PLACE", 4.6);
  translate([0, -32]) words(STORE_NAME, fit(STORE_NAME, 44, 3.4), 1.14);
  side_icons2d(40, H_LABEL_Y + 10, 11);
}
module heart_body() { plaque_body(H_LABEL_Y) heart_tile2d(); }
module heart_up() { plaque_up() heart_raised2d(); }
module heart_tile() { heart_body(); heart_up(); }

// ---------- stand ----------
module stand2d() { offset(r = 8) square([S_W - 16, S_D - 16], center = true); }
module stand() {
  difference() {
    union() {
      linear_extrude(S_H - 2) stand2d();
      translate([0, 0, S_H - 2.01]) domed(2, 2) stand2d();
    }
    // the slot: 2 mm of floor left under it, leaning back
    translate([0, S_SLOT_Y, 2]) rotate([-S_LEAN, 0, 0]) translate([-(T_W + 0.8) / 2, 0, 0]) cube([T_W + 0.8, S_SLOT, 40]);
    // FAVCIRCLES cut into the front edge
    translate([0, -S_D / 2 + 0.7, S_H / 2 - 0.4]) rotate([90, 0, 0]) linear_extrude(3) words("FAVCIRCLES", 5.2, 1.14);
  }
}

// ---------- preview ----------
C_BASE = "#f4f1ea"; C_UP = "#1f3a6e"; C_HEART = "#c8312b"; C_LABEL = "#fffdf7";
module label_dot(y) { color(C_LABEL) translate([0, y, T_BASE - T_LABEL_T]) cylinder(d = T_LABEL_D - 0.6, h = 0.3, $fn = 96); }

if (design == "tile") tile();
else if (design == "heart") heart_tile();
else if (design == "sign") tile(T_FOOT);
else if (design == "stand") stand();
else if (design == "show") {
  translate([-110, 0, 0]) { color(C_BASE) tile_body(); color(C_UP) tile_up(); label_dot(T_LABEL_Y); }
  translate([15, 0, 0]) { color(C_BASE) heart_body(); color(C_HEART) heart_up(); label_dot(H_LABEL_Y); }
  translate([140, 0, 0]) {
    color(C_UP) stand();
    // the sign in its slot: its back against the slot's rear wall, its face toward the customer (-y)
    translate([0, S_SLOT_Y, 2]) rotate([-S_LEAN, 0, 0]) translate([0, S_SLOT - 0.25, T_W / 2 + T_FOOT]) rotate([90, 0, 0])
      { color(C_BASE) tile_body(T_FOOT); color(C_HEART) tile_up(T_FOOT); label_dot(T_LABEL_Y); }
  }
}
