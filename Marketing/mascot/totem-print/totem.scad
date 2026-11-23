// FavCircles Totem: the heart inside the ring, on a base (Wes, 2026-11-20).
// v2 (Wes, 2026-11-22): the NFC tag lives in the BASE, under the round QR label, so one
// circle says "tap or scan". No coin weights (tapping the base presses it down, it can't tip).
// The heart is solid and carries a paintable design instead of "TAP".
// Four one-color parts, each printed flat with no supports:
//   part="ring"        ring, lying flat (back face on the plate)
//   part="heart_front" front heart half, flat (mating) side down; design engraved on its face
//   part="heart_back"  back heart half, flat side down
//   part="base"        base, right side up; ring slot + label recess on top, NFC pocket underneath
//   part="assembly"    everything put together (preview only)
// Hardware: one 38 mm NFC sticker (in the base pocket), two 1.75 mm filament offcuts
// (heart dowels), a 1.5 in QR label, four rubber bumpers, glue.
// All sizes in mm and match Marketing/mascot/favcircles-totem.html.
// Revisions (git tags; each can be printed again from its tag):
//   totem-v1-puffy    2026-11-22  puffy 38 mm heart, pin_drop, SIGN UP, ring icons, network sides
//   totem-v2-classic  2026-11-23  the original 22 mm heart shape (HEART_SHAPE), same engravings

part = "assembly";
$fn = 96;

// ---- ring ----
RING_OUT = 55; RING_IN = 41; RING_D = 18; RING_R = 2.5; RING_CH = 1.2;
// ---- heart ----
HEART_S = 28;          // bezier scale; the outline is this plus HEART_EDGE
HEART_EDGE = 6;        // outline grows 6 mm around the bezier heart (68 mm wide)
HEART_DY = -4;         // heart centre below the ring centre
// Wes 2026-11-23: "rather have the heart less round. like the original design, but keeping the updated engravings."
HEART_SHAPE = "classic";   // "classic" = the original 22 mm heart, flat face with rounded edges; "puffy" = v1's 38 mm heart, round all over
HALF_T = HEART_SHAPE == "puffy" ? 19 : 11;   // thickness of each half
DOME_R = HEART_SHAPE == "puffy" ? 21 : 7;    // how far in from the edge the rounding reaches
TENON_W = 8; TENON_T = 10;            // printed stem from the heart tip into the ring
SOCKET_DEPTH = 6; FIT = 0.2;
DOWEL_D = 1.95; DOWEL_DEPTH = 5; DOWELS = [[-18, 14], [18, 14]];
// ---- base ----
BASE_W = 132; BASE_D = 86; BASE_H = 18; BASE_CORNER = 26; BASE_R = 3;
SLOT = 8; RING_BACK = 14;            // ring centre sits 14 mm behind the base centre
LABEL_D = 38.6; LABEL_T = 0.5; LABEL_Y = -20;
TAG_D = 39; TAG_COVER = 1.2;         // 38 mm NFC sticker in a pocket from underneath, 1.2 mm under the label floor
// ---- engraved lettering (Wes, 2026-11-21: the default; fill with a Posca pen) ----
ENGRAVE = true; ENGRAVE_DEPTH = 0.8;   // measured straight down; the heart face is curved
FONT = "Avenir Next:style=Bold";
// heart face design: "plain", "logo", "hearts" or "fav"
HEART_DESIGN = "pin_drop";   // Wes picked 2026-11-22: red heart, gold pin, Dark Blue ring + base
BASE_TEXT = "PLACES YOU LOVE"; BASE_TEXT_SIZE = 5.6; BASE_TEXT_Z = 7.2;
// Wes 2026-11-22: "'Places you Love' across the front. Join ( ) Us across the top, either side of
// the QR sticker. Favcircles engraved across the arch of the top of the circle enclosing the heart."
// The round label is the "( )": SIGN [label] UP
TOP_WORDS = ["SIGN", "UP"]; TOP_TEXT_SIZE = 7; TOP_GAP = 4.5;   // gap between a word and the label's edge
RING_TEXT = "FAVCIRCLES"; RING_TEXT_SIZE = 6; RING_TEXT_R = 48;  // on the ring's front face, over the top
// Character (Wes 2026-11-22: "more little pin drops to look like a map of pins on either side of
// Favcircles along the ring"; a logo "stamp of authenticity"):
RING_PINS = true;            // place-category icons down both sides of the ring front (module ring_pins2d)
BACK_STAMP = true;           // logo nameplate on the back of the base, left unpainted
MAKER_MARK = true;           // numbered maker's mark under the base, like the stamp under a pot
MAKER_FOR = "";              // the store's name ("" = no "made for" line); make-totem.sh fills it per store
MAKER_NO = "0001";
CITY = "CHARLOTTE";
SIDE_CROWN = false;          // the city's mark (Charlotte's crown) on the right side, painted (replaced by SIDE_PEOPLE)
// Wes 2026-11-22: "the back of the heart can match the front. The back of the circle and sides we can
// use category icons. ... the left and right side of the base we engrave two people, girl and guy,
// connected, representing a network of people." Later: icons only on the ring front; on the sides,
// linked heads (left) and a constellation (right).
HEART_BACK_MATCH = true;     // the heart's back half gets the same design as the front
RING_BACK_ICONS = true;      // place-category icons around the back of the ring (the face printed on the bed)
SIDE_PEOPLE = true;          // the network: linked heads on the left side, a constellation on the right

