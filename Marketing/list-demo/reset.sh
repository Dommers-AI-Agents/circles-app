#!/bin/bash
# reset.sh — restore pristine account state between takes: deletes the circle
# the demo imports from the Google Maps list (matched by sourceListUrl / name)
# and every place inside it, so the share card creates it fresh on camera.
set -eu
cd "$(dirname "$0")/../../backend"
cat > .tmp-demo-reset.js <<'JS'
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
  const circles = await db.collection('circles').where('owner', '==', UID).get();
  let n = 0;
  for (const c of circles.docs) {
    const d = c.data();
    if (d.deletedAt) continue;
    if (!(/rXJr3AmshQAtHA3pW_AsNN8HYb4JyA/.test(d.sourceListUrl || '') || /paris coffee/i.test(d.name || ''))) continue;
    const places = await db.collection('places').where('circleId', '==', c.id).get();
    let k = 0;
    for (const p of places.docs) if (!p.data().deletedAt) { await del(`places/${p.id}`); k++; }
    console.log('deleted circle', JSON.stringify(d.name), c.id, `(${k} places)`, (await del(`circles/${c.id}`)).success); n++;
  }
  if (!n) console.log('no Paris list circle — clean');
  process.exit(0);
})();
JS
node .tmp-demo-reset.js 2>&1 | grep -v Firebase
rm -f .tmp-demo-reset.js
