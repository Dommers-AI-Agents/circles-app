// Favvy, redesigned as printable 3D figures (Wes, 2026-11-17: "more attractive,
// interesting, alluring, unique"). A rounded heart instead of the flat cut-out,
// and the face drawn ON the heart as raised color, no white sticker disc. The
// NFC tag sits inside, behind the eyes.
//
//   openscad -D 'variant="puff"' -o puff.png favvy3d.scad
// variants: "puff", "pin", "wink", "gem", "explorer"

variant = "puff";
$fn = 120;

PINK = "#f4567f"; DEEP = "#c8305e"; INK = "#2b1430"; WHITE = "#ffffff";
CHEEK = "#ff6f98"; MOUTH = "#7a1838"; TONGUE = "#ff7c9c"; GOLD = "#f2c230";

body_color = variant == "wink" ? "#ff6560" : variant == "gem" ? "#d8285f" : variant == "pin" ? "#f24b6a" : variant == "explorer" ? "#e8467a" : PINK;
limb_color = variant == "wink" ? "#e8484f" : variant == "gem" ? GOLD : variant == "pin" ? "#d93a5e" : DEEP;

// heart geometry: two lobes and a tip, hulled; `g` grows it (for decals)
lobe_r = 20; lobe_x = 15; lobe_z = 52;
tip_z  = variant == "pin" ? 6 : variant == "gem" ? 12 : 21;
tip_r  = variant == "pin" ? 2 : variant == "gem" ? 4 : 13;
depth  = 0.64;
gem_fn = 9;

module heart(g = 0) {
    fn = variant == "gem" ? gem_fn : $fn;
    scale([1, depth, 1]) union() {
        hull() { translate([-lobe_x, 0, lobe_z]) sphere(lobe_r + g, $fn = fn); translate([0, 0, tip_z]) sphere(tip_r + g, $fn = fn); }
        hull() { translate([ lobe_x, 0, lobe_z]) sphere(lobe_r + g, $fn = fn); translate([0, 0, tip_z]) sphere(tip_r + g, $fn = fn); }
    }
}

// A flat 2D shape (x across, y up) pressed onto the front of the heart as a
// raised layer between heart(g0) and heart(g1)
module decal(g0, g1) {
    intersection() {
        difference() { heart(g1); heart(g0); }
        rotate([90, 0, 0]) linear_extrude(height = 80) children();
    }
}

module oval(x, z, rx, rz, a = 0) { translate([x, z]) rotate(a) scale([rx, rz]) circle(1); }
module arc2d(x, z, r, w) { translate([x, z]) intersection() {
    difference() { circle(r); circle(r - w); }
    translate([-r, 0]) square([2 * r, r]);
} }

eye_z = 43; eye_x = 9.6;

module face() {
    wink = variant == "wink";
    happy = variant == "pin";
    // eyes
    color(INK) decal(0, 1.1) {
        if (happy) { arc2d(-eye_x, eye_z - 3, 5.2, 2); arc2d(eye_x, eye_z - 3, 5.2, 2); }
        else if (wink) { arc2d(-eye_x, eye_z - 2.5, 5, 1.9); oval(eye_x, eye_z, 4.6, 6); }
        else { oval(-eye_x, eye_z, 4.6, 6); oval(eye_x, eye_z, 4.6, 6); }
    }
    // sparkles in the eyes
    if (!happy) color(WHITE) decal(1.0, 1.6) {
        if (!wink) { oval(-eye_x + 1.7, eye_z + 2.4, 1.9, 1.9); oval(-eye_x - 1.6, eye_z - 2.4, 0.8, 0.8); }
        oval(eye_x + 1.7, eye_z + 2.4, 1.9, 1.9); oval(eye_x - 1.6, eye_z - 2.4, 0.8, 0.8);
    }
    // cheeks
    color(CHEEK) decal(0, 0.7) { oval(-18, 35.5, 5.2, 3.0); oval(18, 35.5, 5.2, 3.0); }
    // mouth: an open smile
    color(MOUTH) decal(0, 0.9) translate([wink ? 1 : 0, 0]) intersection() {
        translate([0, 36.5]) circle(happy ? 5.6 : 5.2);
        translate([-7, 29]) square([14, 7.5]);
    }
    color(TONGUE) decal(0.8, 1.2) translate([wink ? 2.5 : 0, 0]) oval(0, 32.6, wink ? 2.4 : 2.2, wink ? 3.4 : 1.4);
}