RING_CY = BASE_H - SLOT + RING_OUT;  // ring centre height above the table
HEART_TIP = -(HEART_S + HEART_EDGE); // heart-local y of the tip

// ---------- shapes ----------
function bez(p, t) = let(u = 1 - t) p[0]*u*u*u + p[1]*3*u*u*t + p[2]*3*u*t*t + p[3]*t*t*t;
SEGS = [[[0,-1],[-.55,-.62],[-1.05,-.18],[-1,.33]], [[-1,.33],[-.95,.86],[-.36,1.04],[0,.6]],
        [[0,.6],[.36,1.04],[.95,.86],[1,.33]], [[1,.33],[1.05,-.18],[.55,-.62],[0,-1]]];
module heart2d() {
  offset(r = HEART_EDGE)
    polygon([for (c = SEGS) for (i = [0:47]) bez(c, i / 48) * HEART_S]);
}
// a slab with a domed top: vertical at the bottom, flat on top, quarter-ellipse edge
module domed(h, r) {
  minkowski() {
    linear_extrude(0.01) offset(delta = -r) children();
    scale([r, r, h]) intersection() { sphere(1, $fn = 40); translate([-1, -1, 0]) cube(2); }
  }
}

// ---------- ring ----------
module ring_profile() {
  hull() {
    translate([RING_IN + RING_CH, 0]) square([RING_OUT - RING_IN - 2 * RING_CH, 0.01]);
    translate([RING_IN, RING_CH]) square([RING_OUT - RING_IN, 0.01]);
    translate([RING_IN + RING_R, RING_D - RING_R]) circle(RING_R, $fn = 32);
    translate([RING_OUT - RING_R, RING_D - RING_R]) circle(RING_R, $fn = 32);
  }
}
// rough advance widths (in em) of Avenir Next Bold capitals, to space letters along an arc
function cw(c) = c == "I" ? 0.30 : c == "J" ? 0.50 : c == "L" ? 0.52 : c == "F" ? 0.55 : c == "E" ? 0.56 : c == "S" ? 0.58
  : c == "R" ? 0.62 : c == "V" ? 0.66 : c == "A" ? 0.68 : c == "C" ? 0.66 : c == "O" ? 0.76 : c == " " ? 0.30 : 0.64;
function cwsum(t, n) = n <= 0 ? 0 : cw(t[n - 1]) + cwsum(t, n - 1);
// text reading left to right over the top of a circle of radius r (letters upright, bottoms toward the centre)
module arc_text2d(t, r, size, track = 0.10) {
  em = size * 1.38;                                   // cap height `size` → em width
  total = (cwsum(t, len(t)) + track * (len(t) - 1)) * em;
  for (i = [0:len(t) - 1]) {
    mid = (cwsum(t, i) + track * i + cw(t[i]) / 2) * em - total / 2;   // arc length from the top, + to the right
    a = 90 - mid / r * 180 / PI;
    translate([r * cos(a), r * sin(a)]) rotate(a - 90)
      text(t[i], size = size, font = FONT, halign = "center", valign = "center");
  }
}
module ring_text2d() { arc_text2d(RING_TEXT, RING_TEXT_R, RING_TEXT_SIZE); }

