// More FavCircles register characters. Same system as Pinny:
//   - the white FACE disc is the tap target; the NFC tag sits 2 mm behind it
//   - a keyed peg on top takes any city accessory (Charlotte crown shown)
//   - every character stands on a round base with "TAP MY FACE"
//
//   openscad -D 'character="owl"' -D 'part="assembled"' -o out.png characters.scad
// characters: "heart" (Favvy), "star" (Goldie), "cup" (Cuppa), "owl" (Hoot)
// parts: "assembled", "body", "base_text", "face", "face_features", "face_accent", "crown"

use <fav-buddy.scad>   // crown()

character = "heart";
part = "assembled";
$fn = 72;

fit = 0.25;
face_r = 17;
face_t = 2.0;
feat_t = 0.8;
tag_r = 15.5;
peg_r = 3.6;
peg_h = 4.5;
base_h = 5;

// ---------------- shared kit ----------------
module peg_at(z) { translate([0, 0, z - 0.01]) intersection() {
    cylinder(r = peg_r, h = peg_h);
    translate([-peg_r, -peg_r, 0]) cube([2 * peg_r, peg_r + 2.6, peg_h]);
} }

module face_cuts(yp, cz, ring = 19.2) {
    translate([0, yp, cz]) rotate([90, 0, 0]) cylinder(r = ring, h = 40);
    translate([0, yp - 1, cz]) rotate([-90, 0, 0]) cylinder(r = face_r + fit, h = face_t + 1);
    translate([0, yp + face_t - 0.01, cz]) rotate([-90, 0, 0]) cylinder(r = tag_r, h = 0.6);
}

module base_plate(r = 27) {
    difference() {
        cylinder(r1 = r + 1.5, r2 = r, h = base_h);
        translate([0, 0, base_h - 0.6]) difference() { cylinder(r = r - 2.3, h = 1); translate([0, 0, -1]) cylinder(r = r - 3.7, h = 3); }
        translate([0, 0, -0.01]) cylinder(r = r - 6, h = 0.6);   // felt pad recess
    }
}
module base_label(y) {
    translate([0, y, base_h - 0.01]) linear_extrude(0.8)
        text("TAP MY FACE", size = 3.3, font = "Arial Rounded MT Bold", halign = "center", valign = "center");
}
module base_label_room(y) {
    translate([0, y, base_h - 0.02]) linear_extrude(1) offset(r = 0.05)
        text("TAP MY FACE", size = 3.3, font = "Arial Rounded MT Bold", halign = "center", valign = "center");
}
module feet(y = -5, spread = 7) {
    for (s = [-1, 1]) translate([s * spread, y, base_h + 2.2]) rotate([0, 0, s * -14]) scale([1, 1.7, 0.75]) sphere(r = 5);
}
module cheer_arms(x0, z0, y0 = -2) {
    for (s = [-1, 1]) {
        hull() { translate([s * x0, y0, z0]) sphere(r = 5); translate([s * (x0 + 11), y0 - 1, z0 + 11]) sphere(r = 4.5); }
        translate([s * (x0 + 12.5), y0 - 1.5, z0 + 13]) sphere(r = 5.2);
    }
}
// brows: list of [x, y, z] per arch point, mirrored
module brows(pts) {
    for (s = [-1, 1]) for (i = [0 : len(pts) - 2]) hull() {
        translate([s * pts[i][0], pts[i][1], pts[i][2]]) sphere(r = 1.3, $fn = 20);
        translate([s * pts[i + 1][0], pts[i + 1][1], pts[i + 1][2]]) sphere(r = 1.3, $fn = 20);
    }
}

// ---------------- face artwork (2D, face-up) ----------------
module std_eyes() {
    for (s = [-1, 1]) difference() {
        translate([s * 6.2, 3.2]) scale([1, 1.4]) circle(r = 3.1);
        translate([s * 6.2 + 1.1, 5.0]) circle(r = 1.05);
    }
}
module std_smile() { translate([0, -2.6]) difference() { circle(r = 5.4); circle(r = 3.9); translate([-10, 0]) square([20, 10]); } }
module std_cheeks() { for (s = [-1, 1]) translate([s * 11.2, -3.4]) scale([1.25, 1]) circle(r = 2.3); }

module owl_eyes() {
    for (s = [-1, 1]) difference() {
        translate([s * 6.8, 2.6]) circle(r = 4.8);
        translate([s * 6.8 + 1.5, 4.2]) circle(r = 1.5);
    }
}
module owl_beak() { hull() { translate([-2.4, -1.4]) circle(r = 0.8); translate([2.4, -1.4]) circle(r = 0.8); translate([0, -6.4]) circle(r = 0.7); } }

