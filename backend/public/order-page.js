// The store's ordering page (views/orderPage.js): cart, item sheet, checkout.
// CSP disallows inline scripts, so this lives in its own file.
(function () {
  var dataEl = document.getElementById('menu-data');
  if (!dataEl) return;
  var data = JSON.parse(dataEl.textContent);
  var base = data.base || '';
  var slug = data.slug;
  var apiBase = '/order/' + encodeURIComponent(slug);
  var MAX_QTY = 20, MAX_LINES = 50;
  var cartKey = 'fc_cart_' + slug;

  var items = {};
  data.sections.forEach(function (s) { s.items.forEach(function (i) { items[i.id] = i; }); });

  var cart = load();
  var current = null;

  function load() {
    try {
      var raw = JSON.parse(localStorage.getItem(cartKey) || '[]');
      return raw.filter(function (l) { return l && items[l.itemId] && l.qty > 0; });
    } catch (e) { return []; }
  }
  function save() { try { localStorage.setItem(cartKey, JSON.stringify(cart)); } catch (e) { /* private mode */ } }
  function line(id) { for (var i = 0; i < cart.length; i++) if (cart[i].itemId === id) return cart[i]; return null; }
  function priceValue(p) {
    var m = /^\s*\$?\s*(\d+(?:\.\d{1,2})?)\s*(?:usd)?\s*$/i.exec(String(p || ''));
    return m ? parseFloat(m[1]) : null;
  }
  function estimate() {
    var total = 0, partial = false;
    cart.forEach(function (l) { var v = priceValue(items[l.itemId].price); if (v == null) partial = true; else total += v * l.qty; });
    return { total: total, partial: partial };
  }
  function money(n) { return '$' + n.toFixed(2); }
  function estimateText() {
    var e = estimate();
    if (!cart.length) return '';
    if (e.total === 0 && e.partial) return 'Priced at the counter';
    return 'About ' + money(e.total) + (e.partial ? '+' : '');
  }

  var bar = document.getElementById('bar');
  function renderBar() {
    var count = cart.reduce(function (n, l) { return n + l.qty; }, 0);
    bar.hidden = count === 0;
    document.getElementById('barCount').textContent = count;
    document.getElementById('barTotal').textContent = estimateText();
    document.querySelectorAll('.item').forEach(function (el) {
      var l = line(el.getAttribute('data-item-id'));
      el.classList.toggle('inCart', !!l);
      var q = el.querySelector('[data-qty]');
      if (q) q.textContent = l ? l.qty : '';
    });
  }

  // ---- item sheet
  var itemDialog = document.getElementById('itemDialog');
  var qtyOut = document.getElementById('qty');
  var noteIn = document.getElementById('itemNote');
  function openItem(id) {
    var it = items[id]; if (!it) return;
    current = id;
    var l = line(id);
    document.getElementById('itemName').textContent = it.name;
    document.getElementById('itemDesc').textContent = it.description || '';
    document.getElementById('itemPrice').textContent = it.price || '';
    qtyOut.value = l ? l.qty : 1;
    noteIn.value = l ? (l.note || '') : '';
    document.getElementById('itemAdd').textContent = l ? 'Update' : 'Add to order';
    document.getElementById('itemRemove').hidden = !l;
    itemDialog.hidden = false;
    document.getElementById('itemAdd').focus();
  }
  function closeItem() { itemDialog.hidden = true; current = null; }
  document.querySelectorAll('.item').forEach(function (el) {
    el.addEventListener('click', function () { openItem(el.getAttribute('data-item-id')); });
  });
  document.getElementById('qtyMinus').addEventListener('click', function () { qtyOut.value = Math.max(1, Number(qtyOut.value) - 1); });
  document.getElementById('qtyPlus').addEventListener('click', function () { qtyOut.value = Math.min(MAX_QTY, Number(qtyOut.value) + 1); });
  document.getElementById('itemAdd').addEventListener('click', function () {
    if (!current) return;
    var l = line(current);
    var qty = Math.min(MAX_QTY, Math.max(1, Number(qtyOut.value) || 1));
    var note = noteIn.value.trim().slice(0, 200);
    if (l) { l.qty = qty; l.note = note; }
    else if (cart.length >= MAX_LINES) { alert('That is a lot for one order. Place this one, then start another.'); return; }
    else cart.push({ itemId: current, qty: qty, note: note });
    save(); renderBar(); closeItem();
  });
  document.getElementById('itemRemove').addEventListener('click', function () {
    cart = cart.filter(function (l) { return l.itemId !== current; });
    save(); renderBar(); closeItem();
  });
  document.getElementById('itemClose').addEventListener('click', closeItem);

  // ---- cart + checkout
  var cartDialog = document.getElementById('cartDialog');
  var form = document.getElementById('checkout');
  var errEl = document.getElementById('checkoutError');
  function renderCart() {
    var box = document.getElementById('cartLines');
    box.innerHTML = '';
    cart.forEach(function (l) {
      var it = items[l.itemId];
      var row = document.createElement('div'); row.className = 'row';
      var t = document.createElement('span');
      t.textContent = l.qty + '× ' + it.name + (l.note ? ' · ' + l.note : '');
      var p = document.createElement('span'); p.textContent = it.price || '';
      var edit = document.createElement('button'); edit.type = 'button'; edit.className = 'ghost'; edit.textContent = 'Edit';
      edit.addEventListener('click', function () { cartDialog.hidden = true; openItem(l.itemId); });
      row.appendChild(t); row.appendChild(p); row.appendChild(edit);
      box.appendChild(row);
    });
    document.getElementById('cartTotal').textContent = estimateText();
  }
  function fillPickupSlots() {
    var sel = document.getElementById('pickup');
    while (sel.options.length > 1) sel.remove(1);
    var now = new Date();
    var first = new Date(now.getTime() + (data.leadMinutes + 5) * 60000);
    first.setSeconds(0, 0);
    first.setMinutes(Math.ceil(first.getMinutes() / 15) * 15);
    var last = new Date(now.getTime() + 24 * 3600000);
    var fmtDay = function (d) { return d.toDateString() === now.toDateString() ? 'Today' : d.toLocaleDateString([], { weekday: 'short' }); };
    for (var t = first; t < last; t = new Date(t.getTime() + 15 * 60000)) {
      var o = document.createElement('option');
      o.value = t.toISOString();
      o.textContent = fmtDay(t) + ' ' + t.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
      sel.appendChild(o);
    }
  }
  function openCart() {
    if (!cart.length) return;
    renderCart(); fillPickupSlots(); errEl.textContent = '';
    cartDialog.hidden = false;
    form.elements.name.focus();
  }
  document.getElementById('viewOrder').addEventListener('click', openCart);
  document.getElementById('cartClose').addEventListener('click', function () { cartDialog.hidden = true; });
  document.addEventListener('keydown', function (e) { if (e.key === 'Escape') { itemDialog.hidden = true; cartDialog.hidden = true; } });

  form.addEventListener('submit', function (e) {
    e.preventDefault();
    errEl.textContent = '';
    var btn = document.getElementById('placeBtn');
    var body = {
      guest: { name: form.elements.name.value, phone: form.elements.phone.value, email: form.elements.email.value },
      items: cart.map(function (l) { return { itemId: l.itemId, qty: l.qty, note: l.note || undefined }; }),
      note: form.elements.note.value,
      pickup: form.elements.pickup.value,
      website: form.elements.website.value
    };
    if (!body.guest.name.trim()) { errEl.textContent = 'Tell the store who the order is for.'; return; }
    if (!body.guest.phone.trim()) { errEl.textContent = 'Add a phone number the store can call.'; return; }
    btn.disabled = true; btn.textContent = 'Sending…';
    fetch(apiBase + '/orders', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) })
      .then(function (r) { return r.json().then(function (j) { return { ok: r.ok, status: r.status, body: j }; }); })
      .then(function (res) {
        if (!res.ok || !res.body.success) {
          if (res.body.code === 'menu_changed') { errEl.textContent = 'The menu just changed. Reloading it…'; setTimeout(function () { location.reload(); }, 1200); return; }
          errEl.textContent = res.body.message || res.body.error || 'That didn’t go through. Try again.';
          return;
        }
        var d = res.body.data;
        try { localStorage.setItem('fc_order_' + d.order.orderId, d.token); localStorage.removeItem(cartKey); } catch (err) { /* ignore */ }
        location.href = base + '/o/' + encodeURIComponent(d.order.orderId) + '?t=' + encodeURIComponent(d.token);
      })
      .catch(function () { errEl.textContent = 'No connection. Check your signal and try again.'; })
      .then(function () { btn.disabled = false; btn.textContent = 'Place order'; });
  });

  // ---- category chips follow the scroll
  var chips = document.querySelectorAll('.chip');
  if (chips.length && 'IntersectionObserver' in window) {
    var byId = {};
    chips.forEach(function (c) { byId[c.getAttribute('href').slice(1)] = c; });
    var obs = new IntersectionObserver(function (entries) {
      entries.forEach(function (en) {
        if (!en.isIntersecting) return;
        chips.forEach(function (c) { c.classList.remove('on'); });
        var c = byId[en.target.id]; if (c) { c.classList.add('on'); c.scrollIntoView({ block: 'nearest', inline: 'center', behavior: 'smooth' }); }
      });
    }, { rootMargin: '-64px 0px -70% 0px' });
    document.querySelectorAll('section.menu').forEach(function (s) { obs.observe(s); });
  }

  renderBar();
})();
