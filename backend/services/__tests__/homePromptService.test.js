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
function tip(id, data) {
  put('notificationTips', id, { enabled: true, title: id, body: 'b', target: 't', ...data });
}
// The everyday card: an evergreen home tip. (Connection activity used to be
// the bait here; it no longer produces a card — the feed already shows it.)
function homeTip(id, data = {}) {
  tip(id, { surfaces: ['home'], target: 'widgets_tab', ...data });
}
const pick = () => service.pick(ME, { now: NOW });
const state = () => rows('users').get(ME).homePrompt || {};

beforeEach(() => {
  for (const col of mockDb.collections.values()) col.store.docs.clear();
  process.env.HOME_PROMPTS_ENABLED = '1';
  seedUser(ME);
  seedUser('ana', { firstName: 'Ana', profilePicture: 'https://x/ana.jpg' });
  connect(ME, 'ana');
});

describe('gates', () => {
  test('flag off → null and nothing stamped', async () => {
    process.env.HOME_PROMPTS_ENABLED = '0';
    homeTip('t1');
    expect(await pick()).toBeNull();
    expect(state().lastShownAt).toBeUndefined();
  });

  test('accounts younger than 48h get nothing', async () => {
    seedUser(ME, { createdAt: iso(NOW - 47 * HOUR) });
    homeTip('t1');
    expect(await pick()).toBeNull();
  });

  test('a card shown within the last 2h blocks the next one', async () => {
    homeTip('first', { order: 1 });
    homeTip('second', { order: 2 });
    expect((await pick()).key).toBe('first');
    expect(await service.pick(ME, { now: NOW + 1 * HOUR })).toBeNull();
    expect((await service.pick(ME, { now: NOW + 2 * HOUR + 1 })).key).toBe('second');
  });

  test('showing nothing is a valid outcome', async () => {
    expect(await pick()).toBeNull();
    expect(state().lastShownAt).toBeUndefined();
  });
});

describe('scheduled cards (the backend-authored tier)', () => {
  const card = (id, extra = {}) => put('homeCards', id, {
    enabled: true, title: 'Try the new widget', body: 'Water, habits, workouts.',
    target: 'widgets_tab', ...extra
  });

  beforeEach(() => {
    rows('homeCards').clear();
    rows('activities').clear();
  });

  test('an override card beats an evergreen tip at the top of the ladder', async () => {
    homeTip('evergreen', { order: 1 });
    expect((await pick()).type).toBe('feature_tip');   // without a card

    put('users', ME, { ...rows('users').get(ME), homePrompt: {} });
    card('widget-launch', { override: true });
    const picked = await pick();
    expect(picked).toMatchObject({ key: 'card:widget-launch', type: 'custom', title: 'Try the new widget' });
  });

  test('bypassInterval shows it even though the user already had a card today', async () => {
    card('widget-launch', { override: true, bypassInterval: true });
    expect((await pick()).key).toBe('card:widget-launch');
    // Same user, twenty minutes later: normally the 2h window would say no.
    put('users', ME, { ...rows('users').get(ME), homePrompt: { lastShownAt: iso(NOW), acks: {} } });
    expect((await service.pick(ME, { now: NOW + 20 * 60 * 1000 })).key).toBe('card:widget-launch');
  });

  test('without bypassInterval the window still applies', async () => {
    card('gentle', { override: true });
    put('users', ME, { ...rows('users').get(ME), homePrompt: { lastShownAt: iso(NOW), acks: {} } });
    expect(await service.pick(ME, { now: NOW + 20 * 60 * 1000 })).toBeNull();
  });

  test('a card that is not overriding sits above the evergreen tips', async () => {
    tip('evergreen', { order: 1, target: 'all_places_map', surfaces: ['home'] });
    card('soft', { override: false });
    expect((await pick()).key).toBe('card:soft');
  });

  test('the window and the cadence are honoured', async () => {
    card('future', { override: true, startsAt: '2099-01-01' });
    expect(await pick()).toBeNull();

    rows('homeCards').clear();
    card('weekly', { override: true, repeatDays: 7 });
    expect((await pick()).key).toBe('card:weekly');
    await service.ack(ME, 'card:weekly', 'skipped', { now: NOW });
    put('users', ME, { ...rows('users').get(ME), homePrompt: { ...state(), lastShownAt: null } });
    expect(await service.pick(ME, { now: NOW + 6 * DAY })).toBeNull();
    expect((await service.pick(ME, { now: NOW + 8 * DAY })).key).toBe('card:weekly');
  });

  test('audience gates on the build, and an old client is not excluded on a guess', async () => {
    const fresh = () => put('users', ME, { ...rows('users').get(ME), homePrompt: {} });
    card('needs-133', { override: true, audience: { minAppVersion: '1.3.3' } });
    expect(await service.pick(ME, { now: NOW }, { appVersion: '1.3.2' })).toBeNull();
    fresh();
    expect((await service.pick(ME, { now: NOW }, { appVersion: '1.3.3' })).key).toBe('card:needs-133');
    fresh();
    // An old build sends no version at all; excluding it would be a guess.
    expect((await service.pick(ME, { now: NOW })).key).toBe('card:needs-133');
  });

  test('disabled is off, and a broken catalog never blanks the slot', async () => {
    card('off', { override: true, enabled: false });
    expect(await pick()).toBeNull();
  });
});

