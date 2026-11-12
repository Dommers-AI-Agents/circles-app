const tracking = require('../emailTracking');

describe('emailTracking', () => {
  const env = { ...process.env };
  beforeEach(() => { process.env.JWT_SECRET = 'test-secret'; process.env.APP_LINK_BASE = 'https://api.favcircles.com'; });
  afterAll(() => { process.env = env; });

  const html = `<html><body>
    <a href="https://api.favcircles.com/app/open?path=add-place&amp;x=1">Add Your First Place</a>
    <a href='https://favcircles.com'>site</a>
    <a href="mailto:hello@favcircles.com">mail</a>
    <a href="#top">top</a>
    <a href="https://api.favcircles.com/api/email/unsubscribe?uid=u&kind=k&sig=s">unsubscribe</a>
    <img src="https://cdn.example.com/photo.jpg">
  </body></html>`;

  test('rewrites http links to signed redirects, skips mailto/anchor/unsubscribe/src, appends the pixel', () => {
    const out = tracking.instrumentHtml(html, { sendId: 'abc', to: 'john@example.com', kind: 'welcome' });
    expect(out.links).toBe(2);
    expect(out.html).toContain('href="https://api.favcircles.com/e/c?i=abc&amp;t=');
    expect(out.html).toContain("href='https://api.favcircles.com/e/c?i=abc&amp;t=");
    expect(out.html).toContain('href="mailto:hello@favcircles.com"');
    expect(out.html).toContain('href="#top"');
    expect(out.html).toContain('href="https://api.favcircles.com/api/email/unsubscribe?uid=u&kind=k&sig=s"');
    expect(out.html).toContain('<img src="https://cdn.example.com/photo.jpg">');
    expect(out.html).toMatch(/<img src="https:\/\/api\.favcircles\.com\/e\/o\?i=abc&amp;t=[^"]+" width="1" height="1"[^>]*><\/body>/);
  });

  test('the click link round-trips through readParams with the original url, &amp; decoded', () => {
    const out = tracking.instrumentHtml(html, { sendId: 'abc', to: 'john@example.com', kind: 'welcome' });
    const href = out.html.match(/href="(https:\/\/api\.favcircles\.com\/e\/c\?[^"]+)"/)[1].replace(/&amp;/g, '&');
    const query = Object.fromEntries(new URL(href).searchParams.entries());
    const params = tracking.readParams(query);
    expect(params).toEqual(expect.objectContaining({ sendId: 'abc', to: 'john@example.com', kind: 'welcome', url: 'https://api.favcircles.com/app/open?path=add-place&x=1' }));
  });

  test('a tampered destination or signature is refused (no open redirect)', () => {
    const good = new URL(tracking.clickUrl({ sendId: 'abc', to: 'a@b.c', kind: 'k', url: 'https://favcircles.com/x' }));
    const q = Object.fromEntries(good.searchParams.entries());
    expect(tracking.readParams(q)).not.toBeNull();
    expect(tracking.readParams({ ...q, u: Buffer.from('https://evil.example').toString('base64url') })).toBeNull();
    expect(tracking.readParams({ ...q, s: 'x'.repeat(32) })).toBeNull();
    expect(tracking.readParams({ ...q, u: Buffer.from('javascript:alert(1)').toString('base64url'), s: tracking.sign({ sendId: 'abc', to: 'a@b.c', kind: 'k', url: 'javascript:alert(1)' }) })).toBeNull();
  });

  test('the pixel verifies with an empty url', () => {
    const q = Object.fromEntries(new URL(tracking.pixelUrl({ sendId: 'p1', to: 'a@b.c', kind: 'welcome' })).searchParams.entries());
    expect(tracking.readParams(q)).toEqual(expect.objectContaining({ sendId: 'p1', url: '' }));
  });

  test('instrumentMail names the email from its subject, strips `kind`, and leaves multi-recipient or text-only mail alone', () => {
    const one = tracking.instrumentMail({ to: 'A@B.c', subject: 'Welcome to FavCircles — start your map 🗺️', html: '<a href="https://favcircles.com">x</a>' });
    expect(one.kind).toBe('welcome_to_favcircles_start_your_map');
    expect(one.links).toBe(1);
    expect(one.mailOptions.html).toContain('/e/c?');
    expect(one.mailOptions.kind).toBeUndefined();
    const named = tracking.instrumentMail({ to: 'a@b.c', subject: 'x', html: '<p>hi</p>', kind: 'welcome' });
    expect(named.kind).toBe('welcome');
    expect(named.mailOptions.kind).toBeUndefined();
    expect(tracking.instrumentMail({ to: 'a@b.c, d@e.f', subject: 'x', html: '<a href="https://x.y">x</a>' }).sendId).toBeNull();
    expect(tracking.instrumentMail({ to: 'a@b.c', subject: 'x', text: 'plain' }).sendId).toBeNull();
  });

  test('without a secret nothing verifies', () => {
    delete process.env.JWT_SECRET; delete process.env.UNSUBSCRIBE_SECRET;
    const q = Object.fromEntries(new URL(tracking.pixelUrl({ sendId: 'p1', to: 'a@b.c', kind: 'k' })).searchParams.entries());
    expect(tracking.readParams(q)).toBeNull();
  });
});
