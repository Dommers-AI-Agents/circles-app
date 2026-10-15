// Loads posts.json into the instagramPosts queue (backend/services/instagramPublisher.js).
// Posts already posted (or publishing) are never touched; everything else is
// upserted in posts.json order. Wes approved the whole set (2026-10-15), so new
// posts arrive 'approved'; an existing paused/failed status is kept.
//
//   node seed-queue.js            # dry run: prints what would change
//   node seed-queue.js --write    # writes the queue
//   node seed-queue.js --write --token   # also stores ~/.config/favcircles-instagram-token on the server
const path = require('path');
const fs = require('fs');
const os = require('os');
const BACKEND = path.join(__dirname, '../../backend');
process.chdir(BACKEND);
require(path.join(BACKEND, 'node_modules/dotenv')).config();
const { initializeFirebase, getFirestore } = require(path.join(BACKEND, 'config/firebase'));
initializeFirebase();
const db = getFirestore();

const WRITE = process.argv.includes('--write');
const TOKEN = process.argv.includes('--token');
const IG_USER_ID = '17841476136545154'; // @favcircles
const IMAGE_BASE = 'https://favcircles.com/ig/posts/';

(async () => {
  const { posts } = JSON.parse(fs.readFileSync(path.join(__dirname, 'posts.json'), 'utf8'));
  let created = 0, updated = 0, kept = 0;
  for (const [order, p] of posts.entries()) {
    const ref = db.collection('instagramPosts').doc(p.id);
    const snap = await ref.get();
    const prev = snap.exists ? snap.data() : null;
    if (prev && ['posted', 'publishing'].includes(prev.status)) { kept++; continue; }
    const doc = { order, headline: p.headline, imageUrl: IMAGE_BASE + p.id + '.jpg', caption: p.caption,
      status: prev ? prev.status : 'approved', updatedAt: new Date().toISOString() };
    if (WRITE) await ref.set(doc, { merge: true });
    prev ? updated++ : created++;
  }
  console.log(`${WRITE ? '' : '[dry run] '}queue: ${created} new, ${updated} updated, ${kept} already posted`);

  if (TOKEN) {
    const token = fs.readFileSync(path.join(os.homedir(), '.config/favcircles-instagram-token'), 'utf8').trim();
    if (!/^IG[A-Za-z0-9]{100,}$/.test(token)) throw new Error('The token file does not look like an Instagram token');
    if (WRITE) {
      await db.collection('integrations').doc('instagram').set({ accessToken: token, igUserId: IG_USER_ID,
        tokenRefreshedAt: new Date().toISOString(), connectedAt: new Date().toISOString() }, { merge: true });
    }
    console.log(`${WRITE ? '' : '[dry run] '}token stored for @favcircles (${token.length} chars, not printed)`);
  }
  process.exit(0);
})().catch((e) => { console.error(e.message); process.exit(1); });
