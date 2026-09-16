// Home daily-card picker: cadence window, new-account guard, priority order,
// the three kinds of "already knows", visibility gates, and the ack contract.
// Firestore is the in-memory fake (namespaced: the picker reads seven
// collections); the tips catalog goes through the real tipsService so the
// surfaces filter is exercised too.
const { FakeFirestore } = require('../../__fixtures__/fakeFirestore');

const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({
  getFirestore: () => mockDb,
  FieldValue: { arrayUnion: (v) => ({ __arrayUnion: v }) }
}));
jest.mock('../notificationService', () => ({ sendToUser: jest.fn() }));
jest.mock('../sseService', () => ({ notifyUser: jest.fn() }));

const service = require('../homePromptService');
const { HomePromptError } = require('../homePromptService');
const tipsService = require('../tipsService');

const NOW = Date.parse('2026-09-16T15:00:00Z');
const HOUR = 3600 * 1000;
const DAY = 24 * HOUR;
const iso = (ms) => new Date(ms).toISOString();
const ME = 'me';

const rows = (name) => mockDb.rows(name);
const put = (col, id, data) => rows(col).set(id, data);

function seedUser(id, extra = {}) {
  put('users', id, { displayName: `${id} Person`, createdAt: iso(NOW - 30 * DAY), ...extra });
}
function connect(a, b) {
  put('connections', `${a}_${b}`, { userId: a, connectedUserId: b, status: 'accepted' });
}
function activity(id, data) {
  put('activities', id, {
    actorId: 'ana', type: 'place_added', targetType: 'place', targetId: 'p1', targetName: "Mabel's Kitchen",
    circleId: null, metadata: {}, timestamp: new Date(NOW - HOUR), ...data
  });
}
function tip(id, data) {
  put('notificationTips', id, { enabled: true, title: id, body: 'b', target: 't', ...data });
}
const pick = () => service.pick(ME, { now: NOW });
const state = () => rows('users').get(ME).homePrompt || {};

beforeEach(() => {
  for (const col of mockDb.collections.values()) col.store.docs.clear();
  process.env.HOME_PROMPTS_ENABLED = '1';
  seedUser(ME);
  seedUser('ana', { firstName: 'Ana', profilePicture: 'https://x/ana.jpg' });
  connect(ME, 'ana');
  // A place saved yesterday keeps the add-place nudge quiet unless a test wants it.
  put('places', 'mine', { addedBy: ME, createdAt: iso(NOW - DAY) });
});

describe('gates', () => {
  test('flag off → null and nothing stamped', async () => {
    process.env.HOME_PROMPTS_ENABLED = '0';
    activity('a1');
    expect(await pick()).toBeNull();
    expect(state().lastShownAt).toBeUndefined();
  });

  test('accounts younger than 48h get nothing', async () => {
    seedUser(ME, { createdAt: iso(NOW - 47 * HOUR) });
    activity('a1');
    expect(await pick()).toBeNull();
  });

  test('a card shown within the last 20h blocks the next one', async () => {
    activity('a1');
    expect(await pick()).not.toBeNull();
    activity('a2', { targetName: 'Second', timestamp: new Date(NOW + 20 * HOUR) });
    expect(await service.pick(ME, { now: NOW + 19 * HOUR })).toBeNull();
    expect((await service.pick(ME, { now: NOW + 21 * HOUR })).key).toBe('activity:a2');
  });

  test('showing nothing is a valid outcome', async () => {
    expect(await pick()).toBeNull();
    expect(state().lastShownAt).toBeUndefined();
  });
});

