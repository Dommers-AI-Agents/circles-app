const PDFDocument = require('pdfkit');
const art = require('../roundLabelArt');

// Every glyph half as wide as the type is tall, so the arithmetic is easy to read
const measure = (text, size) => [...text].map(() => size / 2);
const fit = (text, extra = {}) => art.fitArcText(text, { measure, radius: 100, maxAngle: 45, size: 10, minSize: 5, spacing: 0, ...extra });
const room = 2 * 100 * 45 * Math.PI / 180; // 157.08

describe('roundLabelArt', () => {
  test('a name that fits keeps its size', () => {
    expect(fit('PORT COFFEE')).toEqual({ text: 'PORT COFFEE', size: 10 });
    expect(fit('  Port   Coffee ')).toEqual({ text: 'Port Coffee', size: 10 });
    expect(fit('')).toEqual({ text: '', size: 10 });
    expect(fit(null).text).toBe('');
  });

  test('a longer name shrinks until it fits, never below the smallest size', () => {
    const name = 'X'.repeat(40); // 200 wide at size 10
    const got = fit(name);
    expect(got.text).toBe(name);
    expect(got.size).toBeLessThan(10);
    expect(got.size).toBeGreaterThanOrEqual(5);
    expect(art.arcLength(measure(got.text, got.size), 0)).toBeLessThanOrEqual(room);
  });

  test('the gaps between letters count, and do not shrink with the type', () => {
    const name = 'X'.repeat(30); // 150 of glyphs at size 10, plus 29 gaps of 1
    const got = fit(name, { spacing: 1 });
    expect(got.size).toBeLessThan(10);
    expect(art.arcLength(measure(got.text, got.size), 1)).toBeLessThanOrEqual(room);
  });

  test('a name too long for the smallest size is cut short, on a whole word when it can be', () => {
    const got = fit('GROOVERS LISTENING BAR AND KITCHEN OF GREATER CHARLOTTE NORTH CAROLINA');
    expect(got.size).toBe(5);
    expect(got.text.endsWith('…')).toBe(true);
    expect(art.arcLength(measure(got.text, 5), 0)).toBeLessThanOrEqual(room);
    const kept = got.text.slice(0, -1);
    expect('GROOVERS LISTENING BAR AND KITCHEN OF GREATER CHARLOTTE NORTH CAROLINA'.startsWith(kept + ' ')).toBe(true);
    // One endless word is simply cut
    const one = fit('X'.repeat(200));
    expect(one.text).toMatch(/^X+…$/);
    expect(art.arcLength(measure(one.text, 5), 0)).toBeLessThanOrEqual(room);
  });

  test('the Totem label keeps its words clear of the code and inside the ring', () => {
    const L = art.TOTEM_LABEL;
    const corner = L.qr / Math.SQRT2;
    const module33 = L.qr / 33; // a store link is a 33 × 33 code
    expect(L.bandInner - corner).toBeGreaterThanOrEqual(2 * module33); // two quiet modules at the corners
    expect(L.bandOuter).toBeLessThanOrEqual(L.diameter / 2 - L.ringInset - L.ringWidth / 2 - 0.5 * art.MM);
    expect(L.diameter / 2 - L.bandOuter).toBeGreaterThanOrEqual(1.5 * art.MM); // type stays 1.5 mm in from the cut
    // Top and bottom words cannot run into each other
    expect(L.topMaxAngle + L.nameMaxAngle).toBeLessThan(180 - 20);
  });

  test('the Totem label says the store name in capitals, or FAVCIRCLES for no store', () => {
    const doc = new PDFDocument({ size: [108, 108], margin: 0 });
    const draw = (name) => art.drawTotemLabel(doc, 54, 54, 'https://api.favcircles.com/s/WIN123?t=totem', name);
    expect(draw('Port Coffee')).toMatchObject({ modules: 33, name: 'PORT COFFEE', nameSize: art.TOTEM_LABEL.size });
    expect(draw('').name).toBe('FAVCIRCLES');
    expect(draw(undefined).name).toBe('FAVCIRCLES');
    const long = draw('Groovers Listening Bar');
    expect(long.name).toBe('GROOVERS LISTENING BAR');
    expect(long.nameSize).toBeLessThan(art.TOTEM_LABEL.size);
    expect(draw('Tommy\'s Tavern + Tap Morristown New Jersey').name).toBe('TOMMY\'S TAVERN + TAP…');
    doc.end();
  });
});
