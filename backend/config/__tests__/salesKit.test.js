const { SALES_KIT } = require('../salesKit');

describe('sales kit', () => {
  const items = SALES_KIT.flatMap((s) => s.items);

  it('has named sections, each with items', () => {
    for (const section of SALES_KIT) {
      expect(section.title).toBeTruthy();
      expect(section.items.length).toBeGreaterThan(0);
    }
  });

  it('gives every item a title and a line saying what it is', () => {
    for (const item of items) {
      expect(item.title).toBeTruthy();
      expect(item.sub).toBeTruthy();
    }
  });

  it('only links over https, with a button label', () => {
    for (const item of items.filter((i) => i.url || i.thumb)) {
      if (item.url) {
        expect(item.url).toMatch(/^https:\/\//);
        expect(item.action).toBeTruthy();
      }
      if (item.thumb) expect(item.thumb).toMatch(/^https:\/\//);
    }
  });

  it('never prints the points cap or a points default (sell-sheet rules)', () => {
    const text = JSON.stringify(SALES_KIT);
    expect(text).not.toMatch(/500 points|25 points|100 points/i);
  });
});
