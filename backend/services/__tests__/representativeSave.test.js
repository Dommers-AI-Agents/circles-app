const { pickRepresentativeSave, MAX_VISIBILITY_CHECKS } = require('../representativeSave');

const save = (id, addedBy, createdAt, extra = {}) => ({ id, addedBy, createdAt, ...extra });

describe('pickRepresentativeSave', () => {
  const sal = save('s1', 'sal', '2026-01-01');
  const newer = save('s2', 'brit', '2026-06-01');

  test('the viewer’s own save wins without any visibility check', async () => {
    const mine = save('m1', 'wes', '2026-09-01');
    const isVisible = jest.fn();
    expect(await pickRepresentativeSave([sal, mine], 'wes', isVisible)).toBe(mine);
    expect(isVisible).not.toHaveBeenCalled();
  });

  test('otherwise the oldest save the viewer may see — a circle-inherited save counts', async () => {
    // Sal's save inherits its circle (privacy followCircle): the gate says
    // yes, so he is credited rather than "a connection".
    const isVisible = async s => s.id === 's1';
    expect(await pickRepresentativeSave([newer, sal], 'wes', isVisible)).toBe(sal);
  });

  test('skips saves the viewer cannot see', async () => {
    const isVisible = async s => s.id === 's2';
    expect(await pickRepresentativeSave([sal, newer], 'wes', isVisible)).toBe(newer);
  });

  test('deleted saves are never credited', async () => {
    const gone = save('s0', 'old', '2025-01-01', { deletedAt: '2026-02-01' });
    expect(await pickRepresentativeSave([gone, sal], 'wes', async () => true)).toBe(sal);
  });

  test('nobody visible → null', async () => {
    expect(await pickRepresentativeSave([sal, newer], 'wes', async () => false)).toBeNull();
    expect(await pickRepresentativeSave([], 'wes', async () => true)).toBeNull();
  });

  test('checks are capped for very popular venues', async () => {
    const many = Array.from({ length: MAX_VISIBILITY_CHECKS + 10 }, (_, i) =>
      save(`p${i}`, `u${i}`, new Date(2026, 0, 1 + i).toISOString()));
    const isVisible = jest.fn(async () => false);
    expect(await pickRepresentativeSave(many, 'wes', isVisible)).toBeNull();
    expect(isVisible).toHaveBeenCalledTimes(MAX_VISIBILITY_CHECKS);
  });
});
