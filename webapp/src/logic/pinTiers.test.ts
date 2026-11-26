import { describe, expect, it } from 'vitest';
import { clampRadius, planPins } from './pinTiers';

const view = { width: 400, height: 800 };
const at = (id: string, x: number, y: number, priority = 0) => ({ id, x, y, priority });

describe('map pin tiering (never clustering)', () => {
  it('gives every place a full pin when there is room', () => {
    const plan = planPins([at('a', 50, 50), at('b', 200, 300), at('c', 350, 700)], view);
    expect(plan.full.sort()).toEqual(['a', 'b', 'c']);
    expect(plan.dots).toEqual([]);
  });

  it('shrinks the lower-priority place to a dot when two pins would overlap', () => {
    const plan = planPins([at('far', 105, 100, 9), at('near', 100, 100, 1)], view);
    expect(plan.full).toEqual(['near']);
    expect(plan.dots).toEqual(['far']);
  });

  it('never drops a crowded place: every place in view is a pin or a dot', () => {
    const crowd = Array.from({ length: 60 }, (_, i) => at(`p${i}`, 200 + (i % 5), 400 + (i % 3), i));
    const plan = planPins(crowd, view);
    expect(plan.full).toEqual(['p0']);
    expect(plan.dots).toHaveLength(59);
  });

  it('draws only what is in view (plus a small margin so panning does not pop)', () => {
    const plan = planPins([at('in', 10, 10), at('edge', -30, 10), at('out', -200, 10), at('below', 100, 900)], view);
    expect(plan.full.sort()).toEqual(['edge', 'in']);
    expect(plan.dots).toEqual([]);
  });

  it('caps full pins, the rest become dots in priority order', () => {
    const row = Array.from({ length: 6 }, (_, i) => at(`p${i}`, 20 + i * 60, 100, i));
    const plan = planPins(row, view, { maxFullPins: 4 });
    expect(plan.full).toEqual(['p0', 'p1', 'p2', 'p3']);
    expect(plan.dots).toEqual(['p4', 'p5']);
  });

  it('caps dots by leaving out the lowest priority', () => {
    const crowd = Array.from({ length: 10 }, (_, i) => at(`p${i}`, 200, 400, i));
    const plan = planPins(crowd, view, { maxDots: 3 });
    expect(plan.full).toEqual(['p0']);
    expect(plan.dots).toEqual(['p1', 'p2', 'p3']);
  });

  it('keeps the selected place a full pin, even crowded or off screen', () => {
    const plan = planPins([at('best', 100, 100, 1), at('picked', 104, 100, 50), at('away', -500, 100, 2)], view, { pinned: ['picked', 'away'] });
    expect(plan.full).toContain('picked');
    expect(plan.full).toContain('away');
    expect(plan.dots).toEqual(['best']);
  });

  it('keeps the given order between equal priorities, and ignores unprojectable points', () => {
    const plan = planPins([at('first', 100, 100, 1), at('second', 102, 100, 1), at('bad', NaN, 100, 0)], view);
    expect(plan.full).toEqual(['first']);
    expect(plan.dots).toEqual(['second']);
  });
});

describe('clampRadius', () => {
  it('stays inside what the server accepts', () => {
    expect(clampRadius(12)).toBe(100);
    expect(clampRadius(2500.4)).toBe(2500);
    expect(clampRadius(900000)).toBe(100000);
    expect(clampRadius(NaN)).toBe(100000);
  });
});
