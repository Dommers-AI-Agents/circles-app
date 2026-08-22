// backend/services/mapDigestService.js
//
// Weekly "your personal map" email — the product's core idea, reinforced:
// first and foremost you are building YOUR OWN map. Each week the digest
// picks one of the user's map views that actually looks great ("All your
// favorite bars — one map", "Your restaurants in Charlotte") renders it as
// an image, and mails it with open/share links.
//
// Cost model: $0 per email. Maps render server-side from OpenStreetMap
// tiles (policy-compliant: tiny volume, proper User-Agent, attribution in
// the email) and are uploaded once to Firebase Storage — email opens hit
// our storage, never a billed maps API.

const StaticMaps = require('staticmaps');
const { getFirestore } = require('../config/firebase');
const { COLLECTIONS } = require('../models/FirestoreModels');
const emailService = require('./emailService');
const { uploadImage } = require('./storage');

const db = getFirestore();

const BRAND_BLUE = '#3478F6';

// category value -> what a human calls a group of them
const CATEGORY_PLURAL = {
  restaurant: 'restaurants',
  cafe: 'coffee spots',
  bar: 'bars',
  hotel: 'hotels',
  retail: 'shops',
  outdoor: 'outdoor spots',
  attraction: 'attractions',
  entertainment: 'entertainment spots',
  fitness: 'fitness spots',
  beauty: 'beauty spots',
  healthcare: 'health spots',
  education: 'schools',
  service: 'services',
  finance: 'finance spots',
  transport: 'transit spots',
  other: 'places'
};

const toRad = (deg) => (deg * Math.PI) / 180;
const distanceKm = (a, b) => {
  const R = 6371;
  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);
  const s = Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(s));
};

/** "1425, Winnifred St, Charlotte, NC, 28203, United States" → "Charlotte".
 *  Address formats vary; a null city just drops the city from the headline. */
const cityFromAddress = (address) => {
  if (!address || typeof address !== 'string') return null;
  const parts = address.split(',').map((p) => p.trim()).filter(Boolean);
  if (parts.length < 3) return null;
  // Walk back from the tail past country/zip/state tokens to the locality
  const junk = (s) => /\d/.test(s) || /^[A-Z]{2}$/.test(s) || /united states|usa/i.test(s);
  let i = parts.length - 1;
  while (i > 0 && junk(parts[i])) i--;
  const candidate = parts[i];
  return candidate && !junk(candidate) && candidate.length >= 3 ? candidate : null;
};

class MapDigestService {

  /** The user's own mapped places (coords present, not deleted). */
  async mappedPlaces(userId) {
    const snap = await db.collection(COLLECTIONS.PLACES)
      .where('addedBy', '==', userId)
      .get();
    const places = [];
    snap.forEach((doc) => {
      const p = doc.data();
      if (p.deletedAt) return;
      const c = p.location && p.location.coordinates;
      if (!Array.isArray(c) || c.length !== 2 || (c[0] === 0 && c[1] === 0)) return;
      places.push({
        id: doc.id,
        name: p.name,
        category: p.category || 'other',
        address: p.address || null,
        lng: c[0],
        lat: c[1]
      });
    });
    return places;
  }