describe('connection activity', () => {
  test('newest unseen place_added from a connection wins and is stamped shown', async () => {
    activity('old', { timestamp: new Date(NOW - 5 * HOUR), targetName: 'Old' });
    activity('new', { timestamp: new Date(NOW - HOUR), circleName: 'Brunch', metadata: { placePhoto: 'https://x/p.jpg' } });
    const card = await pick();
    expect(card).toMatchObject({
      key: 'activity:new', type: 'connection_activity', title: "Ana added Mabel's Kitchen",
      body: 'To Brunch.', target: 'place', data: { placeId: 'p1' }, imageUrl: 'https://x/p.jpg', actorId: 'ana'
    });
    expect(state()).toMatchObject({ lastShownAt: iso(NOW), lastCardId: 'activity:new' });
    expect(state().acks['activity:new'].action).toBe('shown');
  });

  test('activity older than a day, my own, or of an unknown type is ignored', async () => {
    activity('stale', { timestamp: new Date(NOW - 25 * HOUR) });
    activity('mine', { actorId: ME });
    activity('like', { type: 'place_liked' });
    expect(await pick()).toBeNull();
  });

  test('skipping one activity does not suppress the next one from the same person', async () => {
    activity('a1');
    await pick();
    await service.ack(ME, 'activity:a1', 'skipped');
    activity('a2', { targetName: 'Taco Spot', timestamp: new Date(NOW + 22 * HOUR) });
    const card = await service.pick(ME, { now: NOW + 23 * HOUR });
    expect(card.key).toBe('activity:a2');
  });

  test('moment activity respects momentVisibility (network needs a connection, followers needs a follow)', async () => {
    seedUser('bo', { firstName: 'Bo' });
    seedUser(ME, { following: ['bo'] });
    activity('v1', { actorId: 'bo', type: 'video_uploaded', targetType: 'place_video', targetId: 'vid1',
      metadata: { momentVisibility: 'network', momentOwnerId: 'bo', videoThumbnail: 'https://x/t.jpg' } });
    expect(await pick()).toBeNull();
    activity('v1', { actorId: 'bo', type: 'video_uploaded', targetType: 'place_video', targetId: 'vid1',
      metadata: { momentVisibility: 'followers', momentOwnerId: 'bo', videoThumbnail: 'https://x/t.jpg' } });
    const card = await pick();
    expect(card).toMatchObject({ key: 'moment:vid1', title: 'Bo shared a moment', target: 'video', data: { videoId: 'vid1' } });
  });

  test('a check-in at a private place never surfaces', async () => {
    put('places', 'p1', { addedBy: 'ana', privacy: 'private' });
    activity('c', { type: 'check_in', targetType: 'check_in', targetId: 'ci1', metadata: { placeId: 'p1' } });
    expect(await pick()).toBeNull();
  });

  test('skipping a moment\'s activity card also silences it as "latest moment"', async () => {
    seedUser(ME, { following: ['ana'] });
    activity('v1', { type: 'video_uploaded', targetType: 'place_video', targetId: 'vid1',
      metadata: { momentVisibility: 'public', momentOwnerId: 'ana' } });
    const card = await pick();
    expect(card.key).toBe('moment:vid1');
    await service.ack(ME, 'moment:vid1', 'skipped');
    put('placeVideos', 'vid1', { userId: 'ana', uploadStatus: 'ready', deletedAt: null, visibility: 'public',
      placeName: 'Pier 9', createdAt: iso(NOW + 20 * HOUR) });
    expect(await service.pick(ME, { now: NOW + 21 * HOUR })).toBeNull();
  });

  test('circle-scoped rows honour circle privacy; private places never surface', async () => {
    put('circles', 'c1', { owner: 'ana', privacy: 'private', sharedWith: [] });
    activity('a1', { circleId: 'c1' });
    expect(await pick()).toBeNull();
    put('circles', 'c1', { owner: 'ana', privacy: 'public' });
    put('places', 'p1', { addedBy: 'ana', privacy: 'private' });
    expect(await pick()).toBeNull();
    put('places', 'p1', { addedBy: 'ana', privacy: 'public' });
    expect((await pick()).key).toBe('activity:a1');
  });

  test('blocked users contribute nothing', async () => {
    seedUser(ME, { blockedUsers: ['ana'] });
    activity('a1');
    expect(await pick()).toBeNull();
  });

  test('check_in and photo_uploaded copy', async () => {
    activity('c', { type: 'check_in', targetType: 'check_in', targetId: 'ci1',
      metadata: { placeId: 'p1', message: 'Best espresso in town' }, timestamp: new Date(NOW - 2 * HOUR) });
    const checkIn = await pick();
    expect(checkIn.title).toBe("Ana checked in at Mabel's Kitchen");
    expect(checkIn.body).toBe('Best espresso in town');
    expect(checkIn.data.placeId).toBe('p1');
    put('users', ME, { ...rows('users').get(ME), homePrompt: {} });
    activity('ph', { type: 'photo_uploaded', timestamp: new Date(NOW - HOUR) });
    expect((await pick()).title).toBe('Ana added a photo');
  });
});

