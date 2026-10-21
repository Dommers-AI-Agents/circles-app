// Store-owner scans (2026-10-20): menu photos → a full menu draft (Claude),
// hours sign and flyer → drafts (Clairic). Drafts only; nothing is saved by
// a scan. Model replies here are recorded shapes, not live calls.
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({ getFirestore: () => mockDb }));

const sharp = require('sharp');
const storefront = require('../venueStorefront');
const menuReader = require('../scan/menuReader');
const hoursReader = require('../scan/hoursReader');
const flyerReader = require('../scan/flyerReader');
const clairic = require('../scan/clairic');
const images = require('../scan/images');
const scanService = require('../scan');

const pngBase64 = async (w = 3000, h = 1500) =>
  (await sharp({ create: { width: w, height: h, channels: 3, background: '#ffffff' } }).png().toBuffer()).toString('base64');

describe('the full menu', () => {
  test('keeps sections and items, drops empty ones, applies the caps', () => {
    const { value, errors } = storefront.normalizeMenu({
      source: 'scan',
      sections: [
        { name: 'Starters', items: [{ name: 'Garlic knots', price: '$6', description: 'With marinara', tags: ['vegetarian'] }, { name: '  ' }] },
        { name: 'Empty', items: [] },
        { name: '', items: [{ name: 'Water' }] }
      ]
    });
    expect(errors).toEqual([]);
    expect(value.source).toBe('scan');
    expect(value.sections.map((s) => s.name)).toEqual(['Starters', 'Menu']);
    expect(value.sections[0].items).toHaveLength(1);
    expect(value.sections[0].items[0]).toMatchObject({ name: 'Garlic knots', price: '$6', description: 'With marinara', tags: ['vegetarian'] });
    expect(value.sections[0].items[0].id).toBeTruthy();
  });

  test('too many items or sections is an error the editor can show', () => {
    const many = Array.from({ length: 401 }, (_, i) => ({ name: `Item ${i}` }));
    expect(storefront.normalizeMenu({ sections: [{ name: 'All', items: many }] }).errors.join()).toMatch(/400 items/);
    const sections = Array.from({ length: 31 }, (_, i) => ({ name: `S${i}`, items: [{ name: 'x' }] }));
    expect(storefront.normalizeMenu({ sections }).errors.join()).toMatch(/30 sections/);
  });

  test('customers see the menu only while the venue is on Business', () => {
    const venue = { category: 'restaurant', storefront: { menu: { sections: [{ id: 's', name: 'Pizza', items: [{ id: 'i', name: 'Margherita', price: '14' }] }] } } };
    expect(storefront.publicStorefront(venue, { live: true }).menu.sections[0].items[0].name).toBe('Margherita');
    expect(storefront.publicStorefront(venue, { live: false })).toBeNull();
    expect(storefront.ownerStorefront({ category: 'cafe' }).menu.sections).toEqual([]);
  });
});

describe('menu reader', () => {
  test('the model’s menu becomes a clean draft with unsure items kept and flagged', () => {
    const draft = menuReader.toDraft({
      sections: [
        { name: 'Pizza', items: [
          { name: 'Margherita', price: '14', description: 'Tomato, mozzarella, basil', tags: ['vegetarian'] },
          { name: 'Pepper  oni', price: '$16.50', unsure: true },
          { name: '' }
        ] },
        { name: 'Drinks', items: [] }
      ],
      notes: 'Page 2 was cut off at the bottom.'
    });
    expect(draft.itemCount).toBe(2);
    expect(draft.sections).toHaveLength(1);
    expect(draft.sections[0].items[1]).toMatchObject({ name: 'Pepper oni', price: '$16.50', unsure: true });
    expect(draft.notes).toMatch(/cut off/);
  });

  test('not a menu: no sections, the note explains', () => {
    const draft = menuReader.toDraft({ sections: [], notes: 'This is a photo of a dog.' });
    expect(draft.sections).toEqual([]);
    expect(draft.notes).toMatch(/dog/);
  });
});

