// A store's web page (views/storePage.js): sign in with an emailed code,
// save the store, get the points, turn its emails on, redeem at the counter.
// It calls the same API the App Clip does. CSP disallows inline scripts, so
// this lives in its own file. Plain ES5: it has to run on old Android phones.
(function () {
  var dataEl = document.getElementById('store-data');
  if (!dataEl) return;
  var store = JSON.parse(dataEl.textContent);
  // Its own key: the admin dashboard is served from this origin too
  var SESSION_KEY = 'fc.store.session';

  function $(id) { return document.getElementById(id); }
  function text(id, value) { $(id).textContent = value == null ? '' : String(value); }
  var STEPS = ['email', 'code', 'earn', 'done', 'share', 'ticket'];
  function show(step) {
    STEPS.forEach(function (s) { $('step-' + s).hidden = s !== step; });
    window.scrollTo(0, document.body.scrollHeight);
  }

  // ---- session (this phone remembers the sign-in, so later scans skip it)
  function session() {
    try { return JSON.parse(localStorage.getItem(SESSION_KEY) || 'null'); } catch (e) { return null; }
  }
  function saveSession(value) {
    try {
      if (value) localStorage.setItem(SESSION_KEY, JSON.stringify(value));
      else localStorage.removeItem(SESSION_KEY);
    } catch (e) { /* private mode: signed in for this visit only */ }
    memory = value;
  }
  var memory = session();

  // ---- API
  function api(method, path, body, done) {
    var xhr = new XMLHttpRequest();
    xhr.open(method, '/api' + path, true);
    xhr.setRequestHeader('Content-Type', 'application/json');
    if (memory && memory.token) xhr.setRequestHeader('Authorization', 'Bearer ' + memory.token);
    xhr.onreadystatechange = function () {
      if (xhr.readyState !== 4) return;
      var json = null;
      try { json = JSON.parse(xhr.responseText); } catch (e) { json = null; }
      done(xhr.status, json || {});
    };
    xhr.onerror = function () { done(0, {}); };
    xhr.send(body ? JSON.stringify(body) : null);
  }
  function problem(status, json, fallback) {
    if (status === 0) return "You're offline. Check your connection and try again.";
    if (status === 429) return json.message || json.error || 'Too many tries. Wait a few minutes and try again.';
    return json.message || json.error || fallback;
  }
  // The 30-day sign-in ran out (or was revoked): ask for the email code again
  function expired(status) {
    if (status !== 401) return false;
    saveSession(null);
    text('email-err', 'Please sign in again.');
    show('email');
    return true;
  }
  function busy(id, on, label) {
    var button = $(id);
    button.disabled = on;
    if (label) button.textContent = label;
  }

  // ---- step 1: email
  var email = '';
  var isNew = false;
  $('email-form').addEventListener('submit', function (event) {
    event.preventDefault();
    email = $('email').value.replace(/\s+/g, '').toLowerCase();
    text('email-err', '');
    if (!/^[^@]+@[^@]+\.[^@]+$/.test(email)) { text('email-err', 'Enter your email address.'); return; }
    busy('email-go', true, 'Sending your code…');
    api('POST', '/auth/email-code/start', { email: email }, function (status, json) {
      busy('email-go', false, 'Continue');
      if (status !== 200 || !json.success) { text('email-err', problem(status, json, "Couldn't send a code. Try again.")); return; }
      isNew = json.newAccount === true;
      $('name-row').hidden = !isNew;
      text('code-to', email);
      text('code-err', '');
      $('code').value = '';
      show('code');
      $('code').focus();
    });
  });

  // ---- step 2: the code (and a name, for a new account)
  $('code-back').addEventListener('click', function () { show('email'); });
  $('code-form').addEventListener('submit', function (event) {
    event.preventDefault();
    var code = $('code').value.replace(/\D/g, '');
    var name = $('name').value.replace(/\s+/g, ' ').trim();
    text('code-err', '');
    if (code.length !== 6) { text('code-err', 'Enter the 6 digits from the email.'); return; }
    if (isNew && name.length < 2) { text('code-err', 'Add your name so the store knows who earned the points.'); return; }
    busy('code-go', true, 'Signing you in…');
    var body = { email: email, code: code, signupSource: 'store_web', stickerCode: store.code };
    if (isNew) body.displayName = name;
    api('POST', '/auth/email-code/verify', body, function (status, json) {
      busy('code-go', false, 'Sign in');
      if (json.code === 'NAME_REQUIRED') {
        isNew = true;
        $('name-row').hidden = false;
        text('code-err', 'Add your name to finish.');
        return;
      }
      if ((status !== 200 && status !== 201) || !json.token) {
        text('code-err', problem(status, json, "That code didn't work. Try again."));
        return;
      }
      saveSession({ token: json.token, name: (json.user && json.user.displayName) || name || '' });
      var wantsAlerts = !!$('alerts') && $('alerts').checked;
      scan(function () { if (wantsAlerts) turnOnAlerts(); });
    });
  });

  // ---- the store's emails: follow it, then its bell (the App Clip's two calls).
  // Only at sign-in, where the box is: a later scan never turns back on what
  // someone stopped from an email.
  function turnOnAlerts() {
    if (!store.globalPlaceId) return;
    var place = encodeURIComponent(store.globalPlaceId);
    api('POST', '/places/' + place + '/follow', null, function () {
      api('POST', '/places/' + place + '/follow/alerts', null, function () {});
    });
  }

  // ---- the scan: save + points (window), or the visit's points (register)
  function scanBody(extra) {
    // counted: this page's visit was counted as a scan when it was served
    var body = { code: store.code, save: true, counted: true };
    if (store.tag) body.t = store.tag;
    if (store.couponId) body.c = store.couponId;
    for (var key in extra) if (Object.prototype.hasOwnProperty.call(extra, key)) body[key] = extra[key];
    return body;
  }
  function scan(after) {
    if (store.kind === 'register') { askWhere(function (where) { send(where, 0); }); } else { send({}, 0); }
    function send(extra, attempt) {
      api('POST', '/rewards/scan', scanBody(extra), function (status, json) {
        if (expired(status)) return;
        if (status !== 200 || !json.success) {
          var message = problem(status, json, "Couldn't reach the store's rewards. Try again.");
          if (store.kind === 'register') { text('earn-err', message); busy('earn-go', false, "Get today's points"); show('earn'); } else { text('done-err', message); showDone({}); }
          return;
        }
        // The first circle of a brand-new account can take a moment: once more
        if (json.data.savePending && attempt === 0) { setTimeout(function () { send(extra, 1); }, 2500); return; }
        showDone(json.data);
        if (after) after();
      });
    }
  }
  // Same rule as the app: where the phone is goes with a register scan; a
  // phone that won't say still earns (the store sees "location off")
  function askWhere(done) {
    if (!navigator.geolocation) { done({ locationOff: true }); return; }
    var answered = false;
    function finish(value) { if (!answered) { answered = true; done(value); } }
    navigator.geolocation.getCurrentPosition(function (position) {
      finish({ location: { latitude: position.coords.latitude, longitude: position.coords.longitude, accuracy: position.coords.accuracy } });
    }, function (error) {
      finish(error && error.code === 1 ? { locationOff: true } : {});
    }, { enableHighAccuracy: true, timeout: 8000, maximumAge: 60000 });
    setTimeout(function () { finish({}); }, 9000);
  }

  // ---- what they got
  var lastData = {};
  function showDone(data) {
    lastData = data || {};
    var points = data.awarded ? data.awarded.points : 0;
    var title;
    var sub = '';
    if (data.kind === 'register') {
      if (points > 0) { title = ['+' + points + ' points.', 'Thanks for coming in.']; }
      else if (data.notAtStore) { title = ['No points this time.', '']; sub = 'Points are for visits to ' + store.name + '. Scan the code at the register when you are there.'; }
      else if (data.alreadyEarnedToday) { title = ['You already got today\'s points.', '']; sub = 'Come back tomorrow for more.'; }
      else if (data.removedFromRewards) { title = ['No points this time.', '']; sub = store.name + ' has taken you off its rewards. Ask at the counter if that\'s a mistake.'; }
      else { title = ['You\'re signed in.', '']; }
    } else if (points > 0) {
      title = ['Saved.', '+' + points + ' points.'];
      sub = data.earnRate ? 'Scan the code at the register each visit for ' + data.earnRate + ' more.' : '';
    } else if (data.venue) {
      title = [data.alreadySaved && !data.saved ? 'Welcome back.' : 'Saved.', ''];
      sub = data.loyaltyLive && data.earnRate
        ? 'Scan the code at the register each visit for ' + data.earnRate + ' points.'
        : store.name + ' is on your list.';
    } else {
      title = ['You\'re signed in.', ''];
    }
    var titleEl = $('done-title');
    titleEl.textContent = title[0] + ' ';
    if (title[1]) { var gold = document.createElement('span'); gold.className = 'g'; gold.textContent = title[1]; titleEl.appendChild(gold); }
    text('done-sub', sub);

    var coupon = data.coupon;
    var couponEl = $('done-coupon');
    couponEl.hidden = true;
    if (coupon && coupon.status === 'ticket' && coupon.voucher) { showTicket(coupon.voucher); return; }
    if (coupon && coupon.coupon && coupon.coupon.title) {
      couponEl.hidden = false;
      couponEl.textContent = 'Your coupon: ' + coupon.coupon.title;
      var how = document.createElement('span');
      how.textContent = 'Scan the code at the register to use it.';
      couponEl.appendChild(how);
    }

    var live = data.loyaltyLive === true;
    $('done-bal').hidden = !live;
    text('done-points', data.venueBalance || 0);
    var ladder = $('done-ladder');
    ladder.innerHTML = '';
    (live ? data.offers || [] : []).forEach(function (offer) {
      if (!offer || !offer.title || !(offer.pointsCost > 0) || offer.active === false) return;
      var row = document.createElement('li');
      var label = document.createElement('span');
      label.textContent = offer.title;
      var cost = document.createElement('span');
      cost.className = 'c';
      cost.textContent = offer.pointsCost + ' points';
      label.appendChild(cost);
      row.appendChild(label);
      if ((data.venueBalance || 0) >= offer.pointsCost) {
        var button = document.createElement('button');
        button.type = 'button';
        button.textContent = 'Redeem';
        button.addEventListener('click', function () { redeem(offer, button); });
        row.appendChild(button);
      }
      ladder.appendChild(row);
    });
    show('done');
  }

  // ---- redeem: the counter ticket
  var pendingOffer = null;
  function redeem(offer, button) {
    text('done-err', '');
    if (button) button.disabled = true;
    api('POST', '/rewards/redeem-offer', { venueId: store.venueId, offerId: offer.offerId, canShare: true }, function (status, json) {
      if (button) button.disabled = false;
      if (expired(status)) return;
      if (json.code === 'share_required') {
        pendingOffer = offer;
        text('share-sub', 'Rewards at ' + store.name + ' are claimed by name. Share your name and email with ' + store.name + ' to get this one.');
        text('share-err', '');
        show('share');
        return;
      }
      if (status !== 200 || !json.success) { text('done-err', problem(status, json, "Couldn't redeem that. Try again.")); show('done'); return; }
      lastData.venueBalance = json.data.venueBalance != null ? json.data.venueBalance : lastData.venueBalance;
      showTicket(json.data.voucher);
    });
  }
  $('share-no').addEventListener('click', function () { show('done'); });
  $('share-go').addEventListener('click', function () {
    busy('share-go', true);
    api('POST', '/rewards/venues/' + encodeURIComponent(store.venueId) + '/share', {}, function (status, json) {
      busy('share-go', false);
      if (expired(status)) return;
      if (status !== 200 || !json.success) { text('share-err', problem(status, json, "Couldn't share. Try again.")); return; }
      if (pendingOffer) redeem(pendingOffer, null);
    });
  });

  var ticket = null;
  var ticker = null;
  function showTicket(voucher) {
    ticket = voucher;
    text('ticket-title', voucher.offerTitle || 'Your reward');
    text('ticket-code', voucher.voucherCode || '');
    text('ticket-err', '');
    $('ticket-given').hidden = false;
    show('ticket');
    if (ticker) clearInterval(ticker);
    tick();
    ticker = setInterval(tick, 1000);
  }
  function tick() {
    var left = Math.floor((Date.parse(ticket.expiresAt) - Date.now()) / 1000);
    if (!(left > 0)) {
      clearInterval(ticker);
      text('ticket-left', 'This ticket ran out. Your points are back.');
      $('ticket-given').hidden = true;
      return;
    }
    var seconds = left % 60;
    text('ticket-left', 'Good for ' + Math.floor(left / 60) + ':' + (seconds < 10 ? '0' : '') + seconds);
  }
  $('ticket-given').addEventListener('click', function () {
    busy('ticket-given', true);
    api('POST', '/rewards/vouchers/' + encodeURIComponent(ticket.voucherId) + '/given', {}, function (status, json) {
      busy('ticket-given', false);
      if (expired(status)) return;
      if (status !== 200 || !json.success) { text('ticket-err', problem(status, json, "Couldn't mark it given. Try again.")); return; }
      clearInterval(ticker);
      text('ticket-left', 'Given. Enjoy!');
      $('ticket-given').hidden = true;
    });
  });
  $('ticket-back').addEventListener('click', function () {
    if (ticker) clearInterval(ticker);
    refresh();
  });
  // The balance after a ticket: a window scan again changes nothing and pays nothing twice
  function refresh() {
    api('GET', '/rewards/balance', null, function (status, json) {
      if (expired(status)) return;
      var rows = (json.data && json.data.venueBalances) || [];
      for (var i = 0; i < rows.length; i++) if (rows[i].venueId === store.venueId) lastData.venueBalance = rows[i].points || 0;
      lastData.coupon = null;
      lastData.awarded = null;
      showDone(lastData);
    });
  }

  $('sign-out').addEventListener('click', function () {
    saveSession(null);
    text('email-err', '');
    show('email');
  });

  // ---- a returning phone
  $('earn-go').addEventListener('click', function () {
    text('earn-err', '');
    busy('earn-go', true, 'Checking…');
    scan();
  });
  if (memory && memory.token) {
    if (store.kind === 'register') {
      text('earn-title', memory.name ? 'Welcome back, ' + memory.name.split(' ')[0] + '.' : 'Welcome back.');
      text('earn-sub', store.loyaltyLive ? 'Tap for the points from this visit.' : '');
      show('earn');
    } else {
      scan();
    }
  }
})();