describe('latest moment', () => {
  function video(id, data) {
    put('placeVideos', id, {
      userId: 'ana', uploadStatus: 'ready', deletedAt: null, visibility: 'network', placeName: 'Pier 9',
      thumbnailUrl: 'https://x/v.jpg', createdAt: iso(NOW - 2 * HOUR), ...data
    });
  }

  test('newest unwatched network moment in the last day', async () => {
    video('v1');
    const card = await pick();
    expect(card).toMatchObject({ key: 'moment:v1', type: 'latest_moment', title: 'Latest moment from Ana', body: 'At Pier 9.', target: 'video', data: { videoId: 'v1' } });
  });

  test('already watched, older than a day, or network-only from a mere follow → skipped', async () => {
    video('watched');
    put('videoViews', 'x', { userId: ME, videoId: 'watched', viewedAt: iso(NOW - HOUR) });
    video('old', { createdAt: iso(NOW - 2 * DAY) });
    seedUser('bo', { firstName: 'Bo' });
    seedUser(ME, { following: ['bo'] });
    video('bos', { userId: 'bo', visibility: 'network' });
    expect(await pick()).toBeNull();
    video('bos', { userId: 'bo', visibility: 'public' });
    expect((await pick()).title).toBe('Latest moment from Bo');
  });

  test('connection activity outranks a moment', async () => {
    video('v1');
    activity('a1');
    expect((await pick()).key).toBe('activity:a1');
  });
});

describe('add a place', () => {
  beforeEach(() => rows('places').clear());

  test('nudges when nothing was saved this week, then not again for a week', async () => {
    const card = await pick();
    expect(card).toMatchObject({ key: 'add_place', type: 'add_place', title: 'Add a new place?', target: 'add_place' });
    await service.ack(ME, 'add_place', 'skipped');
    expect(await service.pick(ME, { now: NOW + 3 * DAY })).toBeNull();
    expect((await service.pick(ME, { now: NOW + 8 * DAY })).key).toBe('add_place');
  });

  test('a place saved in the last 7 days suppresses the nudge; an older one does not', async () => {
    put('places', 'mine', { addedBy: ME, createdAt: iso(NOW - 2 * DAY) });
    expect(await pick()).toBeNull();
    put('places', 'mine', { addedBy: ME, createdAt: iso(NOW - 9 * DAY) });
    expect((await pick()).key).toBe('add_place');
  });

  test('first-place copy for an empty account', async () => {
    seedUser(ME, { placesCount: 0 });
    expect((await pick()).title).toBe('Save your first place');
  });
});

