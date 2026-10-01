const { clampPagination } = require('../pagination');

describe('clampPagination (security audit 2026-10-01)', () => {
  test('defaults when absent', () => {
    expect(clampPagination({})).toEqual({ limit: 20, offset: 0 });
    expect(clampPagination(undefined, { defaultLimit: 50 })).toEqual({ limit: 50, offset: 0 });
  });

  test('caps limit and offset', () => {
    expect(clampPagination({ limit: '100000', offset: '999999' })).toEqual({ limit: 100, offset: 1000 });
    expect(clampPagination({ limit: '1000' }, { maxLimit: 1000 })).toEqual({ limit: 1000, offset: 0 });
  });

  test('garbage and negatives fall back instead of throwing in the query', () => {
    expect(clampPagination({ limit: 'abc', offset: 'x' })).toEqual({ limit: 20, offset: 0 });
    expect(clampPagination({ limit: '-5', offset: '-3' })).toEqual({ limit: 1, offset: 0 });
    expect(clampPagination({ limit: '0' })).toEqual({ limit: 1, offset: 0 });
  });

  test('passes normal values through', () => {
    expect(clampPagination({ limit: '25', offset: '50' })).toEqual({ limit: 25, offset: 50 });
  });
});
