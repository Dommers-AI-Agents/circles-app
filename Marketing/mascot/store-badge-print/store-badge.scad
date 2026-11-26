// Store badges: a small shape of the store's own, taped by the register, that makes someone ask what
// it is (Wes, 2026-11-26: "what else can we come up with around this size that we can double sided
// tape stick near the register that will make some curious what it is? And perhaps we make them unique
// per store. For example, a monkey for fresh monkee, a race car for caffeena. And matching the logo
// for Port Coffee.")
// Every badge: flat back for tape, the store's 1½ in "TAP OR SCAN" label over an NFC sticker in the
// round recess, the store's name, and "SAVE US ON FAVCIRCLES" (an invitation, never points).
// Printed flat, face up, no supports. Body one colour, everything raised a second: ONE filament
// change at z = T_BASE (3.2 mm).
//   store="monkee"     Fresh Monkee: a winking monkey holding the label          (window code JKI750)
//   store="caffeena"   Caffeena Coffee House: a car parked on the label          (FHVMPK; the Griffith St
//                      shop shares its building with an exotic-car showroom and has racing simulators)
//   store="port"       Port Coffee: their round badge, the ship riding the label (4HOA4V)
//   store="show"       preview of all three, in each store's colours
// The drawings are simplified for a 0.4 mm nozzle; they follow each store's logo, they don't copy it.
include <../tap-plaque-print/tap-plaque.scad>
design = "none";          // tap-plaque.scad draws nothing: it lends the plaque body, lettering and fit()
store = "show";

B_DISC = 25.5;            // the disc the label sits in
B_COLLAR = T_LABEL_D / 2 + 2.2;
P_W = 86; P_H = 19; P_TOP = -20.5; P_CORNER = 6;      // the name plate under the label

// text reading left to right along the BOTTOM of a circle (letters upright, tops toward the centre)
module arc_text_under2d(t, r, size, track = 0.12) {
  em = size * 1.38;
  total = (cwsum(t, len(t)) + track * (len(t) - 1)) * em;
  for (i = [0:len(t) - 1]) {
    mid = (cwsum(t, i) + track * i + cw(t[i]) / 2) * em - total / 2;
    a = -90 + mid / r * 180 / PI;
    translate([r * cos(a), r * sin(a)]) rotate(a + 90)
      text(t[i], size = size, font = FONT, halign = "center", valign = "center");
  }
}
module plate2d() { translate([0, P_TOP - P_H / 2]) offset(r = P_CORNER) square([P_W - 2 * P_CORNER, P_H - 2 * P_CORNER], center = true); }
module plate_words2d(name) {
  translate([0, P_TOP - 7.2]) words(name, fit(name, P_W - 10, 5.6), 1.14);
  translate([0, P_TOP - 14.6]) words("SAVE US ON FAVCIRCLES", fit("SAVE US ON FAVCIRCLES", P_W - 12, 3.4), 1.14);
}
module collar2d() { ring2d(B_COLLAR, 1.4); }
module line(p, q, w) { hull() { translate(p) circle(w / 2, $fn = 20); translate(q) circle(w / 2, $fn = 20); } }

// ---------- Fresh Monkee ----------
M_Y = 40;                 // head centre above the label centre
module monkee2d() {
  circle(B_DISC, $fn = 128); plate2d();
  translate([0, M_Y]) { scale([1.08, 1]) circle(23, $fn = 96); for (s = [-1, 1]) translate([s * 26.5, -4]) circle(9.5, $fn = 64); }
  // the tuft, flicking right
  translate([0, M_Y]) offset(r = 1.2) polygon([[-7, 20], [-1, 28], [1.5, 23.5], [8, 29], [10, 19]]);
  // paws over the label's edge
  for (s = [-1, 1]) for (a = [50]) translate([s * 23.5 * cos(a), 23.5 * sin(a)]) circle(8, $fn = 48);
}
module monkee_raised2d() {
  translate([0, M_Y]) {
    for (s = [-1, 1]) translate([s * 27.2, -4]) circle(4.8, $fn = 48);                    // inner ears
    difference() {
      union() {                                                                         // the face mask
        hull() for (s = [-1, 1]) translate([s * 8.6, 6]) circle(8.6, $fn = 64);
        translate([0, -6]) scale([17, 10.2]) circle(1, $fn = 96);
      }
      translate([-8, 6.4]) scale([2.3, 3.0]) circle(1, $fn = 32);                        // open eye
      translate([8.2, 4.4]) arc2d(3.6, 25, 155, 1.5);                                    // the wink
      for (s = [-1, 1]) translate([s * 2.3, -2.6]) circle(1.0, $fn = 20);                // nostrils
      translate([0, -1.2]) arc2d(11.2, 208, 332, 1.7);                                   // smile
    }
  }
  // fingers gripping the label's edge
  for (s = [-1, 1]) for (a = [36, 45, 54, 63]) line([s * 20.6 * cos(a), 20.6 * sin(a)], [s * 26.4 * cos(a), 26.4 * sin(a)], 2.5);
  plate_words2d("FRESH MONKEE");
}

