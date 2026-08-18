// Public website lead capture: favcircles.com's "get your FavCoins" email
// form posts here. Stores the lead (doc id = normalized email — natural
// dedup) and sends the how-to-get-your-FavCoins email once per address.

const express = require('express');
const rateLimit = require('express-rate-limit');
const router = express.Router();
const { getFirestore } = require('../config/firebase');
const db = getFirestore();

const leadLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 10, // per IP — humans typing their email, not bots
  standardHeaders: true,
  legacyHeaders: false
});

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

router.post('/website', leadLimiter, async (req, res) => {
  try {
    const raw = String((req.body || {}).email || '').trim().toLowerCase();
    if (!EMAIL_RE.test(raw) || raw.length > 254) {
      return res.status(400).json({ success: false, message: 'Please enter a valid email address.' });
    }

    // Doc id = email with '/' and '.' made safe — one lead per address, ever
    const docId = raw.replace(/[/.]/g, '_');
    const ref = db.collection('websiteLeads').doc(docId);
    const existing = await ref.get();

    if (existing.exists && existing.data().emailedAt) {
      // Already emailed — same friendly answer, no re-send (no enumeration,
      // no spamming an address twice)
      return res.status(200).json({ success: true, message: 'Check your inbox — your FavCoins guide is on the way!' });
    }

    await ref.set({
      email: raw,
      source: 'website',
      createdAt: existing.exists ? existing.data().createdAt : new Date().toISOString()
    }, { merge: true });

    const emailService = require('../services/emailService');
    await emailService.sendWebsiteLeadEmail(raw);
    await ref.update({ emailedAt: new Date().toISOString() });

    res.status(200).json({ success: true, message: 'Check your inbox — your FavCoins guide is on the way!' });
  } catch (error) {
    console.error('❌ Website lead capture failed:', error.message);
    res.status(500).json({ success: false, message: 'Something went wrong — please try again.' });
  }
});

module.exports = router;
