// Can I Pet Dat Dog (2026-10-22): dog cards, Dog Park posts, pets and their
// milestone pushes, who sees what, reports, Daily Dog picking and sending,
// and what account deletion takes with it.
const { FakeFirestore, FakeFieldValue } = require('../../__fixtures__/fakeFirestore');

const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => {
  const { FakeFieldValue: FV } = require('../../__fixtures__/fakeFirestore');
  return {
    getFirestore: () => mockDb,
    FieldValue: FV,
    admin: { firestore: { FieldValue: FV, FieldPath: { documentId: () => '__name__' } } }
  };
});
const mockPushes = [];
jest.mock('../notifyQuiet', () => ({ sendInBackground: (to, payload) => mockPushes.push({ to, ...payload }) }));
const mockSent = [];
jest.mock('../notificationService', () => ({ sendToUser: async (to, payload) => { mockSent.push({ to, ...payload }); } }));
const mockAlerts = [];
jest.mock('../adminAlerts', () => ({ alertAdmin: async (a) => { mockAlerts.push(a); return true; } }));
jest.mock('../storage', () => ({ deleteImage: async () => {} }));

process.env.FIREBASE_STORAGE_BUCKET = 'test-bucket';
const IMG = (n) => `https://firebasestorage.googleapis.com/v0/b/test-bucket/o/${n}.jpg?alt=media`;

const dogs = require('../dogParkService');
const s = require('../dogPark/shared');
const posts = require('../dogPark/posts');
const daily = require('../dogPark/daily');
const LINES = require('../../config/dogLines');

const OLD = '2025-01-01T00:00:00.000Z'; // a trusted (week-old) account
const users = {
  wes: { displayName: 'Wes', createdAt: OLD, following: ['ana', 'joe'], blockedBy: ['bob'] }, // bob blocked wes (denormalized both ways)
  ana: { displayName: 'Ana', createdAt: OLD },
  joe: { displayName: 'Joe', createdAt: OLD },
  bob: { displayName: 'Bob', createdAt: OLD, blockedUsers: ['wes'] },
  tess: { displayName: 'App Review', createdAt: OLD, isTestAccount: true },
  r1: { displayName: 'R1', createdAt: OLD }, r2: { displayName: 'R2', createdAt: OLD }, r3: { displayName: 'R3', createdAt: OLD },
  newbie: { displayName: 'New', createdAt: new Date().toISOString() }
};
const code = async (p) => { try { await p; return null; } catch (e) { return e.code; } };

beforeAll(async () => {
  for (const [id, data] of Object.entries(users)) await mockDb.collection('users').doc(id).set(data);
  for (const id of Object.keys(users)) await dogs.join(id);
});
beforeEach(() => { mockPushes.length = 0; mockSent.length = 0; mockAlerts.length = 0; });

describe('dog cards', () => {
  test('are checked, owned, and listed for their owner', async () => {
    expect(await code(dogs.createDog('wes', { name: '' }))).toBe('invalid_name');
    expect(await code(dogs.createDog('wes', { name: 'Biscuit', birthday: '2099-01-01' }))).toBe('invalid_date');
    expect(await code(dogs.createDog('wes', { name: 'Biscuit', photoUrl: 'https://evil.example/x.jpg' }))).toBe('invalid_image');
    const { dog } = await dogs.createDog('wes', { name: ' Biscuit ', breed: 'Corgi', birthday: '2021-04-09', photoUrl: IMG('b') });
    expect(dog).toMatchObject({ name: 'Biscuit', breed: 'Corgi', birthday: '2021-04-09', ownerName: 'Wes', postCount: 0 });
    expect(await code(dogs.updateDog('ana', dog.id, { name: 'Mine now' }))).toBe('not_yours');
    const edited = await dogs.updateDog('wes', dog.id, { personality: 'Professional sock thief' });
    expect(edited.dog).toMatchObject({ name: 'Biscuit', personality: 'Professional sock thief' });
    const me = await dogs.me('wes', { client: { version: '1.4.1', build: null } });
    expect(me).toMatchObject({ member: true, minVersionOk: true });
    expect(me.dogs.map((d) => d.name)).toEqual(['Biscuit']);
    expect((await dogs.me('wes', { client: { version: '1.4.0' } })).minVersionOk).toBe(false);
  });
});