// ---- place-category icons, about 7 mm, strokes 1.2 mm or more so a paint pen fills them ----
module icon_coffee() { difference() { translate([-0.8, -1]) square([5.6, 5], center = true); translate([-0.8, -0.2]) square([3.2, 5], center = true); }
  translate([-0.8, -3.2]) square([5.6, 1.2], center = true); translate([2.6, -0.6]) difference() { circle(1.6, $fn = 24); circle(0.6, $fn = 16); }
  for (x = [-2, 0.4]) translate([x, 2.6]) hull() { circle(0.6, $fn = 12); translate([0.5, 1]) circle(0.6, $fn = 12); } }
module icon_food() { translate([-1.8, 0]) { square([1.2, 7], center = true); for (x = [-1.1, 0, 1.1]) translate([x, 2.4]) square([0.7, 2.6], center = true);
    translate([0, 1]) square([3, 1], center = true); }
  translate([1.8, 0]) hull() { translate([0, -3.5]) square([1.2, 0.1], center = true); translate([0.3, 3.2]) circle(0.9, $fn = 16); translate([0, 0.4]) square([1.2, 0.1], center = true); } }
module icon_drink() { polygon([[-3.2, 3.2], [3.2, 3.2], [0.6, 0], [0.6, -2.6], [2.2, -3.4], [-2.2, -3.4], [-0.6, -2.6], [-0.6, 0]]); }
module icon_shop() { translate([0, -1]) offset(r = 0.4) square([5.6, 4.6], center = true);
  translate([0, 1.6]) difference() { circle(1.8, $fn = 24); circle(1.0, $fn = 24); translate([0, -2]) square([4, 4], center = true); } }
module icon_park() { polygon([[0, 3.8], [3, 0.4], [1.6, 0.4], [3.4, -1.8], [-3.4, -1.8], [-1.6, 0.4], [-3, 0.4]]);   // a pine tree
  translate([0, -2.7]) square([1.4, 1.8], center = true); }
module icon_fitness() { square([6, 1.2], center = true); for (x = [-2.6, 2.6]) translate([x, 0]) square([1.4, 4.4], center = true);
  for (x = [-3.6, 3.6]) translate([x, 0]) square([0.8, 2.8], center = true); }
module icon_music() { translate([-1.4, -2.2]) scale([1.2, 1]) circle(1.4, $fn = 24); translate([0.1, 0.6]) square([1.1, 5.6], center = true);
  translate([0.6, 3.1]) rotate(-25) square([2.6, 1.1]); }
module icon_book() { for (s = [-1, 1]) scale([s, 1]) polygon([[0.3, -2.6], [3.4, -2], [3.4, 3], [0.3, 2.4]]); }
module icon_hotel() { translate([0, -0.6]) square([6.4, 1.3], center = true); translate([-2.6, 0.3]) square([1.2, 4.4], center = true);
  translate([-1.2, 1.1]) circle(1, $fn = 16); translate([1.2, 0.8]) square([3.4, 1.4], center = true); translate([2.6, -1.8]) square([1.2, 1.6], center = true); translate([-2.6, -1.8]) square([1.2, 1.6], center = true); }
RING_ICONS = ["coffee", "food", "drink", "shop", "park", "fitness", "music", "book", "hotel"];
module ring_icon(n) {
  if (n == "coffee") icon_coffee(); else if (n == "food") icon_food(); else if (n == "drink") icon_drink();
  else if (n == "shop") icon_shop(); else if (n == "park") icon_park(); else if (n == "fitness") icon_fitness();
  else if (n == "music") icon_music(); else if (n == "book") icon_book(); else if (n == "hotel") icon_hotel();
}
// evenly round the back of the ring, skipping the bottom, which sits in the base's slot
module ring_icons2d() {
  for (i = [0:len(RING_ICONS) - 1]) let(a = 222 - i * 264 / (len(RING_ICONS) - 1))
    translate([RING_TEXT_R * cos(a), RING_TEXT_R * sin(a)]) ring_icon(RING_ICONS[i]);
}