  /** Candidate views: per category, the densest geographic cluster (12km
   *  greedy). Sorted by size; each carries a headline. */
  buildCandidateViews(places) {
    const byCategory = new Map();
    for (const p of places) {
      if (!byCategory.has(p.category)) byCategory.set(p.category, []);
      byCategory.get(p.category).push(p);
    }

    const views = [];
    for (const [category, group] of byCategory) {
      if (group.length < 3 || category === 'other') continue;

      // Greedy densest cluster: best center = the place with the most
      // neighbors within 12km
      let best = null;
      for (const center of group) {
        const cluster = group.filter((p) => distanceKm(center, p) <= 12);
        if (!best || cluster.length > best.length) best = cluster;
      }

      const plural = CATEGORY_PLURAL[category] || 'places';
      const cityVotes = new Map();
      for (const p of best) {
        const city = cityFromAddress(p.address);
        if (city) cityVotes.set(city, (cityVotes.get(city) || 0) + 1);
      }
      const topCity = [...cityVotes.entries()].sort((a, b) => b[1] - a[1])[0];
      const city = topCity && topCity[1] >= Math.ceil(best.length / 2) ? topCity[0] : null;

      // Whole-category view when the cluster IS the category; city view
      // when it's a local slice
      const isWholeCategory = best.length === group.length;
      const headline = city
        ? `All your favorite ${plural} in ${city}`
        : `All your favorite ${plural} — one map`;

      views.push({
        category,
        plural,
        city,
        headline,
        places: best,
        score: best.length + (city ? 0.5 : 0) + (isWholeCategory ? 0.25 : 0)
      });
    }

    return views.sort((a, b) => b.score - a.score);
  }

  /** Render the view to a PNG buffer: OSM tiles + brand-blue dots. */
  async renderViewImage(view) {
    const map = new StaticMaps({
      width: 1200,
      height: 700,
      paddingX: 90,
      paddingY: 90,
      tileUrl: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      tileRequestHeader: {
        'User-Agent': 'FavCircles-weekly-map-digest/1.0 (wesley@favcircles.com)'
      }
    });

    // Dot size scales with the view's span so pins read at any zoom
    const lats = view.places.map((p) => p.lat);
    const lngs = view.places.map((p) => p.lng);
    const spanKm = Math.max(
      distanceKm({ lat: Math.min(...lats), lng: Math.min(...lngs) },
                 { lat: Math.max(...lats), lng: Math.max(...lngs) }),
      1
    );
    const radiusMeters = Math.max(60, Math.min(600, (spanKm * 1000) / 55));

    for (const p of view.places) {
      map.addCircle({
        coord: [p.lng, p.lat],
        radius: radiusMeters,
        fill: `${BRAND_BLUE}CC`,
        color: '#FFFFFF',
        width: 3
      });
    }

    await map.render();
    return map.image.buffer('image/png');
  }

  /** Renders, uploads, and returns a hosted image URL for the view. */
  async hostedViewImage(view, userId) {
    const buffer = await this.renderViewImage(view);
    const base64 = buffer.toString('base64');
    const url = await uploadImage(base64, `map-digest-${userId}.png`);
    return url;
  }

  buildEmailHtml({ user, view, imageUrl }) {
    const firstName = (user.displayName || 'there').split(' ')[0];
    const count = view.places.length;
    const sampleNames = view.places.slice(0, 6).map((p) => p.name);
    const profileUrl = `https://api.favcircles.com/user/${user.id}`;
    const mapUrl = `https://api.favcircles.com/app/map?focus=${encodeURIComponent(view.category)}`;

    const listItems = sampleNames
      .map((n) => `<li style="margin:4px 0;color:#333;">${n}</li>`)
      .join('');
    const moreLine = count > sampleNames.length
      ? `<p style="color:#666;font-size:14px;margin:6px 0 0;">…and ${count - sampleNames.length} more on your map.</p>`
      : '';

    return `
<div style="font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;max-width:600px;margin:0 auto;background:#ffffff;">
  <div style="background:${BRAND_BLUE};padding:26px 24px;border-radius:0 0 14px 14px;">
    <h1 style="color:#ffffff;margin:0;font-size:22px;">Your map is growing, ${firstName} 🗺️</h1>
    <p style="color:rgba(255,255,255,0.92);margin:8px 0 0;font-size:15px;">
      ${view.headline} — ${count} place${count === 1 ? '' : 's'}, all yours.
    </p>
  </div>

  <div style="padding:20px 24px 0;">
    <a href="${mapUrl}" style="text-decoration:none;">
      <img src="${imageUrl}" alt="${view.headline}" width="552" style="width:100%;border-radius:12px;border:1px solid #e5e5e5;display:block;" />
    </a>
    <p style="color:#999;font-size:11px;margin:6px 0 0;">Map data © OpenStreetMap contributors</p>
  </div>

  <div style="padding:18px 24px 0;">
    <ul style="margin:0;padding-left:20px;font-size:15px;">${listItems}</ul>
    ${moreLine}
  </div>

  <div style="padding:22px 24px;text-align:center;">
    <a href="${mapUrl}"
       style="display:inline-block;background:${BRAND_BLUE};color:#ffffff;text-decoration:none;font-weight:600;font-size:16px;padding:13px 28px;border-radius:9px;">
      Open your map
    </a>
    <p style="margin:14px 0 0;font-size:14px;">
      <a href="${profileUrl}" style="color:${BRAND_BLUE};text-decoration:underline;">Share this map with a friend</a>
      — they'll see every place the moment they follow you.
    </p>
  </div>

  <div style="padding:0 24px 26px;color:#999;font-size:12px;text-align:center;">
    <p style="margin:0;">You're getting this because every place you save builds your personal map on FavCircles.</p>
    <p style="margin:6px 0 0;">Prefer not to get the weekly map? Manage emails in the app: Profile → Settings → Notifications.</p>
  </div>
</div>`;
  }