describe('the Dog Park', () => {
  let biscuit;
  beforeAll(async () => {
    biscuit = (await dogs.createDog('wes', { name: 'Mochi', breed: 'Shiba Inu' })).dog;
  });

  test('a photo post needs our upload and only your own dogs', async () => {
    expect(await code(dogs.createPhotoPost('wes', { photoUrl: 'https://evil.example/x.jpg' }))).toBe('invalid_image');
    const anaDog = (await dogs.createDog('ana', { name: 'Pip' })).dog;
    expect(await code(dogs.createPhotoPost('wes', { photoUrl: IMG('p'), dogIds: [anaDog.id] }))).toBe('invalid_dog');
    const { post } = await dogs.createPhotoPost('wes', { photoUrl: IMG('p'), caption: 'Zoomies', dogIds: [biscuit.id] });
    expect(post).toMatchObject({ kind: 'photo', caption: 'Zoomies', petCount: 0, mine: true, dogs: [{ id: biscuit.id, name: 'Mochi' }] });
    expect(post.shareUrl).toBe(`https://api.favcircles.com/app/widget/dogs?post=${post.id}`);
    expect((await dogs.getDog('ana', biscuit.id)).dog.postCount).toBe(1);
  });

  test('joining is required to post, pet and read the feed', async () => {
    await mockDb.collection('users').doc('lurker').set({ displayName: 'Lurker', createdAt: OLD });
    expect(await code(dogs.feed('lurker', {}))).toBe('not_member');
    expect(await code(dogs.createPhotoPost('lurker', { photoUrl: IMG('l') }))).toBe('not_member');
  });

  test('pets toggle once per person and tell the author at milestones, each once', async () => {
    const { post } = await dogs.createPhotoPost('wes', { photoUrl: IMG('m'), dogIds: [biscuit.id] });
    const first = await dogs.togglePet('ana', post.id);
    expect(first.post).toMatchObject({ petCount: 1, iPetted: true });
    expect(mockPushes).toEqual([expect.objectContaining({ to: 'wes', type: 'dog_pet', title: '🐾 Ana petted Mochi!', data: { postId: post.id } })]);
    const undo = await dogs.togglePet('ana', post.id);
    expect(undo.post).toMatchObject({ petCount: 0, iPetted: false });
    await dogs.togglePet('ana', post.id); // back to 1: milestone 1 was already sent
    expect(mockPushes).toHaveLength(1);
    await dogs.togglePet('wes', post.id); // the author petting their own post: no push
    expect(mockPushes).toHaveLength(1);
  });

  test('milestone pushes: which counts, at most one per post per day', () => {
    const today = '2026-10-22';
    expect(posts.petPush({ petCount: 5, dogs: [{ name: 'Mochi' }] }, { petterName: 'Ana', today }).title).toBe('🐾 Mochi got petted 5 times!');
    expect(posts.petPush({ petCount: 6, dogs: [] }, { petterName: 'Ana', today })).toBeNull();
    expect(posts.petPush({ petCount: 10, petPushDay: today }, { petterName: 'Ana', today })).toBeNull();
    expect(posts.petPush({ petCount: 10, petMilestonesSent: [10] }, { petterName: 'Ana', today })).toBeNull();
    expect(s.milestoneFor(3000)).toBe(3000);
    expect(s.milestoneFor(1500)).toBeNull();
    expect(s.dogNames([{ name: 'A' }, { name: 'B' }, { name: 'C' }])).toBe('A, B and C');
  });

  test('comments tell the author (with a cooldown) and count', async () => {
    const { post } = await dogs.createPhotoPost('wes', { photoUrl: IMG('c'), dogIds: [biscuit.id] });
    const added = await dogs.addComment('ana', post.id, { text: 'Who is a good boy' });
    expect(added.post.commentCount).toBe(1);
    expect(mockPushes.filter((p) => p.type === 'dog_comment')).toHaveLength(1);
    await dogs.addComment('joe', post.id, { text: 'Me too' });
    expect(mockPushes.filter((p) => p.type === 'dog_comment')).toHaveLength(1); // cooldown
    const { comments } = await dogs.listComments('wes', post.id);
    expect(comments.map((c) => c.text).sort()).toEqual(['Me too', 'Who is a good boy']); // same millisecond: order is the db's
    const anas = comments.find((c) => c.authorId === 'ana');
    expect(await code(dogs.deleteComment('joe', post.id, anas.id))).toBe('not_yours');
    await dogs.deleteComment('wes', post.id, anas.id); // the post's author may
    expect((await dogs.getPost('wes', post.id)).post.commentCount).toBe(1);
  });

  test('feeds hide blocked people, test accounts and unfinished uploads', async () => {
    const mine = (await dogs.createPhotoPost('wes', { photoUrl: IMG('w') })).post;
    const bobs = (await dogs.createPhotoPost('bob', { photoUrl: IMG('bob') })).post; // bob blocked wes
    const tests = (await dogs.createPhotoPost('tess', { photoUrl: IMG('t') })).post;
    const anas = (await dogs.createPhotoPost('ana', { photoUrl: IMG('a') })).post;
    await mockDb.collection('dogPosts').doc('uploading1').set({ authorId: 'ana', kind: 'video', status: 'uploading', createdAt: new Date().toISOString() });
    const ids = (await dogs.feed('wes', { tab: 'today' })).posts.map((p) => p.id);
    expect(ids).toEqual(expect.arrayContaining([mine.id, anas.id]));
    expect(ids).not.toContain(bobs.id);
    expect(ids).not.toContain(tests.id);
    expect(ids).not.toContain('uploading1');
    expect(await code(dogs.getPost('wes', bobs.id))).toBe('not_found');
    const following = (await dogs.feed('wes', { tab: 'following' })).posts;
    expect(following.every((p) => ['ana', 'joe'].includes(p.authorId))).toBe(true);
    expect(following.map((p) => p.id)).toContain(anas.id);
    await dogs.togglePet('joe', anas.id);
    await dogs.togglePet('wes', anas.id);
    const top = (await dogs.feed('wes', { tab: 'top' })).posts;
    expect(top[0].id).toBe(anas.id);
    expect(await code(dogs.feed('wes', { tab: 'nope' }))).toBe('invalid_tab');
  });

  test('three trusted reports hide a post from everyone but its author', async () => {
    const { post } = await dogs.createPhotoPost('ana', { photoUrl: IMG('r') });
    await dogs.reportPost('newbie', post.id, { reason: 'spam' }); // a new account doesn't count toward hiding
    await dogs.reportPost('r1', post.id, { reason: 'spam' });
    expect((await dogs.reportPost('r1', post.id, { reason: 'spam' })).alreadyReported).toBe(true);
    await dogs.reportPost('r2', post.id, { reason: 'spam' });
    expect(await code(dogs.getPost('joe', post.id))).toBeNull(); // 2 trusted: still up
    await dogs.reportPost('r3', post.id, { reason: 'spam' });
    expect(await code(dogs.getPost('joe', post.id))).toBe('not_found');
    expect((await dogs.getPost('ana', post.id)).post.id).toBe(post.id);
    expect(mockAlerts.some((a) => /AUTO-HIDDEN/.test(a.title))).toBe(true);
    expect(await code(dogs.reportPost('ana', post.id, {}))).toBe('own_post');
  });

  test('only the author (or an admin) deletes; pets and comments go with it', async () => {
    const { post } = await dogs.createPhotoPost('wes', { photoUrl: IMG('d'), dogIds: [biscuit.id] });
    await dogs.togglePet('ana', post.id);
    await dogs.addComment('ana', post.id, { text: 'cute' });
    expect(await code(dogs.deletePost('ana', post.id))).toBe('not_yours');
    const before = (await dogs.getDog('wes', biscuit.id)).dog.postCount;
    await dogs.deletePost('wes', post.id);
    expect(mockDb.rows('dogPets').has(`${post.id}_ana`)).toBe(false);
    expect([...mockDb.rows('dogComments').values()].some((c) => c.postId === post.id)).toBe(false);
    expect((await dogs.getDog('wes', biscuit.id)).dog.postCount).toBe(before - 1);
  });
});

