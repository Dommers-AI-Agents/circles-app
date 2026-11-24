// backend/services/venueSocialLinks.js
//
// A store's Instagram, Facebook and X (Twitter) links (Wes, 2026-11-24:
// "we are missing links on place view of stores to instagram, facebook,
// twitter"). The store's team types a handle or pastes a link in Manage
// Store → Store details; the place page shows a button per link that is set
// and nothing at all when none are.
//
// Stored on the canonical venue record as `socialLinks.{network}`, always a
// full https address on that network's own site, so the app never opens a
// link someone typed that goes somewhere else. Written only through
// venueDetailsService. Pure.

const { ServiceError } = require('../utils/serviceError');

const NETWORKS = {
  instagram: {
    label: 'Instagram',
    hosts: ['instagram.com', 'instagr.am'],
    home: 'https://www.instagram.com/',
    handle: /^[A-Za-z0-9._]{1,30}$/,
    keepQuery: false
  },
  facebook: {
    label: 'Facebook',
    hosts: ['facebook.com', 'fb.com', 'fb.me'],
    home: 'https://www.facebook.com/',
    handle: /^[A-Za-z0-9.\-]{2,80}$/,
    // facebook.com/profile.php?id=… is a real page address
    keepQuery: true
  },
  twitter: {
    label: 'X',
    hosts: ['x.com', 'twitter.com'],
    home: 'https://x.com/',
    handle: /^[A-Za-z0-9_]{1,15}$/,
    keepQuery: false
  }
};

const SOCIAL_FIELDS = Object.keys(NETWORKS);

const invalid = (network) => new ServiceError(400, 'INVALID_SOCIAL_LINK',
  `That doesn't look like ${network.label === 'X' ? 'an X' : `a${/^[AEIOU]/.test(network.label) ? 'n' : ''} ${network.label}`} link. Enter your handle (like @yourstore) or paste your page's address.`);

const onNetwork = (host, network) => {
  const h = host.toLowerCase().replace(/^(www|m|mobile)\./, '');
  return network.hosts.includes(h);
};

/**
 * What the store typed → the link to keep: null for blank (the link is
 * removed), a full https address otherwise. Throws ServiceError 400 for
 * anything that isn't a handle or an address on that network.
 */
const normalizeSocialLink = (field, input) => {
  const network = NETWORKS[field];
  if (!network) throw new ServiceError(400, 'INVALID_SOCIAL_LINK', 'Unknown link.');
  const text = String(input == null ? '' : input).trim();
  if (!text) return null;
  if (text.length > 300) throw invalid(network);

  // "@giddygoat" or "giddygoat"
  const bare = text.replace(/^@/, '');
  if (network.handle.test(bare) && !/\.(com|am|me)$/i.test(bare)) return network.home + bare;

  // "instagram.com/giddygoat", with or without https://
  let url;
  try {
    url = new URL(/^https?:\/\//i.test(text) ? text : `https://${text}`);
  } catch (_) {
    throw invalid(network);
  }
  if (!onNetwork(url.hostname, network)) throw invalid(network);
  const path = url.pathname.replace(/\/+$/, '');
  if (!path || path === '/') throw invalid(network); // the network's front page is not the store's page
  const host = url.hostname.toLowerCase().replace(/^(m|mobile)\./, 'www.');
  return `https://${host}${path}${network.keepQuery ? url.search : ''}`;
};

/** The links that are set, for a reader: { instagram, facebook, twitter } or null. */
const socialLinksOf = (venue) => {
  const stored = (venue && venue.socialLinks) || {};
  const out = {};
  SOCIAL_FIELDS.forEach((field) => {
    if (typeof stored[field] === 'string' && stored[field].trim()) out[field] = stored[field].trim();
  });
  return Object.keys(out).length > 0 ? out : null;
};

module.exports = { NETWORKS, SOCIAL_FIELDS, normalizeSocialLink, socialLinksOf };
