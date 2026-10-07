// backend/services/coachVoiceService.js
// Coach Mane's voice for FavRun (Wes, 2026-10-07: the phone's voice "sounds
// like a robot", then Chirp "sounds like a weakling" — he's a rough, tough,
// jacked dude with a mane). The app sends the line; Google Cloud
// Text-to-Speech's Gemini TTS, directed by STYLE, returns an MP3 (~6–10 s).
// The app falls back to the on-device voice when there's no signal.
//
// Cost: Gemini Pro TTS bills audio output tokens (~25/s): a ~10 s mile line
// is about half a cent. Repeated lines (the hello) come from a cache.

const { ServiceError } = require('../utils/serviceError');

const MAX_CHARS = 400;
const VOICE = process.env.COACH_VOICE || 'Algenib';
const MODEL = process.env.COACH_VOICE_MODEL || 'gemini-2.5-pro-tts';
const STYLE = {
  savage: "You are Coach Mane: a huge, jacked, rough and tough coach with a lion's mane of hair. " +
    "Bark this in a deep, gravelly, loud, aggressive drill-sergeant voice, like you're yelling at a runner " +
    "from the back of a truck. Intense, dominant, zero sympathy, a little amused.",
  clean: "You are Coach Mane: a huge, jacked, rough and tough coach with a lion's mane of hair. " +
    "Say this in a deep, gravelly, loud, commanding voice — a hard-nosed coach pushing his runner. Intense and strong."
};
const CACHE_MAX = 200;
const cache = new Map(); // style|text → base64 mp3 (LRU by insertion order)

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
async function speak(text, { intensity, fetchImpl = fetch, accessToken } = {}) {
  const line = cleanText(text);
  const style = intensity === 'clean' ? 'clean' : 'savage';
  const key = `${style}|${line}`;
  if (cache.has(key)) {
    const audio = cache.get(key);
    remember(key, audio);
    return { audio, voice: VOICE, cached: true };
  }
  const token = accessToken || await defaultToken();
  const res = await fetchImpl('https://texttospeech.googleapis.com/v1/text:synthesize', {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      input: { prompt: STYLE[style], text: line },
      voice: { languageCode: 'en-US', name: VOICE, modelName: MODEL },
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
  remember(key, audioContent);
  return { audio: audioContent, voice: VOICE, cached: false };
}

async function defaultToken() {
  const admin = require('firebase-admin');
  const { access_token: t } = await admin.app().options.credential.getAccessToken();
  return t;
}

module.exports = { speak, cleanText, MAX_CHARS, _cache: cache };
