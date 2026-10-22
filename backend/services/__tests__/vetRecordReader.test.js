// "Import from your vet" (2026-10-22): the model's tool input → a clean draft,
// the PDF checks, and the scan wrapper's budget and rules.
const reader = require('../scan/vetRecordReader');

describe('toDraft', () => {
  test('keeps real dates, converts kg, drops empty rows and repeats, flags guesses', () => {
    const draft = reader.toDraft({
      petName: '  Biscuit ',
      vet: { clinic: 'Dilworth Animal Hospital', phone: '(704) 555-0100', address: '123 East Blvd, Charlotte, NC' },
      vaccines: [
        { name: 'Rabies 3yr', givenOn: '2024-03-07', dueOn: '2027-03-07' },
        { name: 'rabies 3YR', givenOn: '2024-03-07', dueOn: '2027-03-07' }, // same shot, second page
        { name: 'DHPP', givenOn: 'March 2024', dueOn: '2025-02-30' }, // not ISO; Feb 30 isn't a date
        { name: '', givenOn: '2024-01-01' }
      ],
      vetVisits: [{ date: '2024-03-07', clinic: 'Dilworth', reason: 'Annual exam' }, { reason: 'No date' }],
      medications: [{ name: 'Heartgard Plus', dose: '1 chew', schedule: 'monthly', startedOn: '2024-03-07' }, { dose: 'x' }],
      weights: [{ date: '2024-03-07', value: 12.5, unit: 'kg' }, { value: 31, unit: 'lb' }, { value: -2 }, { value: 9000 }],
      notes: 'Page 2 was cut off'
    });
    expect(draft.petName).toBe('Biscuit');
    expect(draft.vet).toEqual({ clinic: 'Dilworth Animal Hospital', phone: '(704) 555-0100', address: '123 East Blvd, Charlotte, NC' });
    expect(draft.vaccines).toEqual([
      { name: 'Rabies 3yr', givenOn: '2024-03-07', dueOn: '2027-03-07', notes: null, unsure: false },
      { name: 'DHPP', givenOn: null, dueOn: null, notes: null, unsure: true }
    ]);
    expect(draft.vetVisits).toEqual([{ date: '2024-03-07', clinic: 'Dilworth', reason: 'Annual exam', notes: null, unsure: false }]);
    expect(draft.medications.map((m) => m.name)).toEqual(['Heartgard Plus']);
    expect(draft.weights).toEqual([{ date: '2024-03-07', lbs: 27.6, unsure: false }, { date: null, lbs: 31, unsure: false }]);
    expect(draft.notes).toBe('Page 2 was cut off');
  });

  test('nothing readable → empty lists', () => {
    expect(reader.toDraft(undefined)).toMatchObject({ petName: null, vaccines: [], vetVisits: [], medications: [], weights: [] });
  });

  test('isoDate only takes real calendar dates', () => {
    expect(reader.isoDate('2024-02-29')).toBe('2024-02-29');
    expect(reader.isoDate('2023-02-29')).toBeNull();
    expect(reader.isoDate('3/7/2024')).toBeNull();
  });
});

describe('preparePdf', () => {
  const pdf = (pages, extra = '') => Buffer.from(`%PDF-1.7\n${'<< /Type /Page >>\n'.repeat(pages)}<< /Type /Pages >>${extra}`).toString('base64');
  test('accepts a PDF and counts its pages', () => {
    expect(reader.preparePdf(pdf(3)).pages).toBe(3);
    expect(reader.preparePdf(`data:application/pdf;base64,${pdf(1)}`).pages).toBe(1);
  });
  test('refuses what isn’t a PDF, or one that’s too long', () => {
    const code = (fn) => { try { fn(); return null; } catch (e) { return e.code; } };
    expect(code(() => reader.preparePdf(Buffer.from('hello').toString('base64')))).toBe('bad_pdf');
    expect(code(() => reader.preparePdf(''))).toBe('bad_pdf');
    expect(code(() => reader.preparePdf(pdf(21)))).toBe('pdf_too_long');
  });
});

describe('records.scan', () => {
  const mockUsage = [];
  const db = { collection: () => ({ add: async (row) => { mockUsage.push(row); } }) };
  let records;
  let budgetAllowed = true;
  beforeAll(() => {
    jest.resetModules();
    jest.doMock('../dailyBudget', () => ({ consume: async () => ({ allowed: budgetAllowed, used: 1, limit: 10 }) }));
    jest.doMock('../scan/vetRecordReader', () => ({
      ...jest.requireActual('../scan/vetRecordReader'),
      read: async ({ pdf, dogName }) => ({ draft: { petName: dogName, pages: pdf ? pdf.pages : 0 }, usage: { inputTokens: 10, outputTokens: 5 } })
    }));
    records = require('../dogPark/records');
  });
  const code = async (p) => { try { await p; return null; } catch (e) { return e.code; } };
  const pdf = Buffer.from('%PDF-1.4\n<< /Type /Page >>').toString('base64');

  test('needs photos or a PDF, not both', async () => {
    expect(await code(records.scan('u', {}, { db }))).toBe('no_records');
    expect(await code(records.scan('u', { pdf, images: ['x'] }, { db }))).toBe('one_kind');
  });
  test('returns the draft and logs usage without content', async () => {
    const out = await records.scan('u', { pdf, dogName: 'Biscuit' }, { db });
    expect(out.draft).toEqual({ petName: 'Biscuit', pages: 1 });
    expect(mockUsage[0]).toMatchObject({ userId: 'u', kind: 'vetRecords', pdfPages: 1, inputTokens: 10 });
    expect(JSON.stringify(mockUsage[0])).not.toContain('Biscuit');
  });
  test('10 a day', async () => {
    budgetAllowed = false;
    expect(await code(records.scan('u', { pdf }, { db }))).toBe('scan_limit');
    budgetAllowed = true;
  });
});

describe('dog cards and places (pure checks)', () => {
  const shared = require('../dogPark/shared');
  const places = require('../dogPark/places');
  const ok = () => true;
  test('parseDog trims, validates dates, keeps edits partial', () => {
    expect(shared.parseDog({ name: ' Rex ', birthday: '2020-02-29' }, { isAllowedImageUrl: ok })).toMatchObject({ name: 'Rex', birthday: '2020-02-29', breed: null });
    expect(shared.parseDog({ breed: 'Lab' }, { partial: true, isAllowedImageUrl: ok })).toEqual({ breed: 'Lab' });
    expect(() => shared.parseDog({ name: 'Rex', gotchaDay: '2021-13-01' }, { isAllowedImageUrl: ok })).toThrow('Pick a date');
  });
  test('a place needs a name and a real location', () => {
    expect(() => places.parsePlace({ name: 'Park', lat: 0, lng: 0 })).toThrow('A place needs a location');
    expect(places.parsePlace({ name: 'Freedom Park', lat: 35.19, lng: -80.84 })).toMatchObject({ name: 'Freedom Park', category: 'other' });
  });
});
