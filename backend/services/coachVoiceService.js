// backend/services/coachVoiceService.js
// Coach Mane's voice for FavRun (Wes, 2026-10-07: the phone's voice "sounds
// like a robot"). The app sends the line it wants spoken; Google Cloud
// Text-to-Speech (Chirp 3 HD, a natural human voice) returns an MP3. The app
// falls back to the on-device voice when there's no signal.
//
// Cost: Chirp 3 HD is billed per character; a mile's line is ~150 chars, so
// a 5-mile run is ~750 chars. Repeated lines (the hello) come from a cache.

const { ServiceError } = require('../utils/serviceError');

const MAX_CHARS = 400;
const VOICE = process.env.COACH_VOICE || 'en-US-Chirp3-HD-Fenrir';
const CACHE_MAX = 200;
const cache = new Map(); // text → base64 mp3 (LRU by insertion order)

/** Pure (tested): the spoken text, or throws when it isn't speakable. */
function cleanText(text) {
  const t = typeof text === 'string' ? text.replace(/\s+/g, ' ').trim() : '';
  if (!t) throw new ServiceError(400, 'no_text', 'Nothing to say');
  if (t.length > MAX_CHARS) throw new ServiceError(400, 'too_long', 'That line is too long');
  return t;
}

function remember(text, audio) {
  cache.delete(text);
  cache.set(text, audio);
  if (cache.size > CACHE_MAX) cache.delete(cache.keys().next().value);
}

/** { audio: base64 MP3, voice } for one line. */
async function speak(text, { fetchImpl = fetch, accessToken } = {}) {
  const line = cleanText(text);
  if (cache.has(line)) {
    const audio = cache.get(line);
    remember(line, audio);
    return { audio, voice: VOICE, cached: true };
  }
  const token = accessToken || await defaultToken();
  const res = await fetchImpl('https://texttospeech.googleapis.com/v1/text:synthesize', {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      input: { text: line },
      voice: { languageCode: VOICE.slice(0, 5), name: VOICE },
      audioConfig: { audioEncoding: 'MP3' }
    })
  });
  if (!res.ok) {
    const body = await res.text().catch(() => '');
    console.error(`📣 coach voice ${res.status}: ${body.slice(0, 200)}`);
    throw new ServiceError(502, 'voice_failed', 'Coach Mane lost his voice');
  }
  const { audioContent } = await res.json();
  if (!audioContent) throw new ServiceError(502, 'voice_failed', 'Coach Mane lost his voice');
  remember(line, audioContent);
  return { audio: audioContent, voice: VOICE, cached: false };
}

async function defaultToken() {
  const admin = require('firebase-admin');
  const { access_token: t } = await admin.app().options.credential.getAccessToken();
  return t;
}

module.exports = { speak, cleanText, MAX_CHARS, _cache: cache };
