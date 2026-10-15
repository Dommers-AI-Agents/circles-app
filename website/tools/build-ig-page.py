#!/usr/bin/env python3
"""Builds favcircles.com/ig/index.html — the Instagram link-in-bio page
(Wes, 2026-10-15): one email box to stay in touch, the App Store button,
and every widget from widgets/widgets.json. Re-run after widgets.json
changes, then upload ig/index.html over SFTP."""
import html, json, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
data = json.load(open(os.path.join(ROOT, 'widgets/widgets.json')))
widgets = [w for g in data['groups'] for w in g['widgets']]
APP_STORE = 'https://apps.apple.com/us/app/favcircles/id6746807095'

chips = '\n'.join(
    f'      <a class="chip" href="/widgets.html#{html.escape(w["id"])}"><span>{w["emoji"]}</span><b>{html.escape(w["name"])}</b><i>{html.escape(w["tagline"])}</i></a>'
    for w in widgets)

page = f'''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>FavCircles — from Instagram</title>
<meta name="description" content="Your friends' favorite places, plus {len(widgets)} mini-apps. Stay in touch and get FavCircles free on the App Store.">
<meta name="apple-itunes-app" content="app-id=6746807095">
<meta property="og:title" content="FavCircles">
<meta property="og:description" content="Your friends' favorite places, plus {len(widgets)} mini-apps.">
<meta property="og:image" content="https://favcircles.com/app-icon.png">
<link rel="icon" href="/favicon.ico">
<style>
  :root {{ --bg: #f6f5ff; --card: #ffffff; --ink: #1a1a2e; --muted: #5b5b72; --line: #e3e1f5; --brand: #5a4bd1; --brand2: #0E2A47; --ok: #2f855a; --bad: #c53030; }}
  @media (prefers-color-scheme: dark) {{
    :root:not([data-theme="light"]) {{ --bg: #0f1020; --card: #1a1b2e; --ink: #f2f1ff; --muted: #a7a6c2; --line: #2c2d46; --brand: #8f84ff; --ok: #68d391; --bad: #fc8181; }}
  }}
  :root[data-theme="dark"] {{ --bg: #0f1020; --card: #1a1b2e; --ink: #f2f1ff; --muted: #a7a6c2; --line: #2c2d46; --brand: #8f84ff; --ok: #68d391; --bad: #fc8181; }}
  * {{ box-sizing: border-box; margin: 0; padding: 0; }}
  body {{ background: var(--bg); color: var(--ink); font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; line-height: 1.45; }}
  main {{ max-width: 560px; margin: 0 auto; padding: 32px 16px 56px; }}
  .hero {{ text-align: center; }}
  .hero img {{ width: 88px; height: 88px; border-radius: 22px; box-shadow: 0 8px 24px rgba(0,0,0,.15); }}
  .wave {{ margin-top: 18px; color: var(--muted); font-weight: 600; }}
  h1 {{ margin-top: 6px; font-size: 30px; line-height: 1.15; letter-spacing: -.5px; }}
  .lead {{ margin-top: 10px; color: var(--muted); font-size: 17px; }}
  .box {{ margin-top: 26px; background: var(--card); border: 1px solid var(--line); border-radius: 18px; padding: 22px 18px; }}
  .box h2 {{ font-size: 20px; }}
  .box p {{ margin-top: 6px; color: var(--muted); font-size: 15px; }}
  form {{ margin-top: 14px; display: flex; flex-direction: column; gap: 10px; }}
  input[type=email] {{ width: 100%; padding: 14px 16px; font-size: 17px; border-radius: 12px; border: 2px solid var(--line); background: var(--bg); color: var(--ink); }}
  input[type=email]:focus {{ outline: none; border-color: var(--brand); }}
  button, .store {{ display: block; width: 100%; padding: 14px 16px; border: 0; border-radius: 12px; font-size: 17px; font-weight: 700; text-align: center; text-decoration: none; cursor: pointer; }}
  button {{ background: var(--brand); color: #fff; }}
  button:disabled {{ opacity: .6; }}
  .status {{ min-height: 1.2em; font-size: 15px; margin-top: 2px; }}
  .status.ok {{ color: var(--ok); }} .status.bad {{ color: var(--bad); }}
  .fine {{ margin-top: 10px; font-size: 12px; color: var(--muted); }}
  .store {{ margin-top: 14px; background: var(--brand2); color: #fff; }}
  :root[data-theme="dark"] .store {{ background: #f2f1ff; color: #0f1020; }}
  @media (prefers-color-scheme: dark) {{ :root:not([data-theme="light"]) .store {{ background: #f2f1ff; color: #0f1020; }} }}
  h3 {{ margin-top: 34px; font-size: 18px; }}
  .chips {{ margin-top: 12px; display: grid; grid-template-columns: 1fr; gap: 8px; }}
  .chip {{ display: grid; grid-template-columns: 34px 1fr; column-gap: 10px; align-items: center; padding: 12px 14px; border-radius: 14px; background: var(--card); border: 1px solid var(--line); color: var(--ink); text-decoration: none; }}
  .chip span {{ grid-row: span 2; font-size: 26px; text-align: center; }}
  .chip b {{ font-size: 16px; }}
  .chip i {{ font-style: normal; font-size: 14px; color: var(--muted); }}
  .all {{ display: block; margin-top: 14px; text-align: center; color: var(--brand); font-weight: 600; text-decoration: none; }}
</style>
</head>
<body>
<main>
  <section class="hero">
    <img src="/app-icon.png" alt="FavCircles app icon">
    <p class="wave">Hi from Instagram 👋</p>
    <h1>Your friends' favorite places, plus {len(widgets)} mini-apps</h1>
    <p class="lead">Save the places you love, see where the people you trust actually go, and keep the little apps you use every day in one place.</p>
  </section>

  <section class="box" aria-labelledby="stay">
    <h2 id="stay">Stay in touch 📬</h2>
    <p>Get the 2-minute guide now, and a short note when we add new widgets. No spam.</p>
    <form id="ig-form" novalidate>
      <input type="email" id="ig-email" placeholder="you@email.com" autocomplete="email" required aria-label="Your email">
      <button type="submit" id="ig-btn">Keep me posted</button>
      <div class="status" id="ig-status" role="status" aria-live="polite"></div>
    </form>
    <p class="fine">We'll only email you about FavCircles. Reply to any email and we'll stop.</p>
    <a class="store" href="{APP_STORE}">Get FavCircles free on the App Store</a>
  </section>

  <h3>What's inside</h3>
  <div class="chips">
{chips}
  </div>
  <a class="all" href="/widgets.html">See every widget and what it does →</a>
</main>
<script>
  (function () {{
    var form = document.getElementById('ig-form');
    var input = document.getElementById('ig-email');
    var btn = document.getElementById('ig-btn');
    var status = document.getElementById('ig-status');
    form.addEventListener('submit', function (e) {{
      e.preventDefault();
      var email = (input.value || '').trim();
      if (!/^[^\\s@]+@[^\\s@]+\\.[^\\s@]{{2,}}$/.test(email)) {{
        status.textContent = 'Please enter a valid email address.';
        status.className = 'status bad';
        return;
      }}
      btn.disabled = true;
      btn.textContent = 'Sending…';
      status.textContent = '';
      status.className = 'status';
      fetch('https://api.favcircles.com/api/leads/website', {{
        method: 'POST',
        headers: {{ 'Content-Type': 'application/json' }},
        body: JSON.stringify({{ email: email, source: 'instagram' }})
      }}).then(function (r) {{ return r.json(); }}).then(function (data) {{
        if (data.success) {{
          status.textContent = "📬 You're in. Check your inbox for the guide.";
          status.className = 'status ok';
          input.style.display = 'none';
          btn.style.display = 'none';
        }} else {{
          status.textContent = data.message || 'Something went wrong. Please try again.';
          status.className = 'status bad';
        }}
      }}).catch(function () {{
        status.textContent = 'Something went wrong. Please try again.';
        status.className = 'status bad';
      }}).finally(function () {{
        btn.disabled = false;
        btn.textContent = 'Keep me posted';
      }});
    }});
  }})();
</script>
</body>
</html>
'''
out = os.path.join(ROOT, 'favcircles.com/ig/index.html')
os.makedirs(os.path.dirname(out), exist_ok=True)
open(out, 'w').write(page)
print('wrote', os.path.relpath(out, ROOT), '-', len(widgets), 'widgets')
