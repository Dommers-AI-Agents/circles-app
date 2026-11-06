// usage: node cppcreate.js "<page name>" "<promotional text>"  (copies the live version's screenshots as the start)
require('/Users/wesleysgroi/circles-app/backend/node_modules/dotenv').config({ path: '/Users/wesleysgroi/circles-app/backend/.env' });
const asc = require('/Users/wesleysgroi/circles-app/backend/services/appStoreConnect/ascClient.js');
const [name, promo] = process.argv.slice(2);
(async () => {
  const app = '6746807095';
  const v = await asc.get(`/apps/${app}/appStoreVersions?filter[appStoreState]=READY_FOR_SALE&limit=1`);
  const tmpl = v.data[0].id; console.log('template', v.data[0].attributes.versionString, tmpl);
  const body = { data: { type: 'appCustomProductPages', attributes: { name },
      relationships: { app: { data: { type: 'apps', id: app } },
        appCustomProductPageVersions: { data: [{ type: 'appCustomProductPageVersions', id: '${v1}' }] },
        appStoreVersionTemplate: { data: { type: 'appStoreVersions', id: tmpl } } } },
    included: [
      { type: 'appCustomProductPageVersions', id: '${v1}', relationships: { appCustomProductPageLocalizations: { data: [{ type: 'appCustomProductPageLocalizations', id: '${l1}' }] } } },
      { type: 'appCustomProductPageLocalizations', id: '${l1}', attributes: { locale: 'en-US', promotionalText: promo } } ] };
  const r = await asc.post('/appCustomProductPages', body);
  console.log(JSON.stringify(r.data, null, 1));
})().catch(e => console.error(e.message, JSON.stringify(e.details||'')));