describe('Daily Dog', () => {
  test('settings are checked: 1–3 times a day', async () => {
    expect(await code(dogs.updateSettings('joe', { times: ['08:00', '12:00', '15:00', '18:00'] }))).toBe('bad_time');
    expect(await code(dogs.updateSettings('joe', { times: ['25:00'] }))).toBe('bad_time');
    const { prefs } = await dogs.updateSettings('joe', { enabled: true, times: ['18:00', '08:00'] });
    expect(prefs).toEqual({ enabled: true, times: ['08:00', '18:00'] });
    expect(daily.prefsOf({})).toEqual({ enabled: false, times: ['09:00'] });
  });

  test('a slot is due inside its hour on the person’s own clock', () => {
    const user = { dogPrefs: { enabled: true, times: ['09:00'] }, notificationPreferences: { timezone: 'America/New_York' } };
    expect(daily.dueSlot(user, new Date('2026-10-22T13:10:00Z'))).toBe('09:00'); // 9:10 AM EDT
    expect(daily.dueSlot(user, new Date('2026-10-22T14:10:00Z'))).toBeNull();
    expect(daily.dueSlot({ ...user, dogPrefs: { enabled: false } }, new Date('2026-10-22T13:10:00Z'))).toBeNull();
  });

  test('lines: unseen first; the line of the day is stable', () => {
    const lines = [{ id: 'a' }, { id: 'b' }, { id: 'c' }];
    expect(daily.pickLine(['a', 'b'], { lines, random: () => 0 }).id).toBe('c');
    expect(daily.pickLine(['a', 'b', 'c'], { lines, random: () => 0 }).id).toBe('a');
    expect(daily.lineOfTheDay('2026-10-22')).toEqual(daily.lineOfTheDay('2026-10-22'));
    expect(LINES).toHaveLength(150);
    expect(new Set(LINES.map((l) => l.id)).size).toBe(150);
    expect(LINES.every((l) => ['joke', 'line', 'fact'].includes(l.kind) && l.text.length > 10)).toBe(true);
  });

  test('Dog of the Day is yesterday’s most-petted visible post, picked once', async () => {
    const rows = [
      { id: 'x', data: { petCount: 3, createdAt: '2026-10-21T15:00:00Z' } },
      { id: 'y', data: { petCount: 5, createdAt: '2026-10-21T16:00:00Z' } },
      { id: 'z', data: { petCount: 5, createdAt: '2026-10-21T14:00:00Z' } },
      { id: 'n', data: { petCount: 0, createdAt: '2026-10-21T13:00:00Z' } }
    ];
    expect(daily.pickTopPost(rows).id).toBe('z'); // tie → earliest
    expect(daily.pickTopPost([rows[3]])).toBeNull(); // nobody petted anything
    expect(daily.previousDay('2026-11-01')).toBe('2026-10-31');

    // Dates away from the real today (the widget's own reads pick today's)
    const at = '2026-10-01T16:00:00.000Z'; // noon in Charlotte, Oct 1
    const base = { kind: 'photo', status: 'ready', photoUrl: IMG('dd'), dogs: [{ id: 'd1', name: 'Rex' }], createdAt: at };
    await mockDb.collection('dogPosts').doc('dotd_win').set({ ...base, authorId: 'joe', petCount: 9 });
    await mockDb.collection('dogPosts').doc('dotd_test').set({ ...base, authorId: 'tess', petCount: 50 });
    await mockDb.collection('dogPosts').doc('dotd_hidden').set({ ...base, authorId: 'ana', petCount: 40, moderationStatus: 'under_review' });
    const pick = await daily.ensureDogOfTheDay('2026-10-02');
    expect(pick).toMatchObject({ postId: 'dotd_win', petCount: 9 });
    await mockDb.collection('dogPosts').doc('dotd_win').update({ petCount: 1 });
    expect((await daily.ensureDogOfTheDay('2026-10-02')).postId).toBe('dotd_win'); // stored, not re-picked
    const { item } = await dogs.getDaily('wes', 'dotd_2026-10-02');
    expect(item).toMatchObject({ kind: 'dogOfTheDay', post: { id: 'dotd_win' } });
    expect(item.text).toBe('🏆 Rex got petted 9 times yesterday. Give one more?');
    expect(await code(dogs.getDaily('wes', 'dotd_2099-01-01'))).toBe('not_found');
    const line = await dogs.getDaily('wes', `line_${LINES[0].id}`);
    expect(line.item).toMatchObject({ kind: LINES[0].kind, text: LINES[0].text, shareUrl: `https://api.favcircles.com/app/widget/dogs?daily=line_${LINES[0].id}` });
  });

  test('a slot sends the Dog of the Day once, then lines; the slot id is the lock', async () => {
    await mockDb.collection('users').doc('dd').set({
      displayName: 'Daily', createdAt: OLD, dogPrefs: { enabled: true, times: ['09:00', '18:00'] },
      notificationPreferences: { timezone: 'America/New_York' }
    });
    const morning = new Date('2026-10-02T13:05:00Z'); // 9:05 AM EDT
    const r1 = await dogs.runDailyDue({ userId: 'dd', now: morning });
    expect(r1).toMatchObject({ due: 1, sent: 1 });
    expect(mockSent[0]).toMatchObject({ to: 'dd', type: 'daily_dog', title: '🏆 Dog of the Day', data: { dailyId: 'dotd_2026-10-02', postId: 'dotd_win' } });
    const again = await dogs.runDailyDue({ userId: 'dd', now: new Date('2026-10-02T13:20:00Z') });
    expect(again.sent).toBe(0); // the 9:00 slot already went
    mockSent.length = 0;
    await dogs.runDailyDue({ userId: 'dd', now: new Date('2026-10-02T22:05:00Z') });
    expect(mockSent[0].data.dailyId).toMatch(/^line_/);
    const listed = await dogs.listDaily('dd');
    expect(listed.items.map((i) => i.kind)[1]).toBe('dogOfTheDay');
    expect(listed.items).toHaveLength(2);
    const me = await dogs.me('dd', { now: new Date('2026-10-02T22:30:00Z') });
    expect(me.today.id).toBe(mockSent[0].data.dailyId); // the latest thing sent today
  });

  test('someone who blocked the Dog of the Day’s author gets a line instead', async () => {
    await mockDb.collection('users').doc('blocker').set({
      displayName: 'B', createdAt: OLD, blockedUsers: ['joe'],
      dogPrefs: { enabled: true, times: ['09:00'] }, notificationPreferences: { timezone: 'America/New_York' }
    });
    await dogs.runDailyDue({ userId: 'blocker', now: new Date('2026-10-02T13:05:00Z') });
    expect(mockSent[0].data.dailyId).toMatch(/^line_/);
  });
});

