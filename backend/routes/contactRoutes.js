const express = require('express');
const rateLimit = require('express-rate-limit');
const emailService = require('../services/emailService');

const router = express.Router();

// Website contact form — public (site visitors aren't logged in), so keep it
// tight: strict rate limit, honeypot, and hard length caps.
const contactLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 5,
  message: { success: false, message: 'Too many messages — please try again later.' }
});

router.post('/', contactLimiter, async (req, res) => {
  try {
    const { name, email, message, website } = req.body || {};

    // Honeypot: real users never see this field; bots fill everything
    if (website) {
      return res.json({ success: true });
    }

    const cleanEmail = String(email || '').trim().slice(0, 200);
    const cleanName = String(name || '').trim().slice(0, 100);
    const cleanMessage = String(message || '').trim().slice(0, 5000);

    if (!cleanName) {
      return res.status(400).json({ success: false, message: 'Please enter your name.' });
    }
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(cleanEmail)) {
      return res.status(400).json({ success: false, message: 'Please enter a valid email address.' });
    }
    if (cleanMessage.length < 5) {
      return res.status(400).json({ success: false, message: 'Please enter a message.' });
    }

    await emailService.transporter.sendMail({
      from: `"FavCircles Website" <${process.env.EMAIL_FROM_ADDRESS || 'wesley@favcircles.com'}>`,
      to: process.env.CONTACT_EMAIL || 'wesley@favcircles.com',
      replyTo: cleanName ? `"${cleanName.replace(/"/g, '')}" <${cleanEmail}>` : cleanEmail,
      subject: `✉️ Website contact from ${cleanName || cleanEmail}`,
      text: [
        `From: ${cleanName || '(no name)'} <${cleanEmail}>`,
        `Page: ${req.get('referer') || 'unknown'}`,
        '',
        cleanMessage
      ].join('\n')
    });

    return res.json({ success: true, message: "Thanks — your message is on its way. We'll reply to your email." });
  } catch (e) {
    console.error('✉️ contact form send failed:', e.message);
    return res.status(500).json({ success: false, message: "Couldn't send your message. Please email wesley@favcircles.com directly." });
  }
});

module.exports = router;