describe('postcard', () => {
  // A place saved this week is both what suppresses the add-place nudge and
  // what the postcard card is about, so these run with one seeded save.
  const savePlace = (id, extra = {}) => put('places', id, {
    addedBy: ME, name: 'Cafe Lisboa', createdAt: iso(NOW - 2 * DAY),
    photos: ['https://img/1.jpg'], ...extra
  });

  beforeEach(() => {
    rows('places').clear();
    delete process.env.POSTCARD_NUDGE_MIN_MILES;
  });

  test('a recent save with a photo becomes the card, newest first', async () => {
    savePlace('older', { name: 'Old Spot', createdAt: iso(NOW - 5 * DAY), photos: ['https://img/old.jpg'] });
    savePlace('newer');
    const card = await pick();
    expect(card).toMatchObject({
      key: 'postcard_nudge',
      type: 'postcard',
      title: 'Send a postcard from Cafe Lisboa?',
      target: 'postcard',
      imageUrl: 'https://img/1.jpg',
      data: { placeId: 'newer', placeName: 'Cafe Lisboa', photoUrl: 'https://img/1.jpg' }
    });
  });

  test('no photo, no name, deleted, or nothing saved this week → no postcard card', async () => {
    savePlace('nophoto', { photos: [] });
    expect(await pick()).toBeNull();
    savePlace('nophoto', { photos: [''] });
    expect(await pick()).toBeNull();
    savePlace('nophoto', { name: '' });
    expect(await pick()).toBeNull();
    savePlace('nophoto', { deletedAt: iso(NOW - DAY) });
    expect(await pick()).toBeNull();
    savePlace('nophoto', { createdAt: iso(NOW - 9 * DAY) });
    expect((await pick()).key).toBe('add_place'); // stale save → the other nudge
  });

  test('asks at most once a fortnight, and the app pop-up ack silences it too', async () => {
    savePlace('p');
    expect((await pick()).key).toBe('postcard_nudge');
    await service.ack(ME, 'postcard_nudge', 'skipped');
    // Kept fresh so the add-place nudge stays quiet and the only question is
    // whether the postcard card comes back.
    savePlace('p', { createdAt: iso(NOW + 12 * DAY) });
    expect(await service.pick(ME, { now: NOW + 13 * DAY })).toBeNull();
    savePlace('p', { createdAt: iso(NOW + 14 * DAY) });
    expect((await service.pick(ME, { now: NOW + 15 * DAY })).key).toBe('postcard_nudge');
  });

  test('the post-save pop-up can ack the key before any card was shown', async () => {
    // CLIENT_ACK_KEYS: the app asked first, so the home card must stand down
    // without the user ever having been shown one.
    await service.ack(ME, 'postcard_nudge', 'skipped');
    savePlace('p');
    expect(await pick()).toBeNull();
  });

  test('POSTCARD_NUDGE_MIN_MILES only nudges about places far from home', async () => {
    process.env.POSTCARD_NUDGE_MIN_MILES = '50';
    seedUser(ME, { assumedLocation: { latitude: 35.2271, longitude: -80.8431, updatedAt: new Date().toISOString() } });
    savePlace('nearby', { location: { coordinates: [-80.85, 35.23] } }); // Charlotte
    expect(await pick()).toBeNull();
    savePlace('nearby', { location: { coordinates: [-9.1393, 38.7223] } }); // Lisbon
    expect((await pick()).key).toBe('postcard_nudge');
  });

  test('unknown coordinates or no assumed location still nudge', async () => {
    process.env.POSTCARD_NUDGE_MIN_MILES = '50';
    savePlace('p'); // no location at all, and the seeded user has no assumedLocation
    expect((await pick()).key).toBe('postcard_nudge');
  });
});

describe('postcard nudge eligibility (the app\'s post-save pop-up)', () => {
  const eligible = (now = NOW) => service.postcardNudgeEligible(ME, { now });

  beforeEach(() => {
    rows('places').clear();
    delete process.env.POSTCARD_NUDGE_ENABLED;
  });

  test('open by default, and the kill switch closes it', async () => {
    expect(await eligible()).toBe(true);
    process.env.POSTCARD_NUDGE_ENABLED = '0';
    expect(await eligible()).toBe(false);
  });

  test('never in a new account\'s first 48 hours, and never for a stranger', async () => {
    seedUser(ME, { createdAt: iso(NOW - 6 * HOUR) });
    expect(await eligible()).toBe(false);
    expect(await service.postcardNudgeEligible('nobody', { now: NOW })).toBe(false);
  });

  test('a home card that already asked closes the pop-up for a fortnight', async () => {
    // pick() stamps the card as shown, which is what spends the cooldown.
    put('places', 'p', { addedBy: ME, name: 'Cafe Lisboa', createdAt: iso(NOW - DAY), photos: ['https://img/1.jpg'] });
    expect((await pick()).key).toBe('postcard_nudge');
    expect(await eligible()).toBe(false);
    expect(await eligible(NOW + 13 * DAY)).toBe(false);
    expect(await eligible(NOW + 15 * DAY)).toBe(true);
  });

  test('independent of HOME_PROMPTS_ENABLED — the pop-up is its own feature', async () => {
    process.env.HOME_PROMPTS_ENABLED = '0';
    expect(await eligible()).toBe(true);
  });
});

describe('favcoins', () => {
  test('balance card shows once, never after the explainer was seen', async () => {
    put('piggyBanks', ME, { pendingCoins: 12.5, confirmedCoins: 327.5 });
    const card = await pick();
    expect(card).toMatchObject({ key: 'favcoins_balance', title: 'You have 340 FavCoins in your piggy bank 🐷', target: 'favcoins_intro', data: { coins: 340 } });
    await service.ack(ME, 'favcoins_intro', 'acted'); // client-originated key
    put('users', ME, { ...rows('users').get(ME), homePrompt: { ...state(), lastShownAt: null } });
    expect(await pick()).toBeNull();
  });

  test('zero or missing balance → no card; fractional balance keeps two decimals', async () => {
    expect(await pick()).toBeNull();
    put('piggyBanks', ME, { pendingCoins: 0, confirmedCoins: 0 });
    expect(await pick()).toBeNull();
    put('piggyBanks', ME, { pendingCoins: 0.05, confirmedCoins: 1 });
    expect((await pick()).title).toContain('1.05 FavCoins');
  });
});

