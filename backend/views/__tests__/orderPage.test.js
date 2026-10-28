// The public ordering page (views/orderPage.js): escaped, shareable, CSP-clean.
const pages = require('../orderPage');

const P = {
  slug: 'test-bakery', name: 'Test <b>Bakery</b>', address: '1 Elm St, Charlotte, NC 28202', phone: '(704) 555-0199', website: null,
  coverPhotoUrl: 'https://img/cover.jpg', hours: [{ day: 0, label: 'Sun', text: 'Closed' }], category: 'cafe', offeringsLabel: 'Menu',
  ordering: { enabled: true, leadMinutes: 15, note: null },
  menu: { sections: [{ id: 's1', name: 'Pastries', items: [{ id: 'c', name: 'Croissant </script><script>alert(1)</script>', price: '4', description: 'Butter', tags: ['vegetarian'] }] }, { id: 's2', name: 'Drinks', items: [{ id: 'd', name: 'Coffee', price: '3', tags: [] }] }] },
  globalPlaceId: 'gp1', isTestStore: false
};

test('the page escapes the store and its items, and never carries inline code', () => {
  const html = pages.renderOrderPage(P, { base: '', canonicalUrl: 'https://order.favcircles.com/test-bakery' });
  expect(html).toContain('Test &lt;b&gt;Bakery&lt;/b&gt;');
  expect(html).not.toContain('<b>Bakery</b>');
  expect(html).toContain('<meta property="og:image" content="https://img/cover.jpg">');
  expect(html).toContain('<link rel="canonical" href="https://order.favcircles.com/test-bakery">');
  expect(html).not.toContain('noindex');
  expect(html).toContain('/public/order-page.js');
  // The only script blocks are the data block and the external file
  const scripts = html.match(/<script[^>]*>/g);
  expect(scripts.every((s) => /type="application\/json"|src="\/public\//.test(s))).toBe(true);
  expect(html).not.toMatch(/ on\w+="/);
  // The data block can't be broken out of by an item name
  const data = html.match(/<script type="application\/json" id="menu-data">([\s\S]*?)<\/script>/)[1];
  expect(data).not.toContain('<');
  expect(JSON.parse(data).sections[0].items[0].name).toContain('</script>');
  expect(html).toContain('https://api.favcircles.com/place/gp1');
  expect(html).toContain('Place order');
  expect(html).toContain('class="chip on" href="#s-s1"');
});

test('ordering off keeps the menu and drops the cart; a test store is noindex', () => {
  const html = pages.renderOrderPage({ ...P, ordering: null, isTestStore: true }, { base: '/order', canonicalUrl: 'x', noindex: true });
  expect(html).toContain("Online ordering isn't on here right now");
  expect(html).not.toContain('Place order');
  expect(html).not.toContain('order-page.js');
  expect(html).toContain('<meta name="robots" content="noindex">');
  expect(html).toContain('Croissant');
});

test('bare numbers get a dollar sign; typed prices stay as typed', () => {
  expect(pages.priceText('9')).toBe('$9');
  expect(pages.priceText('4.50')).toBe('$4.50');
  expect(pages.priceText('$12')).toBe('$12');
  expect(pages.priceText('MP')).toBe('MP');
  expect(pages.priceText('8 / 14')).toBe('8 / 14');
  expect(pages.priceText(null)).toBe('');
  const html = pages.renderOrderPage({ ...P, menu: { sections: [{ id: 's', name: 'S', items: [{ id: 'a', name: 'Loaf', price: '9', tags: [] }] }] } }, { base: '', canonicalUrl: 'x' });
  expect(html).toContain('<span class="p">$9</span>');
});

test('the status shell and the not-found page', () => {
  const status = pages.renderOrderStatusPage({ base: '', orderId: 'abc123' });
  expect(status).toContain('/public/order-status.js');
  expect(status).toContain('"orderId":"abc123"');
  expect(status).toContain('noindex');
  const nf = pages.renderNotFound({ base: '/order' });
  expect(nf).toContain('Not taking online orders yet');
});