describe('hours reader', () => {
  const ans = (value, confidence = 0.95) => ({ type: 'time', value, confidence, p_null: value === null ? 0.9 : 0.02 });

  test('times per day, a closed day, and a day the sign doesn’t mention', () => {
    const answers = {};
    for (const d of hoursReader.DAYS) {
      answers[`${d}_open`] = ans('07:00:00'); answers[`${d}_close`] = ans('15:00:00'); answers[`${d}_closed`] = { value: null };
    }
    answers.sun_open = ans(null); answers.sun_close = ans(null); answers.sun_closed = { type: 'text', value: 'Closed Sundays', confidence: 0.9 };
    answers.sat_open = ans('08:00', 0.5);
    answers.wed_open = ans(null); answers.wed_close = ans(null);
    const { hours, found } = hoursReader.toDraft(answers);
    expect(hours[0]).toMatchObject({ day: 0, isClosed: true, open: null });
    expect(hours[1]).toMatchObject({ day: 1, open: '07:00', close: '15:00', isClosed: false, unsure: false });
    expect(hours[6]).toMatchObject({ day: 6, open: '08:00', unsure: true });
    expect(hours[3]).toMatchObject({ day: 3, open: null, close: null, isClosed: false });
    expect(found).toBe(6);
  });

  test('bad times are dropped rather than saved', () => {
    expect(hoursReader.hhmm('25:00')).toBeNull();
    expect(hoursReader.hhmm('7:05')).toBe('07:05');
  });
});

describe('flyer reader', () => {
  test('an event: title, message, date and times', () => {
    const d = flyerReader.toDraft({
      title: { value: 'Trivia Night', confidence: 0.95 },
      details: { value: 'Teams of up to 6. Prizes for the top 3!', confidence: 0.9 },
      event_date: { value: '2026-10-30', confidence: 0.6 },
      start_time: { value: '19:00:00', confidence: 0.9 },
      end_time: { value: null },
      is_free: { value: 'Free entry', confidence: 0.9 },
      ends_on: { value: null }
    });
    expect(d).toMatchObject({ title: 'Trivia Night', event: { localDate: '2026-10-30', localTime: '19:00', endTime: null, isFree: true }, expiresOn: null });
    expect(d.unsure).toEqual(['event_date']);
  });

  test('a special that runs until a date, long text clipped to the form’s limits', () => {
    const d = flyerReader.toDraft({
      title: { value: 'Happy hour '.repeat(12), confidence: 0.9 },
      details: { value: 'Half price apps 3–6pm weekdays', confidence: 0.9 },
      event_date: { value: null }, start_time: { value: null }, end_time: { value: null }, is_free: { value: null },
      ends_on: { value: '2026-11-30', confidence: 0.9 }
    });
    expect(d.title.length).toBeLessThanOrEqual(80);
    expect(d.event).toBeNull();
    expect(d.expiresOn).toBe('2026-11-30');
  });

  test('Claude\u2019s wording replaces Clairic\u2019s mangled text; the dates and times stay Clairic\u2019s', () => {
    const clairicDraft = flyerReader.toDraft({
      title: { value: 'HAPP HOUR', confidence: 0.56 }, details: { value: 'Half-price lattes & &ries', confidence: 0.61 },
      event_date: { value: '2026-10-23', confidence: 0.99 }, start_time: { value: '15:00:00', confidence: 0.99 },
      end_time: { value: '18:00:00', confidence: 0.99 }, is_free: { value: null }, ends_on: { value: null }
    });
    expect(clairicDraft.unsure).toEqual(['title', 'details']);
    const d = flyerReader.mergeWording(clairicDraft, { title: 'HAPPY HOUR', details: 'Half-price lattes & pastries every Friday' });
    expect(d).toMatchObject({ title: 'HAPPY HOUR', message: 'Half-price lattes & pastries every Friday', event: { localDate: '2026-10-23', localTime: '15:00', endTime: '18:00' }, unsure: [] });
    // Claude unavailable: Clairic's draft as it was, flags kept
    expect(flyerReader.mergeWording(clairicDraft, null)).toBe(clairicDraft);
    // Clairic unavailable: the wording alone, no event
    expect(flyerReader.mergeWording(null, { title: 'Trivia', details: 'Tuesdays' })).toMatchObject({ title: 'Trivia', message: 'Tuesdays', event: null, unsure: [] });
  });
});

