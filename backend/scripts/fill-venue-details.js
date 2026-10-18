// One-time: make every venue's shared details complete BEFORE reads stop
// falling back to each save's own copy (Wes, 2026-10-18).
//   A. Google-matched venues missing website / phone / hours → Google
//      (services/venueGoogleDetails.fillVenue, empty fields only, ~2¢ each).
//   B. Venues still missing website / phone → the value their saves carry
//      in "Phone:/Website:" lines, when every save agrees. For a Google
//      venue only after Google was asked and had nothing (Google wins
//      whenever it has an answer — Flower Child carried another store's).
//   C. Venues with no description → their saves' real description text
//      (generated filler like "A dining establishment in …" never counts),
//      when every save agrees.
// Disagreements are listed, never guessed. Idempotent. DRY_RUN=true (default)
// changes nothing and makes no Google calls.
//   node scripts/fill-venue-details.js            # preview
//   DRY_RUN=false node scripts/fill-venue-details.js
require('dotenv').config();
require('../config/firebase').initializeFirebase();
const fs = require('fs');
const db = require('../config/firebase').getFirestore();
const { fillVenue, missingFields } = require('../services/venueGoogleDetails');
const { sanitizeVenueDescription } = require('../utils/venueDescriptionSanitizer');

const DRY = process.env.DRY_RUN !== 'false';
const OUT = process.env.OUT || '/tmp/fill-venue-details.json';

const CONTACT = /^\s*(Phone|Website):\s*(.+?)\s*$/i;
function parseDescription(text) {
  const out = { phone: null, website: null, text: '' };
  const rest = [];
  for (const line of String(text || '').split('\n')) {
    const m = CONTACT.exec(line);
    if (m) out[m[1].toLowerCase()] = m[2];
    else if (line.trim() && !/^\s*Rating:/i.test(line)) rest.push(line.trim());
  }
  // Generated filler ("A dining establishment in Charlotte") isn't a description
  out.text = sanitizeVenueDescription(rest.join('\n')) || '';
  return out;
}
const normWebsite = (u) => String(u || '').toLowerCase().replace(/^https?:\/\//, '').replace(/^www\./, '').replace(/[?#].*$/, '').replace(/\/+$/, '');
const normPhone = (p) => String(p || '').replace(/\D/g, '').replace(/^1(?=\d{10}$)/, '');

/** The one value every save agrees on, or { conflict } / null. */
function agreed(values, norm) {
  const byKey = new Map();
  for (const v of values) if (v && norm(v)) byKey.set(norm(v), byKey.get(norm(v)) || v);
  if (byKey.size === 0) return null;
  if (byKey.size > 1) return { conflict: [...byKey.values()] };
  return { value: [...byKey.values()][0] };
}

(async () => {
  const venues = (await db.collection('globalPlaces').get()).docs
    .filter((d) => !d.data().deletedAt && !d.data().mergedInto);
  const saves = (await db.collection('places').where('deletedAt', '==', null).get()).docs;
  const savesByVenue = new Map();
  for (const s of saves) {
    const id = s.data().globalPlaceId;
    if (!id) continue;
    if (!savesByVenue.has(id)) savesByVenue.set(id, []);
    savesByVenue.get(id).push(parseDescription(s.data().description));
  }

  const report = { dryRun: DRY, google: { candidates: 0, filled: {}, skipped: {} }, adopted: { phone: 0, website: 0, description: 0 },
    hiddenOnGoogleVenues: { phoneOrWebsite: 0 }, conflicts: [] };

  // A. Google
  const googleTodo = venues.filter((d) => {
    const v = d.data();
    if (!v.googlePlaceId || (v.googleData && v.googleData.detailsCheckedAt)) return false;
    const m = missingFields(v);
    return m.website || m.phone || m.openingHours;
  });
  report.google.candidates = googleTodo.length;
  if (!DRY) {
    for (let i = 0; i < googleTodo.length; i += 5) {
      const results = await Promise.all(googleTodo.slice(i, i + 5).map((d) => fillVenue(d.id)));
      for (const r of results) {
        if (r.filled) for (const f of r.filled) report.google.filled[f] = (report.google.filled[f] || 0) + 1;
        if (r.skipped) report.google.skipped[r.skipped] = (report.google.skipped[r.skipped] || 0) + 1;
      }
      if (i % 100 === 0) console.log(`google ${i}/${googleTodo.length}`);
    }
  }

  // B + C. From the saves, reading each venue as it is now (after Google)
  const now = new Date().toISOString();
  for (const stale of venues) {
    const d = DRY ? stale : await stale.ref.get();
    const v = d.data();
    const parsed = savesByVenue.get(d.id) || [];
    if (parsed.length === 0) continue;
    const g = v.googleData || {};
    const own = parseDescription(v.description);
    const has = { phone: !!(g.phone || own.phone), website: !!(g.website || own.website), description: !!own.text };
    const phone = has.phone ? null : agreed(parsed.map((p) => p.phone), normPhone);
    const website = has.website ? null : agreed(parsed.map((p) => p.website), normWebsite);
    const text = has.description ? null : agreed(parsed.map((p) => p.text), (t) => t.toLowerCase().replace(/\s+/g, ' ').trim());

    // A Google venue takes a save's phone / website only once Google was
    // asked and had none; a description is only ever what people wrote
    const googleAnswered = !v.googlePlaceId || !!(g.detailsCheckedAt);
    if (!googleAnswered && ((phone && phone.value) || (website && website.value))) report.hiddenOnGoogleVenues.phoneOrWebsite++;
    const update = {};
    const sources = googleAnswered ? [['phone', phone], ['website', website], ['description', text]] : [['description', text]];
    for (const [field, r] of sources) {
      if (!r) continue;
      if (r.conflict) { report.conflicts.push({ venueId: d.id, name: v.name, field, values: r.conflict }); continue; }
      if (field === 'description') update.description = r.value;
      else update[`googleData.${field}`] = r.value;
      report.adopted[field]++;
    }
    if (!DRY && Object.keys(update).length) await stale.ref.update({ ...update, updatedAt: now });
  }

  fs.writeFileSync(OUT, JSON.stringify(report, null, 2));
  console.log(JSON.stringify({ ...report, conflicts: report.conflicts.length }, null, 2));
  console.log(`conflicts listed in ${OUT}`);
  process.exit(0);
})().catch((e) => { console.error(e); process.exit(1); });
