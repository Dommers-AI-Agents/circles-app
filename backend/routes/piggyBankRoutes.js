// backend/routes/piggyBankRoutes.js
// FavCoin piggy bank: balance + history reads, wallet linking, and claiming
// (Phase 4: on-chain settlement to the user's own Cactus wallet). Earning
// happens via hooks in the action controllers; clearing and settlement via
// scheduled tasks.

const express = require('express');
const { bech32m } = require('bech32');
const { protect } = require('../middleware/firebaseAuth');
const piggyBankService = require('../services/piggyBankService');
const cactusWallet = require('../services/cactusWalletService');

const router = express.Router();
router.use(protect);

// A valid self-custody claim address is a bech32m string with the 'cac'
// prefix — full checksum decode, not just a shape check. Returns the
// normalized (lowercased) address or null.
function normalizeCactusAddress(input) {
  if (typeof input !== 'string') return null;
  const address = input.trim().toLowerCase();
  if (!address.startsWith('cac1')) return null;
  try {
    const decoded = bech32m.decode(address, 100);
    return decoded.prefix === 'cac' ? address : null;
  } catch (_) {
    return null;
  }
}

// Builds shipped before 2026.08-b decode every coin field as an INTEGER —
// one fractional value anywhere in the payload breaks their piggy screen.
// New builds advertise decimal support with X-FC-Decimal-Coins: 1; everyone
// else gets integers (floors — fractional rows show as 0 rather than lying).
const wantsDecimals = (req) => req.headers['x-fc-decimal-coins'] === '1';
const intify = (n) => Math.floor(n || 0);
const intifyEvent = (e) => ({ ...e, coins: intify(e.coins) });
function intifyPayload(payload) {
  return {
    ...payload,
    bank: {
      ...payload.bank,
      pendingCoins: intify(payload.bank.pendingCoins),
      confirmedCoins: intify(payload.bank.confirmedCoins),
      lifetimeCoins: intify(payload.bank.lifetimeCoins),
      settledOnChain: intify(payload.bank.settledOnChain)
    },
    activeClaim: payload.activeClaim ? {
      ...payload.activeClaim,
      coins: intify(payload.activeClaim.coins),
      feeCoins: intify(payload.activeClaim.feeCoins),
      netCoins: intify(payload.activeClaim.netCoins)
    } : null,
    events: (payload.events || []).map(intifyEvent),
    config: {
      ...payload.config,
      coinValues: Object.fromEntries(
        Object.entries(payload.config.coinValues).map(([k, v]) => [k, intify(v)])
      )
    }
  };
}

// GET /api/piggy-bank — bank + recent events + display config
router.get('/', async (req, res) => {
  try {
    const payload = await piggyBankService.getPiggyBank(req.user.uid);
    res.status(200).json({
      success: true,
      ...(wantsDecimals(req) ? payload : intifyPayload(payload))
    });
  } catch (error) {
    console.error('🐷 getPiggyBank failed:', error.message);
    res.status(500).json({ success: false, message: 'Failed to load piggy bank' });
  }
});

// GET /api/piggy-bank/history?before=<iso> — paginated ledger
router.get('/history', async (req, res) => {
  try {
    const events = await piggyBankService.getHistory(req.user.uid, req.query.before || null);
    res.status(200).json({
      success: true,
      events: wantsDecimals(req) ? events : events.map(intifyEvent)
    });
  } catch (error) {
    console.error('🐷 piggy history failed:', error.message);
    res.status(500).json({ success: false, message: 'Failed to load history' });
  }
});

// POST /api/piggy-bank/wallet — link/replace the user's Cactus wallet address.
// Changeable anytime: claims snapshot the address, so an in-flight claim
// keeps its original destination.
router.post('/wallet', async (req, res) => {
  try {
    const address = normalizeCactusAddress(req.body.address);
    if (!address) {
      return res.status(400).json({
        success: false, code: 'invalid_address',
        message: 'That doesn\'t look like a Cactus wallet address (cac1…)'
      });
    }
    const result = await piggyBankService.linkWallet(req.user.uid, address);
    res.status(200).json({ success: true, ...result });
  } catch (error) {
    console.error('🐷 linkWallet failed:', error.message);
    res.status(500).json({ success: false, message: 'Failed to link wallet' });
  }
});

// POST /api/piggy-bank/claim — claim the entire confirmed balance (min
// threshold) to the linked wallet. T1 of the settlement state machine.
router.post('/claim', async (req, res) => {
  try {
    if (!cactusWallet.isEnabled()) {
      return res.status(503).json({
        success: false, code: 'claims_disabled', message: 'Claiming is coming soon'
      });
    }
    const result = await piggyBankService.claim(req.user.uid);
    if (!result.ok) {
      const statusByCode = { no_wallet: 400, below_minimum: 400, nothing_to_send: 400, claim_in_flight: 409 };
      return res.status(statusByCode[result.code] || 500).json({ success: false, ...result });
    }
    res.status(200).json({ success: true, claim: result.claim });
  } catch (error) {
    console.error('🐷 claim route failed:', error.message);
    res.status(500).json({ success: false, message: 'Failed to claim' });
  }
});

module.exports = router;