// ---------- Caffeena ----------
C_Y = 19;                 // the car's ground line above the label centre
module car2d() {
  offset(r = 1) offset(delta = -1) {
    polygon([[-44, 6], [-44, 13], [-40, 17], [-30, 18.5], [-18, 25], [-2, 26], [10, 22], [24, 15.5], [38, 12.5], [44, 9], [44, 5], [40, 3.5], [-41, 3.5]]);
    polygon([[-45, 22.5], [-45, 25.5], [-33, 26.5], [-33, 23.5]]);                       // rear wing
    polygon([[-41.5, 16], [-41.5, 24], [-38, 24], [-37, 17.5]]);
  }
  for (x = [-27, 27]) translate([x, 7]) circle(8.5, $fn = 64);
}
module car_raised2d() {
  for (x = [-27, 27]) translate([x, 7]) { ring2d(6.6, 1.6); circle(2.4, $fn = 32); }     // tyres and hubs
  polygon([[-15.2, 23], [-3.6, 23.8], [-3.6, 17.2], [-20.5, 17.2]]);                     // windows
  polygon([[-1.2, 23.8], [7.6, 20.6], [14.6, 17.2], [-1.2, 17.2]]);
  translate([0, 9.6]) { ring2d(4.7, 1.2); text("C", size = 4.6, font = FONT, halign = "center", valign = "center"); }
  polygon([[36.5, 11.6], [42.5, 9.4], [42.5, 7.6], [35, 9.8]]);                          // headlight
}
module caffeena2d() { circle(B_DISC, $fn = 128); plate2d(); translate([0, C_Y]) car2d(); }
module caffeena_raised2d() { collar2d(); translate([0, C_Y]) car_raised2d(); plate_words2d("CAFFEENA"); }

// ---------- Port Coffee ----------
PORT_R = 50; PORT_LABEL_Y = -7;
module port2d() { circle(PORT_R, $fn = 200); }
module port_raised2d() {
  ring2d(PORT_R - 2.6, 1.4);
  arc_text2d("PORT COFFEE CO", 40.2, 5.6, 0.14);
  arc_text_under2d("SAVE US ON FAVCIRCLES", 41.4, 3.5, 0.16);
  for (s = [-1, 1]) translate([s * 41, 3]) square([1.2, 3.6], center = true);            // the dashes at 9 and 3
  translate([0, PORT_LABEL_Y]) {
    collar2d();
    // the saucer swoosh: a crescent under and left of the bowl, tapering to points
    difference() { translate([-2.4, -2.4]) circle(26.4, $fn = 128); circle(B_COLLAR + 1.9, $fn = 128); }
    // the ship, riding the top of the label, bow to the right
    translate([0, 3.2]) {
      difference() {
        polygon([[-17.5, 19.6], [15, 19.6], [23, 27.4], [-19.5, 24.6]]);
        for (x = [-5, -0.8, 3.4]) translate([x, 22.6 + x * 0.04]) circle(0.95, $fn = 20);
      }
      polygon([[-14, 25.6], [-11.6, 29.6], [4.6, 29.6], [10.6, 26.6]]);
      polygon([[-9.4, 30.2], [-7.6, 32.8], [0.4, 32.8], [2.6, 30.2]]);
      translate([-4.4, 34.4]) arc2d(1.5, 100, 260, 0.9);                                  // steam
      translate([-4.4, 37.3]) arc2d(1.5, -80, 80, 0.9);
    }
  }
}

// ---------- parts ----------
module badge_body(label_y = 0) { plaque_body(label_y) children(); }
module monkee_body() { badge_body() monkee2d(); }      module monkee_up() { plaque_up() monkee_raised2d(); }
module caffeena_body() { badge_body() caffeena2d(); }  module caffeena_up() { plaque_up() caffeena_raised2d(); }
module port_body() { badge_body(PORT_LABEL_Y) port2d(); } module port_up() { plaque_up() port_raised2d(); }

if (store == "monkee") { monkee_body(); monkee_up(); }
else if (store == "caffeena") { caffeena_body(); caffeena_up(); }
else if (store == "port") { port_body(); port_up(); }
else if (store == "show") {
  translate([-105, -12, 0]) { color("#3c2415") monkee_body(); color("#f6efe2") monkee_up(); label_dot(0); }
  translate([0, 0, 0]) { color("#2b1707") caffeena_body(); color("#d49c60") caffeena_up(); label_dot(0); }
  translate([108, 0, 0]) { color("#272b4a") port_body(); color("#ffffff") port_up(); label_dot(PORT_LABEL_Y); }
}
