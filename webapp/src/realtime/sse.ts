// The live stream: GET /api/sse/stream (backend/routes/sseRoutes.js,
// services/sseService.js). The stream needs the Authorization header, which
// the browser's EventSource can't send, so this is the one place besides
// api/client.ts that calls fetch: it reads the body as it arrives and feeds
// it through the pure parser in logic/sseParser.ts.
//
//   const off = liveStream.subscribe('new_message', (event) => …);
//   liveStream.start(); … liveStream.stop();
//
// Reconnects 1 s → 2 s → … 30 s (back to 1 s once the server says
// "connected"); a stream that sends nothing for 75 s (heartbeats come every
// 30 s) is dead and is replaced; a tab hidden for a while lets go of the
// stream and takes a fresh one when it comes back, announcing it with a
// local `reconnected` event so screens refetch what they missed.
import { useSyncExternalStore } from 'react';
import { authHeaders } from '../api/client';
import { getSession } from '../auth/session';
import {
  createSseParser, parseStreamEvent, reconnectDelay, streamIsSilent, STREAM_SILENCE_MS, type StreamEvent
} from '../logic/sseParser';

export type StreamStatus = 'idle' | 'connecting' | 'live' | 'down';
export type StreamHandler = (event: StreamEvent) => void;

/** A tab hidden this long lets go of the stream (a phone would kill it anyway) */
const HIDDEN_PAUSE_MS = 60_000;
const WATCHDOG_MS = 5_000;

class LiveStream {
  private handlers = new Map<string, Set<StreamHandler>>();
  private statusListeners = new Set<() => void>();
  private current: StreamStatus = 'idle';
  private running = false;
  private paused = false;
  private generation = 0;
  private controller: AbortController | null = null;
  private attempt = 0;
  private retryTimer: ReturnType<typeof setTimeout> | undefined;
  private watchdog: ReturnType<typeof setInterval> | undefined;
  private hiddenTimer: ReturnType<typeof setTimeout> | undefined;
  private lastByteAt = 0;
  /** Been live since start(): the next "connected" is a reconnect */
  private wasLive = false;
  private listening = false;

  status(): StreamStatus { return this.current; }

  onStatus(listener: () => void): () => void {
    this.statusListeners.add(listener);
    return () => { this.statusListeners.delete(listener); };
  }

  /** `type` is an event type from the server, `reconnected` (local), or '*' for everything */
  subscribe(type: string, handler: StreamHandler): () => void {
    let set = this.handlers.get(type);
    if (!set) { set = new Set(); this.handlers.set(type, set); }
    set.add(handler);
    return () => { set?.delete(handler); };
  }

  start(): void {
    if (this.running) return;
    this.running = true;
    this.paused = false;
    this.wasLive = false;
    this.attempt = 0;
    this.listen(true);
    if (typeof document !== 'undefined' && document.visibilityState === 'hidden') this.onVisibility();
    this.connect();
  }

  stop(): void {
    this.running = false;
    this.paused = false;
    this.listen(false);
    this.disconnect();
    clearTimeout(this.hiddenTimer);
    this.setStatus('idle');
  }

  private setStatus(next: StreamStatus) {
    if (next === this.current) return;
    this.current = next;
    this.statusListeners.forEach((listener) => { try { listener(); } catch { /* a listener's bug isn't the stream's */ } });
  }

  private emit(event: StreamEvent) {
    [this.handlers.get(event.type), this.handlers.get('*')].forEach((set) => {
      set?.forEach((handler) => {
        try { handler(event); } catch (error) { console.warn('Live update handler failed', error); }
      });
    });
  }

  private disconnect() {
    this.generation += 1;
    clearTimeout(this.retryTimer);
    clearInterval(this.watchdog);
    this.retryTimer = undefined;
    this.watchdog = undefined;
    if (this.controller) { this.controller.abort(); this.controller = null; }
  }

  private scheduleReconnect() {
    if (!this.running || this.paused) return;
    this.disconnect();
    this.setStatus('down');
    const wait = reconnectDelay(this.attempt);
    this.attempt += 1;
    this.retryTimer = setTimeout(() => this.connect(), wait);
  }

  private async connect() {
    if (!this.running || this.paused) return;
    if (!getSession()) { this.stop(); return; }
    this.disconnect();
    const generation = this.generation;
    const controller = new AbortController();
    this.controller = controller;
    if (this.current !== 'down') this.setStatus('connecting');
    const stale = () => generation !== this.generation;
    let response: Response;
    try {
      response = await fetch('/api/sse/stream', {
        headers: { Accept: 'text/event-stream', 'X-FC-Inner-Circle': '1', ...authHeaders() },
        cache: 'no-store',
        signal: controller.signal
      });
    } catch {
      if (!stale()) this.scheduleReconnect();
      return;
    }
    if (stale()) { controller.abort(); return; }
    if (response.status === 401) { this.stop(); return; } // signed out elsewhere; the next API call says so
    if (!response.ok || !response.body) { this.scheduleReconnect(); return; }

    const reader = response.body.getReader();
    const decoder = new TextDecoder();
    const parser = createSseParser();
    this.lastByteAt = Date.now();
    this.watchdog = setInterval(() => {
      if (!stale() && streamIsSilent(this.lastByteAt, Date.now(), STREAM_SILENCE_MS)) this.scheduleReconnect();
    }, WATCHDOG_MS);
    try {
      for (;;) {
        const { done, value } = await reader.read();
        if (stale()) return;
        if (done) break;
        this.lastByteAt = Date.now();
        const frames = parser.push(decoder.decode(value, { stream: true }));
        for (const frame of frames) {
          const event = parseStreamEvent(frame.data);
          if (!event) continue;
          if (event.type === 'connected') {
            this.attempt = 0;
            const reconnect = this.wasLive;
            this.wasLive = true;
            this.setStatus('live');
            if (reconnect) this.emit({ type: 'reconnected', timestamp: new Date().toISOString() });
          }
          this.emit(event);
          if (stale()) return;
        }
      }
    } catch {
      // aborted or the connection dropped
    }
    if (!stale()) this.scheduleReconnect();
  }

  // ---- the tab going away and coming back, the network dropping
  private onVisibility = () => {
    if (!this.running) return;
    if (document.visibilityState === 'hidden') {
      clearTimeout(this.hiddenTimer);
      this.hiddenTimer = setTimeout(() => {
        if (!this.running || document.visibilityState !== 'hidden') return;
        this.paused = true;
        this.disconnect();
        this.setStatus('down');
      }, HIDDEN_PAUSE_MS);
      return;
    }
    clearTimeout(this.hiddenTimer);
    if (this.paused) {
      this.paused = false;
      this.attempt = 0;
      this.connect();
    }
  };

  private onOnline = () => {
    if (!this.running || this.paused || this.current === 'live') return;
    this.attempt = 0;
    this.connect();
  };

  private listen(on: boolean) {
    if (typeof window === 'undefined' || on === this.listening) return;
    this.listening = on;
    if (on) {
      document.addEventListener('visibilitychange', this.onVisibility);
      window.addEventListener('online', this.onOnline);
    } else {
      document.removeEventListener('visibilitychange', this.onVisibility);
      window.removeEventListener('online', this.onOnline);
    }
  }
}

export const liveStream = new LiveStream();

/** The stream's state, for a screen that polls while it is down */
export function useStreamStatus(): StreamStatus {
  return useSyncExternalStore(
    (listener) => liveStream.onStatus(listener),
    () => liveStream.status(),
    () => 'idle'
  );
}
