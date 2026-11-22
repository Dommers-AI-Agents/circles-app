// Alternative mascot bodies. Every option keeps the same system as Fav:
// a flat platform + keyed peg on top for the city accessory, and a round
// belly recess for the TAP badge + NFC tag. Crown/badge come from fav-buddy.scad.
//
//   openscad -D 'style="pin"' -o out.png mascot-options.scad
// styles: "egg" (Fav), "pin", "coin", "cactus", "shop"

use <fav-buddy.scad>

style = "pin";
show_parts = "assembled";   // "assembled" or "body"

$fn = 96;
fit = 0.25;
badge_r = 17;
badge_t = 2.6;
peg_r = 3.6;
peg_h = 4.5;

// ---------- shared cutouts ----------
module badge_cuts(yp, cz, flat_r = 19) {
    translate([0, yp, cz]) rotate([90, 0, 0]) cylinder(r = flat_r, h = 30);
    translate([0, yp - 1, cz]) rotate([-90, 0, 0]) cylinder(r = badge_r + fit, h = badge_t + 1);
    translate([0, yp + badge_t - 0.01, cz]) rotate([-90, 0, 0]) cylinder(r = 15.5, h = 0.6);
}
module eye_cuts(x, z, depth_y, r = 2.6) {
    for (s = [-1, 1]) translate([s * x, -45, z]) rotate([-90, 0, 0]) scale([1, 1.35, 1]) cylinder(r = r, h = 45 + depth_y);
}
module smile_cut(z, depth_y, r = 5) {
    translate([0, -45, z]) rotate([-90, 0, 0]) difference() {
        cylinder(r = r, h = 45 + depth_y);
        translate([0, 0, -1]) cylinder(r = r - 1.4, h = 99);
        translate([-20, -40, -1]) cube([40, 40, 99]);
    }
}
module peg_at(z) { translate([0, 0, z - 0.01]) intersection() {
    cylinder(r = peg_r, h = peg_h);
    translate([-peg_r, -peg_r, 0]) cube([2 * peg_r, peg_r + 2.6, peg_h]);
} }

// ---------- 1. Pin: a map-pin buddy (the badge is the pin's hole) ----------
pin_top = 86;
module body_pin() {
    difference() {
        union() {
            intersection() {
                hull() {
                    translate([0, 0, 58]) sphere(r = 31);
                    translate([0, 0, 15]) sphere(r = 4);
                }
                translate([-50, -50, 0]) cube([100, 100, pin_top]);
            }
            // stand so the point can sit on the counter
            cylinder(r1 = 26, r2 = 20, h = 6);
            translate([0, 0, 5.99]) cylinder(r1 = 12, r2 = 5, h = 10);
            peg_at(pin_top);
        }
        badge_cuts(-23, 55, 19.5);
        eye_cuts(8.5, 79, -19);
    }
}

// ---------- 2. Coin: a FavCoin standing on edge ----------
coin_r = 36;
coin_t = 26;
coin_cz = 34;
coin_top = coin_cz + coin_r - 4;
module body_coin() {
    difference() {
        union() {
            intersection() {
                translate([0, coin_t / 2, coin_cz]) rotate([90, 0, 0]) {
                    cylinder(r = coin_r, h = coin_t);
                }
                translate([-50, -50, 0]) cube([100, 100, coin_top]);
            }
            // rim ridges, front and back
            for (y = [-coin_t / 2, coin_t / 2])
                intersection() {
                    translate([0, y, coin_cz]) rotate([90, 0, 0]) rotate_extrude($fn = 128)
                        translate([coin_r - 2.2, 0]) circle(r = 2.2, $fn = 32);
                    translate([-50, -50, 0]) cube([100, 100, coin_top]);
                }
            // little feet
            for (s = [-1, 1]) translate([s * 13, -4, 0]) scale([1.3, 1.8, 0.7]) sphere(r = 6);
            peg_at(coin_top);
        }
        badge_cuts(-coin_t / 2, 28, 18.5);
        eye_cuts(10, 54, -11.5);
        translate([-50, -50, -20]) cube([100, 100, 20]);
    }
}

