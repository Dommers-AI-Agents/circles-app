// backend/services/newsService.js
// Fetches, parses, and caches the publisher RSS feeds behind the News tab.
// The app only ever sees the clean extracted JSON below — feed-format quirks
// live here. Cache is in-memory per Cloud Run instance (10-min TTL); on a
// fetch failure the stale cache keeps serving, so one flaky publisher never
// blanks the merged feed.

const crypto = require('crypto');
const Parser = require('rss-parser');
const NEWS_SOURCES = require('../config/newsSources');

const CACHE_TTL_MS = 10 * 60 * 1000;
const MAX_ITEMS_PER_SOURCE = 15;
const MAX_TOTAL_ITEMS = 60;

const parser = new Parser({
  timeout: 8000,
  headers: { 'User-Agent': 'CirclesApp/1.0 (+https://favcircles.com)' },
  customFields: {
    item: [
      ['media:content', 'mediaContent', { keepArray: true }],
      ['media:thumbnail', 'mediaThumbnail', { keepArray: true }],
      ['content:encoded', 'contentEncoded']
    ]
  }
});

// sourceId -> { items: [extracted], fetchedAt: ms }
const cache = new Map();
// sourceId -> Promise — dedupes concurrent fetches of the same source
const inFlight = new Map();

const catalogById = new Map(NEWS_SOURCES.map((s) => [s.id, s]));

