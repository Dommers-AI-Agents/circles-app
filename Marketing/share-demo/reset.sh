#!/bin/bash
# reset.sh — restore pristine account state between takes: deletes the demo's
# on-camera save (The Crunkleton in the Charlotte NC circle) so the share
# sheet shows "Saved to Charlotte NC" again instead of "Already saved".
set -eu
cd "$(dirname "$0")/../../backend"
cat > .tmp-demo-reset.js <<'JS'
require('dotenv').config();
const jwt = require('jsonwebtoken');
const { initializeFirebase, getFirestore } = require('./config/firebase');
initializeFirebase();
const db = getFirestore();
const UID = '111819744557116370195';
const CIRCLE = 'b8xjuYHHDNnUD4bH8Ijq'; // Charlotte NC
const BASE = 'https://circles-backend-196924649787.us-central1.run.app/api';
(async () => {
  const token = jwt.sign({ uid: UID }, process.env.JWT_SECRET, { expiresIn: '10m' });
  const del = (path) => fetch(`${BASE}/${path}`, { method: 'DELETE', headers: { Authorization: `Bearer ${token}` } }).then(r => r.json());
  const places = await db.collection('places').where('circleId', '==', CIRCLE).get();
  let n = 0;
  for (const p of places.docs) {
    const d = p.data();
    if (d.deletedAt || !/crunkleton/i.test(d.name || '')) continue;
    console.log('deleted place', d.name, p.id, (await del(`places/${p.id}`)).success); n++;
  }
  if (!n) console.log('no Crunkleton save in Charlotte NC — clean');
  process.exit(0);
})();
JS
node .tmp-demo-reset.js 2>&1 | grep -v Firebase
rm -f .tmp-demo-reset.js