describe('catalog feature tips', () => {
  test('home-surface tips only, in order, with the action label from the doc', async () => {
    tip('push-only', { order: 1, target: 'all_places_map' });
    tip('home-b', { order: 20, surfaces: ['home'], target: 'moments_tab', actionLabel: 'Take a look' });
    tip('home-a', { order: 10, surfaces: ['home', 'push'], target: 'widgets_tab' });
    const card = await pick();
    expect(card).toMatchObject({ key: 'home-a', type: 'feature_tip', target: 'widgets_tab', actionLabel: 'Show me' });
  });

  test('push job never sees a home-only card', async () => {
    tip('home-only', { surfaces: ['home'] });
    tip('legacy', {});
    expect((await tipsService.loadCatalog()).map(t => t.id)).toEqual(['legacy']);
  });

  test('noWidgetData / noVideoViews suppress on evidence, and never repeat once acked or in tipsSeen', async () => {
    tip('widgets', { order: 1, surfaces: ['home'], requires: 'noWidgetData' });
    tip('moments', { order: 2, surfaces: ['home'], requires: 'noVideoViews' });
    put('widgetData', `${ME}_water`, { userId: ME, widgetId: 'water' });
    expect((await pick()).key).toBe('moments');
    await service.ack(ME, 'moments', 'skipped');
    put('users', ME, { ...rows('users').get(ME), homePrompt: { ...state(), lastShownAt: null } });
    expect(await pick()).toBeNull();

    rows('widgetData').clear();
    put('users', ME, { ...rows('users').get(ME), tipsSeen: ['widgets'] });
    expect(await pick()).toBeNull();
  });

  test('suppression predicates fail closed when evidence is unknown', () => {
    expect(tipsService.userMatchesRequirement({}, { requires: 'noWidgetData' }, {})).toBe(false);
    expect(tipsService.userMatchesRequirement({}, { requires: 'noWidgetData' }, { hasWidgetData: null })).toBe(false);
    expect(tipsService.userMatchesRequirement({}, { requires: 'noWidgetData' }, { hasWidgetData: false })).toBe(true);
    expect(tipsService.userMatchesRequirement({}, { requires: 'hasPlaces' })).toBe(true);
  });
});

describe('ack', () => {
  test('rejects unknown cards and bad actions; shown never downgrades a skip', async () => {
    await expect(service.ack(ME, 'activity:nope', 'skipped')).rejects.toBeInstanceOf(HomePromptError);
    await expect(service.ack(ME, 'add_place', 'nope')).rejects.toMatchObject({ status: 400 });
    activity('a1');
    await pick();
    await service.ack(ME, 'activity:a1', 'skipped');
    await service.ack(ME, 'activity:a1', 'shown');
    expect(state().acks['activity:a1'].action).toBe('skipped');
  });

  test('dynamic acks older than 90 days are pruned on the next stamp; static keys are kept', async () => {
    seedUser(ME, { homePrompt: { acks: {
      'activity:ancient': { action: 'skipped', at: iso(NOW - 100 * DAY) },
      'moment:recent': { action: 'skipped', at: iso(NOW - 10 * DAY) },
      'favcoins_balance': { action: 'skipped', at: iso(NOW - 400 * DAY) }
    } } });
    activity('a1');
    await pick();
    expect(Object.keys(state().acks).sort()).toEqual(['activity:a1', 'favcoins_balance', 'moment:recent']);
  });

  test('a source that throws does not blank the card slot', async () => {
    const spy = jest.spyOn(service, 'connectionActivityCard').mockRejectedValue(new Error('index missing'));
    const err = jest.spyOn(console, 'error').mockImplementation(() => {});
    put('piggyBanks', ME, { confirmedCoins: 5 });
    expect((await pick()).key).toBe('favcoins_balance');
    spy.mockRestore(); err.mockRestore();
  });
});
