// usage: node cppsubmit.js [submit]  — adds the four pages to an open review submission; "submit" sends it. Run cppwait.js first.
require('/Users/wesleysgroi/circles-app/backend/node_modules/dotenv').config({ path: '/Users/wesleysgroi/circles-app/backend/.env' });
const asc = require('/Users/wesleysgroi/circles-app/backend/services/appStoreConnect/ascClient.js');
const CPPS = ['ab9789e4-1fcc-4cdb-9679-837cbdba2b8a','58c75022-4ff4-4270-9e87-ca732bb26951','aa6ddfd8-6e35-42c4-9270-d58180f48908','985262c3-e739-4151-849c-b2e09a357cdb'];
(async () => {
  const open = await asc.get(`/apps/6746807095/reviewSubmissions?filter[platform]=IOS&filter[state]=READY_FOR_REVIEW,WAITING_FOR_REVIEW,IN_REVIEW,UNRESOLVED_ISSUES`);
  console.log('open submissions', open.data.map(s => `${s.id} ${s.attributes.state}`).join(', '));
  let sub = open.data.find(s => s.attributes.state === 'READY_FOR_REVIEW');
  if (!sub) sub = (await asc.post('/reviewSubmissions', { data: { type: 'reviewSubmissions', attributes: { platform: 'IOS' }, relationships: { app: { data: { type: 'apps', id: '6746807095' } } } } })).data;
  console.log('submission', sub.id, sub.attributes.state);
  for (const c of CPPS) {
    const v = (await asc.get(`/appCustomProductPages/${c}/appCustomProductPageVersions`)).data[0];
    try {
      await asc.post('/reviewSubmissionItems', { data: { type: 'reviewSubmissionItems', relationships: { reviewSubmission: { data: { type: 'reviewSubmissions', id: sub.id } }, appCustomProductPageVersion: { data: { type: 'appCustomProductPageVersions', id: v.id } } } } });
      console.log('added', c);
    } catch (e) { console.log('add failed', c, e.message, JSON.stringify(e.details)); }
  }
  if (process.argv[2] === 'submit') {
    const r = await asc.patch(`/reviewSubmissions/${sub.id}`, { data: { type: 'reviewSubmissions', id: sub.id, attributes: { submitted: true } } });
    console.log('submitted', r.data.attributes.state);
  }
})().catch(e => { console.error(e.message, JSON.stringify(e.details || '')); process.exit(1); });
