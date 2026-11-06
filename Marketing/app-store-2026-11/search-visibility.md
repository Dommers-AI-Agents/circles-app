# Widgets in search: website pages and App Store custom product pages

Goal (Wes, 2026-11-06): people searching for widget features ("pandora alarm", "water reminder")
find FavCircles, **in addition to** its core purpose. Nothing about places changes: the name
"FavCircles: Save Your Places", the subtitle "Share favorites with friends" and the en-US keywords stay.

State 2026-11-06: website pages live; four custom product pages submitted for review; In-App Events still drafts (section 3).

## 1. Keywords: unchanged (Wes, 2026-11-06)

"Don't change the keywords for the widgets. We want people to find the app for its core first."
The Spanish (Mexico) keyword idea is dropped; the place keywords stay as they are. So the custom
product pages below are not tied to search keywords: they are landing pages for links.

## 2. Custom product pages: built and submitted 2026-11-06

Four pages in App Store Connect, each with its own widget slides first and five of the main listing's
slides after (map, friends, circles, place, widgets; Family keeps postcards instead of widgets), the
promotional text below, and a deep link that opens that widget when the app is already installed.
iPad and iPhone Duo slides are the main listing's (copied from 1.4.8). Submitted for review on their
own (review submission 40b8015e…), WAITING_FOR_REVIEW. Until approved, a ppid link shows the main page.

| Page | ppid | Widget slides | Deep link | Website pages linking to it |
|---|---|---|---|---|
| Wake Up & Sleep | ab9789e4-1fcc-4cdb-9679-837cbdba2b8a | Wake Up, Sleep Sounds | /app/widget/wakeup | wakeup, sleepsounds, sleep |
| Health | 58c75022-4ff4-4270-9e87-ca732bb26951 | Water, Medications, Habits | /app/widget/water | water, meds, habits, heartbeat |
| Fitness | aa6ddfd8-6e35-42c4-9270-d58180f48908 | Workouts, FavRun, Calories | /app/widget/workouts | workouts, run, calories, motivation |
| Family | 985262c3-e739-4151-849c-b2e09a357cdb | Events, Fridge Mail, How Are You? | /app/widget/events | events, howareyou, fridgemail, postcard |

Link: `https://apps.apple.com/us/app/favcircles/id6746807095?ppid=<ppid>`. The website's widget pages
use it (`_productPages` in website/widgets/widget-seo.json); use it in ads or posts about a widget too.

Promotional text:
- Wake Up & Sleep: Wake up to your Pandora, Spotify or Apple Music station with real alarms, and drift off to rain, ocean or white noise. Plus 25 more widgets and your favorite places.
- Health: Water reminders, medication reminders with one-tap logging, habits and streaks, all in one free app alongside the places you love.
- Fitness: Log sets, reps and PRs with 16 ready routines, track runs on a GPS map, and count calories. Built into FavCircles, the app for your favorite places.
- Family: Check on Mom or Dad, mail kids' drawings to Grandma, plan parties with RSVPs and one shared album.

**How the slides are made** (`custom-product-pages/`): the screens were shot on a fresh iPhone 17 Pro Max
simulator (iOS 26.5) signed in as the hidden test account widget-demo@favcircles.com ("Jamie Rivera",
isTestAccount, no follows or saves), filled with sample data: `source/seed` builds the widget documents
with the widgets package's own models (`swift run seed source/seed/pts.txt > seed.json`, pts.txt is a real
Freedom Park walking route from Apple Maps) and `seedput.js` saves them through the API; `mkevent.js`
made the sample birthday party (guest replies written directly, emails .invalid and opted out, no
reminder, so nothing is ever sent). Navigation is `simctl openurl https://api.favcircles.com/app/widget/<id>`;
taps go through the UI-test servant (`DuoAppStoreCaptureUITests`, generic `tap:` / `at:` commands).
Slides: `source/<page>.json` → `source/render.sh <page>` → `<page>/*.jpg` (1320×2868).

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
- Google Search Console already has favcircles.com (Domain property). Submit the sitemap there:
  Indexing → Sitemaps → `sitemap.xml` → Submit (needs Wes's Google login).
- Bing, Yandex and other IndexNow engines: all 41 sitemap URLs sent 2026-11-06 (key file
  favcircles.com/62261951175cf49009704928101a02fe.txt; resend after adding pages).
