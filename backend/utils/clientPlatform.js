// backend/utils/clientPlatform.js
// Which phone is asking, from its User-Agent. The only use (2026-11-26): a
// store's QR opens the App Clip / app on an Apple phone and the store's web
// page everywhere else, since there is no Android app. Pure.

/**
 * True for an iPhone, iPod or iPad. An iPad asks as a Mac ("Macintosh" with
 * touch, which a server can't see), so a Mac counts as Apple too: both have
 * the app or the clip. No User-Agent at all is treated as Apple, which keeps
 * link previews and older callers on the page they have always had.
 */
const isAppleDevice = (userAgent) => {
  const ua = String(userAgent || '');
  if (!ua.trim()) return true;
  if (/android/i.test(ua)) return false; // some Android browsers add "like Mac OS X"
  return /iPhone|iPad|iPod|Macintosh/i.test(ua);
};

module.exports = { isAppleDevice };
