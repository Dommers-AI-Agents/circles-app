// Medications widget "Scan a label" (2026-11-23): the model's reply → draft
// reminders. Schedules come from the stated frequency, never a guess; the
// person's details never come back. Model replies are recorded shapes.
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({ getFirestore: () => mockDb }));

const sharp = require('sharp');
const medReader = require('../scan/medReader');
const medScan = require('../scan/medScan');

describe('schedule from the label', () => {
  test('plain daily frequencies get suggested times', () => {
    expect(medReader.schedule({ frequency: 'once_daily' }).times).toEqual([480]);
    expect(medReader.schedule({ frequency: 'twice_daily' }).times).toEqual([480, 1200]);
    expect(medReader.schedule({ frequency: 'three_times_daily' }).times).toEqual([480, 840, 1200]);
    expect(medReader.schedule({ frequency: 'four_times_daily' }).times).toEqual([480, 720, 960, 1200]);
    expect(medReader.schedule({ frequency: 'bedtime' }).times).toEqual([1260]);
    const s = medReader.schedule({ frequency: 'twice_daily' });
    expect(s.unsure).toBe(false);
    expect(s.why).toMatch(/Suggested/);
  });

  test('printed clock times win', () => {
    const s = medReader.schedule({ frequency: 'twice_daily', clockTimes: ['9:00 AM', '21:30'] });
    expect(s.times).toEqual([540, 1290]);
    expect(s.why).toBeNull();
  });

  test('as needed: no reminder', () => {
    const s = medReader.schedule({ frequency: 'as_needed' });
    expect(s).toMatchObject({ times: [], asNeeded: true });
  });

  test('anything not a simple schedule is left to the person', () => {
    for (const f of ['other', 'nonsense', undefined]) {
      const s = medReader.schedule({ frequency: f });
      expect(s.times).toEqual([]);
      expect(s.unsure).toBe(true);
    }
  });

  test('weekly needs the day', () => {
    expect(medReader.schedule({ frequency: 'weekly', weekday: 2 })).toMatchObject({ times: [480], days: [2], unsure: false });
    expect(medReader.schedule({ frequency: 'weekly' })).toMatchObject({ times: [], days: [], unsure: true });
  });

  test('every N hours is spaced from 8 AM, wraps midnight, and is flagged', () => {
    const s = medReader.schedule({ frequency: 'every_n_hours', everyHours: 8 });
    expect(s.times).toEqual([0, 480, 960]);
    expect(s.unsure).toBe(true);
    expect(medReader.schedule({ frequency: 'every_n_hours', everyHours: 4 }).times.length).toBe(6);
    expect(medReader.schedule({ frequency: 'every_n_hours' }).times).toEqual([]);
  });

  test('clock parsing', () => {
    expect(medReader.parseClock('12:00 AM')).toBe(0);
    expect(medReader.parseClock('12 pm')).toBe(720);
    expect(medReader.parseClock('7:15')).toBe(435);
    expect(medReader.parseClock('25:00')).toBeNull();
    expect(medReader.parseClock('noon')).toBeNull();
  });
});

describe('the draft', () => {
  test('dedupes the same bottle, keeps only medicine fields', () => {
    const draft = medReader.toDraft({
      medications: [
        { name: 'Lisinopril', strength: '10 mg', amount: '1 tablet', directions: 'Take 1 tablet by mouth daily', frequency: 'once_daily',
          patient: 'Jane Doe', rxNumber: '123456', pharmacy: 'CVS', note: 'With water' },
        { name: 'lisinopril', strength: '10 MG', frequency: 'once_daily' },
        { name: '  ', frequency: 'once_daily' },
        { name: 'Ibuprofen', strength: '200 mg', frequency: 'as_needed', unsure: true }
      ],
      notes: 'Second label was cut off'
    });
    expect(draft.medications).toHaveLength(2);
    const [a, b] = draft.medications;
    expect(Object.keys(a).sort()).toEqual(['amount', 'asNeeded', 'days', 'directions', 'frequency', 'name', 'note', 'strength', 'times', 'unsure', 'why']);
    expect(JSON.stringify(draft)).not.toMatch(/Jane|123456|CVS/);
    expect(a).toMatchObject({ name: 'Lisinopril', strength: '10 mg', amount: '1 tablet', times: [480], note: 'With water', unsure: false });
    expect(b).toMatchObject({ name: 'Ibuprofen', asNeeded: true, times: [], unsure: true });
    expect(draft.notes).toBe('Second label was cut off');
  });

  test('nothing readable → empty', () => {
    expect(medReader.toDraft(undefined)).toEqual({ medications: [], notes: null });
  });

  test('the model is never asked for the person’s details', () => {
    const props = Object.keys(medReader.TOOL.input_schema.properties.medications.items.properties);
    expect(props).not.toEqual(expect.arrayContaining(['patient']));
    expect(props.join(',')).not.toMatch(/patient|rx|pharmacy|prescriber|phone|address/i);
    expect(medReader.SYSTEM).toMatch(/NEVER copy the patient/);
  });
});

describe('the scan', () => {
  test('consumes the person’s aiScan budget and logs counts only', async () => {
    const png = (await sharp({ create: { width: 800, height: 600, channels: 3, background: '#fff' } }).png().toBuffer()).toString('base64');
    const reader = { read: jest.fn(async () => ({
      draft: medReader.toDraft({ medications: [{ name: 'Metformin', strength: '500 mg', frequency: 'twice_daily', directions: 'Take with meals' }] }),
      usage: { engine: 'claude', model: 'm', inputTokens: 10, outputTokens: 5, truncated: false }
    })) };
    const out = await medScan.scan({ images: [png], userId: 'u1', db: mockDb, reader });
    expect(out.kind).toBe('medLabel');
    expect(out.draft.medications[0]).toMatchObject({ name: 'Metformin', times: [480, 1200] });
    await new Promise((r) => setImmediate(r));
    const usage = (await mockDb.collection('scanUsage').get()).docs.map((d) => d.data());
    expect(usage).toHaveLength(1);
    expect(JSON.stringify(usage[0])).not.toMatch(/Metformin|meals/);
    const budgets = (await mockDb.collection('dailyBudgets').get()).docs.map((d) => d.data());
    expect(budgets.some((b) => b.bucket === 'aiScan' && b.userId === 'u1')).toBe(true);
  });

  test('no photo → 400 before any paid call', async () => {
    const reader = { read: jest.fn() };
    await expect(medScan.scan({ images: [], userId: 'u1', db: mockDb, reader })).rejects.toMatchObject({ status: 400 });
    expect(reader.read).not.toHaveBeenCalled();
  });
});
