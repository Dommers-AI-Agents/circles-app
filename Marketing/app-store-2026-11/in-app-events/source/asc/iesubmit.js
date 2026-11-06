// usage (from in-app-events/): node source/asc/iesubmit.js [submit] — adds the event to an open review
// submission (a new one if none is open); "submit" sends it. Its two images must be COMPLETE first.
require('/Users/wesleysgroi/circles-app/backend/node_modules/dotenv').config({ path: '/Users/wesleysgroi/circles-app/backend/.env' });
const asc = require('/Users/wesleysgroi/circles-app/backend/services/appStoreConnect/ascClient.js');
const APP = '6746807095', REF = 'Holiday favorites 2026';
(async () => {
  const ev = (await asc.get(`/apps/${APP}/appEvents?limit=50`)).data.find(e => e.attributes.referenceName === REF);
  const loc = (await asc.get(`/appEvents/${ev.id}/localizations`)).data[0];
  const shots = (await asc.get(`/appEventLocalizations/${loc.id}/appEventScreenshots`)).data;
  const states = shots.map(x => `${x.attributes.fileName}:${x.attributes.assetDeliveryState?.state}`);
  if (shots.length < 2 || !states.every(x => /:COMPLETE$/.test(x))) { console.log('images not ready', states.join(' ')); process.exit(1); }
  const open = await asc.get(`/apps/${APP}/reviewSubmissions?filter[platform]=IOS&filter[state]=READY_FOR_REVIEW,WAITING_FOR_REVIEW,IN_REVIEW,UNRESOLVED_ISSUES`);
  console.log('open submissions', open.data.map(s => `${s.id} ${s.attributes.state}`).join(', '));
  let sub = open.data.find(s => s.attributes.state === 'READY_FOR_REVIEW');
  if (!sub) sub = (await asc.post('/reviewSubmissions', { data: { type: 'reviewSubmissions', attributes: { platform: 'IOS' }, relationships: { app: { data: { type: 'apps', id: APP } } } } })).data;
  console.log('submission', sub.id, sub.attributes.state);
  await asc.post('/reviewSubmissionItems', { data: { type: 'reviewSubmissionItems', relationships: {
    reviewSubmission: { data: { type: 'reviewSubmissions', id: sub.id } }, appEvent: { data: { type: 'appEvents', id: ev.id } } } } });
  console.log('added', ev.id);
  if (process.argv[2] === 'submit') {
    const r = await asc.patch(`/reviewSubmissions/${sub.id}`, { data: { type: 'reviewSubmissions', id: sub.id, attributes: { submitted: true } } });
    console.log('submitted', r.data.attributes.state);
  }
})().catch(e => { console.error(e.message, JSON.stringify(e.details || '')); process.exit(1); });
