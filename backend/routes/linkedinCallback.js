// LinkedIn OAuth Callback Route
const express = require('express');
const router = express.Router();

// Handle LinkedIn OAuth callback and redirect to app
router.get('/auth/linkedin/callback', (req, res) => {
  const { code, state, error } = req.query;
  
  if (error) {
    // Redirect to app with error
    res.redirect(`com.favcircles.circles://linkedin/callback?error=${error}`);
    return;
  }
  
  if (code) {
    // Redirect to app with authorization code
    res.redirect(`com.favcircles.circles://linkedin/callback?code=${code}&state=${state || ''}`);
  } else {
    // No code or error
    res.redirect(`com.favcircles.circles://linkedin/callback?error=no_code`);
  }
});

module.exports = router;