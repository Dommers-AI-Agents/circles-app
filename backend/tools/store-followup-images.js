#!/usr/bin/env node
// Images for a store follow-up email (Wes, 2026-11-07): the store's own App
// Clip card as iOS shows it after a scan, and its window QR code. The same
// card is public at https://api.favcircles.com/app/clip-card/<windowCode>.jpg,
// which is what the email links to.
//
//   node tools/store-followup-images.js <stickerVenueId | name> <outDir>
require('dotenv').config();
const fs = require('fs');
const path = require('path');
const QRCode = require('qrcode');
const { initializeFirebase, getFirestore } = require('../config/firebase');
initializeFirebase();
const db = getFirestore();
const { cardPreviewJPEG, copyFor } = require('../services/appClipExperienceService');
const rewardService = require('../services/rewardService');

async function findVenue(arg) {
  const doc = await db.collection('stickerVenues').doc(arg).get();
  if (doc.exists) return { venueId: doc.id, ...doc.data() };
  const all = await db.collection('stickerVenues').get();
  const hits = all.docs.filter((d) => (d.data().venueName || '').toLowerCase().includes(arg.toLowerCase()));
  if (hits.length !== 1) {
    throw new Error(hits.length ? `"${arg}" matches ${hits.length} stores: ${hits.map((d) => `${d.data().venueName} (${d.id})`).join(', ')}` : `No store matches "${arg}"`);
  }
  return { venueId: hits[0].id, ...hits[0].data() };
}

(async () => {
  const [arg, outDir] = process.argv.slice(2);
  if (!arg || !outDir) throw new Error('usage: store-followup-images.js <stickerVenueId | name> <outDir>');
  const venue = await findVenue(arg);
  fs.mkdirSync(outDir, { recursive: true });
  fs.writeFileSync(path.join(outDir, 'clip-card.jpg'), await cardPreviewJPEG(venue, 'window'));
  const windowLink = rewardService.stickerUrl(venue.windowCode);
  fs.writeFileSync(path.join(outDir, 'window-qr.png'),
    await QRCode.toBuffer(windowLink, { width: 600, margin: 2, errorCorrectionLevel: 'M' }));
  const { title, subtitle } = copyFor(venue, 'window');
  console.log(JSON.stringify({
    venueId: venue.venueId, name: venue.venueName, address: venue.placeAddress || null,
    windowLink, cardImageUrl: `https://api.favcircles.com/app/clip-card/${venue.windowCode}.jpg`,
    cardTitle: title, cardSubtitle: subtitle,
    claimed: Boolean(venue.ownerUserId), contactEmail: venue.contactEmail || null
  }, null, 2));
  process.exit(0);
})().catch((e) => { console.error(e.message); process.exit(1); });
