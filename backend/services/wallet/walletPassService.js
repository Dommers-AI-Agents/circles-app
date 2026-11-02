// backend/services/wallet/walletPassService.js
// Apple Wallet store cards (2026-11-01): one card per customer per store,
// showing their points there and the next reward. It shows up on the lock
// screen near the store and refreshes itself after every scan or redemption.
//
// The pass is signed with the Pass Type ID certificate (PKCS#7 detached over
// manifest.json, with Apple's WWDR G4 intermediate), and the same certificate
// authenticates the update pushes to APNs, as Apple documents for Wallet.
//
// Env: PASS_TYPE_ID (default pass.com.favcircles.loyalty), and either
// PASS_CERT_PEM_B64 + PASS_KEY_PEM_B64 (preferred), or PASS_CERT_P12_B64
// (the .p12 with its key, base64) + PASS_CERT_PASSWORD. A .p12 that
// node-forge can't read converts with
//   openssl pkcs12 -in pass.p12 -clcerts -nokeys -out cert.pem
//   openssl pkcs12 -in pass.p12 -nocerts -nodes -out key.pem
// Without them every entry point says "not configured" and nothing is
// built or pushed. The yearly renewal (passCertificate.renewIfDue, task
// /api/tasks/wallet-cert-renew) stores a newer certificate in Firestore,
// which then wins over the deployed one.
//
// Records: walletPasses/{serial} = { userId, venueId, authToken, createdAt, updatedAt }
//   serial = sha256(userId:venueId), so a re-add gives the same card.
// walletPassRegistrations/{deviceLibraryIdentifier__serial} =
//   { deviceLibraryIdentifier, serial, pushToken, createdAt }

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const http2 = require('http2');
const forge = require('node-forge');
const passCertificate = require('./passCertificate');
const AdmZip = require('adm-zip');
const sharp = require('sharp');
const { getFirestore } = require('../../config/firebase');
const { COLLECTIONS } = require('../../models/FirestoreModels');
const { STICKER_COLLECTIONS } = require('../../models/StickerModels');
const { ServiceError } = require('../../utils/serviceError');

const TEAM_ID = '67E8B4E8HV';
/// FavCircles on the App Store: Wallet shows it on the card and opens it
const APP_STORE_ID = 6746807095;
const LINK_BASE = () => process.env.STICKER_LINK_BASE_URL || 'https://api.favcircles.com';
const PASSES = 'walletPasses';
const REGISTRATIONS = 'walletPassRegistrations';
const ASSETS = path.join(__dirname, '../../assets/wallet');
const WEB_SERVICE_URL = () => `${process.env.WALLET_WEB_SERVICE_BASE_URL || 'https://api.favcircles.com'}/api/wallet`;

const passTypeId = () => process.env.PASS_TYPE_ID || 'pass.com.favcircles.loyalty';
const configured = () => passCertificate.configured();

const db = () => getFirestore();

// --- credentials ------------------------------------------------------------

// The pass certificate + key (deployed, or renewed by the yearly job) and the
// WWDR intermediate: services/wallet/passCertificate
const credentials = () => passCertificate.currentCredentials();

// --- the card ---------------------------------------------------------------

const serialFor = (userId, venueId) => crypto.createHash('sha256').update(`${userId}:${venueId}`).digest('hex').slice(0, 32);

const coords = (location) => {
  if (!location) return null;
  const latitude = Number(location.latitude ?? location.lat ?? location._latitude);
  const longitude = Number(location.longitude ?? location.lng ?? location._longitude);
  return Number.isFinite(latitude) && Number.isFinite(longitude) ? { latitude, longitude } : null;
};

