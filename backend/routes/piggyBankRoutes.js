// backend/routes/piggyBankRoutes.js
// FavCoin piggy bank: balance + history reads. Earning happens via hooks in
// the action controllers; clearing via the scheduled task. Claiming is
// Phase 4 — the route exists only to reserve the path.

const express = require('express');
const { protect } = require('../middleware/firebaseAuth');
const piggyBankService = require('../services/piggyBankService');

const router = express.Router();
router.use(protect);

// GET /api/piggy-bank — bank + recent events + display config
router.get('/', async (req, res) => {
  try {
    const payload = await piggyBankService.getPiggyBank(req.user.uid);
    res.status(200).json({ success: true, ...payload });
  } catch (error) {
    console.error('🐷 getPiggyBank failed:', error.message);
    res.status(500).json({ success: false, message: 'Failed to load piggy bank' });
  }
});

// GET /api/piggy-bank/history?before=<iso> — paginated ledger
router.get('/history', async (req, res) => {
  try {
    const events = await piggyBankService.getHistory(req.user.uid, req.query.before || null);
    res.status(200).json({ success: true, events });
  } catch (error) {
    console.error('🐷 piggy history failed:', error.message);
    res.status(500).json({ success: false, message: 'Failed to load history' });
  }
});

// POST /api/piggy-bank/claim — Phase 4 (blockchain settlement). Reserved.
router.post('/claim', (req, res) => {
  res.status(501).json({ success: false, message: 'Claiming is coming soon' });
});

module.exports = router;
