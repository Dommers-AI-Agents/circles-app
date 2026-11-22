# Fav — the FavCircles register buddy

One shared body for every city, a city accessory that plugs onto the peg on its head,
and a round **TAP** badge on the belly that hides the NFC tag. Customers tap their
phone on the belly to earn or claim rewards.

Source: `fav-buddy.scad` (OpenSCAD). Print files: `stl/`. Pictures: `renders/`.

## Parts

| File | What | Suggested color | Print |
|---|---|---|---|
| `stl/body.stl` | Shared body (every city) | FavCircles purple | Flat bottom down, no supports (arms may want "supports on build plate only" if your printer droops) |
| `stl/badge.stl` | Belly TAP badge, 34 mm | White, swap to purple at the raised layer (1.8 mm) for two colors | Face up |
| `stl/crown.stl` | Charlotte: Queen City crown | Gold / yellow | Upright (socket hole down) |

Finished size: about 70 mm wide, 55 mm deep, 86 mm tall with the crown.

Starting settings: PLA, 0.2 mm layers (0.12 mm for the badge and crown), 3 walls,
15 % infill for the body (more infill = heavier and harder to knock over).

## Assembly

1. Stick a round **NTAG215** sticker (25 mm or 30 mm) in the shallow pocket inside the
   belly recess. Program it with the store's register link first (same `?t=` tag URL
   as the Register stickers) and test it with a phone.
2. Glue the badge into the recess (a dot of CA glue or double-sided tape). Keep metal,
   magnets and metallic paint away from the tag — they block the tap.
3. Press the crown onto the head peg; the flat on the peg makes the front point face
   forward. A drop of glue makes it permanent.
4. Optional: a felt or non-slip pad (40 mm) under the base, or museum putty so it stays put.

Phone tip for the store: iPhones read NFC at the **top edge**, so tell customers to
touch the top of the phone to Fav's belly.

## Adding a city

Every accessory is the same recipe: a flat-bottomed piece about 28–31 mm across with the
keyed socket underneath (`accessory_socket_base()` in the .scad). Copy the `crown()`
module, change the shape, and add it to the `part` list. Ideas:

- Nashville — cowboy hat
- Austin — tiny cowboy boots or a bat
- New Orleans — jazz hat / trumpet
- Chicago — deep-dish slice hat
- Raleigh — oak acorn cap ("City of Oaks")

Keep city pieces generic: no team names, logos or team color schemes. Have a trademark
check done on a final design before making many.

## Changing the design

Open `fav-buddy.scad` in OpenSCAD (installed at /Applications/OpenSCAD.app). The numbers at
the top control everything: body size, badge size, the clearance `fit` (raise it if parts
are too tight on your printer), and the tag pocket. Export one part with:

    openscad -D 'part="crown"' -o stl/crown.stl fav-buddy.scad