/// pass.json for one customer at one store. Pure: everything comes in.
/// `progress` = { points, nextRewardLine, earnRate, live }
function passJson({ serial, authToken, venue, progress }) {
  const name = venue.venueName || venue.placeName || 'Your store';
  const where = coords(venue.location);
  // The card opens the app on this store's rewards (Wes, 2026-11-02): the
  // app row on the card (appLaunchURL) and a link on its back
  const placeId = venue.globalPlaceId || null;
  const rewardsLink = placeId ? `${LINK_BASE()}/app/rewards/${placeId}` : null;
  const pass = {
    formatVersion: 1,
    passTypeIdentifier: passTypeId(),
    teamIdentifier: TEAM_ID,
    serialNumber: serial,
    authenticationToken: authToken,
    webServiceURL: WEB_SERVICE_URL(),
    organizationName: 'FavCircles',
    description: `${name} rewards on FavCircles`,
    logoText: name.slice(0, 30),
    foregroundColor: 'rgb(255, 255, 255)',
    labelColor: 'rgb(147, 197, 253)',
    backgroundColor: 'rgb(15, 27, 51)',
    sharingProhibited: true,
    associatedStoreIdentifiers: [APP_STORE_ID],
    ...(placeId ? { appLaunchURL: `circles://rewards/${placeId}` } : {}),
    storeCard: {
      primaryFields: [{
        key: 'points',
        label: progress.live ? 'POINTS HERE' : 'SAVED STORE',
        value: progress.live ? progress.points : name,
        ...(progress.live ? { changeMessage: 'You have %@ points at ' + name } : {})
      }],
      secondaryFields: progress.live && progress.nextRewardLine
        ? [{ key: 'next', label: 'NEXT REWARD', value: progress.nextRewardLine }]
        : [],
      auxiliaryFields: progress.live && progress.earnRate
        ? [{ key: 'earn', label: 'EACH VISIT', value: `+${progress.earnRate} points` }]
        : [],
      backFields: [
        ...(rewardsLink ? [{
          key: 'open',
          label: 'Redeem or check your points',
          value: rewardsLink,
          attributedValue: `<a href='${rewardsLink}'>Open ${name} in FavCircles</a>`
        }] : []),
        {
          key: 'how',
          label: 'How it works',
          value: progress.live
            ? `Scan ${name}'s code at the register after you buy something to earn points. To use a reward, open ${name} in FavCircles (the link above, or the FavCircles app on this card) and tap Redeem. This card updates by itself.`
            : `${name} is saved on your FavCircles map. When the store starts rewards, your points show up here.`
        },
        ...(venue.placeAddress ? [{ key: 'address', label: 'Address', value: venue.placeAddress }] : []),
        { key: 'app', label: 'FavCircles', value: 'Open FavCircles to see your rewards, offers and the places your friends love.' }
      ]
    }
  };
  if (where) {
    pass.locations = [{ ...where, relevantText: progress.live ? `You're at ${name}. Scan the register code to earn points.` : `You're at ${name}.` }];
  }
  return pass;
}

async function fetchCover(venue) {
  try {
    const url = await require('../placePhotoService').venueCoverUrl(venue);
    if (!url) return null;
    const response = await fetch(url, { signal: AbortSignal.timeout(4000) });
    if (!response.ok) return null;
    return Buffer.from(await response.arrayBuffer());
  } catch (error) {
    return null;
  }
}

/// manifest.json: SHA-1 of every file in the pass
function manifestFor(files) {
  const manifest = {};
  for (const [name, data] of Object.entries(files)) {
    manifest[name] = crypto.createHash('sha1').update(data).digest('hex');
  }
  return Buffer.from(JSON.stringify(manifest));
}

/// PKCS#7 detached signature over manifest.json, DER
function signManifest(manifest, { cert, key, wwdr }) {
  const p7 = forge.pkcs7.createSignedData();
  p7.content = forge.util.createBuffer(manifest.toString('binary'));
  p7.addCertificate(cert);
  p7.addCertificate(wwdr);
  p7.addSigner({
    key,
    certificate: cert,
    digestAlgorithm: forge.pki.oids.sha256,
    authenticatedAttributes: [
      { type: forge.pki.oids.contentType, value: forge.pki.oids.data },
      { type: forge.pki.oids.messageDigest },
      { type: forge.pki.oids.signingTime, value: new Date() }
    ]
  });
  p7.sign({ detached: true });
  return Buffer.from(forge.asn1.toDer(p7.toAsn1()).getBytes(), 'binary');
}

