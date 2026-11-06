// usage (from custom-product-pages/): node source/asc/cppupload.js <ppid> <slide folder> <main-listing slugs to keep, in order> [deep link]
// Replaces the iPhone 6.9" set: removes the other main-listing slides, uploads <folder>/*.jpg first.
require('/Users/wesleysgroi/circles-app/backend/node_modules/dotenv').config({ path: '/Users/wesleysgroi/circles-app/backend/.env' });
const asc = require('/Users/wesleysgroi/circles-app/backend/services/appStoreConnect/ascClient.js');
const fs = require('fs'), path = require('path'), crypto = require('crypto');
const [cppId, dir, keepCsv, deepLink] = process.argv.slice(2);
const keep = keepCsv.split(',');   // template slugs to keep, in order
(async () => {
  const vs = await asc.get(`/appCustomProductPages/${cppId}/appCustomProductPageVersions`);
  const ver = vs.data[0];
  if (deepLink) {
    await asc.patch(`/appCustomProductPageVersions/${ver.id}`, { data: { type: 'appCustomProductPageVersions', id: ver.id, attributes: { deepLink } } });
    console.log('deepLink set', deepLink);
  }
  const ls = await asc.get(`/appCustomProductPageVersions/${ver.id}/appCustomProductPageLocalizations`);
  const sets = await asc.get(`/appCustomProductPageLocalizations/${ls.data[0].id}/appScreenshotSets`);
  const set = sets.data.find(s => s.attributes.screenshotDisplayType === 'APP_IPHONE_67');
  const shots = await asc.get(`/appScreenshotSets/${set.id}/appScreenshots?limit=50`);
  const existing = shots.data.map(s => ({ id: s.id, name: s.attributes.fileName }));
  console.log('existing', existing.map(e => e.name).join(' '));
  const kept = keep.map(k => existing.find(e => !e.name.startsWith('cpp-') && e.name.includes(k))).filter(Boolean);
  for (const d of existing.filter(e => !e.name.startsWith('cpp-') && !kept.includes(e))) { await asc.del("/appScreenshots/" + d.id); console.log('removed', d.name); }
  const fresh = [];
  for (const f of fs.readdirSync(dir).filter(f => f.endsWith('.jpg')).sort()) {
    const buf = fs.readFileSync(path.join(dir, f));
    const fileName = `cpp-${path.basename(dir)}-${f}`;
    const already = existing.find(e => e.name === fileName);
    if (already) { fresh.push(already.id); continue; }
    const r = await asc.post('/appScreenshots', { data: { type: 'appScreenshots', attributes: { fileName, fileSize: buf.length },
      relationships: { appScreenshotSet: { data: { type: 'appScreenshotSets', id: set.id } } } } });
    await asc.uploadOperations(r.data.attributes.uploadOperations, buf);
    await asc.patch(`/appScreenshots/${r.data.id}`, { data: { type: 'appScreenshots', id: r.data.id,
      attributes: { uploaded: true, sourceFileChecksum: crypto.createHash('md5').update(buf).digest('hex') } } });
    fresh.push(r.data.id); console.log('uploaded', fileName);
  }
  const order = [...fresh, ...kept.map(k => k.id)];
  await asc.patch(`/appScreenshotSets/${set.id}/relationships/appScreenshots`, { data: order.map(id => ({ type: 'appScreenshots', id })) });
  // wait for processing
  for (let i = 0; i < 30; i++) {
    const s = await asc.get(`/appScreenshotSets/${set.id}/appScreenshots?limit=50`);
    const states = s.data.map(x => `${x.attributes.fileName}:${x.attributes.assetDeliveryState?.state}`);
    if (states.every(x => /:COMPLETE$/.test(x))) { console.log('final order', s.data.map(x => x.attributes.fileName).join(' ')); return; }
    if (states.some(x => /FAILED/.test(x))) { console.log('FAILED', states.join(' ')); return; }
    await new Promise(r => setTimeout(r, 5000));
  }
  console.log('still processing');
})().catch(e => { console.error(e.message, JSON.stringify(e.details || '')); process.exit(1); });
