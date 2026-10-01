// security audit 2026-10-01: the pre-auth logger and sanitizer must stay
// linear on hostile bodies, and perUserLimit must count per account across
// instances (Firestore) while failing open.

const docs = new Map();
let failFirestore = false;

const mockDb = {
  collection: (col) => ({
    doc: (id) => ({ __key: `${col}/${id}` })
  }),
  runTransaction: async (fn) => {
    if (failFirestore) throw new Error('firestore unavailable');
    const writes = [];
    const tx = {
      get: async (ref) => ({
        exists: docs.has(ref.__key),
        data: () => docs.get(ref.__key)
      }),
      set: (ref, value) => { writes.push([ref.__key, value]); }
    };
    const result = await fn(tx);
    writes.forEach(([k, v]) => docs.set(k, v));
    return result;
  }
};

jest.mock('../../config/firebase', () => ({
  getFirestore: () => mockDb
}));

const {
  securityLogger, sanitizeInput, sanitizeString, looksSuspicious, perUserLimit, _resetPerUserLimitMemo
} = require('../security');

const mockRes = () => {
  const res = { statusCode: 200, headers: {} };
  res.status = (c) => { res.statusCode = c; return res; };
  res.json = (b) => { res.body = b; return res; };
  res.set = (k, v) => { res.headers[k] = v; return res; };
  return res;
};

describe('securityLogger', () => {
  let errorSpy;
  beforeEach(() => { errorSpy = jest.spyOn(console, 'error').mockImplementation(() => {}); });
  afterEach(() => errorSpy.mockRestore());

  test('a 5 MB "union union…" body finishes fast', () => {
    const body = { text: 'union '.repeat(Math.ceil((5 * 1024 * 1024) / 6)) };
    const next = jest.fn();
    const start = Date.now();
    securityLogger({ url: '/api/x', body, ip: '1.2.3.4', path: '/api/x' }, mockRes(), next);
    expect(Date.now() - start).toBeLessThan(500);
    expect(next).toHaveBeenCalled();
  });

  test('still flags the classic patterns near the start of a body', () => {
    expect(looksSuspicious("x' UNION SELECT password FROM users")).toBe(true);
    expect(looksSuspicious('<script>alert(1)</script>')).toBe(true);
    expect(looksSuspicious('the union of two sets')).toBe(false);
  });

  test('only inspects the first 10 KB', () => {
    expect(looksSuspicious('a'.repeat(20 * 1024) + '<script>')).toBe(false);
  });
});

describe('sanitizeInput', () => {
  test('strips closed script/iframe blocks and event handlers as before', () => {
    expect(sanitizeString('hi <script>alert(1)</script> there')).toBe('hi  there');
    expect(sanitizeString('a<IFRAME src=x></iframe>b')).toBe('ab');
    expect(sanitizeString('<img onerror = "x">')).toBe('<img  "x">');
    expect(sanitizeString('javascript:alert(1)')).toBe('alert(1)');
    expect(sanitizeString('Pizza & Bakery')).toBe('Pizza & Bakery');
  });

  test('leaves an unclosed script tag (old semantics)', () => {
    expect(sanitizeString('<script>no close')).toBe('<script>no close');
  });

  test('repeated unclosed "<script" and "onon…" bodies are linear', () => {
    const start = Date.now();
    sanitizeString('<script'.repeat(150000));
    sanitizeString('on'.repeat(500000));
    sanitizeString('<iframe '.repeat(100000) + '</iframe>');
    expect(Date.now() - start).toBeLessThan(1000);
  });

  test('base64 image fields are not munged', () => {
    const req = { body: { image: 'AAAAonAB=', filename: 'x onload=1' } };
    sanitizeInput(req, mockRes(), () => {});
    expect(req.body.image).toBe('AAAAonAB=');
    expect(req.body.filename).toBe('x 1');
  });
});

describe('perUserLimit', () => {
  let warnSpy;
  beforeEach(() => {
    docs.clear();
    failFirestore = false;
    _resetPerUserLimitMemo();
    warnSpy = jest.spyOn(console, 'warn').mockImplementation(() => {});
  });
  afterEach(() => {
    warnSpy.mockRestore();
    jest.restoreAllMocks();
  });

  const call = async (mw, uid = 'u1') => {
    const res = mockRes();
    const next = jest.fn();
    await mw({ user: uid ? { uid } : undefined, originalUrl: '/x' }, res, next);
    return { res, next };
  };

  test('allows max per window, then 429s with Retry-After', async () => {
    const mw = perUserLimit({ bucket: 'test', windowMs: 60000, max: 3 });
    for (let i = 0; i < 3; i++) {
      const { next } = await call(mw);
      expect(next).toHaveBeenCalled();
    }
    const { res, next } = await call(mw);
    expect(next).not.toHaveBeenCalled();
    expect(res.statusCode).toBe(429);
    expect(res.headers['Retry-After']).toBeDefined();
    // Another account is unaffected
    expect((await call(mw, 'u2')).next).toHaveBeenCalled();
  });

  test('a new fixed window starts a fresh count', async () => {
    const now = jest.spyOn(Date, 'now').mockReturnValue(1_000_000);
    const mw = perUserLimit({ bucket: 'test', windowMs: 60000, max: 1 });
    expect((await call(mw)).next).toHaveBeenCalled();
    expect((await call(mw)).res.statusCode).toBe(429);
    now.mockReturnValue(1_000_000 + 60000);
    expect((await call(mw)).next).toHaveBeenCalled();
    const keys = [...docs.keys()];
    expect(keys).toHaveLength(2);
    expect(keys[0]).toMatch(/^rateLimits\/test_u1_\d+$/);
    expect(docs.get(keys[0]).expiresAt).toBeInstanceOf(Date);
  });

  test('fails open when Firestore errors', async () => {
    failFirestore = true;
    const mw = perUserLimit({ bucket: 'test', windowMs: 60000, max: 1 });
    for (let i = 0; i < 3; i++) {
      expect((await call(mw)).next).toHaveBeenCalled();
    }
  });

  test('does nothing (no Firestore) without an authenticated user', async () => {
    const spy = jest.spyOn(mockDb, 'runTransaction');
    const mw = perUserLimit({ bucket: 'test', windowMs: 60000, max: 1 });
    expect((await call(mw, null)).next).toHaveBeenCalled();
    expect(spy).not.toHaveBeenCalled();
  });

  test('a blocked window is remembered locally (no more Firestore reads)', async () => {
    const mw = perUserLimit({ bucket: 'test', windowMs: 60000, max: 1 });
    await call(mw);
    await call(mw); // blocked, memoised
    const spy = jest.spyOn(mockDb, 'runTransaction');
    expect((await call(mw)).res.statusCode).toBe(429);
    expect(spy).not.toHaveBeenCalled();
  });

  test('rejects bad config', () => {
    expect(() => perUserLimit({ bucket: 'bad/bucket', windowMs: 1, max: 1 })).toThrow();
    expect(() => perUserLimit({ bucket: 'ok', windowMs: 0, max: 1 })).toThrow();
  });
});