describe('blocking from a post', () => {
  test('writes the block both ways and hides their posts', async () => {
    const { post } = await dogs.createPhotoPost('joe', { photoUrl: IMG('j') });
    await dogs.blockAuthor('ana', 'joe');
    expect((await mockDb.collection('users').doc('ana').get()).data().blockedUsers).toContain('joe');
    expect((await mockDb.collection('users').doc('joe').get()).data().blockedBy).toContain('ana');
    expect(await code(dogs.getPost('ana', post.id))).toBe('not_found');
    expect((await dogs.blockAuthor('ana', 'joe')).ok).toBe(true); // already blocked: fine
    expect(await code(dogs.blockAuthor('ana', 'ana'))).toBe('self_block');
  });
});

describe('account deletion', () => {
  test('takes their dogs, posts, pets, comments and sends, and fixes others’ counts', async () => {
    await mockDb.collection('users').doc('gone').set({ displayName: 'Gone', createdAt: OLD });
    await dogs.join('gone');
    const dog = (await dogs.createDog('gone', { name: 'Ghost' })).dog;
    const theirs = (await dogs.createPhotoPost('gone', { photoUrl: IMG('g'), dogIds: [dog.id] })).post;
    const others = (await dogs.createPhotoPost('r1', { photoUrl: IMG('o') })).post;
    await dogs.togglePet('gone', others.id);
    await dogs.addComment('gone', others.id, { text: 'bye' });
    await dogs.togglePet('r2', theirs.id);
    await dogs.addComment('r2', theirs.id, { text: 'hi' });
    await mockDb.collection('dogDailySends').doc('gone_2026-10-02_0900').set({ userId: 'gone', sentAt: '2026-10-22T13:00:00Z' });

    const { deleteAccount } = require('../accountDeletionService');
    const storage = { bucket: () => ({ deleteFiles: async () => {} }) };
    const auth = { deleteUser: async () => {} };
    const out = await deleteAccount('gone', { db: mockDb, auth, storage });
    expect(out.deleted).toBe(true);
    expect(mockDb.rows('dogProfiles').has(dog.id)).toBe(false);
    expect(mockDb.rows('dogPosts').has(theirs.id)).toBe(false);
    expect([...mockDb.rows('dogPets').values()].some((p) => p.userId === 'gone' || p.postId === theirs.id)).toBe(false);
    expect([...mockDb.rows('dogComments').values()].some((c) => c.authorId === 'gone' || c.postId === theirs.id)).toBe(false);
    expect(mockDb.rows('dogDailySends').has('gone_2026-10-02_0900')).toBe(false);
    const after = (await mockDb.collection('dogPosts').doc(others.id).get()).data();
    expect(after).toMatchObject({ petCount: 0, commentCount: 0 });
  });
});

void FakeFieldValue;
