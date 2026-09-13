// Export parity for the activityService barrel: every tracker the app's
// controllers and routes import must still resolve from the old path after
// the split into services/activity/*.

jest.mock('../../config/firebase', () => ({
  admin: { firestore: { FieldValue: {}, Timestamp: {} } },
  getFirestore: () => ({}),
}));
jest.mock('../../controllers/activityController', () => ({ createActivity: jest.fn() }));
jest.mock('../sseService', () => ({}));
jest.mock('../notificationService', () => ({}));

const EXPECTED = [
  'trackCircleCreated',
  'trackPlaceAdded',
  'trackConnectionView',
  'trackCircleView',
  'trackPlaceView',
  'trackCircleLiked',
  'trackCircleCommented',
  'trackPhotoUploaded',
  'trackMomentUpload',
  'trackReaction',
  'trackCheckIn',
  'trackComment',
  'trackPlaceLiked',
  'trackVideoLiked',
  'trackGlobalPlaceLiked',
  'trackSuggestionSent',
  'trackSuggestionAccepted',
  'trackPlaceDiscovered',
  'trackUserFollowed',
  'trackProfileUpdated',
  'trackUserActivity',
  'clearActivityNotification',
  'markCirclePlacesViewed',
  'getConnectionsWithStats',
  'cleanupOldActivity',
  'markCircleActivitiesAsViewed',
  'markPlaceAsViewed',
  'logActivity',
].sort();

describe('activityService barrel', () => {
  test('exports exactly the pre-split surface, every one a function', () => {
    const service = require('../activityService');
    expect(Object.keys(service).sort()).toEqual(EXPECTED);
    for (const name of EXPECTED) {
      expect(typeof service[name]).toBe('function');
    }
  });

  test('each submodule exports a disjoint slice of that surface', () => {
    const modules = ['core', 'circles', 'places', 'media', 'social', 'stats'];
    const seen = new Map();
    for (const m of modules) {
      for (const name of Object.keys(require(`../activity/${m}`))) {
        expect(seen.has(name)).toBe(false);
        seen.set(name, m);
      }
    }
    expect([...seen.keys()].sort()).toEqual(EXPECTED);
  });

  test('cross-module helpers resolve to functions (a missing export would fail silently at runtime)', () => {
    const core = require('../activity/core');
    expect(typeof core.resolvePlacePhoto).toBe('function');
    expect(typeof core.logActivity).toBe('function');
    const places = require('../activity/places');
    expect(typeof places.trackPlaceAdded).toBe('function');
    expect(typeof places.trackPlaceLiked).toBe('function');
    expect(require('../activityService').resolvePlacePhoto).toBeUndefined();
  });
});
