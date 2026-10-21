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

/** @param {object} user  a user doc's data (or a projected user) */
const isHiddenAccount = (user) => {
  if (!user) return true;
  if (user.isTestAccount === true || user.isFakeProfile === true) return true;
  if (user.mergedInto || user.active === false) return true;
  return TEST_ACCOUNT_EMAILS.has(String(user.email || '').trim().toLowerCase());
};

module.exports = { isHiddenAccount, TEST_ACCOUNT_EMAILS, HIDDEN_ACCOUNT_FIELDS };