// a small map pin, `h` tall, centred on its middle (solid; a hole would be too small to paint)
module mini_pin2d(h) { s = h / PIN_H; translate([0, -(PIN_CY + PIN_R - PIN_H / 2) * s]) scale(s) pin2d(); }
// down both sides of the ring front from FAVCIRCLES almost to the base: place-category icons,
// evenly spaced (Wes 2026-11-22: pins between them were "way too busy... just keep the categories").
// Angles in degrees from the top; icons stay upright.
RING_ICON_FROM = 50; RING_ICON_TO = 150;
FRONT_ICONS = [["coffee", "food", "drink", "shop"], ["park", "fitness", "music", "book"]];   // left side, right side
module ring_pins2d() {
  for (si = [0, 1]) let(side = si == 0 ? -1 : 1, n = len(FRONT_ICONS[si])) for (i = [0:n - 1])
    let(d = RING_ICON_FROM + i * (RING_ICON_TO - RING_ICON_FROM) / (n - 1), a = 90 - side * d)
      translate([RING_TEXT_R * cos(a), RING_TEXT_R * sin(a)]) ring_icon(FRONT_ICONS[si][i]);
}

module ring() {
  difference() {
    rotate_extrude($fn = 240) ring_profile();
    // FAVCIRCLES over the top of the front face (the face printed up, z = RING_D)
    if (ENGRAVE && RING_TEXT != "") translate([0, 0, RING_D - ENGRAVE_DEPTH]) linear_extrude(ENGRAVE_DEPTH + 1) ring_text2d();
    if (ENGRAVE && RING_PINS) translate([0, 0, RING_D - ENGRAVE_DEPTH]) linear_extrude(ENGRAVE_DEPTH + 1) ring_pins2d();
    // seen from behind, x is flipped
    if (ENGRAVE && RING_BACK_ICONS) translate([0, 0, -1]) linear_extrude(1 + ENGRAVE_DEPTH) mirror([1, 0, 0]) ring_icons2d();
    // socket for the heart's stem, at the bottom of the ring (-y)
    translate([-(TENON_W / 2 + FIT), -(RING_IN + SOCKET_DEPTH + 0.5), RING_D / 2 - TENON_T / 2 - FIT])
      cube([TENON_W + 2 * FIT, SOCKET_DEPTH + 0.5 + 1, TENON_T + 2 * FIT]);
  }
}

// ---------- heart halves ----------
// heart-local: tip toward -y, mating face at z = 0, outer face at z = HALF_T
module heart_half(front) {
  stem_bottom = -(RING_IN + SOCKET_DEPTH) - HEART_DY;   // reaches the bottom of the socket
  difference() {
    union() {
      heart_body();
      // half of the stem
      translate([-TENON_W / 2, stem_bottom, 0]) cube([TENON_W, HEART_TIP - stem_bottom + 10, TENON_T / 2]);
    }
    // design cut ENGRAVE_DEPTH into the curved face (the face's own shape, moved down)
    if ((front || HEART_BACK_MATCH) && ENGRAVE && HEART_DESIGN != "plain") intersection() {
      translate([0, 0, -1]) linear_extrude(HALF_T + 2) heart_design();
      difference() { heart_body(); translate([0, 0, -ENGRAVE_DEPTH]) heart_body(); }
    }
    for (d = DOWELS) translate([d[0], d[1], -1]) cylinder(d = DOWEL_D, h = DOWEL_DEPTH + 1, $fn = 24);
  }
}

module heart_body() { render() domed(HALF_T, DOME_R) heart2d(); }

function heart_pts(sc) = [for (c = SEGS) for (i = [0:23]) bez(c, i / 24) * sc];
module ring2d(r, w) { difference() { circle(r + w / 2, $fn = 96); circle(r - w / 2, $fn = 96); } }

