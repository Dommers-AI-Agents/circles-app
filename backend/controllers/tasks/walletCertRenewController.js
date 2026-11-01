// backend/controllers/tasks/walletCertRenewController.js
//
// Monthly: renews the Apple Wallet pass certificate once it has 45 days or
// less left (about once a year), through the App Store Connect API, and
// tells the admins either way something happened (2026-11-01). A failed
// renewal pages through scheduledTask's alert and retries next month, with
// weeks still left on the old certificate.
const { scheduledTask } = require('../../middleware/scheduledTask');
const passCertificate = require('../../services/wallet/passCertificate');
const { alertAdmin } = require('../../services/adminAlerts');

exports.renew = scheduledTask({
  name: 'wallet-cert-renew', log: '🪪 Wallet certificate check triggered via API', failure: 'Wallet certificate renewal failed',
  run: async (req) => {
    const result = await passCertificate.renewIfDue({ force: req.query.force === 'true' });
    if (result.renewed) {
      alertAdmin({
        key: 'wallet_cert_renewed',
        title: 'Apple Wallet certificate renewed',
        body: `New Pass Type ID certificate ${result.certificateId}, good until ${result.expiresAt.slice(0, 10)} (the old one ran to ${String(result.previousExpiresAt).slice(0, 10)}). Nothing to do.`
      });
    }
    return result;
  }
});
