// public/scan-landing.js — the /q/<code> page (Scan Actions) and the /s/<code>
// sticker page. The site's CSP only runs our own script files, so this can't
// be inline.
//
// Deferred deep link: an App Store install loses the link, so tapping "Get"
// puts the code on the clipboard (clipboard writes need a tap). The app
// reads it once on its first launch and finishes what the code was for.
(function () {
  var button = document.getElementById('get-app');
  if (!button) return;
  var payload = button.getAttribute('data-clipboard');
  if (!payload) return;
  button.addEventListener('click', function () {
    try { navigator.clipboard.writeText(payload); } catch (e) { /* no clipboard: the app asks again */ }
  });
})();
