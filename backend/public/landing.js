// public/landing.js — the shared-link landing pages (connect, place, user,
// widget, tab, quote, sticker /s, Scan Action /q). The site's CSP only runs
// our own script files (script-src 'self'), so none of this can be inline:
// it used to be, and silently never ran (found 2026-11-11).
//
// <meta name="fc-app-link" content="circles://…">: try the app first (in-app
// browsers that don't open Universal Links), then the App Store from
// <meta name="fc-store-url"> if the page is still showing.
//
// <a id="get-app" data-clipboard="…">: deferred deep link. An App Store
// install loses the link, so tapping "Get" leaves it on the clipboard (a
// write needs a tap); the app reads it once on its first launch.
(function () {
  var meta = function (name) {
    var el = document.querySelector('meta[name="' + name + '"]');
    return el ? el.getAttribute('content') : null;
  };

  var appLink = meta('fc-app-link');
  var storeUrl = meta('fc-store-url');
  if (appLink && /^circles:\/\//.test(appLink)) {
    window.location = appLink;
    if (storeUrl && /^https:\/\/apps\.apple\.com\//.test(storeUrl)) {
      setTimeout(function () { if (!document.hidden) window.location = storeUrl; }, 1500);
    }
  }

  var button = document.getElementById('get-app');
  var payload = button && button.getAttribute('data-clipboard');
  if (payload) {
    button.addEventListener('click', function () {
      try { navigator.clipboard.writeText(payload); } catch (e) { /* no clipboard: the app asks again */ }
    });
  }
})();