module face_features_2d() { if (character == "owl") owl_eyes(); else { std_eyes(); std_smile(); } }
module face_accent_2d() { if (character == "owl") owl_beak(); else std_cheeks(); }

module face() { cylinder(r = face_r, h = face_t); }
module face_features() { translate([0, 0, face_t - 0.01]) linear_extrude(feat_t) face_features_2d(); }
module face_accent() { translate([0, 0, face_t - 0.01]) linear_extrude(feat_t * 0.75) face_accent_2d(); }

// ---------------- 1. Favvy, the heart ----------------
// "Fav" = favorite. A puffy heart; flat front holds the face.
heart_face = [-15, 51];
heart_top = 80;
module heart_2d() {
    offset(r = -4) union() {
        hull() { translate([-13, 60]) circle(r = 18); translate([0, 11]) circle(r = 4); }
        hull() { translate([13, 60]) circle(r = 18); translate([0, 11]) circle(r = 4); }
    }
}
module heart_body() {
    difference() {
        union() {
            minkowski() {
                rotate([90, 0, 0]) translate([0, 0, -11]) linear_extrude(22) heart_2d();
                sphere(r = 4, $fn = 20);
            }
            translate([0, 0, 68]) cylinder(r1 = 9, r2 = 8, h = heart_top - 68);   // neck for the accessory
            base_plate();
            translate([0, 0, base_h - 0.01]) cylinder(r1 = 7, r2 = 4.6, h = 9);
            feet();
            cheer_arms(28, 46);
            brows([[3.8, -15.3, 72.5], [7.2, -15.3, 74.3], [10.6, -15.3, 72.7]]);
            peg_at(heart_top);
        }
        face_cuts(heart_face[0], heart_face[1]);
        base_label_room(-20.2);
    }
}

// ---------------- 2. Goldie, the reward star ----------------
star_face = [-13, 42];
star_top = 76;
function star_pts(R, r) = [for (i = [0 : 9]) let(a = 90 + i * 36, rr = (i % 2 == 0) ? R : r) [rr * cos(a), rr * sin(a)]];
module star_2d() { offset(r = -3) translate([0, 42]) polygon(star_pts(44, 22)); }
module star_body() {
    difference() {
        union() {
            intersection() {
                minkowski() {
                    rotate([90, 0, 0]) translate([0, 0, -10]) linear_extrude(20) star_2d();
                    sphere(r = 3, $fn = 20);
                }
                translate([-60, -60, 0]) cube([120, 120, star_top]);
            }
            base_plate(30);
            for (s = [-1, 1]) translate([s * 25.5, -6, base_h + 2.4]) scale([1.1, 1.7, 0.75]) sphere(r = 5);   // feet under the bottom points
            brows([[3.2, -13.3, 62.4], [5.8, -13.3, 63.9], [8.2, -13.3, 62.4]]);
            peg_at(star_top);
        }
        face_cuts(star_face[0], star_face[1]);
        base_label_room(-22.5);
    }
}

// ---------------- 3. Cuppa, the coffee cup ----------------
cup_face = [-25, 30];
cup_top = 54;          // coffee surface inside the rim
cup_r1 = 29; cup_r2 = 33; cup_z0 = 2.6; cup_z1 = 56;
function cup_r(z) = cup_r1 + (cup_r2 - cup_r1) * (z - cup_z0) / (cup_z1 - cup_z0);
module cup_body() {
    difference() {
        union() {
            // saucer
            difference() {
                cylinder(r1 = 36, r2 = 43, h = 4);
                translate([0, 0, 2.6]) cylinder(r1 = 39.5, r2 = 41, h = 2);
                translate([0, 0, -0.01]) cylinder(r = 28, h = 0.6);
            }
            // cup
            translate([0, 0, cup_z0 - 0.01]) cylinder(r1 = cup_r1, r2 = cup_r2, h = cup_z1 - cup_z0);
            translate([0, 0, cup_z1]) rotate_extrude($fn = 96) translate([cup_r2 - 0.8, 0]) circle(r = 2.4, $fn = 24);
            // handle (right) — the cup's "arm"
            translate([cup_r(30) - 2, 0, 31]) rotate([90, 0, 0]) rotate_extrude(angle = 360, $fn = 64) translate([11, 0]) scale([1, 1.25]) circle(r = 3.6, $fn = 24);
            // waving arm (left)
            hull() { translate([-(cup_r(34) - 3), -2, 34]) sphere(r = 5); translate([-(cup_r(34) + 8), -3, 45]) sphere(r = 4.5); }
            translate([-(cup_r(34) + 9.5), -3.5, 47]) sphere(r = 5.2);
            // feet peeking out on the saucer
            for (s = [-1, 1]) translate([s * 15, -28, 4.4]) scale([1, 1.5, 0.7]) sphere(r = 4.6);
            brows([for (p = [[3.8, 50.3], [7.2, 52.1], [10.6, 50.5]]) [p[0], -sqrt(pow(cup_r(p[1]), 2) - p[0] * p[0]) - 0.3, p[1]]]);
        }
        // inside of the handle loop and the coffee surface
        translate([cup_r(30) - 2, 0, 31]) rotate([90, 0, 0]) cylinder(r = 7.6, h = 40, center = true);
        translate([0, 0, cup_r1 > 0 ? cup_top : 0]) cylinder(r = cup_r2 - 2.6, h = 10);
        face_cuts(cup_face[0], cup_face[1]);
    }
    peg_at(cup_top);
}
module cup_label() {   // on the saucer in front of the cup
    translate([0, -36.4, 2.59]) linear_extrude(0.8)
        text("TAP MY FACE", size = 3.1, font = "Arial Rounded MT Bold", halign = "center", valign = "center");
}

