// backend/services/emailSuppression.js
//
// Addresses we must stop mailing: hard bounces (a Hide My Email relay the
// person switched off answers "550 5.1.1 user not found"; a dead or full
// inbox). Mailing them again only teaches receivers like iCloud that we send
// junk. One Firestore doc per address, emailSuppressions/{lowercased email},
// checked by a nodemailer plugin on the ONE transport every email goes
// through, so no sender can forget to look.
//
// We don't clear the email off the user: it still identifies the account
// (duplicate-signup check, login matching, merges). Remove the doc to undo.
//
// CLI (from backend/, .env loaded):
//   node services/emailSuppression.js add <email> "<reason>"
//   node services/emailSuppression.js remove <email>
//   node services/emailSuppression.js list
const { getFirestore } = require('../config/firebase');

const COLLECTION = 'emailSuppressions';
const REFRESH_MS = 10 * 60 * 1000;

let cache = new Set();
let loadedAt = 0;
let loading = null;

const normalize = (email) => String(email || '').trim().toLowerCase();

/** Loads the list; concurrent callers share one read. */
const refresh = async () => {
  if (loading) return loading;
  loading = (async () => {
    try {
      const snap = await getFirestore().collection(COLLECTION).get();
      cache = new Set(snap.docs.map((d) => d.id));
      loadedAt = Date.now();
    } catch (e) {
      // Keep sending on a read failure; the old list still applies
      console.warn(`📧 Couldn't refresh email suppressions: ${e.message}`);
    } finally {
      loading = null;
    }
  })();
  return loading;
};

const isSuppressed = async (email) => {
  if (Date.now() - loadedAt > REFRESH_MS) await refresh();
  return cache.has(normalize(email));
};

const suppress = async (email, reason, source = 'manual') => {
  const id = normalize(email);
  if (!id.includes('@')) throw new Error(`Not an email address: ${email}`);
  await getFirestore().collection(COLLECTION).doc(id)
    .set({ email: id, reason: reason || 'bounced', source, suppressedAt: new Date().toISOString() }, { merge: true });
  cache.add(id);
};

const unsuppress = async (email) => {
  const id = normalize(email);
  await getFirestore().collection(COLLECTION).doc(id).delete();
  cache.delete(id);
};

/** Pulls plain addresses out of nodemailer's to/cc/bcc shapes. */
const addressesOf = (field) => {
  if (!field) return [];
  const list = Array.isArray(field) ? field : String(field).split(',');
  return list.map((a) => {
    if (a && typeof a === 'object') return a.address || '';
    const m = String(a).match(/<([^>]+)>/);
    return (m ? m[1] : String(a)).trim();
  }).filter(Boolean);
};

/**
 * nodemailer 'compile' plugin: drops suppressed recipients; if nobody is
 * left, fails the send with code SUPPRESSED (not transient, so no retries).
 */
const transportPlugin = (mail, callback) => {
  (async () => {
    const data = mail.data;
    let kept = 0;
    let dropped = 0;
    for (const field of ['to', 'cc', 'bcc']) {
      const all = addressesOf(data[field]);
      if (!all.length) continue;
      const keep = [];
      for (const address of all) {
        if (await isSuppressed(address)) dropped++; else keep.push(address);
      }
      kept += keep.length;
      data[field] = keep.length ? keep : undefined;
    }
    if (dropped) console.log(`📧 Skipped ${dropped} suppressed recipient(s) for "${data.subject || ''}"`);
    if (dropped && !kept) {
      const err = new Error('All recipients are on the email suppression list');
      err.code = 'SUPPRESSED';
      return callback(err);
    }
    return callback();
  })().catch((e) => {
    // Never block mail because the check itself broke
    console.warn(`📧 Suppression check failed: ${e.message}`);
    callback();
  });
};

module.exports = { COLLECTION, isSuppressed, suppress, unsuppress, refresh, transportPlugin, addressesOf };

if (require.main === module) {
  require('../config/firebase').initializeFirebase();
  const [cmd, email, reason] = process.argv.slice(2);
  (async () => {
    if (cmd === 'add') { await suppress(email, reason); console.log(`suppressed ${normalize(email)}`); }
    else if (cmd === 'remove') { await unsuppress(email); console.log(`removed ${normalize(email)}`); }
    else if (cmd === 'list') {
      const snap = await getFirestore().collection(COLLECTION).get();
      snap.docs.forEach((d) => console.log(d.id, '·', d.data().reason));
    } else { console.log('usage: add <email> "<reason>" | remove <email> | list'); }
    process.exit(0);
  })().catch((e) => { console.error(e.message); process.exit(1); });
}
