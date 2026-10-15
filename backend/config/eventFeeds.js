// Free event calendars for the Local tab's "Happening nearby", one row per
// library system. A user sees a system's programs when they're inside its
// radius, and only programs at branches within 10 miles of them.
//
// type:
//   bibliocommons — { libraryId }: the subdomain of its events page
//                   (cmlibrary.bibliocommons.com → "cmlibrary"). Branch
//                   locations come with the events.
//   libcal        — { host, calendarId } (-1 = every public calendar).
//                   Events name a branch or room; `branches` places them.
//   mcldaz        — Maricopa County Library District's events site: its RSS
//                   feed has the times, its list page has the branch.
// `branches` (libcal, mcldaz): name, words that identify it in an event's
// location, and where it is (OpenStreetMap, 2026-10-15).
const LIBRARY_FEEDS = [
  {
    type: 'bibliocommons',
    libraryId: 'cmlibrary',
    name: 'Charlotte Mecklenburg Library',
    center: { lat: 35.2271, lng: -80.8431 },
    radiusMiles: 35,
    timeZone: 'America/New_York'
  },
  {
    // Chandler, AZ
    type: 'bibliocommons',
    libraryId: 'chandler',
    name: 'Chandler Public Library',
    center: { lat: 33.3062, lng: -111.8413 },
    radiusMiles: 20,
    timeZone: 'America/Phoenix'
  },
  {
    // Phoenix, incl. Laveen (Prickly Pear, formerly Cesar Chavez)
    type: 'libcal',
    host: 'calendar.phoenixpubliclibrary.org',
    calendarId: -1,
    name: 'Phoenix Public Library',
    center: { lat: 33.4484, lng: -112.0740 },
    radiusMiles: 30,
    timeZone: 'America/Phoenix',
    branches: [
      { name: "Acacia", match: ["Acacia"], lat: 33.56621, lng: -112.06309 },
      { name: "Agave", match: ["Agave"], lat: 33.69942, lng: -112.1399 },
      { name: "Century", match: ["Century"], lat: 33.50595, lng: -112.04342 },
      { name: "Cholla", match: ["Cholla"], lat: 33.57816, lng: -112.11981 },
      { name: "Desert Broom", match: ["Desert Broom"], lat: 33.75444, lng: -111.99233 },
      { name: "Desert Sage", match: ["Desert Sage"], lat: 33.47397, lng: -112.22334 },
      { name: "Harmon", match: ["Harmon"], lat: 33.43573, lng: -112.07993 },
      { name: "Ironwood", match: ["Ironwood"], lat: 33.30485, lng: -111.98954 },
      { name: "Juniper", match: ["Juniper"], lat: 33.65447, lng: -112.09837 },
      { name: "Mesquite", match: ["Mesquite"], lat: 33.60467, lng: -111.98343 },
      { name: "Ocotillo", match: ["Ocotillo"], lat: 33.39253, lng: -112.07479 },
      { name: "Palo Verde", match: ["Palo Verde"], lat: 33.50046, lng: -112.16976 },
      { name: "Prickly Pear", match: ["Prickly Pear", "Cesar Chavez"], lat: 33.37687, lng: -112.13859 },
      { name: "Saguaro", match: ["Saguaro"], lat: 33.47875, lng: -111.98288 },
      { name: "Yucca", match: ["Yucca"], lat: 33.51983, lng: -112.09165 },
      { name: "Burton Barr Central", match: ["Burton Barr"], lat: 33.46244, lng: -112.07317 },
      { name: "South Mountain Community", match: ["South Mountain"], lat: 33.38217, lng: -112.03132 }
    ]
  },
  {
    // Gilbert (Southeast Regional, Perry), Queen Creek and the rest of the county
    type: 'mcldaz',
    host: 'events.mcldaz.org',
    name: 'Maricopa County Library District',
    center: { lat: 33.45, lng: -112.07 },
    radiusMiles: 60,
    timeZone: 'America/Phoenix',
    branches: [
      { name: "Aguila", match: ["Aguila"], lat: 33.94237, lng: -113.17214 },
      { name: "Ed Robson", match: ["Ed Robson"], lat: 33.21839, lng: -111.88166 },
      { name: "El Mirage", match: ["El Mirage"], lat: 33.60694, lng: -112.32435 },
      { name: "Fairway", match: ["Fairway"], lat: 33.58062, lng: -112.28826 },
      { name: "Fountain Hills", match: ["Fountain Hills"], lat: 33.60283, lng: -111.72183 },
      { name: "Georgia T. Lord", match: ["Georgia T. Lord"], lat: 33.46744, lng: -112.38541 },
      { name: "Guadalupe", match: ["Guadalupe"], lat: 33.36203, lng: -111.96259 },
      { name: "Litchfield Park", match: ["Litchfield Park"], lat: 33.5138, lng: -112.35845 },
      { name: "North Valley Regional", match: ["North Valley Regional"], lat: 33.85232, lng: -112.14027 },
      { name: "Perry", match: ["Perry"], lat: 33.26253, lng: -111.74778 },
      { name: "Queen Creek", match: ["Queen Creek"], lat: 33.25026, lng: -111.63548 },
      { name: "Southeast Regional", match: ["Southeast Regional"], lat: 33.36369, lng: -111.73748 },
      { name: "Sun City", match: ["Sun City"], lat: 33.63649, lng: -112.27529 },
      { name: "White Tank", match: ["White Tank"], lat: 33.56711, lng: -112.49773 }
    ]
  },
  {
    // Wall, Belmar and the rest of Monmouth County, NJ
    type: 'libcal',
    host: 'monmouthcountylib.libcal.com',
    calendarId: 21037,
    name: 'Monmouth County Library',
    center: { lat: 40.2601, lng: -74.2738 },
    radiusMiles: 30,
    timeZone: 'America/New_York',
    branches: [
      { name: "Headquarters", match: ["Headquarters", "Manalapan"], lat: 40.29343, lng: -74.30372 },
      { name: "Allentown", match: ["Allentown"], lat: 40.17759, lng: -74.58505 },
      { name: "Atlantic Highlands", match: ["Atlantic Highlands"], lat: 40.4126, lng: -74.03796 },
      { name: "Colts Neck", match: ["Colts Neck"], lat: 40.29596, lng: -74.19042 },
      { name: "Eastern", match: ["Eastern Branch", "Eastern"], lat: 40.31812, lng: -74.06149 },
      { name: "Hazlet", match: ["Hazlet"], lat: 40.42768, lng: -74.17658 },
      { name: "Holmdel", match: ["Holmdel"], lat: 40.36467, lng: -74.16639 },
      { name: "Howell", match: ["Howell"], lat: 40.17201, lng: -74.17937 },
      { name: "Marlboro", match: ["Marlboro"], lat: 40.33071, lng: -74.26204 },
      { name: "Ocean Township", match: ["Ocean Township"], lat: 40.25348, lng: -74.03474 },
      { name: "Oceanport", match: ["Oceanport"], lat: 40.3193, lng: -74.00386 },
      { name: "Wall Township", match: ["Wall Township", "Wall Branch", "Wall Library"], lat: 40.1539, lng: -74.07209 },
      { name: "West Long Branch", match: ["West Long Branch"], lat: 40.29069, lng: -74.0163 }
    ]
  }
];

// The big-city bulk pass (2026-10-15): 32 more systems, generated by
// backend/tools/build-library-feeds.py (BiblioCommons branch lists; LibCal
// branches located with OpenStreetMap). Hand-made rows above win on a clash.
const GENERATED = require('./libraryFeeds.generated.json');
const keyOf = (feed) => feed.libraryId || feed.host;
const handMade = new Set(LIBRARY_FEEDS.map(keyOf));
for (const feed of GENERATED) {
  if (!handMade.has(keyOf(feed))) LIBRARY_FEEDS.push(feed);
}

module.exports = { LIBRARY_FEEDS };
