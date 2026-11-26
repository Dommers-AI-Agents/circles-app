import { describe, expect, it } from 'vitest';
import { createSseParser, parseStreamEvent, reconnectDelay, streamIsSilent } from './sseParser';

// Frames as the server really sent them (captured from /api/sse/stream)
const CONNECTED = 'data: {"type":"connected","message":"SSE connection established"}\n\n';
const NEW_MESSAGE = 'data: {"type":"new_message","data":{"messageId":"m1","conversationId":"c1","senderId":"u2","senderName":"Blake","content":"hi","type":"text"},"timestamp":"2026-11-26T14:12:03.089Z"}\n\n';

describe('createSseParser', () => {
  it('reads whole frames', () => {
    const parser = createSseParser();
    const frames = parser.push(CONNECTED + NEW_MESSAGE);
    expect(frames).toHaveLength(2);
    expect(parseStreamEvent(frames[0].data)).toEqual({ type: 'connected', message: 'SSE connection established' });
    expect(parseStreamEvent(frames[1].data)?.type).toBe('new_message');
  });

  it('skips the heartbeat comment and counts it', () => {
    const parser = createSseParser();
    expect(parser.push(':heartbeat\n\n')).toEqual([]);
    expect(parser.comments()).toBe(1);
    expect(parser.push(NEW_MESSAGE)).toHaveLength(1);
  });

  it('puts a frame together from chunks cut anywhere', () => {
    for (let cut = 1; cut < NEW_MESSAGE.length; cut++) {
      const parser = createSseParser();
      const frames = [...parser.push(NEW_MESSAGE.slice(0, cut)), ...parser.push(NEW_MESSAGE.slice(cut))];
      expect(frames).toHaveLength(1);
      expect(parseStreamEvent(frames[0].data)?.type).toBe('new_message');
    }
  });

  it('reads one character at a time', () => {
    const parser = createSseParser();
    const frames = (CONNECTED + ':heartbeat\n\n' + NEW_MESSAGE).split('').flatMap((char) => parser.push(char));
    expect(frames.map((frame) => parseStreamEvent(frame.data)?.type)).toEqual(['connected', 'new_message']);
  });

  it('joins several data lines with a newline', () => {
    const parser = createSseParser();
    expect(parser.push('data: {"type":"x",\ndata: "data":1}\n\n')).toEqual([{ data: '{"type":"x",\n"data":1}' }]);
    expect(parser.push('data: one\ndata:\ndata: three\n\n')).toEqual([{ data: 'one\n\nthree' }]);
  });

  it('accepts CRLF and bare CR line ends', () => {
    expect(createSseParser().push('data: a\r\n\r\ndata: b\r\n\r\n')).toEqual([{ data: 'a' }, { data: 'b' }]);
    expect(createSseParser().push('data: a\r\rdata: b\r\r')).toEqual([{ data: 'a' }, { data: 'b' }]);
  });

  it('keeps a CRLF together when the chunk ends between the two', () => {
    const parser = createSseParser();
    const frames = [...parser.push('data: a\r'), ...parser.push('\n\r'), ...parser.push('\ndata: b\r\n\r'), ...parser.push('\n')];
    expect(frames).toEqual([{ data: 'a' }, { data: 'b' }]);
  });

  it('does not end a frame early when a chunk ends on the CR of the data line', () => {
    const parser = createSseParser();
    expect(parser.push('data: a\r')).toEqual([]);
    expect(parser.push('\ndata: b\r\n')).toEqual([]);
    expect(parser.push('\r\n')).toEqual([{ data: 'a\nb' }]);
  });

  it('reads the event name and id, strips one leading space only, ignores other fields', () => {
    const parser = createSseParser();
    expect(parser.push('event: ping\nid: 7\nretry: 500\nwhatever\ndata:  two spaces\n\n')).toEqual([{ event: 'ping', id: '7', data: ' two spaces' }]);
    // The event name does not carry over to the next frame
    expect(parser.push('data:x\n\n')).toEqual([{ id: '7', data: 'x' }]);
  });

  it('drops a frame with no data and waits for the blank line', () => {
    const parser = createSseParser();
    expect(parser.push('event: nothing\n\n')).toEqual([]);
    expect(parser.push('data: unfinished\n')).toEqual([]);
    expect(parser.push('\n')).toEqual([{ data: 'unfinished' }]);
  });
});

describe('parseStreamEvent', () => {
  it('needs an object with a type', () => {
    expect(parseStreamEvent('{"type":"notification_count","data":{"count":2},"timestamp":"t"}')).toEqual({ type: 'notification_count', data: { count: 2 }, timestamp: 't' });
    expect(parseStreamEvent('not json')).toBeNull();
    expect(parseStreamEvent('{"data":1}')).toBeNull();
    expect(parseStreamEvent('[1]')).toBeNull();
    expect(parseStreamEvent('null')).toBeNull();
    expect(parseStreamEvent('{"type":""}')).toBeNull();
  });
});

describe('reconnectDelay', () => {
  it('doubles from 1 s and stops at 30 s', () => {
    expect([0, 1, 2, 3, 4, 5, 6, 50].map((n) => reconnectDelay(n))).toEqual([1000, 2000, 4000, 8000, 16000, 30000, 30000, 30000]);
    expect(reconnectDelay(-3)).toBe(1000);
    expect(reconnectDelay(NaN)).toBe(1000);
  });
});

describe('streamIsSilent', () => {
  it('is dead after 75 s with no bytes', () => {
    expect(streamIsSilent(0, 74_999)).toBe(false);
    expect(streamIsSilent(0, 75_000)).toBe(true);
  });
});
