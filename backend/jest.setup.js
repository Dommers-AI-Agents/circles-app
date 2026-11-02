// Tests start with the private-profile registry loaded and empty (every
// profile public), as a running server is after its first load. Tests about
// private profiles set their own via profilePrivacy._setForTests.
require('./services/profilePrivacy')._setForTests([]);
