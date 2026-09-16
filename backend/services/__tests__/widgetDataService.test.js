// Widget document store tests: optimistic versioning, payload guards, id
// regex, and batch reads. Firestore is an in-memory mock (same shape as the
// piggy bank tests) — what's under test is the lock + validation logic that
// keeps two devices from silently overwriting each other.

const stores = {};
const store = (name) => (stores[name] = stores[name] || new Map());

function makeDocRef(col, id) {
  return {
    __col: col, __id: id,
    get: async () => ({
      exists: store(col).has(id),
      data: () => store(col).get(id),
      ref: makeDocRef(col, id)
    }),
    set: async (value) => { store(col).set(id, value); },
    delete: async () => { store(col).delete(id); }
  };
}

const mockDb = {
  collection: (col) => ({
    doc: (id) => makeDocRef(col, id)
  }),
  getAll: async (...refs) => refs.map(ref => ({
    id: ref.__id,
    exists: store(ref.__col).has(ref.__id),
    data: () => store(ref.__col).get(ref.__id)
  })),
  runTransaction: async (fn) => {
    const ops = [];
    const tx = {
      get: async (ref) => ({
        exists: store(ref.__col).has(ref.__id),
        data: () => store(ref.__col).get(ref.__id)
      }),
      set: (ref, value) => { ops.push(() => store(ref.__col).set(ref.__id, value)); }
    };
    const result = await fn(tx);
    ops.forEach(op => op());
    return result;
  }
};

jest.mock('../../config/firebase', () => ({
  getFirestore: () => mockDb
}));

const service = require('../widgetDataService');
const {
  ValidationError, VersionConflictError, WIDGET_ID_RE, WIDGET_PAYLOAD_MAX_BYTES, MAX_BATCH_IDS
} = require('../widgetDataService');

const rows = () => store('widgetData');
const body = (version, payload = '{"goalMl":2000}', schemaVersion = 1) => ({ version, payload, schemaVersion });

beforeEach(() => {
  Object.keys(stores).forEach(k => stores[k].clear());
});

