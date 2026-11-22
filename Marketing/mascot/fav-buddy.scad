// FavCircles register mascot — "Fav", the tap buddy.
// One shared body for every city; the city's accessory plugs onto the
// peg on top of the head; the round belly badge covers an NFC tag.
//
// Parts (set `part` or pass -D 'part="crown"' on the command line):
//   "body"      shared body, print upright, no supports
//   "badge"     belly "TAP" badge, print face up (swap filament at the
//               raised layer for a two-color badge)
//   "crown"     Charlotte accessory (Queen City crown), print upright
//   "assembled" preview of the whole figure
//   "exploded"  preview with parts pulled apart
//
// Units: millimetres. Designed for FDM, 0.4 mm nozzle, PLA.

part = "assembled";

$fn = 96;

// ---------- shared dimensions ----------
body_rx = 32;          // half width
body_ry = 27.2;        // half depth
body_rz = 43.2;        // half height of the egg
body_cz = 26;          // egg centre height (bottom is cut flat at z = 0)
top_cut = 64;          // flat "hat platform" on the head
belly_plane = -22;     // y of the flat belly face (front is -y)
belly_cz = 22;         // belly badge centre height
belly_flat_r = 19;     // flat ring around the badge
badge_r = 17;          // badge radius (34 mm across)
badge_t = 2.6;         // badge thickness = distance from tag to phone
fit = 0.25;            // clearance for press fits
tag_r = 15.5;          // pocket for a 25-30 mm round NTAG215 sticker
tag_depth = 0.6;

peg_r = 3.6;           // accessory peg on the head
peg_h = 4.5;
peg_flat = 2.6;        // flat side on the peg so accessories face forward

// ---------- helpers ----------
module egg() {
    translate([0, 0, body_cz]) scale([body_rx, body_ry, body_rz]) sphere(r = 1, $fn = 128);
}

module keyed_peg(r, h) {
    intersection() {
        cylinder(r = r, h = h);
        translate([-r, -r, 0]) cube([2 * r, r + peg_flat, h]);   // flat on the back (+y)
    }
}

// ---------- body ----------
module body() {
    difference() {
        union() {
            intersection() {
                egg();
                translate([-50, -50, 0]) cube([100, 100, top_cut]);
            }
            // little arms
            for (s = [-1, 1])
                translate([s * (body_rx - 2.5), -2, 25])
                    rotate([0, s * -20, 0]) scale([0.8, 0.7, 1.45]) sphere(r = 6.5);
            // accessory peg
            translate([0, 0, top_cut - 0.01]) keyed_peg(peg_r, peg_h);
        }
        // flat belly face (a circle, like the FavCircles mark)
        translate([0, belly_plane, belly_cz]) rotate([90, 0, 0]) cylinder(r = belly_flat_r, h = 20);
        // badge recess
        translate([0, belly_plane - 1, belly_cz]) rotate([-90, 0, 0])
            cylinder(r = badge_r + fit, h = badge_t + 1);
        // NFC tag pocket behind the badge
        translate([0, belly_plane + badge_t - 0.01, belly_cz]) rotate([-90, 0, 0])
            cylinder(r = tag_r, h = tag_depth);
        // eyes (engraved; they read as eyes in any filament color)
        for (s = [-1, 1])
            translate([s * 9, -30, 52]) rotate([-90, 0, 0])
                scale([1, 1.35, 1]) cylinder(r = 2.6, h = 12.5);
        // smile
        translate([0, -30, 46.8]) rotate([-90, 0, 0])
            difference() {
                cylinder(r = 5, h = 7.2);
                translate([0, 0, -1]) cylinder(r = 3.6, h = 12);
                translate([-10, -20, -1]) cube([20, 20, 14]);   // keep the lower half = a smile
            }
        // optional felt / anti-slip pad recess under the base
        translate([0, 0, -0.01]) cylinder(r = 20, h = 0.6);
    }
}

