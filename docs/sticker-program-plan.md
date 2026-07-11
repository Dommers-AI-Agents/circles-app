# FavCircles Sticker Program — Physical Rollout Plan

The app side is built: sticker QR codes deep-link into the app (or the App Store), new users earn
points attributed to the venue, saves/visits/redemptions are tracked per venue, and venues get a
monthly performance email. This document covers everything outside the codebase: producing the
stickers, pitching venues, and running the program.

## 1. How the system works (quick reference)

Each venue gets **two QR codes** when you create it via the admin API:

| Piece | Where it lives | What scanning does |
|---|---|---|
| **Window sticker** | Front window / door / table tents | Opens the app (or App Store). New users get **+100 pts**; saving the place earns **+50 pts** |
| **Register card** | Behind the counter, staff-controlled, shown with a purchase | Verified visit: **+25 pts**, max once per day per venue. Immediately offers redemption if the user has enough points |

Redemption: the user picks an offer (e.g. "Free drip coffee — 250 pts"), their phone shows a
**5-minute countdown voucher** with the venue name, offer, and a 4-character code. Staff sees the
live countdown (can't be screenshotted meaningfully) and applies the discount.

Points economy (server-side constants in `backend/config/rewardConfig.js`):
signup 100 · save 50 · visit 25 · share-conversion 50.
A sensible first offer costs 200–300 pts ≈ 4–8 visits — frequent enough to motivate, rare enough
that a $3–5 giveaway is cheap customer acquisition for the venue.

## 2. Onboarding a venue (operational checklist)

1. **Create the venue** (needs `ADMIN_SECRET` from the backend .env):
   ```bash
   curl -X POST https://circles-backend-196924649787.us-central1.run.app/api/rewards/admin/venues \
     -H "Authorization: Bearer $ADMIN_SECRET" -H "Content-Type: application/json" \
     -d '{
       "venueName": "Blue Door Cafe",
       "contactName": "Maria",
       "contactEmail": "maria@bluedoorcafe.com",
       "googlePlaceId": "ChIJ...",
       "placeName": "Blue Door Cafe",
       "placeAddress": "123 Main St, Austin TX",
       "category": "cafe",
       "location": { "lat": 30.2672, "lng": -97.7431 },
       "offers": [
         { "title": "Free drip coffee", "pointsCost": 250 },
         { "title": "10% off your order", "pointsCost": 150 }
       ]
     }'
   ```
   The response contains `windowStickerUrl` and `registerCardUrl` — these are the QR targets.
   Get the `googlePlaceId` + coordinates from Google Maps (share link → place ID finder) —
   it's what ties saves to the venue, and coordinates enable GPS-verified visits.

2. **Generate the QR PNGs** (print resolution, error correction H):
   ```bash
   cd backend && npm install qrcode   # first time only
   node scripts/generateStickerQR.js <WINDOW_CODE> <REGISTER_CODE> ./sticker-qr
   ```

3. **Print** (see specs below), **deliver**, and **verify with a live scan** on-site before leaving:
   scan the window QR with the iOS Camera (should open app / App Store page) and the register QR
   from a logged-in test account (should show "+25 points").

4. Confirm the venue's contact email — that's where the monthly report goes.

## 3. Sticker design & print specs

### Window sticker (~4×4 in)
- **Copy (hierarchy top to bottom):**
  1. `Don't forget us! 💜` (large)
  2. `Save {Venue Name} on FavCircles & earn rewards for coming back`
  3. QR code (min 1.5×1.5 in printed — bigger scans faster through glass)
  4. `Scan me 📲 · New members get 100 points`
- **Material:** weatherproof white vinyl, UV-laminated, **front-adhesive** version for inside-glass
  mounting (survives weather, can't be peeled by passersby). Order a standard-adhesive batch too
  for register areas / doors.
- **QR:** already generated at error-correction H with a proper quiet zone — don't crop the white
  margin, don't recolor below ~70% contrast, never place over a photo.
- **Vendors:** Sticker Mule, StickerApp, or Sticker Giant — custom die-cut vinyl runs ≈ $60–120
  per 50 at this size. Order small batches until the design is proven.

### Register card (~3×3 in, card or small sticker)
- **Copy:** `Buying something? Scan to earn 25 points 🧾` + QR + `FavCircles member rewards`
- Print as a **counter card or laminated card kept staff-side** — the whole fraud model relies on
  this code only being scannable with a purchase. It should not be visible/reachable from the
  customer side.
- Include a tiny staff line on the back: *"Customer redeeming? Check their screen shows a live
  countdown + today's offer, then apply the discount."*

### Before mass printing — domain decision
The QR encodes `https://circles-backend-196924649787.us-central1.run.app/s/CODE`. QR users never
see the URL, so the pilot can ship as-is. But **printed stickers are permanent** — before a big
print run, consider mapping a short domain (e.g. `go.favcircles.com`) to Cloud Run and setting
`STICKER_LINK_BASE_URL`. That requires serving the AASA file on that domain and adding
`applinks:go.favcircles.com` to the iOS entitlements (app update), so do it deliberately, not mid-pilot.

## 4. The venue pitch

**The 30-second version:**
> "FavCircles users save their favorite places and get rewarded for coming back. This sticker turns
> your window into a customer-retention channel: people who scan it save your place in the app, earn
> points every time they buy something here, and cash points in for a reward you choose — like a free
> coffee. You only give away the reward when someone has already paid you 5–10 times. Every month I'll
> email you exactly how many people scanned, saved, and came back. The sticker and setup are free."

**Objection handling:**
- *"What does it cost?"* — Nothing but the redeemed offers, which you choose and can change. A 250-point
  free coffee means ~6 verified purchases first.
- *"Will staff need training?"* — One sentence: "If someone shows a countdown screen with our offer on
  it, apply the discount." The register card lives by the till.
- *"How do I know it works?"* — Monthly email with scans, signups, saves, repeat visits, redemptions.
  If it's zeros after two months, peel it off.

**Who to pitch first:** independent cafes, breakfast spots, and counter-service restaurants with
regulars and visible foot traffic. Skip table-service fine dining for the pilot (voucher-at-counter
flow fits counters best).

## 5. Rollout phases

**Phase 0 — Dry run (week 1):** Create 1 test venue (a friendly local spot or your own test data),
print 2 stickers at a local print shop, walk the full loop end-to-end: fresh phone → scan → App Store
→ install → signup → +100 → save → +50 → register scan → +25 → redeem → voucher shown.

**Phase 1 — Pilot (weeks 2–6):** 5–10 venues in one walkable neighborhood (density matters — one
user should encounter multiple stickers). Visit each venue at week 2 to check the sticker is still up
and staff remembers the redemption flow. Set up the Cloud Scheduler job for monthly reports:
```bash
gcloud scheduler jobs create http venue-reports \
  --schedule="0 9 1 * *" --uri="https://<backend>/api/tasks/send-venue-reports" \
  --http-method=POST --headers="Authorization=Bearer $SCHEDULER_SECRET"
```

**Phase 2 — Iterate (weeks 6–10):** Read the numbers. Key ratios: scans→installs (sticker copy &
placement), installs→saves (in-app flow), saves→repeat visits (points economy). Tune point values in
`rewardConfig.js` (server-side, no app release needed) and offer pricing with venues.

**Phase 3 — Scale:** Custom short domain, bulk sticker printing, a one-page venue signup form, and
consider a venue self-serve stats page (deferred from V1).

## 6. Anti-fraud posture (V1)

- Signup bonus: once per account, only within 7 days of account creation.
- Save bonus: once per venue, server verifies the place actually exists in the user's circles.
- Visit: once per venue per day; register code is physically staff-controlled; GPS proximity is
  enforced when the app sends coordinates.
- Redemption: atomic balance check; voucher expires in 5 minutes; venue staff visually confirm.
- Deferred (add if abuse appears): device fingerprinting, GPS required (not optional) for visits,
  velocity limits across venues, staff-tap voucher confirmation.

## 7. What was deliberately left out of V1

Venue self-serve portal · Android · in-app QR camera (the iOS Camera app handles QR → universal
link natively) · custom short domain · POS integration. All are additive later.