/// The .pkpass zip from pass.json + images, signed with `creds`
function packagePass(pass, images, creds) {
  const files = { 'pass.json': Buffer.from(JSON.stringify(pass)), ...images };
  const manifest = manifestFor(files);
  const zip = new AdmZip();
  for (const [name, data] of Object.entries(files)) zip.addFile(name, data);
  zip.addFile('manifest.json', manifest);
  zip.addFile('signature', signManifest(manifest, creds));
  return zip.toBuffer();
}

async function passImages(venue) {
  const images = {};
  for (const name of ['icon.png', 'icon@2x.png', 'icon@3x.png', 'logo.png', 'logo@2x.png', 'logo@3x.png']) {
    images[name] = fs.readFileSync(path.join(ASSETS, name));
  }
  // The store's photo across the card (storeCard strip: 375×123 points)
  const cover = await fetchCover(venue);
  if (cover) {
    try {
      images['strip.png'] = await sharp(cover).resize(375, 123, { fit: 'cover' }).png().toBuffer();
      images['strip@2x.png'] = await sharp(cover).resize(750, 246, { fit: 'cover' }).png().toBuffer();
      images['strip@3x.png'] = await sharp(cover).resize(1125, 369, { fit: 'cover' }).png().toBuffer();
    } catch (error) {
      console.warn('⚠️ Wallet strip image skipped:', error.message);
    }
  }
  return images;
}

async function loadVenue(venueId) {
  const doc = await db().collection(STICKER_COLLECTIONS.STICKER_VENUES).doc(venueId).get();
  if (!doc.exists || doc.data().active === false) throw new ServiceError(404, 'VENUE_NOT_FOUND', 'Store not found');
  return { venueId: doc.id, ...doc.data() };
}

/// Points here and the next reward, the way the store page says it
async function progressFor(userId, venue) {
  const rewardService = require('../rewardService');
  const rewardProgress = require('../rewardProgress');
  const { activeOffers } = require('../venueHelpers.js');
  const { isVenueLoyaltyActive } = require('../ownerSubscriptionService');
  const live = await isVenueLoyaltyActive(venue);
  const userDoc = await db().collection(COLLECTIONS.USERS).doc(userId).get();
  const points = rewardService.venuePointsFrom(userDoc.exists ? userDoc.data() : {}, venue.venueId);
  const earnRate = live ? rewardService.effectiveEarnRate(venue) : null;
  const next = live ? rewardProgress.nextReward(activeOffers(venue), points, earnRate) : null;
  return { live, points, earnRate, nextRewardLine: next ? rewardProgress.nextRewardLine(next) : null };
}

/// The customer's card for this store, creating its record the first time
async function passForCustomer(userId, venueId) {
  const creds = await credentials();
  const venue = await loadVenue(venueId);
  const serial = serialFor(userId, venueId);
  const ref = db().collection(PASSES).doc(serial);
  const existing = await ref.get();
  let authToken = existing.exists ? existing.data().authToken : null;
  if (!authToken) {
    authToken = crypto.randomBytes(24).toString('hex');
    const now = new Date().toISOString();
    await ref.set({ userId, venueId, authToken, createdAt: now, updatedAt: now });
  }
  const pass = passJson({ serial, authToken, venue, progress: await progressFor(userId, venue) });
  return packagePass(pass, await passImages(venue), creds);
}

// --- the web service Wallet calls ------------------------------------------

/// The pass record when `authorization` is "ApplePass <its token>"
async function authorizedPass(serial, authorization) {
  const token = String(authorization || '').replace(/^ApplePass\s+/i, '');
  if (!token) return null;
  const doc = await db().collection(PASSES).doc(String(serial)).get();
  if (!doc.exists) return null;
  const stored = Buffer.from(String(doc.data().authToken || ''));
  const given = Buffer.from(token);
  if (stored.length !== given.length || !crypto.timingSafeEqual(stored, given)) return null;
  return { serial: doc.id, ...doc.data() };
}

const registrationId = (deviceLibraryIdentifier, serial) => `${String(deviceLibraryIdentifier).slice(0, 200)}__${serial}`;

