// The guest's order status page (views/orderPage.js renderOrderStatusPage).
// Polls like the app does while the order is open. CSP: no inline scripts.
(function () {
  var data = JSON.parse(document.getElementById('status-data').textContent);
  var base = data.base || '';
  var orderId = data.orderId;
  var key = 'fc_order_' + orderId;
  var token = null;
  try {
    var q = new URLSearchParams(location.search);
    if (q.get('t')) { token = q.get('t'); localStorage.setItem(key, token); history.replaceState(null, '', location.pathname); }
    else token = localStorage.getItem(key);
  } catch (e) { token = token || new URLSearchParams(location.search).get('t'); }

  var statusEl = document.getElementById('status');
  var errEl = document.getElementById('statusError');
  var cancelBtn = document.getElementById('cancelBtn');
  var again = document.getElementById('again');
  var timer = null;
  var OPEN = { placed: 1, accepted: 1, ready: 1 };

  function el(tag, cls, text) { var e = document.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = text; return e; }
  function time(iso) { try { return new Date(iso).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' }); } catch (e) { return ''; } }

  function render(o) {
    document.getElementById('storeName').textContent = o.venueName;
    var meta = document.getElementById('storeMeta');
    meta.innerHTML = '';
    if (o.venuePhone) { var a = el('a', null, 'Call ' + o.venuePhone); a.href = 'tel:' + o.venuePhone.replace(/[^+\d]/g, ''); meta.appendChild(a); }
    statusEl.innerHTML = '';
    var big = el('p', 'big', o.statusLabel);
    var sub;
    if (o.status === 'placed') sub = 'Waiting for the store to accept it. Pay at pickup.';
    else if (o.status === 'accepted') sub = o.readyAt ? 'Ready around ' + time(o.readyAt) + '. Pay at pickup.' : 'They’re on it. Pay at pickup.';
    else if (o.status === 'ready') sub = 'Head to the counter to pick it up and pay.';
    else if (o.status === 'declined') sub = o.declineReason || 'The store couldn’t take this one.';
    else if (o.status === 'expired') sub = 'Nobody answered in time, so don’t head over for it. Try calling the store.';
    else if (o.status === 'cancelled') sub = 'You cancelled this order.';
    else if (o.status === 'picked_up') sub = 'Picked up. Enjoy!';
    statusEl.appendChild(big); statusEl.appendChild(el('p', 'sub', sub || ''));
    var ul = el('ul');
    o.lines.forEach(function (l) {
      var li = el('li'); li.appendChild(el('span', null, l.qty + '× ' + l.name + (l.note ? ' · ' + l.note : ''))); li.appendChild(el('span', null, l.price || ''));
      ul.appendChild(li);
    });
    var tot = el('li'); tot.appendChild(el('b', null, 'Estimate'));
    tot.appendChild(el('b', null, o.estimate ? 'About $' + Number(o.estimate).toFixed(2) + (o.estimateIsPartial ? '+' : '') : 'At the counter'));
    ul.appendChild(tot);
    statusEl.appendChild(ul);
    var pick = el('p', 'sub', o.pickup && !o.pickup.asap && o.pickup.at ? 'Pickup at ' + time(o.pickup.at) : 'Pickup as soon as it’s ready');
    statusEl.appendChild(pick);
    cancelBtn.hidden = o.status !== 'placed';
    if (o.slug) { again.href = base + '/' + o.slug; again.hidden = false; }
    if (!OPEN[o.status] && timer) { clearInterval(timer); timer = null; }
  }

  function fetchStatus() {
    if (!token) { errEl.textContent = 'This link has no order attached. Open the one from your email or the page you ordered on.'; return; }
    fetch('/order/api/orders/' + encodeURIComponent(orderId), { headers: { Authorization: 'Bearer ' + token } })
      .then(function (r) { return r.json(); })
      .then(function (j) { if (!j.success) { errEl.textContent = j.message || 'Order not found.'; return; } errEl.textContent = ''; render(j.data); })
      .catch(function () { errEl.textContent = 'No connection. Trying again…'; });
  }

  cancelBtn.addEventListener('click', function () {
    if (!confirm('Cancel this order?')) return;
    cancelBtn.disabled = true;
    fetch('/order/api/orders/' + encodeURIComponent(orderId) + '/cancel', { method: 'POST', headers: { Authorization: 'Bearer ' + token } })
      .then(function (r) { return r.json(); })
      .then(function (j) { if (j.success) render(j.data); else errEl.textContent = j.message || 'Couldn’t cancel.'; })
      .catch(function () { errEl.textContent = 'No connection.'; })
      .then(function () { cancelBtn.disabled = false; });
  });

  function start() { if (!timer) timer = setInterval(fetchStatus, 10000); }
  document.addEventListener('visibilitychange', function () {
    if (document.hidden) { if (timer) { clearInterval(timer); timer = null; } } else { fetchStatus(); start(); }
  });
  fetchStatus(); start();
})();
