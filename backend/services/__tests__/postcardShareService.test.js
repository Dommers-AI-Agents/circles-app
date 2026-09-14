// Public postcard links: validation and the token shape.
const stores = {};
const store = (name) => (stores[name] = stores[name] || new Map());
const mockDb = {
  collection: (col) => ({
    doc: (id) => ({
      get: async () => ({ exists: store(col).has(id), data: () => store(col).get(id) }),
      set: async (value) => { store(col).set(id, value); },
      update: async (value) => { store(col).set(id, { ...store(col).get(id), ...value }); }
    })
  })
};
jest.mock('../../config/firebase', () => ({ getFirestore: () => mockDb }));

const service = require('../postcardShareService');

describe('postcardShareService', () => {
  const bucket = 'test-bucket';
  beforeAll(() => { process.env.FIREBASE_STORAGE_BUCKET = bucket; });
  const good = `https://firebasestorage.googleapis.com/v0/b/${bucket}/o/pc.jpg?alt=media&token=x`;

  test('creates an unguessable link and reads it back', async () => {
    const share = await service.create({ senderId: 'u1', senderName: 'Wes', imageUrl: good, message: ' hi ', placeRef: { name: 'Paris' } });
    expect(share.url).toBe(`https://favcircles.com/postcard/${share.token}`);
    expect(service.TOKEN_RE.test(share.token)).toBe(true);
    const read = await service.get(share.token);
    expect(read.message).toBe('hi');
    expect(read.placeName).toBe('Paris');
    expect(read.senderName).toBe('Wes');
  });

  test('rejects foreign image hosts and long messages', async () => {
    await expect(service.create({ senderId: 'u1', imageUrl: 'https://evil.example/x.jpg' })).rejects.toMatchObject({ status: 400, code: 'invalid_image' });
    await expect(service.create({ senderId: 'u1', imageUrl: good, message: 'x'.repeat(501) })).rejects.toMatchObject({ code: 'invalid_message' });
    await expect(service.create({ senderId: 'u1', imageUrl: good, templateId: 'Bad Template' })).rejects.toMatchObject({ code: 'invalid_template' });
  });

  test('unknown or malformed tokens are null', async () => {
    expect(await service.get('nope')).toBeNull();
    expect(await service.get('../etc/passwd')).toBeNull();
    expect(await service.get('AAAAAAAAAAAAAAAAAAAA')).toBeNull();
  });
});