describe('save', () => {
  test('first save: v0 → v1, createdAt == updatedAt, stored under uid_widgetId', async () => {
    const r = await service.save('u1', 'water', body(0));
    expect(r.created).toBe(true);
    expect(r.previousUpdatedAt).toBeNull();
    expect(r.document).toMatchObject({ widgetId: 'water', version: 1, payload: '{"goalMl":2000}', schemaVersion: 1 });
    expect(r.document.createdAt).toBe(r.document.updatedAt);
    expect(r.document).not.toHaveProperty('userId');
    expect(r.document).not.toHaveProperty('payloadBytes');

    const stored = rows().get('u1_water');
    expect(stored).toMatchObject({ userId: 'u1', widgetId: 'water', version: 1, payloadBytes: 15 });
  });

  test('matching version increments and preserves createdAt', async () => {
    const first = await service.save('u1', 'water', body(0));
    const second = await service.save('u1', 'water', body(1, '{"goalMl":2500}'));
    expect(second.created).toBe(false);
    expect(second.previousUpdatedAt).toBe(first.document.updatedAt);
    expect(second.document.version).toBe(2);
    expect(second.document.createdAt).toBe(first.document.createdAt);
    expect(second.document.payload).toBe('{"goalMl":2500}');
  });

  test('stale version rejects with the current doc and leaves the store unchanged', async () => {
    await service.save('u1', 'water', body(0));
    await service.save('u1', 'water', body(1, '{"goalMl":2500}'));
    const before = { ...rows().get('u1_water') };

    let err;
    try { await service.save('u1', 'water', body(1, '{"goalMl":9}')); } catch (e) { err = e; }
    expect(err).toBeInstanceOf(VersionConflictError);
    expect(err.status).toBe(409);
    expect(err.code).toBe('VERSION_CONFLICT');
    expect(err.current).toMatchObject({ widgetId: 'water', version: 2, payload: '{"goalMl":2500}' });
    expect(rows().get('u1_water')).toEqual(before);
  });

  test('a non-zero version on a never-saved doc conflicts with current = null', async () => {
    await expect(service.save('u1', 'water', body(3))).rejects.toMatchObject({ code: 'VERSION_CONFLICT', current: null });
    expect(rows().size).toBe(0);
  });

  test('invalid JSON → 400 invalid_payload', async () => {
    await expect(service.save('u1', 'water', body(0, '{nope'))).rejects.toMatchObject({ status: 400, code: 'invalid_payload' });
  });

  test('scalar / array / null top level → 400 invalid_payload', async () => {
    for (const bad of ['42', '"str"', '[1,2]', 'null']) {
      await expect(service.save('u1', 'water', body(0, bad))).rejects.toMatchObject({ status: 400, code: 'invalid_payload' });
    }
    expect(rows().size).toBe(0);
  });

  test('non-string payload → 400 invalid_payload', async () => {
    await expect(service.save('u1', 'water', { version: 0, payload: { goalMl: 1 } })).rejects.toMatchObject({ status: 400, code: 'invalid_payload' });
  });

  test('> 200 KB → 413 payload_too_large (byte-measured, not char-measured)', async () => {
    const big = `{"x":"${'a'.repeat(WIDGET_PAYLOAD_MAX_BYTES)}"}`;
    await expect(service.save('u1', 'water', body(0, big))).rejects.toMatchObject({ status: 413, code: 'payload_too_large' });
    // Multibyte: 70k chars of a 3-byte glyph is 210 KB
    const multi = `{"x":"${'€'.repeat(70 * 1024)}"}`;
    await expect(service.save('u1', 'water', body(0, multi))).rejects.toMatchObject({ status: 413, code: 'payload_too_large' });
  });

  test('exactly at the cap is accepted', async () => {
    const wrapper = '{"x":""}';
    const fill = 'a'.repeat(WIDGET_PAYLOAD_MAX_BYTES - Buffer.byteLength(wrapper));
    const r = await service.save('u1', 'water', body(0, `{"x":"${fill}"}`));
    expect(rows().get('u1_water').payloadBytes).toBe(WIDGET_PAYLOAD_MAX_BYTES);
    expect(r.document.version).toBe(1);
  });

  test('invalid version → 400 invalid_version', async () => {
    for (const v of [-1, 1.5, '1', undefined, null]) {
      await expect(service.save('u1', 'water', body(v))).rejects.toMatchObject({ status: 400, code: 'invalid_version' });
    }
  });

  test('schemaVersion is optional and carried forward when omitted', async () => {
    await service.save('u1', 'water', { version: 0, payload: '{}', schemaVersion: 3 });
    const r = await service.save('u1', 'water', { version: 1, payload: '{"a":1}' });
    expect(r.document.schemaVersion).toBe(3);
  });
});

describe('widget id regex', () => {
  test.each([
    ['water', true], ['prefs', true], ['calories_2026-09', true], ['bill-split', true],
    ['a1', true], ['a'.repeat(48), true],
    ['a', false], ['Water', false], ['1water', false], ['Bad.Id', false], ['_prefs', false],
    ['water/x', false], ['a'.repeat(49), false], ['', false], ['calories 2026', false]
  ])('%s → %s', (id, ok) => {
    expect(WIDGET_ID_RE.test(id)).toBe(ok);
  });

  test('save / get / remove reject a bad id with 400 invalid_widget_id', async () => {
    await expect(service.save('u1', 'Bad.Id', body(0))).rejects.toMatchObject({ status: 400, code: 'invalid_widget_id' });
    await expect(service.get('u1', 'Bad.Id')).rejects.toMatchObject({ status: 400, code: 'invalid_widget_id' });
    await expect(service.remove('u1', 'Bad.Id')).rejects.toMatchObject({ status: 400, code: 'invalid_widget_id' });
    await expect(service.getMany('u1', ['water', 'Bad.Id'])).rejects.toBeInstanceOf(ValidationError);
  });
});

