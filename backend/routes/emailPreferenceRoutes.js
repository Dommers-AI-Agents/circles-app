// backend/routes/emailPreferenceRoutes.js
//
// One-click unsubscribe links in our emails land here. No login: an email
// client can't carry a JWT, so the link carries an HMAC of (uid, kind) made
// with the server secret instead. A valid signature flips
// users/{uid}.emailPreferences[kind] = false; anything else is a 400.
const express = require('express');
const followSuggestions = require('../services/followSuggestionEmailService');

const router = express.Router();

const KNOWN_KINDS = new Set([followSuggestions.PREFERENCE_KEY, 'weeklyMapDigest']);
const LABELS = {
  [followSuggestions.PREFERENCE_KEY]: '"People you may know" emails',
  weeklyMapDigest: 'the weekly map email'
};

const page = (title, body) => `<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${title}</title>
<div style="font-family:-apple-system,Helvetica,Arial,sans-serif;max-width:480px;margin:48px auto;padding:0 24px;color:#1a202c;text-align:center;">
  <h1 style="font-size:22px;">${title}</h1>
  <p style="font-size:15px;line-height:1.6;color:#4a5568;">${body}</p>
  <p style="margin-top:28px;"><a href="https://favcircles.com" style="color:#3478F6;">favcircles.com</a></p>
</div>`;

router.get('/unsubscribe', async (req, res) => {
  const uid = String(req.query.uid || '').replace(/[^a-zA-Z0-9._-]/g, '');
  const kind = String(req.query.kind || '');
  const sig = String(req.query.sig || '');
  if (!uid || !KNOWN_KINDS.has(kind) || !followSuggestions.verifyUnsubscribeToken(uid, kind, sig)) {
    return res.status(400).send(page("That link didn't work", 'It may be incomplete or from an older email. You can manage emails from the app.'));
  }
  try {
    await followSuggestions.unsubscribe(uid, kind);
    return res.send(page("You're unsubscribed", `We won't send you ${LABELS[kind]} any more.`));
  } catch (e) {
    console.error('Unsubscribe failed:', e.message);
    return res.status(500).send(page('Something went wrong', 'Please try the link again in a moment.'));
  }
});

module.exports = router;
