# FavCircles Store-Owner Tri-Fold Brochure — Print Spec

Roll-fold (letter tri-fold) companion to the sell sheet, same brand system:
purple gradient front, gunmetal QR back, Georgia display + Helvetica body,
gold accents. Copy mirrors the sell sheet / store-owners page.

## Files

| File | Use |
|---|---|
| `FavCircles-Store-Owner-Brochure.pdf` | **Send this to FedEx Office / any print shop.** 2 pages, each 11×8.5" landscape. Page 1 = outside (flap · back cover · front cover), page 2 = inside spread. |
| `side1-preview.png`, `side2-preview.png` | Quick look at each side. |
| `_source/brochure-template.html` | Editable source. Rebuild: inject the app icon b64 + QR path (same assets as the sell sheet / table tents), then Chrome headless `--print-to-pdf`. |

## Ordering at FedEx Office (office.fedex.com → Brochures)

- Product: **Brochure**, size **8.5" × 11"**, fold: **Tri-fold** (roll fold),
  **double-sided** (flip on short edge), full color.
- Paper: 100 lb gloss text or matte text both work; gloss makes the purple pop.
- The PDF is laid out flat — FedEx's tri-fold option folds it correctly as-is.
- No bleed margin is included; the design runs to the page edge. Choose
  "print to edge / full bleed" if offered; if the shop requires a bleed file,
  ask and the source can be re-exported at 11.25×8.75 with 0.125" bleed.

## Panel map

- **Front cover** (outside right): brand + "Turn your regulars into your best
  marketing." + First-3-months-free badge.
- **Back cover** (outside middle): App Store QR (same vector as stickers /
  coasters) + contact + FavCircles.com.
- **Fold-in flap** (outside left, 1/16" narrower so it tucks): price
  comparison + the 4 claim steps.
- **Inside spread**: benefits · counter flow + points table · free-vs-Business
  tiers + economics.

Fold ticks are printed as tiny dashed marks at the top/bottom edges
(3.625" and 7.3125" from the left on side 1; mirrored on side 2).

## Consistency notes

- Pricing says **$49.99/mo, first 3 months free — limited-time early-adopter
  offer** (matches the sell sheet after the 2026-08-12 legal-language change;
  never print "rate locked for life").
- Claim step 1 includes "not on the map yet? Add it in seconds" (add-and-claim
  flow shipped 2026-08-12).