describe('postcard', () => {
  // A place saved this week is both what suppresses the add-place nudge and
  // what the postcard card is about, so these run with one seeded save.
  // A save carrying the user's OWN photo — hasOwnPhotos/ownPhotoUrl are what
  // the create and photo-upload paths stamp.
  const savePlace = (id, extra = {}) => put('places', id, {
    addedBy: ME, name: 'Cafe Lisboa', createdAt: iso(NOW - 2 * DAY),
    photos: ['https://img/1.jpg'], hasOwnPhotos: true, ownPhotoUrl: 'https://img/1.jpg', ...extra
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

  test("the venue's stock photos are not a reason to send a postcard", async () => {
    // A POI save: Google's photo and an Apple Look Around still, none of them
    // the user's. The app never named an upload, so no card.
    savePlace('poi', { hasOwnPhotos: false, ownPhotoUrl: null, photos: ['https://google/stock.jpg'] });
    expect(await pick()).toBeNull();
  });

  test('the card uses their photo, not whichever one sorts first', async () => {
    savePlace('mixed', { photos: ['https://google/stock.jpg', 'https://img/mine.jpg'], ownPhotoUrl: 'https://img/mine.jpg' });
    const card = await pick();
    expect(card.imageUrl).toBe('https://img/mine.jpg');
    expect(card.data.photoUrl).toBe('https://img/mine.jpg');
  });

  test('no photo, no name, deleted, or nothing saved this week → no postcard card', async () => {
    savePlace('nophoto', { photos: [], ownPhotoUrl: null });
    expect(await pick()).toBeNull();
    savePlace('nophoto', { photos: [''], ownPhotoUrl: null });
    expect(await pick()).toBeNull();
    savePlace('nophoto', { name: '' });
    expect(await pick()).toBeNull();
    savePlace('nophoto', { deletedAt: iso(NOW - DAY) });
    expect(await pick()).toBeNull();
    savePlace('nophoto', { createdAt: iso(NOW - 9 * DAY) });
    expect(await pick()).toBeNull(); // a stale save is nothing to write home about
  });

  test('asks at most once a fortnight, and the app pop-up ack silences it too', async () => {
    savePlace('p');
    expect((await pick()).key).toBe('postcard_nudge');
    await service.ack(ME, 'postcard_nudge', 'acted', { now: NOW });
    // Kept fresh so the add-place nudge stays quiet and the only question is
    // whether the postcard card comes back.
    savePlace('p', { createdAt: iso(NOW + 12 * DAY) });
    expect(await service.pick(ME, { now: NOW + 13 * DAY })).toBeNull();
    savePlace('p', { createdAt: iso(NOW + 14 * DAY) });
    expect((await service.pick(ME, { now: NOW + 15 * DAY })).key).toBe('postcard_nudge');
  });

  test('a "Not now" from the app pop-up holds the card only a few days', async () => {
    savePlace('p');
    await service.ack(ME, 'postcard_nudge', 'skipped', { now: NOW });
    savePlace('p', { createdAt: iso(NOW + 2 * DAY) });
    expect(await service.pick(ME, { now: NOW + 2 * DAY })).toBeNull();
    savePlace('p', { createdAt: iso(NOW + 3 * DAY) });
    expect((await service.pick(ME, { now: NOW + 4 * DAY })).key).toBe('postcard_nudge');
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
    put('places', 'p', { addedBy: ME, name: 'Cafe Lisboa', createdAt: iso(NOW - DAY), photos: ['https://img/1.jpg'], hasOwnPhotos: true, ownPhotoUrl: 'https://img/1.jpg' });
    expect((await pick()).key).toBe('postcard_nudge');
    expect(await eligible()).toBe(false);
    expect(await eligible(NOW + 13 * DAY)).toBe(false);
    expect(await eligible(NOW + 15 * DAY)).toBe(true);
  });

  // Wes tapped "Not Now" on a Saturday; the following week a photo he took
  // at the airport got no offer. A no holds days, a yes holds the fortnight.
  test('"Not now" holds three days; being asked and saying yes holds a fortnight', async () => {
    await service.ack(ME, 'postcard_nudge', 'skipped', { now: NOW });
    expect(await eligible(NOW + 2 * DAY)).toBe(false);
    expect(await eligible(NOW + 4 * DAY)).toBe(true);

    await service.ack(ME, 'postcard_nudge', 'acted', { now: NOW });
    expect(await eligible(NOW + 4 * DAY)).toBe(false);
    expect(await eligible(NOW + 15 * DAY)).toBe(true);
  });

  test('the home card honours the same shorter hold after a "Not now"', async () => {
    put('places', 'p', { addedBy: ME, name: 'Cafe Lisboa', createdAt: iso(NOW - DAY), photos: ['https://img/1.jpg'], hasOwnPhotos: true, ownPhotoUrl: 'https://img/1.jpg' });
    await service.ack(ME, 'postcard_nudge', 'skipped', { now: NOW - 4 * DAY });
    expect((await pick()).key).toBe('postcard_nudge');
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

  test('noWidgetData / noVideoViews suppress on evidence', async () => {
    homeTip('widgets', { order: 1, requires: 'noWidgetData' });
    homeTip('moments', { order: 2, requires: 'noVideoViews' });
    put('widgetData', `${ME}_water`, { userId: ME, widgetId: 'water' });
    expect((await pick()).key).toBe('moments');
  });

  // The catalog is a rotation, not a list of one-time announcements: with two
  // tips shown once each, the old rule left the home card silent for good.
  test('tips rotate: never-shown first, then least recent, never the same one twice running', async () => {
    homeTip('a', { order: 1 }); homeTip('b', { order: 2 }); homeTip('c', { order: 3 });
    const at = (h) => service.pick(ME, { now: NOW + h * HOUR });
    expect((await at(0)).key).toBe('a');
    expect((await at(3)).key).toBe('b');
    expect((await at(6)).key).toBe('c');
    // All three seen within the day: the floor holds and nothing shows…
    expect(await at(9)).toBeNull();
    // …until 'a' is a day old, and it comes round first as the least recent.
    expect((await at(25)).key).toBe('a');
    expect((await at(28)).key).toBe('b');
  });

  test('a skip waits three days, trying it waits a week, and the push job\'s tipsSeen no longer mutes a home tip', async () => {
    homeTip('a', { order: 1 }); homeTip('b', { order: 2 });
    put('users', ME, { ...rows('users').get(ME), tipsSeen: ['a'] });   // the push channel already sent it
    expect((await pick()).key).toBe('a');                              // home still rotates it
    await service.ack(ME, 'a', 'skipped', { now: NOW });
    const at = (h) => service.pick(ME, { now: NOW + h * HOUR });
    expect((await at(3)).key).toBe('b');
    await service.ack(ME, 'b', 'acted', { now: NOW + 3 * HOUR });
    expect(await at(48)).toBeNull();                 // a: skipped 2 days ago (needs 3); b: tried (needs 7)
    expect((await at(73)).key).toBe('a');            // a's three days are up
    expect(await at(76)).toBeNull();                 // a just shown; b still inside its week
    expect((await at(172)).key).toBe('b');           // b's week is up
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
    homeTip('t1');
    await pick();
    await service.ack(ME, 't1', 'skipped');
    await service.ack(ME, 't1', 'shown');
    expect(state().acks['t1'].action).toBe('skipped');
  });

  test('dynamic acks older than 90 days are pruned on the next stamp; static keys are kept', async () => {
    seedUser(ME, { homePrompt: { acks: {
      'activity:ancient': { action: 'skipped', at: iso(NOW - 100 * DAY) },
      'moment:recent': { action: 'skipped', at: iso(NOW - 10 * DAY) },
      'favcoins_balance': { action: 'skipped', at: iso(NOW - 400 * DAY) }
    } } });
    homeTip('t1');
    await pick();
    expect(Object.keys(state().acks).sort()).toEqual(['favcoins_balance', 'moment:recent', 't1']);
  });

  test('a source that throws does not blank the card slot', async () => {
    const spy = jest.spyOn(service, 'postcardCard').mockRejectedValue(new Error('index missing'));
    const err = jest.spyOn(console, 'error').mockImplementation(() => {});
    put('piggyBanks', ME, { confirmedCoins: 5 });
    expect((await pick()).key).toBe('favcoins_balance');
    spy.mockRestore(); err.mockRestore();
  });
});

describe('presentation', () => {
  test('every organic card covers the screen; a scheduled card may opt into inline', async () => {
    homeTip('t1');
    expect((await pick()).presentation).toBe('overlay');
    put('users', ME, { ...rows('users').get(ME), homePrompt: {} });
    put('homeCards', 'quiet', { enabled: true, title: 'Quiet', target: 'widgets_tab', override: true, presentation: 'inline' });
    expect((await pick()).presentation).toBe('inline');
  });
});
