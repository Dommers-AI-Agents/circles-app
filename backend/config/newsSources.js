// backend/config/newsSources.js
// Curated catalog of publisher-direct RSS feeds for the Feeds tab.
// Publisher-official feeds only — no Google News (its RSS is licensed for
// personal, non-commercial use) and no commercial news APIs. Adding a source
// or category is a config change here; no app update needed. The app groups
// the picker by `category` (catalog order defines display order).
//
// All URLs verified 200 + XML on 2026-07-18. Gotchas: Yahoo's bare /rss
// returns 403 (use /rss/topstories); Travel + Leisure blocks non-browser
// clients entirely (excluded).

module.exports = [
  // News
  { id: 'yahoo',        displayName: 'Yahoo News',           category: 'News',          feedUrl: 'https://news.yahoo.com/rss/topstories',                        homepage: 'https://news.yahoo.com',              color: '#6001D2' },
  { id: 'bbc',          displayName: 'BBC News',             category: 'News',          feedUrl: 'https://feeds.bbci.co.uk/news/rss.xml',                        homepage: 'https://www.bbc.com/news',            color: '#BB1919' },
  { id: 'npr',          displayName: 'NPR',                  category: 'News',          feedUrl: 'https://feeds.npr.org/1001/rss.xml',                           homepage: 'https://www.npr.org',                 color: '#237BBD' },
  { id: 'nyt',          displayName: 'New York Times',       category: 'News',          feedUrl: 'https://rss.nytimes.com/services/xml/rss/nyt/HomePage.xml',    homepage: 'https://www.nytimes.com',             color: '#000000' },

  // Business
  { id: 'cnbc',         displayName: 'CNBC',                 category: 'Business',      feedUrl: 'https://www.cnbc.com/id/100003114/device/rss/rss.html',        homepage: 'https://www.cnbc.com',                color: '#005594' },

  // Tech
  { id: 'techcrunch',   displayName: 'TechCrunch',           category: 'Tech',          feedUrl: 'https://techcrunch.com/feed/',                                 homepage: 'https://techcrunch.com',              color: '#0A8935' },
  { id: 'wired',        displayName: 'WIRED',                category: 'Tech',          feedUrl: 'https://www.wired.com/feed/rss',                               homepage: 'https://www.wired.com',               color: '#000000' },

  // Sports
  { id: 'espn',         displayName: 'ESPN',                 category: 'Sports',        feedUrl: 'https://www.espn.com/espn/rss/news',                           homepage: 'https://www.espn.com',                color: '#D00000' },

  // Fashion & Style
  { id: 'vogue',        displayName: 'Vogue',                category: 'Fashion',       feedUrl: 'https://www.vogue.com/feed/rss',                               homepage: 'https://www.vogue.com',               color: '#000000' },
  { id: 'gq',           displayName: 'GQ',                   category: 'Fashion',       feedUrl: 'https://www.gq.com/feed/rss',                                  homepage: 'https://www.gq.com',                  color: '#000000' },

  // Travel
  { id: 'cntraveler',   displayName: 'Condé Nast Traveler',  category: 'Travel',        feedUrl: 'https://www.cntraveler.com/feed/rss',                          homepage: 'https://www.cntraveler.com',          color: '#C8102E' },
  { id: 'atlasobscura', displayName: 'Atlas Obscura',        category: 'Travel',        feedUrl: 'https://www.atlasobscura.com/feeds/latest',                    homepage: 'https://www.atlasobscura.com',        color: '#B5541B' },

  // Food
  { id: 'eater',        displayName: 'Eater',                category: 'Food',          feedUrl: 'https://www.eater.com/rss/index.xml',                          homepage: 'https://www.eater.com',               color: '#D2232A' },
  { id: 'bonappetit',   displayName: 'Bon Appétit',          category: 'Food',          feedUrl: 'https://www.bonappetit.com/feed/rss',                          homepage: 'https://www.bonappetit.com',          color: '#E4002B' },

  // Entertainment & Design
  { id: 'variety',      displayName: 'Variety',              category: 'Entertainment', feedUrl: 'https://variety.com/feed/',                                    homepage: 'https://variety.com',                 color: '#1A282C' },
  { id: 'archdigest',   displayName: 'Architectural Digest', category: 'Design',        feedUrl: 'https://www.architecturaldigest.com/feed/rss',                 homepage: 'https://www.architecturaldigest.com', color: '#000000' }
];
