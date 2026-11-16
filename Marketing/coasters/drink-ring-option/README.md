# Drink-ring coaster (option B, 2026-11-16)

A second coaster design. The original art in the folder above is unchanged.

**Idea:** a coaster is read by someone sitting in a bar or cafe with a drink. Face A speaks to that
moment ("You're sitting in someone's favorite place. Is it one of yours?") inside a gold circle, like the ring a
glass leaves. Both faces end the same way: "Scan to save." · QR · FavCircles. Face B turns the circles into circles on a map ("Leave your mark.").

## Files
- `FavCircles-coaster-drink-ring-A-hook-print-4.25in-600dpi.png` — face A, for the printer
- `FavCircles-coaster-drink-ring-B-map-print-4.25in-600dpi.png` — face B, for the printer
- `*-preview.png` — how each face looks cut round (not for print)
- `source/build.js` — regenerates everything (`node build.js`; needs Chrome and `backend/node_modules`)
- `source/face-*-guides.png` — cut line (magenta) and safe area (dashed cyan)

## Print spec
- 4 in round coaster, full colour both sides. Art is a 4.25 in square (2550 px at 600 dpi): 1/8 in
  bleed all round, background runs to the edge, the printer cuts the circle.
- Words and the QR code stay inside a 3.7 in circle.
- QR: `https://api.favcircles.com/s/JOINUS` (generic App Clip). About 0.55 in of dots on face A,
  0.5 in on face B, black on white.
- Colours are sRGB: charcoal #111317, gold #F6C945, blue #3F8FDB, green #7CC464.
- A thin rim line runs about 1/8 in inside the cut, as on the original coasters. A cut that lands off-centre will show against it, so ask the printer about their cutting tolerance.
