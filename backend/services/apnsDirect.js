// backend/services/apnsDirect.js
// A plain alert push straight to APNs (HTTP/2 + a token-signed .p8), for the
// one sender with no Firebase SDK: the App Clip. Its ephemeral notifications
// need no permission prompt but arrive only through APNs, under the clip's
// own bundle id. Everything else goes through FCM.
//
// Env: APNS_KEY_ID, APNS_KEY_P8_B64 (the .p8 file, base64), APNS_TEAM_ID
// (defaults to the FavCircles team). Without a key, sends are skipped.
const http2 = require('http2');
const jwt = require('jsonwebtoken');

const TEAM_ID = () => process.env.APNS_TEAM_ID || '67E8B4E8HV';
const HOSTS = { production: 'https://api.push.apple.com', development: 'https://api.sandbox.push.apple.com' };

const configured = () => !!(process.env.APNS_KEY_ID && process.env.APNS_KEY_P8_B64);

// Apple wants the provider token reused for up to an hour (and refreshed at
// least that often); 50 minutes keeps clear of both limits
let cached = null;
function providerToken(nowMs = Date.now()) {
  if (cached && nowMs - cached.at < 50 * 60 * 1000) return cached.token;
  const key = Buffer.from(process.env.APNS_KEY_P8_B64, 'base64').toString('utf8');
  const token = jwt.sign({ iss: TEAM_ID(), iat: Math.floor(nowMs / 1000) }, key, {
    algorithm: 'ES256', header: { alg: 'ES256', kid: process.env.APNS_KEY_ID }
  });
  cached = { token, at: nowMs };
  return token;
}

/**
 * @returns {Promise<true|'gone'|false>} 'gone' = the token is dead
 */
function sendAlert({ deviceToken, topic, title, body, environment = 'production', expiresAt }) {
  if (!configured() || !deviceToken) return Promise.resolve(false);
  return new Promise((resolve) => {
    const client = http2.connect(HOSTS[environment] || HOSTS.production);
    client.on('error', (error) => { console.warn('⚠️ APNs connection failed:', error.message); resolve(false); });
    const req = client.request({
      ':method': 'POST',
      ':path': `/3/device/${deviceToken}`,
      authorization: `bearer ${providerToken()}`,
      'apns-topic': topic,
      'apns-push-type': 'alert',
      'apns-priority': '10',
      ...(expiresAt ? { 'apns-expiration': String(Math.floor(expiresAt / 1000)) } : {})
    });
    let status = 0; let text = '';
    req.on('response', (headers) => { status = headers[':status']; });
    req.on('data', (chunk) => { text += chunk; });
    req.on('end', () => {
      client.close();
      if (status === 200) return resolve(true);
      if (status === 410 || /BadDeviceToken|Unregistered/.test(text)) return resolve('gone');
      console.warn(`⚠️ APNs refused a push (${status}): ${text}`);
      resolve(false);
    });
    req.on('error', (error) => { client.close(); console.warn('⚠️ APNs push failed:', error.message); resolve(false); });
    req.end(JSON.stringify({ aps: { alert: { title, body }, sound: 'default' } }));
  });
}

module.exports = { configured, sendAlert };