module capsule(a, b, r1, r2) { hull() { translate(a) sphere(r1); translate(b) sphere(r2); } }

module limbs() {
    color(limb_color) {
        if (variant == "puff" || variant == "gem") {
            capsule([-30, 0, 40], [-41, -2, 57], 5, 6);
            capsule([ 30, 0, 40], [ 41, -2, 57], 5, 6);
        } else if (variant == "pin") {
            // hands on its cheeks
            translate([-23, -9, 33]) scale([1, 0.8, 1]) sphere(5.6);
            translate([ 23, -9, 33]) scale([1, 0.8, 1]) sphere(5.6);
        } else if (variant == "wink") {
            capsule([-30, 0, 36], [-38, -3, 24], 5, 6);
            capsule([ 30, 0, 44], [ 42, -2, 68], 5, 6);       // waving
        } else if (variant == "explorer") {
            capsule([-30, 0, 38], [-21, -14, 24], 5, 5.5);
            capsule([ 30, 0, 38], [ 21, -14, 24], 5, 5.5);
        }
        if (variant != "pin" && variant != "gem")
            for (s = [-1, 1]) translate([s * 9, -1, 4]) scale([1.4, 1.9, 0.8]) sphere(6);
    }
}

module base() {
    if (variant == "pin") {
        color("#ffffff") cylinder(r1 = 33, r2 = 32, h = 4);
        color(body_color) for (r = [10, 19, 28]) translate([0, 0, 3.8])
            difference() { cylinder(r = r, h = 1.2); translate([0, 0, -1]) cylinder(r = r - 1.6, h = 4); }
        color(DEEP) translate([0, 0, 4]) cylinder(r = 4, h = 1.6);
    } else if (variant == "gem") {
        color(GOLD) { cylinder(r1 = 24, r2 = 16, h = 9, $fn = 8); translate([0, 0, 9]) cylinder(r1 = 9, r2 = 12, h = 4, $fn = 8); }
    } else {
        color("#ffffff") translate([0, 0, -5]) cylinder(r1 = 31, r2 = 30, h = 5);
    }
}

module beret() {
    color("#4b2a66") {
        translate([4, 0, 70]) rotate([0, -14, 0]) scale([1.05, 0.8, 0.36]) sphere(21);
        translate([6, 0, 78]) sphere(2.6);
    }
}

module map() {
    // three folded panels held in front of the tummy
    panels = [[[-17, 21], [-6, 23]], [[-6, 23], [6, 21]], [[6, 21], [17, 23]]];
    for (i = [0 : 2]) color(i == 1 ? "#f3dfae" : "#fff4d8")
        hull() for (p = panels[i]) translate([p[0], -24 + (i == 1 ? 1.2 : 0), p[1]]) cube([0.01, 1.2, 14]);
    color("#1a9a8f") for (k = [0 : 5]) translate([-14 + k * 5.4, -24.6, 26 + 4 * sin(k * 70)]) rotate([90, 0, 0]) cylinder(r = 0.9, h = 0.6);
    color(PINK) translate([14, -24.8, 30]) rotate([90, 0, 0]) cylinder(r = 2.2, h = 0.8);
}

module sparkle(p, s) { color(GOLD) translate(p) scale(s) {
    hull() { cube([0.6, 0.6, 6], center = true); cube([1.6, 1.6, 0.1], center = true); }
    hull() { cube([6, 0.6, 0.6], center = true); cube([0.1, 1.6, 1.6], center = true); }
} }

module figure() {
    tilt = variant == "wink" ? -9 : 0;
    lift = variant == "gem" ? 8 : variant == "pin" ? 0 : 0;
    base();
    translate([0, 0, lift]) rotate([0, tilt, 0]) {
        color(body_color) heart();
        face();
        limbs();
        if (variant == "explorer") { beret(); map(); }
    }
    if (variant == "gem") { sparkle([38, -6, 82], 1.3); sparkle([-40, -4, 30], 0.9); }
}

figure();
