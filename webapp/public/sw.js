// The web app's service worker (served at /sw.js on app.favcircles.com by
// backend/routes/webAppRoutes.js). It does one job: show a notification the
// server pushed (backend/services/webPush.js) and open the right screen when
// it is tapped. It caches nothing, so a deploy is never held back by it.
self.addEventListener('install', function () { self.skipWaiting(); });
self.addEventListener('activate', function (event) { event.waitUntil(self.clients.claim()); });

self.addEventListener('push', function (event) {
  var data = {};
  try { data = event.data ? event.data.json() : {}; } catch (e) { data = {}; }
  var title = data.title || 'FavCircles';
  event.waitUntil(self.registration.showNotification(title, {
    body: data.body || '',
    tag: data.tag || 'favcircles',
    icon: 'https://favcircles.com/app-icon.png',
    badge: 'https://favcircles.com/app-icon.png',
    data: { url: typeof data.url === 'string' && data.url.charAt(0) === '/' ? data.url : '/' }
  }));
});

self.addEventListener('notificationclick', function (event) {
  event.notification.close();
  var url = (event.notification.data && event.notification.data.url) || '/';
  event.waitUntil(self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(function (windows) {
    for (var i = 0; i < windows.length; i++) {
      var open = windows[i];
      if ('focus' in open) {
        if ('navigate' in open) return open.navigate(url).then(function (moved) { return (moved || open).focus(); });
        return open.focus();
      }
    }
    return self.clients.openWindow(url);
  }));
});