// ---------- 3. Cactus: a cactus in a pot (badge on the pot) ----------
cactus_top = 92;
module cactus_pot() {
    cylinder(r1 = 28, r2 = 31, h = 34);
    translate([0, 0, 30]) cylinder(r = 33, h = 7);
}
module cactus_plant() {
    intersection() {
        hull() {
            translate([0, 0, 36]) cylinder(r = 17, h = 1);
            translate([0, 0, cactus_top - 12]) scale([1, 0.92, 1]) sphere(r = 16);
        }
        translate([-50, -50, 0]) cube([100, 100, cactus_top]);
    }
    for (s = [-1, 1]) {
        hull() { translate([s * 12, 0, 56]) sphere(r = 6.5); translate([s * 22, 0, 56]) sphere(r = 6.5); }
        hull() { translate([s * 22, 0, 56]) sphere(r = 6.5); translate([s * 23, 0, 68]) sphere(r = 6); }
    }
    peg_at(cactus_top);
}
module cactus_cuts() {
    for (a = [0 : 30 : 359]) if (a != 270 && a != 240 && a != 300)
        rotate([0, 0, a]) translate([17.2, 0, 40]) cylinder(r = 0.9, h = cactus_top - 46, $fn = 16);
    translate([0, -27, 19]) rotate([90, 0, 0]) cylinder(r = 19, h = 20);
    translate([0, -28, 19]) rotate([-90, 0, 0]) cylinder(r = badge_r + fit, h = badge_t + 1);
    translate([0, -27 + badge_t - 0.01, 19]) rotate([-90, 0, 0]) cylinder(r = 15.5, h = 0.6);
    eye_cuts(6, 76, -13.3, 2.3);
    smile_cut(70, -14.2, 4.2);
    translate([0, 0, 37]) cylinder(r = 26, h = 0.8);   // "soil" groove
}
module body_cactus() { difference() { union() { cactus_pot(); cactus_plant(); } cactus_cuts(); } }

// ---------- 4. Shop: a little storefront with an awning ----------
shop_w = 64;
shop_d = 44;
shop_h = 62;
module body_shop() {
    difference() {
        union() {
            translate([-shop_w / 2, -shop_d / 2, 0]) cube([shop_w, shop_d, shop_h]);
            // roof slab
            translate([-shop_w / 2 - 3, -shop_d / 2 - 3, shop_h]) cube([shop_w + 6, shop_d + 6, 5]);
            // awning: striped wedge over the front
            for (i = [0 : 7]) {
                x0 = -shop_w / 2 - 2 + i * (shop_w + 4) / 8;
                translate([x0, -shop_d / 2, shop_h - 14])
                    rotate([0, 90, 0]) linear_extrude((shop_w + 4) / 8 - (i % 2 == 0 ? 0 : 0.0))
                        polygon([[0, 0], [-9, 0], [0, -10 - (i % 2) * 0.8]]);
            }
            peg_at(shop_h + 5);
        }
        // window "eyes"
        for (s = [-1, 1]) translate([s * 15, -shop_d / 2 - 1, 34]) rotate([-90, 0, 0]) cylinder(r = 6, h = 4.5);
        // badge on the door / front
        translate([0, -shop_d / 2 - 1, 14]) rotate([-90, 0, 0]) cylinder(r = badge_r + fit, h = badge_t + 1);
        translate([0, -shop_d / 2 + badge_t - 0.01, 14]) rotate([-90, 0, 0]) cylinder(r = 15.5, h = 0.6);
        smile_cut(37, -shop_d / 2 + 2, 4.2);
    }
}

// ---------- layout ----------
function badge_pos(s) =
    s == "pin"    ? [-23, 55] :
    s == "coin"   ? [-coin_t / 2, 28] :
    s == "cactus" ? [-27, 19] :
    s == "shop"   ? [-shop_d / 2, 14] : [-22, 22];
function top_z(s) =
    s == "pin" ? pin_top : s == "coin" ? coin_top : s == "cactus" ? cactus_top :
    s == "shop" ? shop_h + 5 : 64;

module body_for(s) {
    if (s == "pin") body_pin();
    else if (s == "coin") body_coin();
    else if (s == "cactus") body_cactus();
    else if (s == "shop") body_shop();
    else body();
}

body_colors = [["egg", "#7b5cd6"], ["pin", "#e5484d"], ["coin", "#f2b632"], ["cactus", "#3fa66b"], ["shop", "#7b5cd6"]];
function color_of(s) = [for (c = body_colors) if (c[0] == s) c[1]][0];
crown_col = (style == "coin") ? "#7b5cd6" : "#f2c230";

if (show_parts == "body") body_for(style);
else {
    if (style == "cactus") {
        color("#c46b3a") difference() { cactus_pot(); cactus_cuts(); }
        color(color_of(style)) difference() { cactus_plant(); cactus_cuts(); }
    } else color(color_of(style)) body_for(style);
    bp = badge_pos(style);
    color("white") translate([0, bp[0], bp[1]]) rotate([90, 0, 0]) translate([0, 0, -badge_t]) badge();
    color(crown_col) translate([0, 0, top_z(style)]) crown();
    if (style == "shop") color("white") for (i = [1 : 2 : 7]) {   // awning stripes
        x0 = -shop_w / 2 - 2 + i * (shop_w + 4) / 8;
        translate([x0 - 0.01, -shop_d / 2 - 0.02, shop_h - 14])
            rotate([0, 90, 0]) linear_extrude((shop_w + 4) / 8 + 0.02)
                polygon([[0.02, 0.02], [-9.02, 0.02], [0.02, -10.85]]);
    }
}
