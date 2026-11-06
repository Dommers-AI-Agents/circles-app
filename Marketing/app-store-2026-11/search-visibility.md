# App Store search for the widgets (drafts for Wes to approve)

Goal (Wes, 2026-11-06): people searching for widget features ("pandora alarm", "water reminder")
find FavCircles, **in addition to** its core purpose. Nothing about places changes: the name
"FavCircles: Save Your Places", the subtitle "Share favorites with friends" and the en-US keywords stay.

Nothing below is in App Store Connect yet. The website half is live (favcircles.com/widgets/…).

## 1. Extra keyword field: Spanish (Mexico) localization — ships with 1.4.10

iOS search only reads name, subtitle, keywords and IAP names. The US App Store is widely reported
(by ASO tools, not documented by Apple) to also index the **Spanish (Mexico)** keyword field, so it
adds 100 characters without touching the place keywords.

- **Keywords (es-MX), 98 chars:**
  `alarm,pandora,spotify,water,reminder,habit,tracker,pill,medication,sleep,noise,workout,run,calorie`
- Apple combines words across fields: "water"+"reminder", "habit"+"tracker", "sleep"+"noise",
  "pandora"+"alarm", "pill"+"reminder" all count as phrases. No words repeated from the name or subtitle
  (they're already indexed).
- es-MX needs its own name, subtitle, description and screenshots. Use the en-US ones as they are
  (English text is allowed in that localization), so Mexico shoppers see the same page.
- Can't be added to 1.4.9 (waiting for review, locked). Add it when 1.4.10 is created.

## 2. Custom product pages with search keywords — needs screenshots

Since July 2025 a custom product page can be given keywords; when the app ranks for one of them, that
page shows in search instead of the main one. Keywords must already be in a keyword field (the es-MX
field above is what makes the app rank for them; the page decides what people see). Pages can be set up
anytime, and are searchable once approved and visible. Only screenshots, app previews and promotional
text (170 characters) can differ; name and subtitle stay the same.

**Blocker:** each page needs its own screenshots of those widgets. None exist yet; this is the one
piece of work that unblocks the pages (and would improve the website pages too).

| Page | Keywords to assign | Promotional text |
|---|---|---|
| Wake Up & sleep | alarm, pandora, spotify, sleep, noise | Wake up to your Pandora, Spotify or Apple Music station with real alarms, and drift off to rain, ocean or white noise. Plus 25 more widgets and your favorite places. |
| Health | water, reminder, pill, medication, habit, tracker | Water reminders, medication reminders with one-tap logging, habits and streaks, all in one free app alongside the places you love. |
| Fitness | workout, run, calorie | Log sets, reps and PRs with 16 ready routines, track runs on a GPS map, and count calories. Built into FavCircles, the app for your favorite places. |
| Family | (no family terms in the field yet; add in a later keyword round) | Check on Mom or Dad, mail kids' drawings to Grandma, plan parties with RSVPs and one shared album. |

## 3. In-App Events — can go up anytime, no app update

Events show in search results and can be featured. Each needs a 1920×1080 card image and a
1080×1920 details image (to make), plus:

**Wake Up**
- Badge: New Feature (or Major Update)
- Name (≤30): `Wake up to your music`
- Short description (≤50): `Real alarms that open Pandora or Spotify`
- Long description (≤120): `Real iPhone alarms that ring even on silent, then open your Pandora, Spotify or Apple Music station.`
- Dates: two weeks from when 1.4.9 is live. Deep link: the Wake Up widget.

**Sleep Sounds Bedtime**
- Badge: New Feature
- Name: `Bedtime sounds, on time`
- Short: `Rain, ocean and white noise, ready at bedtime`
- Long: `Mix rain, ocean, fire and white noise with a fade-out timer, and a bedtime reminder that plays it.`

## 4. Website (live)

- 27 pages at favcircles.com/widgets/<slug>.html (source: website/widgets/widget-seo.json), linked from
  widgets.html, with Smart App Banner, structured data and FAQ.
- sitemap.xml + robots.txt.
- **Wes:** add favcircles.com to Google Search Console (Domain property; the TXT record can go in via
  Cloudflare) and submit https://favcircles.com/sitemap.xml. Same in Bing Webmaster Tools (it can
  import from Search Console).
