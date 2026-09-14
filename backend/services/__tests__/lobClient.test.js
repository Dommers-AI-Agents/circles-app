// The wire format Lob actually receives. `from: null` and an absent `from`
// are not the same request, and we rely on the latter: printed postcards go
// out with no return address.
const originalFetch = global.fetch;

describe('createPostcard body', () => {
  let sentBody;

  beforeEach(() => {
    process.env.LOB_API_KEY = 'test_key';
    sentBody = null;
    global.fetch = jest.fn(async (url, options) => {
      sentBody = JSON.parse(options.body);
      return {
        ok: true,
        status: 200,
        text: async () => JSON.stringify({ id: 'psc_1', expected_delivery_date: '2026-09-20', url: 'https://lob.test/p.pdf' })
      };
    });
  });

  afterAll(() => { global.fetch = originalFetch; });

  const lobClient = require('../lobClient');

  const args = {
    idempotencyKey: 'order-1',
    description: 'test',
    to: { name: 'Ana', address_line1: '1 Main', address_city: 'Austin', address_state: 'TX', address_zip: '78701', address_country: 'US' },
    frontUrl: 'https://example.test/front.jpg',
    backHtml: '<html></html>'
  };

  it('omits `from` entirely when there is no return address', async () => {
    await lobClient.createPostcard(args);
    expect(Object.prototype.hasOwnProperty.call(sentBody, 'from')).toBe(false);
  });

  it('omits `from` rather than sending null when one is passed explicitly', async () => {
    await lobClient.createPostcard({ ...args, from: null });
    expect(Object.prototype.hasOwnProperty.call(sentBody, 'from')).toBe(false);
  });

  it('includes `from` when there is a return address', async () => {
    await lobClient.createPostcard({ ...args, from: { name: 'FavCircles', address_city: 'Charlotte' } });
    expect(sentBody.from).toMatchObject({ name: 'FavCircles' });
  });

  it('sends the order id as the idempotency key so a retry cannot double-mail', async () => {
    await lobClient.createPostcard(args);
    expect(global.fetch.mock.calls[0][1].headers['Idempotency-Key']).toBe('order-1');
  });
});
