// Scan Actions (Wes, 2026-11-11): a QR that saves a place, a set of places,
// or hands a store to its owner. What may go in a QR, what a scanner sees,
// and that finishing one saves each place once.
const { FakeFirestore, FakeFieldValue } = require('../../__fixtures__/fakeFirestore');
const mockDb = new FakeFirestore({ namespaced: true });
jest.mock('../../config/firebase', () => ({
  getFirestore: () => mockDb,
  getStorage: () => ({ bucket: () => ({}) }),
  FieldValue: require('../../__fixtures__/fakeFirestore').FakeFieldValue
}));

const { ScanActionService, normalizeCode, shareVerdict } = require('../scanActionService');

const put = (col, id, data) => mockDb.collection(col).doc(id).set(data);
const get = async (col, id) => (await mockDb.collection(col).doc(id).get()).data();
const NOW = Date.parse('2026-11-11T18:00:00Z');
const wes = { uid: 'wes', email: 'wes@example.com' };
const friend = { uid: 'friend', email: 'f@example.com' };
const ctxFor = (uid, connections = []) => ({ viewerId: uid, connections: new Set(connections), following: new Set(), innerCircleOwners: new Set(), innerCircleLists: new Map() });

let saves;
let approvals;
const makeService = (overrides = {}) => new ScanActionService({
  db: mockDb,
  now: () => NOW,
  buildViewerContext: async (uid) => ctxFor(uid),
  defaultCircle: async () => ({ id: 'friendFav' }),
  savePlace: async (user, body) => {
    saves.push({ user: user.uid, body });
    const dup = [...mockDb.rows('places').values()].find((p) => p.addedBy === user.uid && p.globalPlaceId === body.globalPlaceId && p.deletedAt === null);
    if (dup) return { status: 400, payload: { code: 'DUPLICATE_PLACE', existingPlaceId: 'old', existingCircleId: dup.circleId } };
    const id = `new_${saves.length}`;
    await put('places', id, { addedBy: user.uid, globalPlaceId: body.globalPlaceId, circleId: body.circleId, deletedAt: null });
    return { status: 201, payload: { place: { id } } };
  },
  approveClaim: async (claimId, approver) => { approvals.push({ claimId, approver }); return { data: { venueId: 'vNew' } }; },
  ...overrides
});

beforeEach(async () => {
  for (const name of ['places', 'circles', 'globalPlaces', 'scanActions', 'users', 'stickerVenues', 'venueClaimRequests']) mockDb.rows(name).clear();
  saves = [];
  approvals = [];
  await put('users', 'wes', { displayName: 'Wes', profilePicture: 'https://x/wes.jpg' });
  await put('circles', 'brunch', { owner: 'wes', privacy: 'public', name: 'Brunch' });
  await put('circles', 'secret', { owner: 'wes', privacy: 'private', name: 'Secret' });
  await put('globalPlaces', 'gOver', { name: 'Over Easy', address: '1 Main St, Chandler', category: 'restaurant', applePlaceId: 'I123', location: { type: 'Point', coordinates: [-111.84, 33.30] } });
  await put('globalPlaces', 'gCafe', { name: 'Cafe', address: '2 Main St', category: 'cafe', googlePlaceId: 'G1', location: { type: 'Point', coordinates: [-111.84, 33.31] } });
  await put('globalPlaces', 'gHome', { name: 'Mom’s house', address: '9 Elm St', category: 'other' });
  await put('globalPlaces', 'gPending', { name: 'New spot', address: '3 Main St', approvalStatus: 'pending', googlePlaceId: 'G2' });
  await put('places', 'sOver', { addedBy: 'wes', circleId: 'brunch', globalPlaceId: 'gOver', name: 'Over Easy', privateNotes: 'secret note', deletedAt: null, applePlaceId: 'I123' });
  await put('places', 'sCafe', { addedBy: 'wes', circleId: 'secret', globalPlaceId: 'gCafe', name: 'Cafe', deletedAt: null, googlePlaceId: 'G1' });
  await put('places', 'sHome', { addedBy: 'wes', circleId: 'secret', globalPlaceId: 'gHome', name: 'Mom’s house', deletedAt: null });
  await put('places', 'sHomePublic', { addedBy: 'wes', circleId: 'brunch', globalPlaceId: 'gHome', name: 'Mom’s house', deletedAt: null });
  await put('places', 'sPending', { addedBy: 'wes', circleId: 'brunch', globalPlaceId: 'gPending', name: 'New spot', deletedAt: null });
  await put('places', 'sOthers', { addedBy: 'stranger', circleId: 'theirs', globalPlaceId: 'gHome', name: 'Home', deletedAt: null, privacy: 'private' });
});

