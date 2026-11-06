// usage: node ieinfo.js — the app's In-App Events and their states
require('/Users/wesleysgroi/circles-app/backend/node_modules/dotenv').config({ path: '/Users/wesleysgroi/circles-app/backend/.env' });
const asc = require('/Users/wesleysgroi/circles-app/backend/services/appStoreConnect/ascClient.js');
(async () => {
  const r = await asc.get('/apps/6746807095/appEvents?limit=50');
  for (const e of r.data) console.log(e.id, e.attributes.referenceName, e.attributes.eventState, JSON.stringify(e.attributes.territorySchedules));
  console.log(r.data.length, 'events');
})().catch(e => { console.error(e.message, JSON.stringify(e.details || '')); process.exit(1); });