module arc2d(r, a0, a1, w) {
  polygon(concat([for (i = [0:32]) let(a = a0 + (a1 - a0) * i / 32) [(r + w / 2) * cos(a), (r + w / 2) * sin(a)]],
                 [for (i = [32:-1:0]) let(a = a0 + (a1 - a0) * i / 32) [(r - w / 2) * cos(a), (r - w / 2) * sin(a)]]));
  for (a = [a0, a1]) translate([r * cos(a), r * sin(a)]) circle(w / 2, $fn = 20);
}
module line2d(p, q, w) { hull() { translate(p) circle(w / 2, $fn = 20); translate(q) circle(w / 2, $fn = 20); } }
module sparkle(s) { offset(r = s * 0.06) polygon([[0, s], [s * 0.2, s * 0.2], [s, 0], [s * 0.2, -s * 0.2], [0, -s], [-s * 0.2, -s * 0.2], [-s, 0], [-s * 0.2, s * 0.2]]); }
module mitten() { hull() { translate([-14, -6]) circle(6, $fn = 40); translate([-6, -4]) circle(4, $fn = 32); translate([-12, 4]) circle(4.5, $fn = 32); } translate([-6, 1]) rotate(20) hull() { circle(2, $fn = 20); translate([5, 0]) circle(2, $fn = 20); } }
module cup2d() { polygon([[-9, 9], [9, 9], [7, -6], [-7, -6]]); }
// map pin, heart-local: round head centred at PIN_CY, point PIN_H below the top of the head
PIN_CY = 7; PIN_R = 11; PIN_H = 33;
module pin2d() {
  translate([0, PIN_CY]) circle(PIN_R, $fn = 72);
  hull() {
    translate([0, PIN_CY]) intersection() { circle(PIN_R, $fn = 72); translate([-PIN_R, -PIN_R]) square([2 * PIN_R, PIN_R]); }
    translate([0, PIN_CY + PIN_R - PIN_H]) circle(0.9, $fn = 16);
  }
}
module tab2d() { polygon([[-9, 5], [9, 5], [9, -6], [0, -2], [-9, -6]]); }

