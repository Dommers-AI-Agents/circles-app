const { renderNotFound, renderPostcard } = require('../postcardPage');

test('not-found page links back to the site', () => {
  const html = renderNotFound();
  expect(html).toContain('<title>Postcard not found</title>');
  expect(html).toContain('https://favcircles.com');
});

test('postcard page escapes what the sender typed and carries the share metadata', () => {
  const html = renderPostcard({
    token: 'tok1', senderName: 'Wes <b>', placeName: 'Watson\'s Tires', placeCity: 'Belmar',
    message: 'Hi "Mom"', imageUrl: 'https://x/img.jpg', createdAt: '2026-09-18T12:00:00Z'
  });
  expect(html).toContain('<title>A postcard from Watson&#39;s Tires, Belmar</title>');
  expect(html).toContain('Wes &lt;b&gt;');
  expect(html).toContain('Hi &quot;Mom&quot;');
  expect(html).toContain('<meta property="og:image" content="https://x/img.jpg">');
  expect(html).toContain('/postcard/tok1/download');
  expect(html).not.toContain('<b>');
});
