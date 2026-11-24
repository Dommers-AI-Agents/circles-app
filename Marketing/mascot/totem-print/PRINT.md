# Printing a FavCircles Totem (Bambu P1S)

## Files
| Plate | File | Spool | Time | Filament |
|---|---|---|---|---|
| 1 | `bambu/Totem 1 - ring + base.3mf` | Dark Blue, PLA Matte | 3 h 12 min | 108 g |
| 2 | `bambu/Totem 2 - heart halves.3mf` | Red, PLA Basic | 53 min | 31 g |

The plain files have No. 0001 under the base and no store name. For a store:

    ./make-totem.sh <windowCode> totem "Store Name" 0002

That makes `stores/<code>-totem/`: the store's plate 1 (its maker's mark says MADE FOR STORE NAME, No. 0002) and the QR label sheet. Plate 2 is the same for every store.

## Print
1. Open the plate's .3mf in Bambu Studio (or send it from Bambu Handy).
2. When it asks, map the filament to the AMS slot with the right spool: Dark Blue Matte for plate 1, Red for plate 2.
3. Textured or smooth PEI plate, glue stick not needed. No supports, no color changes.
4. Let the plate cool before taking the parts off. The ring's back face has the icons pressed into it, so don't scrape it.

## Finish
- **Gold paint:** Posca PC-1MR (extra fine) for the small icons and the ring lettering; PC-3M for the base lettering and the heart pins. Fill each engraving, then wipe the surface right away with a slightly damp paper towel. The back nameplate is left unpainted on purpose.
- **Heart:** cut two 5 mm pieces of 1.75 mm filament for the dowels, glue the two halves together (CA glue), stem down.
- **Assemble:** push the heart's stem into the socket at the bottom of the ring, then set the ring into the base's slot. A drop of glue in each makes it permanent.

## Tap and scan
1. Store Admin → NFC stickers → + → Points → "Totem". Write that sticker (38 mm round NTAG) with the app.
2. Stick it on the ceiling of the pocket under the base.
3. Make the store's label: `./make-totem.sh <windowCode> totem "Store Name"` (or in the app: Settings → Sticker Venues → QR button → Totem QR labels for several stores). It says TAP OR SCAN round the top and the store's name round the bottom. Print `stores/<code>-totem/sheet.pdf` on Avery 8293 at Actual size and put the label in the round recess on top.
4. Test: tap a phone on the label and scan the QR. Both should open the store.

## Versions
Each version Wes picks is a git tag; the old ones can always be printed again (`git checkout <tag> -- Marketing/mascot/totem-print`, or set the switch in totem.scad).
- `totem-v1-puffy` (2026-11-22): puffy 38 mm heart. `HEART_SHAPE = "puffy"` rebuilds it with today's engravings.
- `totem-v2-classic` (2026-11-23): the original 22 mm heart with a flat face, same engravings. Current.