// ---------- belly badge ----------
module badge() {
    t_face = 0.8;   // raised artwork height (swap filament here)
    cylinder(r = badge_r, h = badge_t - t_face);
    translate([0, 0, badge_t - t_face - 0.01]) {
        // outer ring
        difference() {
            cylinder(r = badge_r - 1.0, h = t_face);
            translate([0, 0, -1]) cylinder(r = badge_r - 2.6, h = t_face + 2);
        }
        // TAP
        translate([0, 1.2, 0]) linear_extrude(t_face)
            text("TAP", size = 7.2, font = "Arial Rounded MT Bold", halign = "center", valign = "center");
        // three little circles under the word (FavCircles nod)
        for (i = [-1, 0, 1])
            translate([i * 4.2, -7.2, 0]) difference() {
                cylinder(r = 1.6, h = t_face);
                translate([0, 0, -1]) cylinder(r = 0.7, h = t_face + 2);
            }
    }
}

// ---------- city accessory base: every accessory starts with this ----------
module accessory_socket_base(r_base, h_base) {
    difference() {
        children();
        translate([0, 0, -0.01]) keyed_peg(peg_r + fit, peg_h + 0.6);
    }
}

// ---------- Charlotte: Queen City crown ----------
crown_r_bottom = 13.8;   // band radius where it sits on the head
crown_r_top = 15.6;      // flares outward like a real crown
crown_wall = 2.2;
crown_floor = peg_h + 1.0;
crown_band_h = 4.5;      // band height above the floor
crown_points = 5;
crown_point_h = 9;

module crown() {
    top = crown_floor + crown_band_h;
    r_in_top = crown_r_top - crown_wall;
    accessory_socket_base() union() {
        // flared band with a solid floor that sits on the head platform
        difference() {
            cylinder(r1 = crown_r_bottom, r2 = crown_r_top, h = top);
            translate([0, 0, crown_floor]) cylinder(r1 = crown_r_bottom - crown_wall, r2 = r_in_top, h = top);
        }
        // trim rings
        translate([0, 0, 0.9]) rotate_extrude($fn = 96) translate([crown_r_bottom + 0.1, 0]) circle(r = 0.9, $fn = 24);
        translate([0, 0, top - 0.6]) rotate_extrude($fn = 96) translate([crown_r_top, 0]) circle(r = 0.9, $fn = 24);
        // points with ball tips; one faces straight forward (-y)
        for (i = [0 : crown_points - 1]) {
            a = 90 + i * 360 / crown_points;
            r_mid = crown_r_top - crown_wall / 2 + 1.2;   // points lean out a little
            hull() {
                intersection() {
                    difference() {
                        translate([0, 0, top - 0.01]) cylinder(r = crown_r_top, h = 0.6);
                        translate([0, 0, top - 1]) cylinder(r = r_in_top, h = 3);
                    }
                    rotate([0, 0, -a]) translate([0, 0, top - 1])
                        linear_extrude(3) polygon([[0, 0], [40 * cos(-34), 40 * sin(-34)], [40 * cos(34), 40 * sin(34)]]);
                }
                rotate([0, 0, -a]) translate([r_mid, 0, top + crown_point_h]) sphere(r = 0.9, $fn = 24);
            }
            rotate([0, 0, -a]) translate([r_mid, 0, top + crown_point_h + 1.5]) sphere(r = 2.2, $fn = 40);
            // jewel on the band under each point
            rotate([0, 0, -a]) translate([(crown_r_bottom + crown_r_top) / 2 - 0.3, 0, top / 2 + 0.6])
                scale([0.6, 1, 1]) sphere(r = 1.8, $fn = 32);
        }
    }
}

// ---------- layout ----------
body_color = "#7b5cd6";
badge_color = "#ffffff";
crown_color = "#f2c230";

module assembled(gap = 0) {
    color(body_color) body();
    color(badge_color)
        translate([0, belly_plane - gap * 1.6, belly_cz]) rotate([90, 0, 0])
            translate([0, 0, -badge_t]) badge();
    color(crown_color) translate([0, 0, top_cut + gap * 1.4]) crown();
}

if (part == "body") body();
else if (part == "badge") badge();
else if (part == "crown") crown();
else if (part == "exploded") assembled(gap = 12);
else assembled();
