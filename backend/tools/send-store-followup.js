#!/usr/bin/env node
// Store follow-up email (Wes, 2026-11-07), sent by our server from
// wesley@favcircles.com with the store's card in the email.
//
//   node tools/send-store-followup.js <stickerVenueId | name> --to owner@x.com [--name Vickie] [--send]
//
// Without --send it only writes a preview (preview.html + the card) to
// --out (default: the system temp dir) and prints where. Wes says "send"
// before --send is used for a real store.
require('dotenv').config();
const fs = require('fs');
const os = require('os');
const path = require('path');
const { initializeFirebase, getFirestore } = require('../config/firebase');
initializeFirebase();
const db = getFirestore();
const { buildStoreFollowup } = require('../services/storeFollowupEmail');

function flag(name) {
  const i = process.argv.indexOf(`--${name}`);
  return i > 0 ? process.argv[i + 1] : null;
}

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
  const store = process.argv[2];
  const to = flag('to');
  if (!store || store.startsWith('--')) throw new Error('usage: send-store-followup.js <store> --to email [--name First] [--send]');
  const venue = await findVenue(store);
  const email = await buildStoreFollowup(venue, { ownerName: flag('name') });
  const outDir = flag('out') || fs.mkdtempSync(path.join(os.tmpdir(), 'store-followup-'));
  fs.mkdirSync(outDir, { recursive: true });
  fs.writeFileSync(path.join(outDir, 'card.jpg'), email.attachments[0].content);
  fs.writeFileSync(path.join(outDir, 'preview.html'), email.html.replace('cid:storecard', 'card.jpg'));
  console.log(`Store: ${venue.venueName}\nSubject: ${email.subject}\nCard on the website: ${email.cardUrl}\nPreview: ${path.join(outDir, 'preview.html')}`);
  if (!process.argv.includes('--send')) { console.log('Not sent (add --send).'); process.exit(0); }
  if (!to) throw new Error('--to is required to send');
  const emailService = require('../services/emailService');
  const result = await emailService.sendEmail({
    to, subject: email.subject, html: email.html, text: email.text,
    attachments: email.attachments, fromName: 'Wes Sgroi'
  });
  if (!result?.success) throw new Error(`Not sent: ${JSON.stringify(result)}`);
  console.log(`Sent to ${to} (${result.messageId})`);
  process.exit(0);
})().catch((e) => { console.error(e.message); process.exit(1); });
