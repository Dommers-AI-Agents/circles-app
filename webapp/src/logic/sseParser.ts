// Reads a text/event-stream by hand. The browser's EventSource can't send
// the Authorization header the stream needs, so realtime/sse.ts reads the
// body with fetch and feeds the text through here. Pure: text in, frames out.
//
// The server (backend/services/sseService.js) writes unnamed frames,
//   data: {"type":"new_message","data":{…},"timestamp":"…"}\n\n
// and a `:heartbeat` comment every 30 s. The parser follows the standard all
// the same: LF, CRLF or CR line ends, several `data:` lines joined with a
// newline, comments, and chunks that stop anywhere (mid-line, between the
// CR and the LF, mid-frame).

export interface SseFrame {
  /** `event:` name, when the server names one (ours never does) */
  event?: string;
  /** The `data:` lines, joined with "\n" */
  data: string;
  id?: string;
}

export interface SseParser {
  /** Feed the next piece of text; returns the frames it completed */
  push(chunk: string): SseFrame[];
  /** Comment lines seen so far (the heartbeats) */
  comments(): number;
}

export function createSseParser(): SseParser {
  let buffer = '';
  let dataLines: string[] = [];
  let event: string | undefined;
  let id: string | undefined;
  let commentCount = 0;
  // A chunk ended on "\r": a "\n" that opens the next one belongs to it
  let skipLineFeed = false;

  const takeLine = (line: string, frames: SseFrame[]) => {
    if (line === '') {
      // A blank line ends the frame; one with no data is dropped
      if (dataLines.length > 0) {
        const frame: SseFrame = { data: dataLines.join('\n') };
        if (event) frame.event = event;
        if (id !== undefined) frame.id = id;
        frames.push(frame);
      }
      dataLines = [];
      event = undefined;
      return;
    }
    if (line.charAt(0) === ':') { commentCount += 1; return; }
    const colon = line.indexOf(':');
    const field = colon === -1 ? line : line.slice(0, colon);
    let value = colon === -1 ? '' : line.slice(colon + 1);
    if (value.charAt(0) === ' ') value = value.slice(1);
    if (field === 'data') dataLines.push(value);
    else if (field === 'event') event = value;
    else if (field === 'id') id = value;
    // `retry:` and unknown fields are ignored
  };

  return {
    push(chunk: string): SseFrame[] {
      const frames: SseFrame[] = [];
      let text = chunk;
      if (skipLineFeed && text.length > 0) {
        if (text.charAt(0) === '\n') text = text.slice(1);
        skipLineFeed = false;
      }
      buffer += text;
      let start = 0;
      for (let i = 0; i < buffer.length; i++) {
        const char = buffer.charAt(i);
        if (char !== '\n' && char !== '\r') continue;
        takeLine(buffer.slice(start, i), frames);
        if (char === '\r') {
          if (i + 1 < buffer.length) { if (buffer.charAt(i + 1) === '\n') i += 1; }
          else skipLineFeed = true;
        }
        start = i + 1;
      }
      buffer = buffer.slice(start);
      return frames;
    },
    comments: () => commentCount
  };
}

/** One thing the server said: `{type, data, timestamp}` (the first frame, "connected", has no data). */
export interface StreamEvent {
  type: string;
  data?: unknown;
  timestamp?: string;
  [key: string]: unknown;
}

/** A frame's JSON as an event; null for anything that isn't `{type: "…"}`. */
export function parseStreamEvent(data: string): StreamEvent | null {
  try {
    const value = JSON.parse(data);
    if (value && typeof value === 'object' && !Array.isArray(value) && typeof value.type === 'string' && value.type) {
      return value as StreamEvent;
    }
    return null;
  } catch {
    return null;
  }
}

/** Wait before reconnect number `attempt` (0 = the first retry): 1 s, 2 s, 4 s … capped at 30 s. */
export function reconnectDelay(attempt: number, baseMs = 1000, maxMs = 30_000): number {
  const safe = Math.max(0, Math.floor(Number.isFinite(attempt) ? attempt : 0));
  return Math.min(maxMs, baseMs * 2 ** Math.min(safe, 20));
}

/** No bytes at all (not even a heartbeat, sent every 30 s) for this long means the stream is dead. */
export const STREAM_SILENCE_MS = 75_000;
export const streamIsSilent = (lastByteAt: number, now: number, limitMs = STREAM_SILENCE_MS): boolean => now - lastByteAt >= limitMs;
