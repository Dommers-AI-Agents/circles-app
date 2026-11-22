// Pinny — the FavCircles map-pin mascot.
// The pin's round hole is Pinny's face: a white disc with eyes, smile and
// cheeks, glued over the NFC tag. Customers tap Pinny's face.
// Same city-accessory peg on top as Fav (crown etc. from fav-buddy.scad).
//
// Parts (-D 'part="..."'):
//   "body"          red pin with arms, feet, eyebrows and base   (color 1)
//   "base_text"     raised "TAP MY FACE" on the base                 (color 2, white)
//   "face"          white face disc                              (color 2, white)
//   "face_features" eyes + smile on the face                     (color 3, dark)
//   "face_cheeks"   cheeks on the face                           (color 4, pink)
//   "crown"         Charlotte crown                              (gold)
//   "assembled" / "exploded"  previews
// Load body + base_text together, and face + face_features + face_cheeks
// together, as single objects with multiple parts in Bambu Studio, then pick a
// filament per part.

use <fav-buddy.scad>

part = "assembled";
$fn = 96;

fit = 0.25;
face_r = 17;          // 34 mm face disc
face_t = 2.0;         // tag sits 2.0 mm behind the face surface (closer = more reliable tap)
feat_t = 0.8;         // raised eyes / smile / cheeks
tag_r = 15.5;
peg_r = 3.6;
peg_h = 4.5;

head_r = 31;
head_cz = 60;
tip_z = 15;
top_cut = 88;
face_plane = -23;     // y of the flat face (front is -y)
face_cz = 57;
base_h = 5;

pin_red = "#e5484d";

module peg_at(z) { translate([0, 0, z - 0.01]) intersection() {
    cylinder(r = peg_r, h = peg_h);
    translate([-peg_r, -peg_r, 0]) cube([2 * peg_r, peg_r + 2.6, peg_h]);
} }

module pin_shape() {
    intersection() {
        hull() {
            translate([0, 0, head_cz]) sphere(r = head_r, $fn = 128);
            translate([0, 0, tip_z]) sphere(r = 4);
        }
        translate([-60, -60, 0]) cube([120, 120, top_cut]);
    }
}

module arms() {
    // cheering: both arms up at about 45 degrees (prints without supports)
    for (s = [-1, 1]) {
        hull() {
            translate([s * 25, -2, head_cz - 2]) sphere(r = 5.2);
            translate([s * 37, -3, head_cz + 10]) sphere(r = 4.6);
        }
        translate([s * 38.5, -3.5, head_cz + 12]) sphere(r = 5.4);   // hand
    }
}

module feet() {
    for (s = [-1, 1])
        translate([s * 7, -5, base_h + 2.2]) rotate([0, 0, s * -14]) scale([1, 1.7, 0.75]) sphere(r = 5);
}

module eyebrows() {
    // happy arched brows above the face
    for (s = [-1, 1]) {
        hull() {
            translate([s * 3.8, -26.2, 79.4]) sphere(r = 1.3, $fn = 24);
            translate([s * 7.2, -25.6, 81.2]) sphere(r = 1.3, $fn = 24);
        }
        hull() {
            translate([s * 7.2, -25.6, 81.2]) sphere(r = 1.3, $fn = 24);
            translate([s * 10.6, -24.2, 79.6]) sphere(r = 1.3, $fn = 24);
        }
    }
}

module base() {
    // the "spot" Pinny points at
    difference() {
        cylinder(r1 = 28, r2 = 26.5, h = base_h);
        translate([0, 0, base_h - 0.6]) difference() {
            cylinder(r = 24.2, h = 1);
            translate([0, 0, -1]) cylinder(r = 22.8, h = 3);
        }
    }
    translate([0, 0, base_h - 0.01]) cylinder(r1 = 7, r2 = 4.6, h = tip_z - base_h);
}

module base_text() {
    translate([0, -20.2, base_h - 0.01]) linear_extrude(0.8)
        text("TAP MY FACE", size = 3.3, font = "Arial Rounded MT Bold", halign = "center", valign = "center");
}

module body() {
    difference() {
        union() {
            pin_shape();
            base();
            feet();
            arms();
            eyebrows();
            peg_at(top_cut);
        }
        // flat circle (the pin hole) + face recess + tag pocket
        translate([0, face_plane, face_cz]) rotate([90, 0, 0]) cylinder(r = face_r + 2.2, h = 30);
        translate([0, face_plane - 1, face_cz]) rotate([-90, 0, 0]) cylinder(r = face_r + fit, h = face_t + 1);
        translate([0, face_plane + face_t - 0.01, face_cz]) rotate([-90, 0, 0]) cylinder(r = tag_r, h = 0.6);
        // room for the raised text so the two parts don't overlap
        translate([0, -20.2, base_h - 0.02]) linear_extrude(1)
            offset(r = 0.05) text("TAP MY FACE", size = 3.3, font = "Arial Rounded MT Bold", halign = "center", valign = "center");
        // felt pad recess
        translate([0, 0, -0.01]) cylinder(r = 22, h = 0.6);
    }
}

// ---------- face (printed face up; features sit on top) ----------
module face() { cylinder(r = face_r, h = face_t); }

module eye_shape(s) {
    difference() {
        translate([s * 6.2, 3.2]) scale([1, 1.4]) circle(r = 3.1);
        translate([s * 6.2 + 1.1, 5.0]) circle(r = 1.05);        // highlight shows the white face
    }
}
module face_features() {
    translate([0, 0, face_t - 0.01]) linear_extrude(feat_t) {
        eye_shape(-1);
        eye_shape(1);
        // smile
        translate([0, -2.6]) difference() {
            circle(r = 5.4);
            circle(r = 3.9);
            translate([-10, 0]) square([20, 10]);
        }
    }
}
module face_cheeks() {
    translate([0, 0, face_t - 0.01]) linear_extrude(feat_t * 0.75)
        for (s = [-1, 1]) translate([s * 11.2, -3.4]) scale([1.25, 1]) circle(r = 2.3);
}

// ---------- previews ----------
module face_assembly(gap = 0) {
    translate([0, face_plane - gap, face_cz]) rotate([90, 0, 0]) translate([0, 0, -face_t]) {
        color("white") face();
        color("#2b2340") face_features();
        color("#ff8fa3") face_cheeks();
    }
}
module assembled(gap = 0) {
    color(pin_red) body();
    color("white") base_text();
    face_assembly(gap * 1.6);
    color("#f2c230") translate([0, 0, top_cut + gap * 1.3]) crown();
}

if (part == "body") body();
else if (part == "base_text") base_text();
else if (part == "face") face();
else if (part == "face_features") face_features();
else if (part == "face_cheeks") face_cheeks();
else if (part == "crown") crown();
else if (part == "exploded") assembled(gap = 14);
else assembled();
