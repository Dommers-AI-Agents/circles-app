// The waitlist on a store's web page (views/orderPage.js): join with a name,
// party size and email; then the place in line, polled every 15 s. The
// entry's token lives in localStorage so a reopened tab finds its spot.
(function () {
  var box = document.getElementById('waitlist');
  if (!box) return;
  var data = JSON.parse(document.getElementById('waitlist-data').textContent);
  var form = document.getElementById('waitlistForm');
  var status = document.getElementById('waitlistStatus');
  var err = document.getElementById('waitlistError');
  var leaveBtn = document.getElementById('waitlistLeave');
  var key = 'favcircles.waitlist.' + data.slug;
  var timer = null;

  function saved() { try { return JSON.parse(localStorage.getItem(key) || 'null'); } catch (e) { return null; } }
  function remember(v) { try { v ? localStorage.setItem(key, JSON.stringify(v)) : localStorage.removeItem(key); } catch (e) {} }

  function show(entry) {
    var open = entry.status === 'waiting' || entry.status === 'notified';
    form.hidden = open;
    status.hidden = !open && entry.status !== 'seated';
    leaveBtn.hidden = !open;
    if (entry.status === 'notified') {
      status.innerHTML = '<p class="big">Your table is ready</p><p class="sub">Head to the host stand — they’ll hold it for ' + (entry.holdMinutes || 15) + ' minutes.</p>';
    } else if (open) {
      var place = entry.position ? 'You’re #' + entry.position + ' in line' : 'You’re in line';
      var wait = entry.estimateMinutes ? ' · about ' + entry.estimateMinutes + ' min' : '';
      status.innerHTML = '<p class="big">' + place + wait + '</p><p class="sub">Party of ' + entry.partySize + '. We’ll email you the moment your table is ready.</p>';
    } else if (entry.status === 'seated') {
      status.innerHTML = '<p class="big">Enjoy!</p><p class="sub">You’re seated.</p>';
    } else {
      status.hidden = true;
      remember(null);
    }
  }

  function poll(s) {
    clearTimeout(timer);
    fetch(data.base + '/api/waitlist/' + encodeURIComponent(s.entryId) + '?t=' + encodeURIComponent(s.token))
      .then(function (r) { return r.json(); })
      .then(function (body) {
        if (!body.success) { remember(null); form.hidden = false; status.hidden = true; leaveBtn.hidden = true; return; }
        show(body.data);
        if (body.data.status === 'waiting' || body.data.status === 'notified') timer = setTimeout(function () { poll(s); }, 15000);
      })
      .catch(function () { timer = setTimeout(function () { poll(s); }, 30000); });
  }

  form.addEventListener('submit', function (ev) {
    ev.preventDefault();
    err.textContent = '';
    var f = new FormData(form);
    var btn = form.querySelector('button[type=submit]');
    btn.disabled = true;
    fetch(data.base + '/' + encodeURIComponent(data.slug) + '/waitlist', {
      method: 'POST', headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ name: f.get('name'), email: f.get('email'), partySize: Number(f.get('party')), website: f.get('website') })
    })
      .then(function (r) { return r.json(); })
      .then(function (body) {
        btn.disabled = false;
        if (!body.success) { err.textContent = body.message || 'Couldn’t join the line. Ask at the host stand.'; return; }
        var s = { entryId: body.data.entry.entryId, token: body.data.token };
        remember(s);
        show(body.data.entry);
        poll(s);
      })
      .catch(function () { btn.disabled = false; err.textContent = 'Couldn’t reach the store just now. Try again.'; });
  });

  leaveBtn.addEventListener('click', function () {
    var s = saved();
    if (!s) return;
    fetch(data.base + '/api/waitlist/' + encodeURIComponent(s.entryId) + '/leave?t=' + encodeURIComponent(s.token), { method: 'POST' })
      .then(function () { remember(null); clearTimeout(timer); form.hidden = false; status.hidden = true; leaveBtn.hidden = true; });
  });

  var existing = saved();
  if (existing) poll(existing);
})();
