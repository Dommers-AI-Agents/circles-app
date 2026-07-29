// Tests for the circle advisor's deterministic halves: prompt construction and
// the sanitizer that stands between a model reply and somebody's saved places.
// No network — `advise()` itself is not exercised here.

const { buildPrompt, sanitize, isEnabled } = require('../circleAdvisor');

const circle = (id, name, extra = {}) => ({
  id,
  name,
  placesCount: extra.placesCount ?? 5,
  topCategories: extra.topCategories,
  topCities: extra.topCities,
  isSystem: extra.isSystem
});

describe('buildPrompt', () => {
  it('describes each circle on its own line with the fields that carry signal', () => {
    const prompt = buildPrompt([
      circle('c1', 'Charlotte NC', { placesCount: 40, topCategories: ['restaurant'], topCities: ['Charlotte'] })
    ]);

    expect(prompt).toContain('id=c1');
    expect(prompt).toContain('name="Charlotte NC"');
    expect(prompt).toContain('places=40');
    expect(prompt).toContain('categories=restaurant');
    expect(prompt).toContain('cities=Charlotte');
  });

  it('omits optional fields rather than emitting empty ones', () => {
    const prompt = buildPrompt([circle('c1', 'Untitled thing', { placesCount: 0 })]);
    expect(prompt).not.toContain('categories=');
    expect(prompt).not.toContain('cities=');
  });

  it('quotes names so a comma or quote in a circle name cannot break the line format', () => {
    const prompt = buildPrompt([circle('c1', 'Ben\'s "best" spots, 2025')]);
    expect(prompt).toContain(JSON.stringify('Ben\'s "best" spots, 2025'));
  });
});

describe('sanitize — scheme labels', () => {
  const circles = [circle('c1', 'Charlotte'), circle('c2', 'Pizza')];

  it('keeps labels for circles that exist', () => {
    const out = sanitize(
      { schemes: [{ circleId: 'c1', scheme: 'place', confidence: 0.9 }], merges: [] },
      circles
    );
    expect(out.schemes).toHaveLength(1);
    expect(out.schemes[0].scheme).toBe('place');
  });

  it('drops labels for circles that were never sent', () => {
    const out = sanitize(
      { schemes: [{ circleId: 'ghost', scheme: 'place', confidence: 0.9 }], merges: [] },
      circles
    );
    expect(out.schemes).toHaveLength(0);
  });

  it('tolerates a reply with neither key', () => {
    expect(sanitize({}, circles)).toEqual({ schemes: [], merges: [] });
  });
});

describe('sanitize — merge proposals', () => {
  const circles = [
    circle('belmar', 'Belmar', { placesCount: 25 }),
    circle('asbury', 'Asbury Park', { placesCount: 19 }),
    circle('pizza', 'Pizza Slices', { placesCount: 10 }),
    circle('checkins', 'Check-in Places', { isSystem: true }),
    circle('trip', 'Rhode Island weekend July 2025', { placesCount: 8 })
  ];
  const placeScheme = [
    { circleId: 'belmar', scheme: 'place', confidence: 0.95 },
    { circleId: 'asbury', scheme: 'place', confidence: 0.95 },
    { circleId: 'pizza', scheme: 'type', confidence: 0.9 },
    { circleId: 'checkins', scheme: 'system', confidence: 1 },
    { circleId: 'trip', scheme: 'trip', confidence: 0.9 }
  ];

  const run = (merges) => sanitize({ schemes: placeScheme, merges }, circles).merges;

  it('keeps a same-scheme merge', () => {
    const out = run([
      { circleIds: ['belmar', 'asbury'], keepCircleId: 'belmar', suggestedName: 'Jersey Shore', reason: 'Both cover the same stretch of shore.' }
    ]);
    expect(out).toHaveLength(1);
    expect(out[0].keepCircleId).toBe('belmar');
  });

  it('rejects a merge spanning two different schemes', () => {
    // "Pizza Slices" (type) and "Belmar" (place) answer different questions.
    expect(run([
      { circleIds: ['belmar', 'pizza'], keepCircleId: 'belmar', suggestedName: 'Belmar', reason: 'Overlapping places.' }
    ])).toHaveLength(0);
  });

  it('never folds a system circle into anything', () => {
    expect(run([
      { circleIds: ['belmar', 'checkins'], keepCircleId: 'belmar', suggestedName: 'Belmar', reason: 'Overlap.' }
    ])).toHaveLength(0);
  });

  it('never merges away a trip — it is a memory, not a category', () => {
    expect(run([
      { circleIds: ['trip', 'belmar'], keepCircleId: 'belmar', suggestedName: 'Belmar', reason: 'Same geography.' }
    ])).toHaveLength(0);
  });

  it('rejects a merge naming a keeper outside its own group', () => {
    expect(run([
      { circleIds: ['belmar', 'asbury'], keepCircleId: 'pizza', suggestedName: 'Shore', reason: 'Overlap.' }
    ])).toHaveLength(0);
  });

  it('rejects a group of fewer than two real circles', () => {
    expect(run([
      { circleIds: ['belmar'], keepCircleId: 'belmar', suggestedName: 'Belmar', reason: 'Alone.' }
    ])).toHaveLength(0);
    expect(run([
      { circleIds: ['belmar', 'ghost'], keepCircleId: 'belmar', suggestedName: 'Belmar', reason: 'Half real.' }
    ])).toHaveLength(0);
  });

  it('deduplicates repeated ids before counting the group', () => {
    expect(run([
      { circleIds: ['belmar', 'belmar'], keepCircleId: 'belmar', suggestedName: 'Belmar', reason: 'Same circle twice.' }
    ])).toHaveLength(0);
  });

  it('strips unknown ids from an otherwise valid group', () => {
    const out = run([
      { circleIds: ['belmar', 'asbury', 'ghost'], keepCircleId: 'belmar', suggestedName: 'Shore', reason: 'Overlap.' }
    ]);
    expect(out).toHaveLength(1);
    expect(out[0].circleIds).toEqual(['belmar', 'asbury']);
  });
});

describe('isEnabled', () => {
  const original = { ...process.env };
  afterEach(() => { process.env = { ...original }; });

  it('is off without the flag', () => {
    process.env.CIRCLE_ADVISOR_ENABLED = 'false';
    process.env.ANTHROPIC_API_KEY = 'sk-test';
    expect(isEnabled()).toBe(false);
  });

  it('is off without a key, even with the flag on', () => {
    process.env.CIRCLE_ADVISOR_ENABLED = 'true';
    delete process.env.ANTHROPIC_API_KEY;
    expect(isEnabled()).toBe(false);
  });

  it('is on with both', () => {
    process.env.CIRCLE_ADVISOR_ENABLED = 'true';
    process.env.ANTHROPIC_API_KEY = 'sk-test';
    expect(isEnabled()).toBe(true);
  });
});