// ---------------- 4. Hoot, the local-guide owl ----------------
owl_face = [-19, 52];
owl_top = 79;
module owl_egg() { translate([0, 0, 42]) scale([31, 28, 40]) sphere(r = 1, $fn = 112); }
module owl_body() {
    difference() {
        union() {
            intersection() { owl_egg(); translate([-60, -60, 4]) cube([120, 120, owl_top - 4]); }
            base_plate(30);
            // ear tufts
            for (s = [-1, 1]) hull() { translate([s * 17, 0, 70]) sphere(r = 6.5); translate([s * 25, 0, 86]) sphere(r = 1.6); }
            // wings
            for (s = [-1, 1]) translate([s * 29.5, 3, 37]) rotate([0, s * -12, 0]) scale([0.42, 1, 1.3]) sphere(r = 14);
            // three-toed feet
            for (s = [-1, 1]) for (t = [-1, 0, 1]) translate([s * 8 + t * 3.2, -16 + abs(t) * 0.8, base_h + 1.6]) scale([0.8, 1.6, 0.7]) sphere(r = 2.6);
            brows([[4.2, -22.4, 75.6], [8.2, -21.0, 76.6], [12.4, -18.4, 74.6]]);
            peg_at(owl_top);
        }
        face_cuts(owl_face[0], owl_face[1], 20.5);
        // belly feather marks
        for (p = [[-7, 26], [7, 26], [0, 21], [-14, 20], [14, 20]])
            translate([p[0], -45, p[1]]) rotate([-90, 0, 0]) difference() {
                cylinder(r = 3.6, h = 45 - 25.2);
                translate([0, 0, -1]) cylinder(r = 2.4, h = 99);
                translate([-10, -20, -1]) cube([20, 20, 99]);
            }
        base_label_room(-24.5);
    }
}

// ---------------- dispatch ----------------
function face_pos() = character == "heart" ? heart_face : character == "star" ? star_face : character == "cup" ? cup_face : owl_face;
function top_z() = character == "heart" ? heart_top : character == "star" ? star_top : character == "cup" ? cup_top : owl_top;
function body_color() = character == "heart" ? "#ef5d8a" : character == "star" ? "#f3b52b" : character == "cup" ? "#3bb3a6" : "#9a6a45";
function accent_color() = character == "owl" ? "#f29b30" : "#ff8fa3";
function crown_color() = character == "star" ? "#7b5cd6" : "#f2c230";
function label_y() = character == "heart" ? -20.2 : character == "star" ? -22.5 : -24.5;

module body_any() {
    if (character == "heart") heart_body();
    else if (character == "star") star_body();
    else if (character == "cup") cup_body();
    else owl_body();
}
module label_any() { if (character == "cup") cup_label(); else base_label(label_y()); }

module assembled() {
    color(body_color()) body_any();
    color("white") label_any();
    if (character == "cup") color("#6b4226") translate([0, 0, cup_top]) cylinder(r = cup_r2 - 2.65, h = 0.3);
    fp = face_pos();
    translate([0, fp[0], fp[1]]) rotate([90, 0, 0]) translate([0, 0, -face_t]) {
        color("white") face();
        color("#2b2340") face_features();
        color(accent_color()) face_accent();
    }
    color(crown_color()) translate([0, 0, top_z()]) crown();
}

if (part == "body") body_any();
else if (part == "base_text") label_any();
else if (part == "face") face();
else if (part == "face_features") face_features();
else if (part == "face_accent") face_accent();
else if (part == "crown") crown();
else assembled();