// the paintable design on the heart's front face (heart-local, centre of the dome near y = 2)
module heart_design() {
  if (HEART_DESIGN == "logo") {         // the FavCircles mark in miniature: a heart inside a ring
    translate([0, 1]) ring2d(13, 2.2);
    translate([0, 0.5]) polygon(heart_pts(7.5));
  }
  else if (HEART_DESIGN == "hearts") {  // a big outline heart with a small solid one inside
    translate([0, 1]) difference() { offset(r = 0.9) polygon(heart_pts(15)); offset(r = -0.9) polygon(heart_pts(15)); }
    translate([0, 1.5]) polygon(heart_pts(5.5));
    for (p = [[-20, 10, 3.2], [21, 9, 2.6], [-14, -14, 2.4], [15, -13, 3]]) translate([p[0], p[1]]) polygon(heart_pts(p[2]));
  }
  // ---- ChatGPT's ideas (2026-11-22), strokes ~2.2 mm ----
  else if (HEART_DESIGN == "wink") {
    translate([-11, 6]) scale([3.6, 5]) circle(1, $fn = 48);
    translate([11, 3.5]) arc2d(5.5, 25, 155, 2.6);
    translate([1.5, 4]) rotate(-6) arc2d(15, 222, 318, 2.6);
  }
  else if (HEART_DESIGN == "door") rotate(4) {
    W = 18; difference() {
      union() { translate([-W / 2 - 1.1, -17]) square([W + 2.2, 21]); translate([0, 4]) circle(W / 2 + 1.1, $fn = 64); }
      union() { translate([-W / 2 + 1.1, -15.9]) square([W - 2.2, 21]); translate([0, 4]) circle(W / 2 - 1.1, $fn = 64); }
    }
    translate([4.6, -6]) circle(2.4, $fn = 32);
    line2d([-11, -20], [-3, -20], 2.2); line2d([3, -20], [11, -20], 2.2);
  }
  else if (HEART_DESIGN == "orbit") {
    translate([0, 1]) rotate(-22) difference() { scale([21, 9]) circle(1, $fn = 96); scale([18.8, 6.8]) circle(1, $fn = 96); }
    translate([-2, 2]) circle(6, $fn = 48);
    translate([0, 1]) rotate(-22) translate([19.9 * cos(35), 7.9 * sin(35)]) circle(2.9, $fn = 32);
  }
  else if (HEART_DESIGN == "contours") difference() {
    union() for (k = [18, 12.5, 7]) translate([0, 1 + (18 - k) * 0.08]) difference() { offset(r = 1.1) polygon(heart_pts(k)); offset(r = -1.1) polygon(heart_pts(k)); }
    translate([0, -2]) rotate(-35) translate([0, -2.2]) square([30, 4.4]);
  }
  else if (HEART_DESIGN == "bite") {
    intersection() {   // a scalloped bite, set inside the right lobe (the outline stays whole)
      offset(delta = -5) heart2d();
      for (q = [[16, 16], [22, 9], [21, 1]]) translate(q) circle(7, $fn = 48);
    }
    translate([9, -6]) circle(1.7, $fn = 24); translate([5, -10.5]) circle(1.3, $fn = 24);
  }
  else if (HEART_DESIGN == "thread") {
    P = [[0, 16], [-4, 7], [3, -1], [-2, -10], [1, -18]];
    for (i = [0:3]) line2d(P[i], P[i + 1], 2.2);
    for (q = [[-0.5, 3], [0.5, -5.5], [-0.5, -14]]) translate(q) for (r = [45, -45]) rotate(r) line2d([-4.5, 0], [4.5, 0], 2);
  }
  else if (HEART_DESIGN == "pinky") {
    for (m = [0, 1]) mirror([m, 0]) {
      difference() { offset(r = 1.1) mitten(); offset(r = -1.1) mitten(); }
    }
    translate([-1.8, 2.2]) arc2d(3.2, -70, 160, 2);
    translate([1.8, 0.2]) arc2d(3.2, 110, 340, 2);
  }
  else if (HEART_DESIGN == "disco") {
    translate([-5, 1]) sparkle(13); translate([11, 12]) sparkle(6.5); translate([12, -8]) sparkle(5);
  }
  else if (HEART_DESIGN == "stamp") {   // the store's own pictogram; a coffee cup here
    translate([0, -3]) {
      difference() { offset(r = 1.1) cup2d(); offset(r = -1.1) cup2d(); }
      translate([9.8, 4]) arc2d(4, -90, 90, 2.2);
      for (x = [-3.5, 3.5]) translate([x, 13]) for (i = [0:1]) line2d([0, 0 + i * 4], [1.6, 2 + i * 4], 1.8);
      line2d([-10, -9], [10, -9], 2.2);
    }
    line2d([-20, -6], [-20, 6], 2.2); line2d([20, -6], [20, 6], 2.2);
  }
  else if (HEART_DESIGN == "keep") {
    translate([0, 5]) text("KEEP", size = 10.5, font = "Avenir Next:style=Heavy", halign = "center", valign = "center", spacing = 1.06);
    translate([0, -10]) difference() { offset(r = 1.1) tab2d(); offset(r = -1.1) tab2d(); }
  }
  // ---- The map pin (Wes 2026-11-22: "an engraved Pin in the middle of the heart. Represents the pin
  //      on a map of place. inside the heart of the circle.") Kept inside the heart's flat top, so it
  //      can be filled with paint or printed flush in a second color with only a few AMS swaps ----
  else if (HEART_DESIGN == "pin")          // the classic map pin: solid, with a round hole
    difference() { pin2d(); translate([0, PIN_CY]) circle(4.6, $fn = 48); }
  else if (HEART_DESIGN == "pin_heart")    // the pin's hole is a little heart: a favorite place
    difference() { pin2d(); translate([0, PIN_CY - 0.4]) polygon(heart_pts(5)); }
  else if (HEART_DESIGN == "pin_drop") {   // the pin outline, just landed, with its shadow on the map
    difference() { pin2d(); offset(r = -2.4) pin2d(); }
    translate([0, PIN_CY]) circle(3.8, $fn = 40);
    translate([0, PIN_CY + PIN_R - PIN_H - 1.6]) scale([1, 0.32]) difference() { circle(8.5, $fn = 64); circle(6, $fn = 64); }
  }
  else if (HEART_DESIGN == "fav")
    translate([0, 1]) text("fav", size = 15, font = "Avenir Next:style=Heavy Italic", halign = "center", valign = "center");
}