describe('codes', () => {
  test('codes are 8 easy-to-read characters; guide slugs are codes too', () => {
    expect(normalizeCode('ab7k2mqz')).toBe('AB7K2MQZ');
    expect(normalizeCode('AB0K2MQZ')).toBeNull(); // no zero
    expect(normalizeCode('Share-A-Place')).toBe('share-a-place');
    expect(normalizeCode('../etc')).toBeNull();
  });
});

describe('what may go in a QR', () => {
  test('a known business is shareable even from a private circle; a private home is not', async () => {
    const svc = makeService();
    const made = await svc.create(wes, { kind: 'placeSet', title: 'Brunch', saveIds: ['sOver', 'sCafe', 'sHome', 'sPending', 'sOthers'] });
    expect(made.places.map((p) => p.globalPlaceId)).toEqual(['gOver', 'gCafe']);
    expect(made.leftOutPrivate).toBe(1); // Mom's house in the private circle
    expect(made.leftOutHidden).toBe(2); // pending venue + someone else's private save
    expect(made.url).toMatch(/\/q\/[2-9A-Z]{8}$/);
    const stored = await get('scanActions', made.code);
    expect(JSON.stringify(stored)).not.toContain('secret note');
    expect(stored.expiresAt).toBe('2026-12-11T18:00:00.000Z');
  });

  test('a home saved in a public circle may go (its saver chose to show it)', () => {
    const verdict = shareVerdict({ save: { addedBy: 'wes', deletedAt: null }, circle: { owner: 'wes', privacy: 'public' }, venue: {}, creatorId: 'wes', ctx: ctxFor('wes') });
    expect(verdict).toBe('ok');
  });

  test('one private place alone says so', async () => {
    await expect(makeService().create(wes, { kind: 'place', saveId: 'sHome' })).rejects.toMatchObject({ status: 400, code: 'all_private' });
  });

  test('store setup codes are staff-only', async () => {
    await put('stickerVenues', 'v1', { venueName: 'Sal’s', globalPlaceId: 'gCafe' });
    await expect(makeService().create(wes, { kind: 'storeSetup', venueId: 'v1' })).rejects.toMatchObject({ status: 403 });
  });
});

describe('scanning', () => {
  test('the scanner sees the venue and which places they already have', async () => {
    const svc = makeService();
    const { code } = await svc.create(wes, { kind: 'placeSet', title: 'Brunch', saveIds: ['sOver', 'sCafe'] });
    await put('places', 'fCafe', { addedBy: 'friend', circleId: 'friendFav', globalPlaceId: 'gCafe', deletedAt: null });
    const seen = await svc.resolve(code.toLowerCase(), 'friend');
    expect(seen.creator.displayName).toBe('Wes');
    expect(seen.places).toHaveLength(2);
    expect(seen.places.find((p) => p.globalPlaceId === 'gCafe')).toMatchObject({ alreadySaved: true, savedPlaceId: 'fCafe' });
    expect(seen.places.find((p) => p.globalPlaceId === 'gOver')).toMatchObject({ alreadySaved: false, name: 'Over Easy', location: { lat: 33.30, lng: -111.84 } });
  });

  test('a venue held for approval after the QR was made drops out', async () => {
    const svc = makeService();
    const { code } = await svc.create(wes, { kind: 'placeSet', title: 'x', saveIds: ['sOver', 'sCafe'] });
    await mockDb.collection('globalPlaces').doc('gCafe').update({ approvalStatus: 'rejected' });
    const seen = await svc.resolve(code, null);
    expect(seen.places.map((p) => p.globalPlaceId)).toEqual(['gOver']);
  });

  test('guide codes resolve without a document', async () => {
    const seen = await makeService().resolve('see-widgets', null);
    expect(seen).toMatchObject({ kind: 'guide', guide: { appGuide: 'widgets' } });
    const store = await makeService().resolve('store-setup', null);
    expect(store).toMatchObject({ kind: 'storeSetup', guide: { appGuide: 'storeSetup' }, store: null });
  });
});