// Thumbnails must be https for the app (ATS); upgrade or drop
const httpsOrNull = (url) => {
  if (!url || typeof url !== 'string') return null;
  if (url.startsWith('https://')) return url;
  if (url.startsWith('http://')) return url.replace(/^http:\/\//, 'https://');
  return null;
};

const extractThumbnail = (item) => {
  // media:content — prefer explicit images, pick the widest variant
  const mediaContent = (item.mediaContent || [])
    .map((m) => m && m.$)
    .filter((attrs) => attrs && attrs.url)
    .filter((attrs) => {
      if (attrs.medium) return attrs.medium === 'image';
      if (attrs.type) return String(attrs.type).startsWith('image/');
      return true;
    })
    .sort((a, b) => (parseInt(b.width, 10) || 0) - (parseInt(a.width, 10) || 0));
  if (mediaContent.length > 0) return httpsOrNull(mediaContent[0].url);

  const mediaThumbnail = (item.mediaThumbnail || []).map((m) => m && m.$).find((attrs) => attrs && attrs.url);
  if (mediaThumbnail) return httpsOrNull(mediaThumbnail.url);

  if (item.enclosure && item.enclosure.url && String(item.enclosure.type || '').startsWith('image/')) {
    return httpsOrNull(item.enclosure.url);
  }

  const html = item.contentEncoded || item.content || '';
  const imgMatch = /<img[^>]+src=["']([^"']+)["']/i.exec(html);
  if (imgMatch) return httpsOrNull(imgMatch[1]);

  return null;
};

const truncateSnippet = (text, maxLength = 200) => {
  const trimmed = String(text || '').replace(/\s+/g, ' ').trim();
  if (!trimmed) return null;
  if (trimmed.length <= maxLength) return trimmed;
  const cut = trimmed.slice(0, maxLength);
  const lastSpace = cut.lastIndexOf(' ');
  return `${cut.slice(0, lastSpace > 100 ? lastSpace : maxLength)}…`;
};

const extractItem = (item, source, fetchedAtISO) => {
  const idSeed = item.link || item.guid || item.title || Math.random().toString();
  let pubDate = fetchedAtISO;
  const parsed = new Date(item.isoDate || item.pubDate || '');
  if (!Number.isNaN(parsed.getTime())) pubDate = parsed.toISOString();

  return {
    id: crypto.createHash('md5').update(idSeed).digest('hex'),
    title: String(item.title || '').trim(),
    link: item.link || source.homepage,
    sourceId: source.id,
    sourceName: source.displayName,
    pubDate,
    thumbnailUrl: extractThumbnail(item),
    snippet: truncateSnippet(item.contentSnippet)
  };
};

// Some publishers (CNBC, TechCrunch) ship image-less RSS — no media tags,
// no enclosures, nothing. For those items, pull the article page's og:image
// meta tag instead (present on every article for social sharing). Runs once
// per cache cycle, best-effort, capped per source.
const OG_ENRICH_LIMIT = MAX_ITEMS_PER_SOURCE;
const OG_FETCH_TIMEOUT_MS = 5000;
const OG_BODY_CAP_BYTES = 64 * 1024; // og:image lives in <head>; never read whole pages

const fetchOgImage = async (articleUrl) => {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), OG_FETCH_TIMEOUT_MS);
  try {
    const response = await fetch(articleUrl, {
      signal: controller.signal,
      redirect: 'follow',
      headers: {
        'User-Agent': 'Mozilla/5.0 (compatible; CirclesApp/1.0; +https://favcircles.com)',
        Accept: 'text/html'
      }
    });
    if (!response.ok || !response.body) return null;

    let html = '';
    const reader = response.body.getReader();
    const decoder = new TextDecoder();
    while (html.length < OG_BODY_CAP_BYTES) {
      const { done, value } = await reader.read();
      if (done) break;
      html += decoder.decode(value, { stream: true });
    }
    reader.cancel().catch(() => {});

    const match = /<meta[^>]+property=["']og:image["'][^>]+content=["']([^"']+)["']/i.exec(html)
      || /<meta[^>]+content=["']([^"']+)["'][^>]+property=["']og:image["']/i.exec(html);
    return match ? httpsOrNull(match[1].replace(/&amp;/g, '&')) : null;
  } catch (error) {
    return null;
  } finally {
    clearTimeout(timer);
  }
};

const enrichMissingThumbnails = async (items) => {
  const missing = items.filter((item) => !item.thumbnailUrl).slice(0, OG_ENRICH_LIMIT);
  if (missing.length === 0) return;
  await Promise.allSettled(missing.map(async (item) => {
    const ogImage = await fetchOgImage(item.link);
    if (ogImage) item.thumbnailUrl = ogImage;
  }));
};

const fetchSource = async (source) => {
  const cached = cache.get(source.id);
  if (cached && Date.now() - cached.fetchedAt < CACHE_TTL_MS) {
    return cached.items;
  }

  if (inFlight.has(source.id)) {
    return inFlight.get(source.id);
  }

  const fetchPromise = (async () => {
    try {
      const feed = await parser.parseURL(source.feedUrl);
      const fetchedAtISO = new Date().toISOString();
      const items = (feed.items || [])
        .slice(0, MAX_ITEMS_PER_SOURCE)
        .map((item) => extractItem(item, source, fetchedAtISO))
        .filter((item) => item.title && item.link);
      await enrichMissingThumbnails(items);
      cache.set(source.id, { items, fetchedAt: Date.now() });
      return items;
    } catch (error) {
      console.error(`⚠️ News fetch failed for ${source.id}:`, error.message);
      // Serve stale cache rather than nothing
      if (cached) return cached.items;
      throw error;
    } finally {
      inFlight.delete(source.id);
    }
  })();

  inFlight.set(source.id, fetchPromise);
  return fetchPromise;
};

// Catalog for clients — feed URLs stay server-side
const getCatalog = () => NEWS_SOURCES.map(({ id, displayName, category, homepage, color }) => ({
  id, displayName, category, homepage, color
}));

const isValidSourceId = (id) => catalogById.has(id);

// Merged, newest-first feed for the given source ids. A failing source is
// reported in `sourcesFailed`, never thrown.
const getFeedForSources = async (sourceIds) => {
  const sources = [...new Set(sourceIds || [])]
    .map((id) => catalogById.get(id))
    .filter(Boolean);

  const results = await Promise.allSettled(sources.map(fetchSource));

  const articles = [];
  const sourcesFailed = [];
  results.forEach((result, index) => {
    if (result.status === 'fulfilled') {
      articles.push(...result.value);
    } else {
      sourcesFailed.push(sources[index].id);
    }
  });

  articles.sort((a, b) => b.pubDate.localeCompare(a.pubDate));

  return { articles: articles.slice(0, MAX_TOTAL_ITEMS), sourcesFailed };
};

module.exports = { getCatalog, getFeedForSources, isValidSourceId };