// ---------- base ----------
module base2d() {
  offset(r = BASE_CORNER) square([BASE_W - 2 * BASE_CORNER, BASE_D - 2 * BASE_CORNER], center = true);
}
// base frame: x = width, y = depth (front is -y), z = up
module base() {
  difference() {
    union() {
      linear_extrude(BASE_H - BASE_R) base2d();
      translate([0, 0, BASE_H - BASE_R - 0.01]) domed(BASE_R, BASE_R) base2d();
    }
    // ring slot: the ring's own shape plus a little play
    translate([0, RING_BACK, RING_CY]) rotate([90, 0, 0])
      difference() {
        cylinder(r = RING_OUT + 0.25, h = RING_D + 0.5, center = true, $fn = 240);
        cylinder(r = RING_IN - 0.25, h = RING_D + 2, center = true, $fn = 240);
      }
    translate([0, LABEL_Y, BASE_H - LABEL_T]) cylinder(d = LABEL_D, h = 5, $fn = 128);
    // NFC pocket, open underneath; the sticker goes on its ceiling, right under the label
    translate([0, LABEL_Y, -1]) cylinder(d = TAG_D, h = 1 + BASE_H - LABEL_T - TAG_COVER, $fn = 128);
    if (ENGRAVE) translate([0, -BASE_D / 2 + ENGRAVE_DEPTH, BASE_TEXT_Z]) rotate([90, 0, 0]) linear_extrude(3)
      text(BASE_TEXT, size = BASE_TEXT_SIZE, font = FONT, halign = "center", valign = "center", spacing = 1.12);
    if (ENGRAVE) translate([0, 0, BASE_H - ENGRAVE_DEPTH]) linear_extrude(ENGRAVE_DEPTH + 1) base_top_text2d();
    base_marks_cut();
  }
}

// the FavCircles mark: a heart inside a ring
module logo2d(d) { ring2d(d / 2 - d * 0.07, d * 0.11); translate([0, -d * 0.02]) polygon(heart_pts(d * 0.24)); }
// back nameplate: logo, FAVCIRCLES, the city and year, in a rounded frame (seen from behind: x flipped)
module back_stamp2d() {
  difference() { offset(r = 2.5) square([66, 9.5], center = true); offset(r = 1.7) square([66, 9.5], center = true); }
  translate([-26.5, 0]) logo2d(10.5);
  translate([-19, 1.9]) text("FAVCIRCLES", size = 3.6, font = FONT, halign = "left", valign = "center", spacing = 1.12);
  translate([-19, -3.1]) text(str(CITY, " · EST. 2026"), size = 2.4, font = FONT, halign = "left", valign = "center", spacing = 1.15);
}
// under the base, behind the NFC pocket: the maker's mark. Model-frame top view; it reads correctly
// when the base is tipped over toward you (front edge away), so each line is flipped front-to-back
// and the first line is the one nearest the middle.
module mark_line(y, t, size) { translate([0, y]) mirror([0, 1, 0]) text(t, size = size, font = FONT, halign = "center", valign = "center", spacing = 1.1); }
module maker_mark2d() {
  translate([0, 9]) mirror([0, 1, 0]) logo2d(13);
  mark_line(19.5, "FAVCIRCLES", 3.8);
  if (MAKER_FOR != "") mark_line(26, str("MADE FOR ", MAKER_FOR), 3);
  mark_line(MAKER_FOR != "" ? 32 : 26, str("No. ", MAKER_NO, " · ", CITY), 3);
}
// the network on the sides: linked heads (left) and a constellation (right). Wes 2026-11-22: the
// girl-and-guy pair read as a handshake; "do the heads only on one side, and the constellation on the other"
module bust2d() { translate([0, 2]) circle(1.8, $fn = 24);                     // head
  translate([0, -3.3]) intersection() { scale([1.05, 1.1]) circle(2.8, $fn = 32); translate([-4, 0]) square([8, 3.2]); } }   // shoulders
module link2d(p, q, w = 1.0) { hull() { translate(p) circle(w / 2, $fn = 12); translate(q) circle(w / 2, $fn = 12); } }
SIDE_HEADS = [[-12, -1.8], [-5.5, 2.2], [0.5, -2.6], [6.5, 2.2], [12.5, -1.8]];
SIDE_HEAD_LINKS = [[0, 1], [1, 2], [0, 2], [2, 3], [1, 3], [3, 4], [2, 4]];
module side_heads2d() {
  for (l = SIDE_HEAD_LINKS) link2d(SIDE_HEADS[l[0]], SIDE_HEADS[l[1]]);
  for (h = SIDE_HEADS) translate(h) bust2d();
}
SIDE_STARS = [[-13, -2.5, 1.3], [-7.5, 3.5, 1.0], [-2, -3.5, 1.5], [3.5, 3, 0], [8.5, -2, 1.1], [13, 3.5, 1.4], [-4, 1.5, 0.8]];
SIDE_STAR_LINKS = [[0, 1], [0, 2], [1, 6], [6, 2], [2, 3], [1, 3], [3, 4], [3, 5], [4, 5]];
module side_constellation2d() {
  for (l = SIDE_STAR_LINKS) link2d([SIDE_STARS[l[0]][0], SIDE_STARS[l[0]][1]], [SIDE_STARS[l[1]][0], SIDE_STARS[l[1]][1]]);
  for (st = SIDE_STARS) translate([st[0], st[1]]) if (st[2] == 0) translate([0, 0.4]) polygon(heart_pts(2.6)); else circle(st[2], $fn = 24);
}

