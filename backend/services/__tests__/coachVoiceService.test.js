const voice = require('../coachVoiceService');

const okFetch = (calls) => async (url, init) => {
  calls.push(JSON.parse(init.body));
  return { ok: true, json: async () => ({ audioContent: 'QUJD' }) };
};

describe('coachVoiceService', () => {
  beforeEach(() => voice._cache.clear());

  test('cleans whitespace and refuses empty or long lines', () => {
    expect(voice.cleanText('  First mile   done. ')).toBe('First mile done.');
    expect(() => voice.cleanText('')).toThrow('Nothing to say');
    expect(() => voice.cleanText(42)).toThrow('Nothing to say');
    expect(() => voice.cleanText('x'.repeat(voice.MAX_CHARS + 1))).toThrow('too long');
  });

  test('synthesizes with the Chirp voice, then serves repeats from cache', async () => {
    const calls = [];
    const a = await voice.speak('Go run.', { fetchImpl: okFetch(calls), accessToken: 't' });
    const b = await voice.speak('Go  run. ', { fetchImpl: okFetch(calls), accessToken: 't' });
    expect(a).toEqual({ audio: 'QUJD', voice: 'en-US-Chirp3-HD-Fenrir', cached: false });
    expect(b.cached).toBe(true);
    expect(calls).toHaveLength(1);
    expect(calls[0].voice).toEqual({ languageCode: 'en-US', name: 'en-US-Chirp3-HD-Fenrir' });
    expect(calls[0].audioConfig.audioEncoding).toBe('MP3');
  });

  test('a provider failure is a 502 and is not cached', async () => {
    const bad = async () => ({ ok: false, status: 403, text: async () => 'denied' });
    jest.spyOn(console, 'error').mockImplementation(() => {});
    await expect(voice.speak('Hi', { fetchImpl: bad, accessToken: 't' })).rejects.toMatchObject({ status: 502 });
    expect(voice._cache.size).toBe(0);
  });
});
