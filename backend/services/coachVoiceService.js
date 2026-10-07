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
const RATE = Number(process.env.COACH_VOICE_RATE) || 1.2; // Wes: "sounds like a 70 year old"
// One voice for both Tough love and Savage (Wes, 2026-10-07: "the savage voice
// is good, use it for both"); only the words differ, chosen by the app.
const STYLE = "You are Coach Mane: a jacked, 35-year-old powerlifter coach in his prime with a lion's mane. " +
  "Deliver this FAST, punchy and clipped — rapid-fire, no pauses between sentences, like a confident, " +
  "demanding drill sergeant barking orders. Deep, gravelly, loud, dominant. Never slow, never tired, never old.";
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
/** Firestore copy of each spoken line, shared by every server instance (the
 *  hello and roasts repeat; generating one takes ~6 s). Keyed by everything
 *  that changes the sound. */
function storeKey(style, line) {
  return require('crypto').createHash('sha1').update([MODEL, VOICE, RATE, style, line].join('|')).digest('hex');
}
const storeDoc = (id) => require('../config/firebase').getFirestore().collection('coachVoiceCache').doc(id);

async function speak(text, { fetchImpl = fetch, accessToken, store = true } = {}) {
  const line = cleanText(text);
  const style = 'savage'; // the one voice (intensity only changes the words)
  const key = `${style}|${line}`;
  if (cache.has(key)) {
    const audio = cache.get(key);
    remember(key, audio);
    return { audio, voice: VOICE, cached: true };
  }
  const id = storeKey(style, line);
  if (store) {
    const saved = await storeDoc(id).get().catch(() => null);
    if (saved && saved.exists && saved.data().audio) {
      remember(key, saved.data().audio);
      return { audio: saved.data().audio, voice: VOICE, cached: true };
    }
  }
  const token = accessToken || await defaultToken();
  const res = await fetchImpl('https://texttospeech.googleapis.com/v1/text:synthesize', {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      input: { prompt: STYLE, text: line },
      voice: { languageCode: 'en-US', name: VOICE, modelName: MODEL },
      audioConfig: { audioEncoding: 'MP3', speakingRate: RATE }
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
  if (store) storeDoc(id).set({ audio: audioContent, text: line, style, voice: VOICE, createdAt: new Date().toISOString() }).catch(() => {});
  return { audio: audioContent, voice: VOICE, cached: false };
}

async function defaultToken() {
  const admin = require('firebase-admin');
  const { access_token: t } = await admin.app().options.credential.getAccessToken();
  return t;
}

module.exports = { speak, cleanText, MAX_CHARS, _cache: cache };