// Charlotte's crown, for the side
module crown2d() {
  polygon([[-6.5, -3.5], [6.5, -3.5], [7, 3], [3.3, 0.2], [0, 4.6], [-3.3, 0.2], [-7, 3]]);
  for (p = [[-7, 3.6], [0, 5.3], [7, 3.6]]) translate(p) circle(1.25, $fn = 20);
  translate([0, -5]) square([13, 1.6], center = true);
}

// SIGN and UP on the base top, either side of the round label
module base_top_text2d() {
  translate([-(LABEL_D / 2 + TOP_GAP), LABEL_Y]) text(TOP_WORDS[0], size = TOP_TEXT_SIZE, font = FONT, halign = "right", valign = "center", spacing = 1.08);
  translate([LABEL_D / 2 + TOP_GAP, LABEL_Y]) text(TOP_WORDS[1], size = TOP_TEXT_SIZE, font = FONT, halign = "left", valign = "center", spacing = 1.08);
}

// the back stamp, the maker's mark and the side crown, as solids to cut away
module base_marks_cut() {
  if (BACK_STAMP) translate([0, BASE_D / 2 - ENGRAVE_DEPTH, (BASE_H - BASE_R) / 2]) rotate([90, 0, 180])
    linear_extrude(3) back_stamp2d();
  if (MAKER_MARK) translate([0, 0, -1]) linear_extrude(1 + 0.6) maker_mark2d();
  if (SIDE_CROWN) translate([BASE_W / 2 - ENGRAVE_DEPTH, 0, (BASE_H - BASE_R) / 2]) rotate([90, 0, 90]) linear_extrude(3) crown2d();
  if (SIDE_PEOPLE) {
    translate([BASE_W / 2 - ENGRAVE_DEPTH, 0, 7.6]) rotate([90, 0, 90]) linear_extrude(3) side_constellation2d();  // right side, read from the right
    translate([-(BASE_W / 2 - ENGRAVE_DEPTH), 0, 7.6]) rotate([90, 0, -90]) linear_extrude(3) side_heads2d();     // left side, read from the left
  }
}

// ---------- assembly (upright: x = width, y = depth, z = up) ----------
module assembly() {
  color("green") base();
  // ring stands up: its plate-down (back) face points to +y
  translate([0, RING_BACK + RING_D / 2, RING_CY]) rotate([90, 0, 0]) color("green") ring();
  translate([0, RING_BACK, RING_CY + HEART_DY]) rotate([90, 0, 0]) color("orange") {
    heart_half(true);                     // outer face (local +z) ends up facing -y, the customer
    mirror([0, 0, 1]) heart_half(false);
  }
}

if (part == "ring") ring();
else if (part == "heart_front") heart_half(true);
else if (part == "heart_back") heart_half(false);
else if (part == "heart_plate") { translate([-40, 0, 0]) heart_half(true); translate([40, 0, 0]) heart_half(false); }
else if (part == "base") base();
else if (part == "paint") intersection() {   // just the paint that fills the engraving (viewer)
  translate([0, 0, -1]) linear_extrude(HALF_T + 2) heart_design();
  difference() { heart_body(); translate([0, 0, -ENGRAVE_DEPTH]) heart_body(); }
}
else if (part == "heart_painted") {   // preview: the design filled with white paint
  color("orange") heart_half(true);
  color("white") intersection() {
    translate([0, 0, -1]) linear_extrude(HALF_T + 2) heart_design();
    difference() { heart_body(); translate([0, 0, -ENGRAVE_DEPTH]) heart_body(); }
  }
}
else if (part == "none") { }   // for files that include this one
else assembly();