  /** Build + send one user's digest. Returns a result descriptor. */
  async sendDigestToUser(user, { toOverride = null } = {}) {
    if (user.emailPreferences && user.emailPreferences.weeklyMapDigest === false) {
      return { userId: user.id, sent: false, reason: 'opted_out' };
    }
    const email = toOverride || user.email;
    if (!email || email.endsWith('@privaterelay.appleid.com')) {
      return { userId: user.id, sent: false, reason: 'no_usable_email' };
    }

    const places = await this.mappedPlaces(user.id);
    const views = this.buildCandidateViews(places);
    if (views.length === 0) {
      return { userId: user.id, sent: false, reason: 'no_view_worth_sending' };
    }

    // Rotate through the user's best views week to week so consecutive
    // emails show different slices of their map
    const week = Math.floor(Date.now() / (7 * 24 * 3600 * 1000));
    const view = views[week % Math.min(views.length, 4)];

    const imageUrl = await this.hostedViewImage(view, user.id);
    const html = this.buildEmailHtml({ user, view, imageUrl });
    const count = view.places.length;
    const subject = view.city
      ? `${count} favorite ${view.plural} in ${view.city} — your map 🗺️`
      : `All ${count} of your favorite ${view.plural} — one map 🗺️`;

    await emailService.sendEmail({
      to: email,
      subject,
      html,
      text: `${view.headline} — ${count} places on your FavCircles map. Open the app to see it: https://api.favcircles.com/app/map?focus=${view.category}`
    });

    return { userId: user.id, sent: true, headline: view.headline, count, imageUrl };
  }

  /** Weekly pass over active users. Gated behind WEEKLY_MAP_DIGEST_ENABLED. */
  async runWeeklyDigest() {
    const usersSnap = await db.collection(COLLECTIONS.USERS).get();
    const results = { sent: 0, skipped: 0 };
    for (const doc of usersSnap.docs) {
      const user = { id: doc.id, ...doc.data() };
      try {
        const r = await this.sendDigestToUser(user);
        if (r.sent) {
          results.sent++;
          console.log(`🗺️ Map digest sent to ${user.email}: ${r.headline} (${r.count})`);
        } else {
          results.skipped++;
        }
        // Gentle pacing for the SMTP server and the OSM tile servers
        await new Promise((res) => setTimeout(res, 1500));
      } catch (e) {
        results.skipped++;
        console.error(`🗺️ Map digest failed for ${user.id}:`, e.message);
      }
    }
    console.log(`🗺️ Weekly map digest complete: ${results.sent} sent, ${results.skipped} skipped`);
    return results;
  }
}

module.exports = new MapDigestService();
