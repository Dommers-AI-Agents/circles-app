# FavCircles Table Tents — Print Spec

Matches the winner window-sticker design (`Window-Stickers/Favs/Winner/`):
ghost road + dashed centerline, map pins, app icon, "Every great place has a
story. / Remember yours.", the same App Store QR code, and the FavCircles
wordmark. Two colorways: **gunmetal** (#3A3F47 → #15171C) and **purple**
(#667eea → #764ba2).

## Finished size
A-frame tent, **4″ wide × 6″ tall** per face, with two 0.75″ base flaps that
overlap and glue/tape underneath.

## Files (per colorway: `gunmetal`, `purple`)

| File | Use |
|---|---|
| `…-{color}.pdf` | **Send this to the print shop.** Flat 4.5″ × 14″ with 0.125″ bleed, crop marks, and dashed fold marks (fold at 0.75″ / 6.75″ apex / 12.75″ from trim top). Top panel is intentionally upside-down on the flat — it reads upright once folded. |
| `…-{color}.svg` | Editable source. Text is live (needs Georgia Bold + Helvetica Neue — both ship with macOS); PDF/PNG exports already have them baked in. |
| `…-{color}-300dpi.png` | Raster proof / online print services that want PNG. |
| `…-{color}-CMYK.tiff` | 300 dpi CMYK conversion for shops that require it. |
| `…-{color}-letter-homeprint.pdf` | DIY: prints one tent on 8.5×11 card stock at 75% scale (3″ × 4.5″ faces) with cut/fold guides and assembly steps. |
| `…-{color}-preview.png` | Quick look. |

## Print shop notes
- Order as a **flat, scored card** ("table tent, 4×6, 3 scores") on 14–16 pt
  cover stock, matte or soft-touch laminate.
- Trim size 4″ × 13.5″; bleed included on all sides; scores at the dashed marks.
- Both faces are identical, so the tent reads the same from either side.
- QR code is the same code used on the window sticker / coasters (App Store
  link) — vector-exact copy, 1.5″ printed size, scans easily.

## Regenerating
`_source/make_table_tents.py` (Python, needs `rsvg-convert` + ImageMagick)
recreates every file in this folder from the winner sticker's extracted QR path
and app icon (also in `_source/`).
