require('/Users/wesleysgroi/circles-app/backend/node_modules/dotenv').config({ path: '/Users/wesleysgroi/circles-app/backend/.env' });
const asc = require('/Users/wesleysgroi/circles-app/backend/services/appStoreConnect/ascClient.js');
const CPPS = ['ab9789e4-1fcc-4cdb-9679-837cbdba2b8a','58c75022-4ff4-4270-9e87-ca732bb26951','aa6ddfd8-6e35-42c4-9270-d58180f48908','985262c3-e739-4151-849c-b2e09a357cdb'];
(async () => {
  for (let i = 0; i < 60; i++) {
    let pending = 0, failed = 0;
    for (const c of CPPS) {
      const v = (await asc.get(`/appCustomProductPages/${c}/appCustomProductPageVersions`)).data[0];
      const l = (await asc.get(`/appCustomProductPageVersions/${v.id}/appCustomProductPageLocalizations`)).data[0];
      for (const s of (await asc.get(`/appCustomProductPageLocalizations/${l.id}/appScreenshotSets`)).data)
        for (const x of (await asc.get(`/appScreenshotSets/${s.id}/appScreenshots?limit=50`)).data) {
          const st = x.attributes.assetDeliveryState?.state;
          if (st === 'FAILED') { failed++; console.log('FAILED', c, x.attributes.fileName, JSON.stringify(x.attributes.assetDeliveryState.errors)); }
          else if (st !== 'COMPLETE') pending++;
        }
    }
    console.log(new Date().toISOString(), 'pending', pending, 'failed', failed);
    if (!pending) return;
    await new Promise(r => setTimeout(r, 30000));
  }
})();