describe('images', () => {
  test('downscaled to 2,000 px on the long edge as JPEG', async () => {
    const [img] = await images.prepare([await pngBase64()]);
    const meta = await sharp(Buffer.from(img.base64, 'base64')).metadata();
    expect(img.mediaType).toBe('image/jpeg');
    expect(Math.max(meta.width, meta.height)).toBe(2000);
  });

  test('refuses no photos, too many, or something that isn’t an image', async () => {
    await expect(images.prepare([])).rejects.toMatchObject({ code: 'no_images' });
    const one = await pngBase64(10, 10);
    await expect(images.prepare([one, one, one, one, one])).rejects.toMatchObject({ code: 'too_many_images' });
    await expect(images.prepare([Buffer.from('not an image').toString('base64')])).rejects.toMatchObject({ code: 'bad_image' });
  });
});

describe('the scan service', () => {
  const venue = { venueId: 'v1', timeZone: 'America/New_York' };
  beforeEach(() => { mockDb.rows('dailyBudgets').clear(); mockDb.rows('scanUsage').clear(); });

  test('an unknown kind is refused before any model is called', async () => {
    await expect(scanService.scan({ kind: 'receipt', images: [], venue, userId: 'u', db: mockDb })).rejects.toMatchObject({ code: 'bad_kind' });
  });

  test('without Cloudflare set up, hours and flyer scans say so (the editor still works by hand)', async () => {
    const saved = { a: process.env.CLOUDFLARE_ACCOUNT_ID, t: process.env.CLOUDFLARE_AI_TOKEN };
    delete process.env.CLOUDFLARE_ACCOUNT_ID; delete process.env.CLOUDFLARE_AI_TOKEN;
    await expect(scanService.scan({ kind: 'hours', images: [await pngBase64(50, 50)], venue, userId: 'u', db: mockDb }))
      .rejects.toMatchObject({ status: 503, code: 'scan_unavailable' });
    // A flyer with neither Cloudflare nor Claude set up says so too
    const key = process.env.ANTHROPIC_API_KEY; delete process.env.ANTHROPIC_API_KEY;
    await expect(scanService.scan({ kind: 'flyer', images: [await pngBase64(50, 50)], venue, userId: 'u', db: mockDb }))
      .rejects.toMatchObject({ status: 503, code: 'scan_unavailable' });
    if (key) process.env.ANTHROPIC_API_KEY = key;
    Object.assign(process.env, saved.a ? { CLOUDFLARE_ACCOUNT_ID: saved.a } : {}, saved.t ? { CLOUDFLARE_AI_TOKEN: saved.t } : {});
  });

  test('20 scans a day per venue, then a clear refusal', async () => {
    const spy = jest.spyOn(hoursReader, 'read').mockResolvedValue({ draft: { hours: [], found: 0 }, usage: { engine: 'clairic', inputTokens: 900 } });
    const img = await pngBase64(50, 50);
    for (let i = 0; i < 20; i += 1) await scanService.scan({ kind: 'hours', images: [img], venue, userId: 'u', db: mockDb });
    await expect(scanService.scan({ kind: 'hours', images: [img], venue, userId: 'u', db: mockDb })).rejects.toMatchObject({ status: 429, code: 'scan_limit' });
    await new Promise((r) => setImmediate(r));
    expect([...mockDb.rows('scanUsage').values()][0]).toMatchObject({ venueId: 'v1', kind: 'hours', engine: 'clairic', inputTokens: 900 });
    spy.mockRestore();
  });

  test('clairic.read keeps a confident value, flags an unsure one, leaves a missing one empty', () => {
    expect(clairic.read({ value: '07:00', confidence: 0.9 })).toEqual({ value: '07:00', unsure: false });
    expect(clairic.read({ value: '07:00', confidence: 0.4 })).toEqual({ value: '07:00', unsure: true });
    expect(clairic.read({ value: null, p_null: 0.9 })).toEqual({ value: null, unsure: false });
  });
});
