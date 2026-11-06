// usage (from in-app-events/): node source/asc/iecreate.js
// Creates the "Your holiday favorites" In-App Event (core app: a circle of holiday spots, shared),
// its en-US text and its two images (event-card.jpg, event-details.jpg). Safe to rerun: reuses the event.
require('/Users/wesleysgroi/circles-app/backend/node_modules/dotenv').config({ path: '/Users/wesleysgroi/circles-app/backend/.env' });
const asc = require('/Users/wesleysgroi/circles-app/backend/services/appStoreConnect/ascClient.js');
const fs = require('fs'), crypto = require('crypto');
const APP = '6746807095';
const REF = 'Holiday favorites 2026';
const TEXT = {
  name: 'Your holiday favorites',
  shortDescription: 'Save and share the spots that make your season',
  longDescription: 'Put the lights, cocoa and gift shops you love in one circle, then share it with friends and family before they visit.'
};
const attributes = {
  referenceName: REF,
  badge: 'SPECIAL_EVENT',
  deepLink: 'https://api.favcircles.com/app/open?path=add-place',
  purchaseRequirement: 'NO_COST_ASSOCIATED',
  primaryLocale: 'en-US',
  priority: 'NORMAL',
  purpose: 'APPROPRIATE_FOR_ALL_USERS',
  // Black Friday through Dec 27 (31 days max), shown from 14 days before
  territorySchedules: [{ territories: ['USA'], publishStart: '2026-11-13T14:00:00Z', eventStart: '2026-11-27T14:00:00Z', eventEnd: '2026-12-28T04:59:00Z' }]
};
(async () => {
  let ev = (await asc.get(`/apps/${APP}/appEvents?limit=50`)).data.find(e => e.attributes.referenceName === REF);
  if (!ev) {
    ev = (await asc.post('/appEvents', { data: { type: 'appEvents', attributes, relationships: { app: { data: { type: 'apps', id: APP } } } } })).data;
    console.log('created', ev.id);
  } else {
    await asc.patch(`/appEvents/${ev.id}`, { data: { type: 'appEvents', id: ev.id, attributes: { ...attributes, primaryLocale: undefined } } });
    console.log('updated', ev.id);
  }
  const locs = (await asc.get(`/appEvents/${ev.id}/localizations`)).data;
  let loc = locs.find(l => l.attributes.locale === 'en-US');
  if (!loc) loc = (await asc.post('/appEventLocalizations', { data: { type: 'appEventLocalizations', attributes: { locale: 'en-US', ...TEXT },
    relationships: { appEvent: { data: { type: 'appEvents', id: ev.id } } } } })).data;
  else await asc.patch(`/appEventLocalizations/${loc.id}`, { data: { type: 'appEventLocalizations', id: loc.id, attributes: TEXT } });
  console.log('localization', loc.id);

  const existing = (await asc.get(`/appEventLocalizations/${loc.id}/appEventScreenshots`)).data;
  for (const [file, type] of [['event-card.jpg', 'EVENT_CARD'], ['event-details.jpg', 'EVENT_DETAILS_PAGE']]) {
    const buf = fs.readFileSync(file);
    const sum = crypto.createHash('md5').update(buf).digest('hex');
    const old = existing.find(s => s.attributes.appEventAssetType === type);
    if (old && old.attributes.fileSize === buf.length) { console.log('kept', file); continue; }
    if (old) await asc.del(`/appEventScreenshots/${old.id}`);
    const r = await asc.post('/appEventScreenshots', { data: { type: 'appEventScreenshots',
      attributes: { fileName: file, fileSize: buf.length, appEventAssetType: type },
      relationships: { appEventLocalization: { data: { type: 'appEventLocalizations', id: loc.id } } } } });
    await asc.uploadOperations(r.data.attributes.uploadOperations, buf);
    await asc.patch(`/appEventScreenshots/${r.data.id}`, { data: { type: 'appEventScreenshots', id: r.data.id, attributes: { uploaded: true } } });
    console.log('uploaded', file, sum);
  }
  for (let i = 0; i < 40; i++) {
    const s = (await asc.get(`/appEventLocalizations/${loc.id}/appEventScreenshots`)).data;
    const states = s.map(x => `${x.attributes.fileName}:${x.attributes.assetDeliveryState?.state}`);
    console.log(states.join(' '));
    if (s.length === 2 && states.every(x => /:COMPLETE$/.test(x))) break;
    if (states.some(x => /FAILED/.test(x))) { console.log(JSON.stringify(s.map(x => x.attributes.assetDeliveryState))); process.exit(1); }
    await new Promise(r => setTimeout(r, 10000));
  }
  const e = (await asc.get(`/appEvents/${ev.id}`)).data;
  console.log('event', e.id, e.attributes.eventState);
})().catch(e => { console.error(e.message, JSON.stringify(e.details || '')); process.exit(1); });
