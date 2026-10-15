// Free event calendars for the Local tab's "Happening nearby". Adding a
// city's library is one row: its BiblioCommons id (the subdomain of its
// events page, e.g. cmlibrary.bibliocommons.com → "cmlibrary"), a centre
// and the radius its branches cover.
const LIBRARY_FEEDS = [
  {
    libraryId: 'cmlibrary',
    name: 'Charlotte Mecklenburg Library',
    center: { lat: 35.2271, lng: -80.8431 },
    radiusMiles: 35,
    timeZone: 'America/New_York'
  }
];

module.exports = { LIBRARY_FEEDS };