describe('get / getMany / remove', () => {
  test('get returns null for a never-saved widget, the client doc otherwise', async () => {
    expect(await service.get('u1', 'water')).toBeNull();
    await service.save('u1', 'water', body(0));
    const doc = await service.get('u1', 'water');
    expect(doc).toMatchObject({ widgetId: 'water', version: 1 });
    expect(doc).not.toHaveProperty('userId');
  });

  test('getMany returns only the caller\'s docs, in client shape, skipping misses', async () => {
    await service.save('u1', 'water', body(0));
    await service.save('u1', 'calories_2026-09', body(0, '{"days":{}}'));
    await service.save('u2', 'habits', body(0));
    const docs = await service.getMany('u1', ['water', 'calories_2026-09', 'habits', 'water']);
    expect(docs.map(d => d.widgetId).sort()).toEqual(['calories_2026-09', 'water']);
    docs.forEach(d => {
      expect(d).not.toHaveProperty('userId');
      expect(d).not.toHaveProperty('payloadBytes');
    });
  });

  test('getMany with no ids returns [] without touching getAll', async () => {
    const spy = jest.spyOn(mockDb, 'getAll');
    expect(await service.getMany('u1', [])).toEqual([]);
    expect(spy).not.toHaveBeenCalled();
    spy.mockRestore();
  });

  test('getMany rejects more than MAX_BATCH_IDS distinct ids', async () => {
    const ids = Array.from({ length: MAX_BATCH_IDS + 1 }, (_, i) => `w${i}`);
    await expect(service.getMany('u1', ids)).rejects.toMatchObject({ status: 400, code: 'too_many_ids' });
    // Duplicates collapse before the count
    const dupes = Array.from({ length: MAX_BATCH_IDS + 5 }, () => 'water');
    expect(await service.getMany('u1', dupes)).toEqual([]);
  });

  test('remove deletes the doc and a later save starts at v1 again', async () => {
    await service.save('u1', 'water', body(0));
    await service.remove('u1', 'water');
    expect(rows().has('u1_water')).toBe(false);
    const r = await service.save('u1', 'water', body(0));
    expect(r.created).toBe(true);
    expect(r.document.version).toBe(1);
  });
});


// A widget payload is a plain Codable struct, so a client decoding a document
// it doesn't fully understand drops the unknown fields. Letting it save would
// delete those fields from the server permanently — not a conflict, just
// silent data loss caused by a build that already shipped.
describe('schema downgrade protection', () => {
  test('an older client cannot overwrite a document written by a newer one', async () => {
    const saved = await service.save('u1', 'stocks', { version: 0, payload: '{"lists":[{"name":"Tech"}]}', schemaVersion: 2 });
    expect(saved.document.schemaVersion).toBe(2);

    await expect(
      service.save('u1', 'stocks', { version: saved.document.version, payload: '{"entries":[]}', schemaVersion: 1 })
    ).rejects.toMatchObject({ code: 'SCHEMA_TOO_OLD' });

    // The newer document is still intact.
    const after = await service.get('u1', 'stocks');
    expect(after.payload).toBe('{"lists":[{"name":"Tech"}]}');
    expect(after.schemaVersion).toBe(2);
  });

  test('the rejection carries the stored document so the client can adopt it', async () => {
    const saved = await service.save('u1', 'stocks', { version: 0, payload: '{"lists":[]}', schemaVersion: 2 });
    try {
      await service.save('u1', 'stocks', { version: saved.document.version, payload: '{"entries":[]}', schemaVersion: 1 });
      throw new Error('should have been refused');
    } catch (error) {
      expect(error.code).toBe('SCHEMA_TOO_OLD');
      expect(error.current.schemaVersion).toBe(2);
      expect(error.storedSchema).toBe(2);
      expect(error.incomingSchema).toBe(1);
    }
  });

  test('the same schema still saves normally', async () => {
    const saved = await service.save('u1', 'stocks', { version: 0, payload: '{"lists":[]}', schemaVersion: 2 });
    const again = await service.save('u1', 'stocks', { version: saved.document.version, payload: '{"lists":[1]}', schemaVersion: 2 });
    expect(again.document.version).toBe(2);
  });

  test('a newer schema upgrades the document', async () => {
    const saved = await service.save('u1', 'stocks', { version: 0, payload: '{"entries":[]}', schemaVersion: 1 });
    const upgraded = await service.save('u1', 'stocks', { version: saved.document.version, payload: '{"lists":[]}', schemaVersion: 2 });
    expect(upgraded.document.schemaVersion).toBe(2);
  });

  test('documents written before schemaVersion existed stay writable', async () => {
    // Everything already in production carries null. Blocking those would
    // break every existing widget rather than protect anything.
    const saved = await service.save('u1', 'water', { version: 0, payload: '{}' });
    expect(saved.document.schemaVersion).toBeNull();
    const again = await service.save('u1', 'water', { version: saved.document.version, payload: '{"goalMl":1}', schemaVersion: 1 });
    expect(again.document.schemaVersion).toBe(1);
  });
});
