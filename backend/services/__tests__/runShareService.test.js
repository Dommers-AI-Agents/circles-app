jest.mock('../../config/firebase', () => ({ getFirestore: () => ({}) }));
jest.mock('../notifyQuiet', () => ({ sendInBackground: jest.fn() }));
jest.mock('../../utils/networkAccess', () => ({ getConnectedUserIds: jest.fn() }));
const { splitMessage, finishMessage, toClientRun, canView } = require('../runShareService');
const { passesItemGates } = require('../activityPrivacy');

describe('run sharing', () => {
  test('mile pushes: time, total, and something fun', () => {
    const m = splitMessage({ name: 'Wes', unit: 'mi', splits: [540, 525, 522], n: 3 });
    expect(m.title).toBe('🏃 Wes hit mile 3');
    expect(m.body).toMatch(/^8:42 that mile · 26:27 total\. /);
    expect(splitMessage({ name: 'Wes', unit: 'mi', splits: [540, 500], n: 2 }).body).toMatch(/Picking up speed/);
  });

  test('crossing 5K and the half are celebrated', () => {
    // mile 4 ends at 6.44 km: crosses 5K
    expect(splitMessage({ name: 'Wes', unit: 'mi', splits: [500, 500, 500, 500], n: 4 }).body).toMatch(/5K/);
    expect(splitMessage({ name: 'Wes', unit: 'km', splits: Array(5).fill(300), n: 5 }).body).toMatch(/5K/);
    expect(splitMessage({ name: 'Wes', unit: 'km', splits: Array(22).fill(300), n: 22 }).body).toMatch(/HALF MARATHON/);
  });

  test('finish push', () => {
    expect(finishMessage({ name: 'Wes', unit: 'mi', distanceM: 1609.344 * 3.1, movingSec: 1650 }))
      .toEqual({ title: '🏁 Wes finished!', body: '3.10 mi in 27:30 · 8:52/mi. Tap for the map and splits.' });
  });

  test('who can see a run, and what they get', () => {
    const data = { ownerId: 'wes', ownerName: 'Wes', status: 'live', unit: 'mi', token: 'abcdefghijklmnopqrst',
      watcherIds: ['sal'], watcherNames: { sal: 'Sal' }, invitedIds: ['sal', 'brit'], splits: [500], cheers: [] };
    expect(canView(data, 'wes') && canView(data, 'sal') && canView(data, 'brit')).toBe(true);
    expect(canView(data, 'stranger')).toBe(false);
    const forSal = toClientRun('r1', data, 'sal');
    expect(forSal.watching).toBe(true);
    expect(forSal.isMine).toBe(false);
    expect(forSal.invitedCount).toBe(1);
    expect(forSal.shareUrl).toMatch(/\/app\/run\/abcdefghijklmnopqrst$/);
  });

  test('a posted run in the feed: connections, or the chosen Inner Circle list', () => {
    const ctx = { connections: new Set(['wes']), innerCircleLists: new Map([['wes', new Set(['fam'])]]), innerCircleGrantors: new Set(['wes']) };
    const row = (meta) => ({ type: 'run_shared', actorId: 'wes', metadata: meta });
    expect(passesItemGates(row({ runAudience: 'connections' }), 'sal', ctx)).toBe(true);
    expect(passesItemGates(row({ runAudience: 'innerCircle', audienceListId: 'fam' }), 'sal', ctx)).toBe(true);
    expect(passesItemGates(row({ runAudience: 'innerCircle', audienceListId: 'gym' }), 'sal', ctx)).toBe(false);
    expect(passesItemGates(row({ runAudience: 'connections' }), 'sal', { connections: new Set() })).toBe(false);
  });
});
