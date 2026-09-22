// backend/services/venueStorefront.js
//
// The storefront: what an owner puts on their store's page beyond loyalty —
// their menu (or services, products, rooms), the buttons that make money
// (reserve / order / catering / book), and a gallery of their own photos.
//
// Stored on the venue doc under `storefront.{offerings,actions,gallery}`.
// Pure rules here; the controller does I/O.
//
// Gating: offerings and gallery are Business-tier (they hide when the
// owner's subscription lapses, like announcements). Actions are free — a
// working Reserve button helps the customer whoever is paying.

const MAX_FEATURED_ITEMS = 8;
const MAX_MENU_FILES = 6;
const MAX_GALLERY_PHOTOS = 12;
const MAX_TAGS_PER_ITEM = 3;

const ACTION_KEYS = ['reserve', 'order', 'catering', 'book'];
const ACTION_LABELS = { reserve: 'Reserve', order: 'Order', catering: 'Catering', book: 'Book' };

/** The word for "the thing this store sells", by venue category. */
const offeringsLabel = (category) => {
  switch (category) {
    case 'restaurant': case 'cafe': case 'bar': return 'Menu';
    case 'hotel': return 'Rooms';
    case 'retail': return 'Products';
    case 'service': case 'healthcare': case 'fitness': case 'education': case 'finance': return 'Services';
    default: return 'What we offer';
  }
};

const isHttpsUrl = (value) => {
  try {
    const u = new URL(String(value));
    return u.protocol === 'https:' || u.protocol === 'http:';
  } catch (e) { return false; }
};

const cleanText = (v, max) => String(v == null ? '' : v).trim().slice(0, max);

/**
 * Normalizes and validates a submitted offerings block. Returns
 * { value, errors }. `value` is safe to store when errors is empty.
 */
const normalizeOfferings = (input = {}) => {
  const errors = [];
  const out = { link: null, files: [], featured: [] };

  if (input.link !== undefined && input.link !== null && String(input.link).trim() !== '') {
    if (!isHttpsUrl(input.link)) errors.push('link must be a web address');
    else out.link = String(input.link).trim();
  }

  const files = Array.isArray(input.files) ? input.files : [];
  if (files.length > MAX_MENU_FILES) errors.push(`at most ${MAX_MENU_FILES} menu files`);
  files.slice(0, MAX_MENU_FILES).forEach((f, i) => {
    if (!f || !isHttpsUrl(f.url)) { errors.push(`files[${i}].url must be a web address`); return; }
    const kind = f.kind === 'pdf' ? 'pdf' : 'image';
    out.files.push({ url: String(f.url).trim(), kind, label: cleanText(f.label, 60) || null });
  });

  const featured = Array.isArray(input.featured) ? input.featured : [];
  if (featured.length > MAX_FEATURED_ITEMS) errors.push(`at most ${MAX_FEATURED_ITEMS} featured items`);
  featured.slice(0, MAX_FEATURED_ITEMS).forEach((item, i) => {
    const name = cleanText(item && item.name, 60);
    if (!name) { errors.push(`featured[${i}].name is required`); return; }
    let price = null;
    if (item.price !== undefined && item.price !== null && String(item.price).trim() !== '') {
      price = cleanText(item.price, 20);
    }
    if (item.photoUrl && !isHttpsUrl(item.photoUrl)) errors.push(`featured[${i}].photoUrl must be a web address`);
    const tags = (Array.isArray(item.tags) ? item.tags : [])
      .map((t) => cleanText(t, 24)).filter(Boolean).slice(0, MAX_TAGS_PER_ITEM);
    out.featured.push({
      itemId: cleanText(item.itemId, 40) || `item_${Date.now()}_${i}`,
      name,
      price,
      description: cleanText(item.description, 200) || null,
      photoUrl: item.photoUrl ? String(item.photoUrl).trim() : null,
      tags
    });
  });

  return { value: out, errors };
};

/** Each action is a URL or absent. Unknown keys are dropped, not errors. */
const normalizeActions = (input = {}) => {
  const errors = [];
  const out = {};
  ACTION_KEYS.forEach((key) => {
    const v = input[key];
    if (v === undefined || v === null || String(v).trim() === '') { out[key] = null; return; }
    if (!isHttpsUrl(v)) { errors.push(`${key} must be a web address`); return; }
    out[key] = String(v).trim();
  });
  return { value: out, errors };
};

const normalizeGallery = (input = []) => {
  const errors = [];
  const photos = Array.isArray(input) ? input : [];
  if (photos.length > MAX_GALLERY_PHOTOS) errors.push(`at most ${MAX_GALLERY_PHOTOS} gallery photos`);
  const out = [];
  photos.slice(0, MAX_GALLERY_PHOTOS).forEach((p, i) => {
    if (!p || !isHttpsUrl(p.url)) { errors.push(`photos[${i}].url must be a web address`); return; }
    out.push({
      photoId: cleanText(p.photoId, 40) || `photo_${Date.now()}_${i}`,
      url: String(p.url).trim(),
      caption: cleanText(p.caption, 80) || null
    });
  });
  return { value: out, errors };
};

/**
 * What a customer sees. `live` = the venue's paid features are on (owner
 * has Business for this venue, or it's comped). Actions always show; the
 * label rides along so the client never has to know the category rule.
 */
const publicStorefront = (venue, { live }) => {
  const s = (venue && venue.storefront) || {};
  const actions = {};
  ACTION_KEYS.forEach((k) => { actions[k] = (s.actions && s.actions[k]) || null; });
  const hasAnyAction = ACTION_KEYS.some((k) => actions[k]);
  const offerings = live && s.offerings ? s.offerings : null;
  const gallery = live && Array.isArray(s.gallery) ? s.gallery : [];
  const hasOfferings = !!(offerings && (offerings.link || (offerings.files || []).length || (offerings.featured || []).length));
  if (!hasAnyAction && !hasOfferings && !gallery.length) return null;
  return {
    offeringsLabel: offeringsLabel(venue.category),
    offerings: hasOfferings ? offerings : null,
    actions: hasAnyAction ? actions : null,
    gallery
  };
};

/** The owner's own view: everything, whether or not it's live yet. */
const ownerStorefront = (venue) => {
  const s = (venue && venue.storefront) || {};
  return {
    offeringsLabel: offeringsLabel(venue.category),
    offerings: s.offerings || { link: null, files: [], featured: [] },
    actions: Object.fromEntries(ACTION_KEYS.map((k) => [k, (s.actions && s.actions[k]) || null])),
    gallery: Array.isArray(s.gallery) ? s.gallery : []
  };
};

module.exports = {
  MAX_FEATURED_ITEMS, MAX_MENU_FILES, MAX_GALLERY_PHOTOS, MAX_TAGS_PER_ITEM,
  ACTION_KEYS, ACTION_LABELS,
  offeringsLabel, normalizeOfferings, normalizeActions, normalizeGallery,
  publicStorefront, ownerStorefront
};