describe('finishing', () => {
  test('saves the picked places into the chosen circle, skipping ones already saved, crediting the creator', async () => {
    const svc = makeService();
    const { code } = await svc.create(wes, { kind: 'placeSet', title: 'Brunch', saveIds: ['sOver', 'sCafe'] });
    await put('places', 'fCafe', { addedBy: 'friend', circleId: 'friendFav', globalPlaceId: 'gCafe', deletedAt: null });
    const done = await svc.complete(code, friend, { circleId: 'friendBrunch', requestId: 'req-12345678' });
    expect(done.saved.map((s) => s.globalPlaceId)).toEqual(['gOver']);
    expect(done.alreadySaved.map((s) => s.globalPlaceId)).toEqual(['gCafe']);
    const body = saves[0].body;
    expect(body).toMatchObject({ circleId: 'friendBrunch', globalPlaceId: 'gOver', name: 'Over Easy', refUserId: 'wes', applePlaceId: 'I123',
      location: { type: 'Point', coordinates: [-111.84, 33.30] } });
    expect(body.clientSaveId).toMatch(/^scan-[0-9a-f]{40}$/);
    expect(body.privateNotes).toBeUndefined();
  });

  test('only the ticked places; no circle picked = the default (Want to Try)', async () => {
    const svc = makeService();
    const { code } = await svc.create(wes, { kind: 'placeSet', title: 'x', saveIds: ['sOver', 'sCafe'] });
    const done = await svc.complete(code, friend, { globalPlaceIds: ['gCafe'] });
    expect(done.circleId).toBe('friendFav');
    expect(saves.map((s) => s.body.globalPlaceId)).toEqual(['gCafe']);
  });

  test('an expired QR saves nothing', async () => {
    const { code } = await makeService().create(wes, { kind: 'place', saveId: 'sOver' });
    const later = makeService({ now: () => NOW + 31 * 24 * 60 * 60 * 1000 });
    await expect(later.complete(code, friend, {})).rejects.toMatchObject({ status: 410, code: 'expired' });
    expect(saves).toHaveLength(0);
  });
});

describe('store setup', () => {
  const staff = { uid: 'staff', email: 'staff@favcircles.com', isSuperUser: true };
  const owner = { uid: 'sal', email: 'sal@example.com', displayName: 'Sal' };

  test('the first redeemer gets a pre-approved claim; nobody else can use it', async () => {
    await put('stickerVenues', 'v1', { venueName: 'Sal’s', globalPlaceId: 'gCafe', placeAddress: '2 Main St' });
    const svc = makeService();
    const { code, expiresAt } = await svc.create(staff, { kind: 'storeSetup', venueId: 'v1' });
    expect(expiresAt).toBe('2026-11-25T18:00:00.000Z');

    const done = await svc.complete(code, owner, { contactName: 'Sal', contactPhone: '555' });
    expect(done).toMatchObject({ kind: 'storeSetup', venueId: 'vNew', alreadyRedeemed: false });
    expect(approvals).toEqual([{ claimId: 'v1_sal', approver: { approverId: 'staff', approverEmail: 'staff@favcircles.com' } }]);
    const claim = await get('venueClaimRequests', 'v1_sal');
    expect(claim).toMatchObject({ venueId: 'v1', userId: 'sal', preApprovedBy: 'staff', scanCode: code, contactPhone: '555' });

    expect(await svc.complete(code, owner, {})).toMatchObject({ alreadyRedeemed: true });
    await expect(svc.complete(code, friend, {})).rejects.toMatchObject({ status: 409, code: 'already_redeemed' });
    expect(approvals).toHaveLength(1);
  });

  test('a failed approval gives the code back', async () => {
    await put('stickerVenues', 'v1', { venueName: 'Sal’s' });
    const failing = makeService({ approveClaim: async () => { throw Object.assign(new Error('Venue already has an owner'), { status: 409, code: 'has_owner' }); } });
    const { code } = await failing.create(staff, { kind: 'storeSetup', venueId: 'v1' });
    await expect(failing.complete(code, owner, {})).rejects.toMatchObject({ code: 'has_owner' });
    expect((await get('scanActions', code)).redeemedBy).toBeNull();
  });

  test('an owned store can’t get a setup code', async () => {
    await put('stickerVenues', 'v1', { venueName: 'Sal’s', ownerUserId: 'someone' });
    await expect(makeService().create(staff, { kind: 'storeSetup', venueId: 'v1' })).rejects.toMatchObject({ status: 409, code: 'store_owned' });
  });
});

void FakeFieldValue;

describe('a place page showing the venue itself', () => {
  test('falls back to the venue id when the id names no save', async () => {
    const made = await makeService().create(wes, { kind: 'place', saveId: 'gCafe', globalPlaceId: 'gCafe' });
    expect(made.places.map((p) => p.globalPlaceId)).toEqual(['gCafe']);
  });

  test('never falls back past a private save', async () => {
    await expect(makeService().create(wes, { kind: 'place', saveId: 'sHome', globalPlaceId: 'gHome' }))
      .rejects.toMatchObject({ code: 'all_private' });
  });
});

describe('guide catalog', () => {
  test('every guide id is letters and hyphens and can never read as a made code', () => {
    const { SCAN_GUIDES } = require('../../config/scanGuides');
    for (const guide of SCAN_GUIDES) {
      expect(guide.id).toMatch(/^[a-z][a-z-]{2,39}$/);
      expect(/^[A-Z]{8}$/.test(guide.id.toUpperCase()) && !guide.id.includes('-')).toBe(false);
      expect(normalizeCode(guide.id)).toBe(guide.id);
    }
  });
});
