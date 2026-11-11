// public/postcard-page.js — the public postcard page's lightbox (tap the card
// to see it full size, Save, Close). A file, not inline: the site's CSP only
// runs our own scripts, and the inline version never ran (found 2026-11-11).
(function () {
  var lb = document.getElementById('lightbox');
  var card = document.getElementById('card');
  if (!lb || !card) return;
  var open = function () { lb.classList.add('open'); document.body.style.overflow = 'hidden'; };
  var close = function () { lb.classList.remove('open'); document.body.style.overflow = ''; };
  card.addEventListener('click', open);
  var closeButton = document.getElementById('lb-close');
  if (closeButton) closeButton.addEventListener('click', close);
  lb.addEventListener('click', function (e) { if (e.target === lb) close(); });
  document.addEventListener('keydown', function (e) { if (e.key === 'Escape') close(); });
  var hint = document.getElementById('lb-hint');
  if (hint && !/iPhone|iPad/.test(navigator.userAgent)) hint.textContent = 'Save downloads the full-size postcard.';
})();
