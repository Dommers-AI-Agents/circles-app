// A store's web page for phones with no app (views/storePage.js): escaped,
// CSP-clean, and it only talks about points where the store's rewards are live.
const { renderStorePage } = require('../storePage');

const P = {
  code: 'WIN123', tag: null, kind: 'window', venueId: 'v1', globalPlaceId: 'gp1',
  name: 'Sal\'s <b>Bakery</b>', address: '1 Elm St, Charlotte, NC', coverUrl: 'https://img/cover.jpg?a=1&b=2',
  loyaltyLive: true, scanPoints: 25, earnRate: 10,
  offers: [{ offerId: 'o1', title: 'Free coffee </script><script>alert(1)</script>', pointsCost: 50 }],
  coupon: null
};

test('escapes the store and carries no inline code', () => {
  const html = renderStorePage(P);
  expect(html).toContain('Sal&#39;s &lt;b&gt;Bakery&lt;/b&gt;');
  expect(html).not.toContain('<b>Bakery</b>');
  const scripts = html.match(/<script[^>]*>/g);
  expect(scripts.every((s) => /type="application\/json"|src="\/public\//.test(s))).toBe(true);
  expect(html).not.toMatch(/ on\w+="/);
  expect(html).toContain('<script src="/public/store-page.js" defer>');
  const data = html.match(/<script type="application\/json" id="store-data">([\s\S]*?)<\/script>/)[1];
  expect(data).not.toContain('<');
  expect(JSON.parse(data)).toMatchObject({ code: 'WIN123', kind: 'window', venueId: 'v1', globalPlaceId: 'gp1', loyaltyLive: true });
  expect(html).toContain('<meta name="robots" content="noindex">');
});

test('a live window code promises the save bonus and names the first reward', () => {
  const html = renderStorePage(P);
  expect(html).toContain('Save us. Get 25 points.');
  expect(html).toContain('(50 points)');
  expect(html).toContain("background-image:url('https://img/cover.jpg?a=1&amp;b=2'),linear-gradient(");
  expect(html).toContain('specials and events');
});

test('a store whose rewards are not live is saved with no word about points', () => {
  const html = renderStorePage({ ...P, loyaltyLive: false, scanPoints: 0, earnRate: null, offers: [] });
  expect(html).toContain('<span class="g">Save us.</span>');
  expect(html.replace(/<style>[\s\S]*?<\/style>/, '')).not.toMatch(/\d+ points/);
});

test('a register code is about the visit; a coupon on the link is named', () => {
  const register = renderStorePage({ ...P, kind: 'register', scanPoints: 10 });
  expect(register).toContain('Get your 10 points.');
  const coupon = renderStorePage({ ...P, coupon: { couponId: 'ABCDEF', title: '20% off <any> order' } });
  expect(coupon).toContain('Your coupon: 20% off &lt;any&gt; order');
  expect(JSON.parse(coupon.match(/id="store-data">([\s\S]*?)<\/script>/)[1]).couponId).toBe('ABCDEF');
});

test('with no photo the backdrop is the brand wash, never a flat page', () => {
  const html = renderStorePage({ ...P, coverUrl: null });
  expect(html).toContain('<div class="back"></div>');
  expect(html).toContain('.back{position:fixed;inset:0;z-index:-2;background:linear-gradient(');
});

test("the photo's address is kept as stored and cannot break out of the style", () => {
  const { cssUrl } = require('../storePage');
  // A storage path's %2F stays %2F (encoding it again breaks the photo)
  expect(cssUrl('https://storage/o/circles%2Fa.jpg?alt=media&token=t')).toBe('https://storage/o/circles%2Fa.jpg?alt=media&token=t');
  expect(cssUrl("https://x/a b').jpg")).toBe('https://x/a%20b%27%29.jpg');
  expect(cssUrl('javascript:alert(1)')).toBeNull();
  expect(cssUrl('http://x/a.jpg')).toBeNull();
  expect(cssUrl(null)).toBeNull();
});
