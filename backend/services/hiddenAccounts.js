// Accounts no one should find, follow or connect with (Wes, 2026-10-21): the
// App Review account and our own test accounts. One rule for every people
// surface — search, discover, suggestions, contact matches — so a new
// surface can't forget one.
//
// Mark a test account with `isTestAccount: true` on its user doc; the emails
// below are caught even without the flag. Fake (demo) profiles, merged-away
// and deactivated accounts are hidden too.
const TEST_ACCOUNT_EMAILS = new Set([
  'appreview@favcircles.com',
  'review@favcircles.com',
  'test@favcircles.com',
  'phototest@favcircles.com'
]);

// Fields a .select() must include for isHiddenAccount to decide
const HIDDEN_ACCOUNT_FIELDS = ['email', 'isTestAccount', 'isFakeProfile', 'mergedInto', 'active'];

/**
 * Our own test sign-ups by their address (Wes, 2026-11-01): any favcircles.com
 * email starting with "tester" or "cliptest" (tester1.4.5@, cliptest-123@),
 * so a fresh test account is treated as one from its first second, before
 * anyone remembers to flag it.
 */
const isTestEmail = (email) => {
  const e = String(email || '').trim().toLowerCase();
  return TEST_ACCOUNT_EMAILS.has(e) || /^(tester|cliptest)[^@]*@favcircles\.com$/.test(e);
};

/** @param {object} user  a user doc's data (or a projected user) */
const isHiddenAccount = (user) => {
  if (!user) return true;
  if (user.isTestAccount === true || user.isFakeProfile === true) return true;
  if (user.mergedInto || user.active === false) return true;
  return isTestEmail(user.email);
};

module.exports = { isHiddenAccount, isTestEmail, TEST_ACCOUNT_EMAILS, HIDDEN_ACCOUNT_FIELDS };
