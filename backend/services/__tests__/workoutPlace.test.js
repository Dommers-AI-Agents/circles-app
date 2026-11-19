jest.mock('../../config/firebase', () => ({ getFirestore: () => null }));
const { pickWorkoutCheckIn, checkInCovers } = require('../workoutPlace');

const at = (iso, extra = {}) => ({ startTime: iso, placeName: 'Dowd YMCA', globalPlaceId: 'gp1', ...extra });
const workout = { startedAt: '2026-11-19T12:00:00Z', durationSeconds: 54 * 60 };

describe('workout place', () => {
  test('the check-in on the way in is the gym', () => {
    expect(pickWorkoutCheckIn([at('2026-11-19T11:50:00Z')], workout).placeName).toBe('Dowd YMCA');
  });

  test('closest to the start wins; outside the window never counts', () => {
    const list = [at('2026-11-19T09:00:00Z', { placeName: 'Too early' }), at('2026-11-19T11:30:00Z', { placeName: 'Gym' }),
      at('2026-11-19T13:30:00Z', { placeName: 'Too late' })];
    expect(pickWorkoutCheckIn(list, workout).placeName).toBe('Gym');
    expect(pickWorkoutCheckIn([list[0], list[2]], workout)).toBeNull();
  });

  test('a private or off-feed check-in never tells where a workout was', () => {
    expect(pickWorkoutCheckIn([at('2026-11-19T11:50:00Z', { isPrivate: true })], workout)).toBeNull();
    expect(pickWorkoutCheckIn([at('2026-11-19T11:50:00Z', { showInActivityFeed: false })], workout)).toBeNull();
  });

  test('the check-in must reach everyone the workout reaches', () => {
    const plain = at('x'); // connections
    expect(checkInCovers(plain, { audience: 'connections' })).toBe(true);
    expect(checkInCovers(plain, { audience: 'innerCircle' })).toBe(true);
    expect(checkInCovers(plain, { audience: 'followers' })).toBe(false);
    expect(checkInCovers(at('x', { audience: 'public' }), { audience: 'followers' })).toBe(true);
    const inner = at('x', { audience: 'innerCircle' });
    expect(checkInCovers(inner, { audience: 'connections' })).toBe(false);
    expect(checkInCovers(inner, { audience: 'innerCircle', audienceListId: 'gym' })).toBe(true);
    const oneList = at('x', { audience: 'innerCircle', audienceListId: 'gym' });
    expect(checkInCovers(oneList, { audience: 'innerCircle', audienceListId: 'gym' })).toBe(true);
    expect(checkInCovers(oneList, { audience: 'innerCircle', audienceListId: 'family' })).toBe(false);
    expect(checkInCovers(oneList, { audience: 'innerCircle' })).toBe(false);
  });
});
