#!/bin/bash
# reset.sh — restore pristine account state between takes: deletes the demo's
# "Date Nights" circle and any Office Depot / Supperland saves inside it.
set -eu
cd "$(dirname "$0")/../../backend"
cat > .tmp-demo-reset.js <<'EOF'
require('dotenv').config();
const jwt = require('jsonwebtoken');
const { initializeFirebase, getFirestore } = require('./config/firebase');
initializeFirebase();
const db = getFirestore();
const UID = '111819744557116370195';
const BASE = 'https://circles-backend-196924649787.us-central1.run.app/api';
(async () => {
  const token = jwt.sign({ uid: UID }, process.env.JWT_SECRET, { expiresIn: '10m' });
  const del = (path) => fetch(`${BASE}/${path}`, { method: 'DELETE', headers: { Authorization: `Bearer ${token}` } }).then(r => r.json());
  const circles = await db.collection('circles').where('owner', '==', UID).where('name', '==', 'Date Nights').get();
  for (const c of circles.docs) {
    const places = await db.collection('places').where('circleId', '==', c.id).get();
    for (const p of places.docs) {
      if (!p.data().deletedAt) console.log('deleted place', p.data().name, (await del(`places/${p.id}`)).success);
    }
    console.log('deleted circle Date Nights', (await del(`circles/${c.id}`)).success);
  }
  if (circles.empty) console.log('no Date Nights circle — clean');
  process.exit(0);
})();
EOF
node .tmp-demo-reset.js 2>&1 | grep -v Firebase
rm -f .tmp-demo-reset.js