/// Returns 201 for a new registration, 200 for one Wallet already had
async function registerDevice({ deviceLibraryIdentifier, serial, pushToken }) {
  const ref = db().collection(REGISTRATIONS).doc(registrationId(deviceLibraryIdentifier, serial));
  const existing = await ref.get();
  await ref.set({ deviceLibraryIdentifier, serial, pushToken: String(pushToken || ''), createdAt: existing.exists ? existing.data().createdAt : new Date().toISOString() });
  return existing.exists ? 200 : 201;
}

async function unregisterDevice({ deviceLibraryIdentifier, serial }) {
  await db().collection(REGISTRATIONS).doc(registrationId(deviceLibraryIdentifier, serial)).delete();
}

/// Serials on this device changed since `since` (ISO), and the newest change
async function updatedSerials(deviceLibraryIdentifier, since) {
  const regs = await db().collection(REGISTRATIONS).where('deviceLibraryIdentifier', '==', String(deviceLibraryIdentifier)).get();
  const serials = regs.docs.map((d) => d.data().serial);
  const passes = await Promise.all(serials.map((s) => db().collection(PASSES).doc(s).get()));
  const changed = passes.filter((p) => p.exists && (!since || String(p.data().updatedAt) > String(since)));
  if (!changed.length) return null;
  const lastUpdated = changed.map((p) => String(p.data().updatedAt)).sort().pop();
  return { serialNumbers: changed.map((p) => p.id), lastUpdated };
}

/// The latest card for a pass record (Wallet's update fetch)
async function latestPass(record) {
  const creds = await credentials();
  const venue = await loadVenue(record.venueId);
  const pass = passJson({ serial: record.serial, authToken: record.authToken, venue, progress: await progressFor(record.userId, venue) });
  return packagePass(pass, await passImages(venue), creds);
}

// --- update pushes -----------------------------------------------------------

/// An empty push to one device: Wallet then asks the web service what changed.
/// @returns {Promise<true|'gone'|false>}
async function pushUpdate(pushToken) {
  const { certPem, keyPem } = await credentials();
  return new Promise((resolve) => {
    const client = http2.connect('https://api.push.apple.com', { cert: certPem, key: keyPem });
    client.on('error', (error) => { console.warn('⚠️ Wallet APNs connection failed:', error.message); resolve(false); });
    const req = client.request({
      ':method': 'POST',
      ':path': `/3/device/${pushToken}`,
      'apns-topic': passTypeId(),
      // Wallet's convention: an empty alert-type push at high priority (a
      // background push may be deferred or dropped)
      'apns-push-type': 'alert',
      'apns-priority': '10'
    });
    let status = 0; let text = '';
    req.on('response', (headers) => { status = headers[':status']; });
    req.on('data', (chunk) => { text += chunk; });
    req.on('end', () => {
      client.close();
      if (status === 200) return resolve(true);
      if (status === 410 || /BadDeviceToken|Unregistered/.test(text)) return resolve('gone');
      console.warn(`⚠️ Wallet APNs refused an update (${status}): ${text}`);
      resolve(false);
    });
    req.on('error', (error) => { client.close(); console.warn('⚠️ Wallet update push failed:', error.message); resolve(false); });
    req.end('{}');
  });
}

/// The customer's points at this store changed: bump the card and tell every
/// device holding it. Fire and forget; never throws.
async function balanceChanged(userId, venueId) {
  if (!configured() || !userId || !venueId) return;
  try {
    const serial = serialFor(userId, venueId);
    const ref = db().collection(PASSES).doc(serial);
    if (!(await ref.get()).exists) return; // they never added this store's card
    await ref.update({ updatedAt: new Date().toISOString() });
    const regs = await db().collection(REGISTRATIONS).where('serial', '==', serial).get();
    await Promise.all(regs.docs.map(async (doc) => {
      const outcome = await pushUpdate(doc.data().pushToken);
      if (outcome === 'gone') await doc.ref.delete();
    }));
  } catch (error) {
    console.error(`⚠️ Wallet card update failed (${venueId}):`, error.message);
  }
}

module.exports = {
  PASSES, REGISTRATIONS,
  configured, passTypeId, serialFor, passJson, manifestFor, signManifest, packagePass,
  passForCustomer, authorizedPass, registerDevice, unregisterDevice, updatedSerials, latestPass, balanceChanged,
  _resetCredentials: () => passCertificate._resetCache()
};
