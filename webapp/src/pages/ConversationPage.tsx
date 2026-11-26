// One chat. Newest messages at the bottom, older ones load as you scroll up
// (the place you were reading stays put). Day dividers, runs of messages
// drawn together, "Read"/"Sent" under my last message in a one-on-one chat
// (logic/chatTimeline.ts, the iOS rules). New messages arrive through the
// live stream; when the stream is down the chat looks every 15 s.
import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState, type ReactNode, type RefObject } from 'react';
import { Link, useParams } from 'react-router-dom';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import {
  conversations as loadConversations, markRead, messagesPage, sendMessage, type ChatPerson, type Message, type Outgoing
} from '../api/messages';
import { ApiError, messageOf } from '../api/client';
import { uploadImage } from '../api/upload';
import { useAuth } from '../auth/AuthContext';
import { dateOf, receipt, rows as timelineRows, timeLabel, type Entry } from '../logic/chatTimeline';
import {
  chunk, conversationTitle, firstName, idOf, isGroup, mergeMessages, oldestStamp, otherPerson, readByOther, unreadIds
} from '../logic/chatThread';
import { MESSAGE_KEYS } from '../logic/liveInvalidations';
import { BADGE_KEYS } from '../realtime/badges';
import { useStreamStatus } from '../realtime/sse';
import { Avatar, Head, LoadError, Spinner } from '../ui/kit';
import { Composer } from '../ui/chat/Composer';
import { MessageActionsSheet } from '../ui/chat/MessageActions';
import { MessageBubble } from '../ui/chat/MessageBubble';
import '../ui/chat/chat.css';
import './ConversationPage.css';

const PAGE = 50;
/** Scrolled this close to the top: fetch the page before */
const OLDER_TRIGGER_PX = 320;
/** This close to the bottom counts as reading the newest */
const BOTTOM_SLACK_PX = 90;

interface Pending {
  localId: string;
  createdAt: string;
  status: 'sending' | 'failed';
  error?: string;
  /** null while a photo is still going up */
  outgoing: Outgoing | null;
  file?: File;
  preview?: string;
}

const pendingAsMessage = (pending: Pending, conversationId: string, myId: string): Message => ({
  _id: pending.localId,
  conversationId,
  senderId: myId,
  type: pending.outgoing?.type || 'image',
  content: pending.outgoing?.content || '',
  mediaUrl: pending.outgoing?.mediaUrl || null,
  metadata: pending.outgoing?.metadata || null,
  readBy: [myId],
  createdAt: pending.createdAt
});

function usePageVisible(): boolean {
  const [visible, setVisible] = useState(() => typeof document === 'undefined' || document.visibilityState === 'visible');
  useEffect(() => {
    const onChange = () => setVisible(document.visibilityState === 'visible');
    document.addEventListener('visibilitychange', onChange);
    return () => document.removeEventListener('visibilitychange', onChange);
  }, []);
  return visible;
}

/** With a phone keyboard up, the chat ends where the keyboard starts, so the box stays in sight */
function useKeyboardAwareHeight(ref: RefObject<HTMLElement>) {
  useEffect(() => {
    const viewport = window.visualViewport;
    if (!viewport) return undefined;
    const update = () => {
      const el = ref.current;
      if (!el) return;
      if (window.innerHeight - viewport.height < 120) { el.style.height = ''; return; }
      const top = el.getBoundingClientRect().top;
      el.style.height = `${Math.max(220, Math.round(viewport.height + viewport.offsetTop - top))}px`;
    };
    viewport.addEventListener('resize', update);
    viewport.addEventListener('scroll', update);
    return () => { viewport.removeEventListener('resize', update); viewport.removeEventListener('scroll', update); };
  }, [ref]);
}

export function ConversationPage() {
  const { conversationId = '' } = useParams();
  return <Chat key={conversationId} conversationId={conversationId} />;
}

function Chat({ conversationId }: { conversationId: string }) {
  const { userId: myId = '' } = useAuth();
  const queryClient = useQueryClient();
  const live = useStreamStatus() === 'live';
  const visible = usePageVisible();

  // ---- who it's with (there is no single-conversation endpoint: the list has it)
  const list = useQuery({ queryKey: [...MESSAGE_KEYS.conversations], queryFn: loadConversations });
  const conversation = (list.data || []).find((c) => idOf(c) === conversationId) || null;
  const askedAgain = useRef(false);
  useEffect(() => {
    // Opened from a profile a moment after the chat was made: the cached list predates it
    if (list.data && !conversation && !list.isFetching && !askedAgain.current) {
      askedAgain.current = true;
      list.refetch();
    }
  }, [list, conversation]);

  // ---- messages: the newest page is the query (the live stream refreshes it); everything seen is kept
  const [loaded, setLoaded] = useState<Message[]>([]);
  const [pending, setPending] = useState<Pending[]>([]);
  const [hasMore, setHasMore] = useState(true);
  const [older, setOlder] = useState<'idle' | 'loading' | 'error'>('idle');
  const [blocked, setBlocked] = useState(false);
  const [menuFor, setMenuFor] = useState<Message | null>(null);

  const latest = useQuery({
    queryKey: [...MESSAGE_KEYS.thread(conversationId)],
    queryFn: () => messagesPage(conversationId, undefined, PAGE),
    refetchInterval: (query) => {
      if (!live) return 15_000;
      // No event says a message was read, edited or deleted: look now and then,
      // more often while my last message waits to be read
      const page = query.state.data as Message[] | undefined;
      const last = page && page[page.length - 1];
      return last && last.senderId === myId && !readByOther(last) ? 10_000 : 60_000;
    }
  });

  useEffect(() => {
    if (!latest.data) return;
    setLoaded((have) => mergeMessages(have, latest.data || []));
  }, [latest.data]);
  const firstPageSeen = useRef(false);
  useEffect(() => {
    if (latest.data && !firstPageSeen.current) {
      firstPageSeen.current = true;
      // A short first page is the whole chat (the server can drop a row or two of its own)
      if (latest.data.length < PAGE - 10) setHasMore(false);
    }
  }, [latest.data]);

  const messages = useMemo(() => mergeMessages(loaded, latest.data || []), [loaded, latest.data]);

  /** Change one message wherever it is kept */
  const patch = useCallback((messageId: string, change: (message: Message) => Message) => {
    const apply = (have: Message[] | undefined) => (have ? have.map((m) => (idOf(m) === messageId ? change(m) : m)) : have);
    setLoaded((have) => apply(have) || have);
    queryClient.setQueryData<Message[]>([...MESSAGE_KEYS.thread(conversationId)], (have) => apply(have));
  }, [conversationId, queryClient]);

  // ---- who's who
  const group = isGroup(conversation);
  const other: ChatPerson | null = useMemo(() => {
    const fromList = otherPerson(conversation, myId) as ChatPerson | null;
    if (fromList && fromList.displayName) return fromList;
    const theirs = messages.find((m) => m.senderId !== myId && m.senderDetails);
    if (theirs?.senderDetails) return { ...theirs.senderDetails, _id: theirs.senderId };
    return fromList;
  }, [conversation, messages, myId]);
  const title = conversation ? conversationTitle(conversation, myId) : (other?.displayName || 'Chat');
  const otherFirst = group ? '' : firstName(other);
  const people = useMemo(() => {
    const byId = new Map<string, ChatPerson>();
    (conversation?.participantDetails || []).forEach((p) => byId.set(idOf(p), p));
    messages.forEach((m) => { if (m.senderDetails && !byId.has(m.senderId)) byId.set(m.senderId, m.senderDetails); });
    return byId;
  }, [conversation, messages]);

  // ---- scrolling
  const scroller = useRef<HTMLDivElement>(null);
  const content = useRef<HTMLDivElement>(null);
  const screen = useRef<HTMLElement>(null);
  const atBottom = useRef(true);
  const anchor = useRef<{ height: number; top: number } | null>(null);
  const loadingOlder = useRef(false);
  useKeyboardAwareHeight(screen);

  const toBottom = () => { const el = scroller.current; if (el) el.scrollTop = el.scrollHeight; };

  const loadOlder = useCallback(async () => {
    const el = scroller.current;
    const before = oldestStamp(messages);
    if (loadingOlder.current || !hasMore || !before || !el) return;
    loadingOlder.current = true;
    setOlder('loading');
    try {
      const page = await messagesPage(conversationId, before, PAGE);
      if (page.length === 0) setHasMore(false);
      else {
        anchor.current = { height: el.scrollHeight, top: el.scrollTop };
        setLoaded((have) => mergeMessages(have, page));
      }
      setOlder('idle');
    } catch {
      setOlder('error');
    } finally {
      loadingOlder.current = false;
    }
  }, [conversationId, hasMore, messages]);

  // An older page went in above: keep the message being read where it was
  useLayoutEffect(() => {
    const el = scroller.current;
    if (!el || !anchor.current) return;
    el.scrollTop = anchor.current.top + (el.scrollHeight - anchor.current.height);
    anchor.current = null;
  }, [loaded]);

  // Reading the newest: stay with it as messages and photos come in
  useLayoutEffect(() => { if (atBottom.current) toBottom(); });
  useEffect(() => {
    const el = content.current;
    if (!el || typeof ResizeObserver === 'undefined') return undefined;
    const observer = new ResizeObserver(() => { if (atBottom.current && !anchor.current) toBottom(); });
    observer.observe(el);
    return () => observer.disconnect();
  }, []);

  const onScroll = () => {
    const el = scroller.current;
    if (!el) return;
    atBottom.current = el.scrollHeight - el.scrollTop - el.clientHeight < BOTTOM_SLACK_PX;
    if (el.scrollTop < OLDER_TRIGGER_PX && older === 'idle') loadOlder();
  };

  // ---- reading: mark what they sent as read while the chat is open and in front
  const readSent = useRef(new Set<string>());
  useEffect(() => {
    if (!visible || !myId || messages.length === 0) return;
    const ids = unreadIds(messages, myId, readSent.current);
    if (ids.length === 0) return;
    ids.forEach((id) => readSent.current.add(id));
    (async () => {
      for (const part of chunk(ids, 100)) {
        try { await markRead(conversationId, part); } catch { part.forEach((id) => readSent.current.delete(id)); }
      }
      queryClient.invalidateQueries({ queryKey: [...BADGE_KEYS.messages] });
      queryClient.invalidateQueries({ queryKey: [...MESSAGE_KEYS.conversations] });
    })();
  }, [messages, visible, myId, conversationId, queryClient]);

  // ---- sending
  const updatePending = (localId: string, change: Partial<Pending>) =>
    setPending((have) => have.map((p) => (p.localId === localId ? { ...p, ...change } : p)));

  const deliver = async (item: Pending) => {
    updatePending(item.localId, { status: 'sending', error: undefined });
    let outgoing = item.outgoing;
    try {
      if (!outgoing && item.file) {
        const mediaUrl = await uploadImage(item.file);
        outgoing = { type: 'image', content: '', mediaUrl };
        updatePending(item.localId, { outgoing });
      }
      if (!outgoing) throw new Error('Nothing to send.');
      const saved = await sendMessage(conversationId, outgoing);
      atBottom.current = true;
      setLoaded((have) => mergeMessages(have, [saved]));
      setPending((have) => have.filter((p) => p.localId !== item.localId));
      if (item.preview) setTimeout(() => URL.revokeObjectURL(item.preview as string), 30_000);
      queryClient.invalidateQueries({ queryKey: [...MESSAGE_KEYS.conversations] });
    } catch (e) {
      const isBlocked = e instanceof ApiError && e.code === 'blocked';
      if (isBlocked) setBlocked(true);
      updatePending(item.localId, {
        status: 'failed',
        error: isBlocked ? "Couldn't send: you can't message this person." : `Couldn't send. ${messageOf(e)}`
      });
    }
  };

  const queue = (item: Omit<Pending, 'localId' | 'createdAt' | 'status'>) => {
    const next: Pending = { ...item, localId: `local-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`, createdAt: new Date().toISOString(), status: 'sending' };
    atBottom.current = true;
    setPending((have) => [...have, next]);
    deliver(next);
  };

  const sendText = (text: string) => queue({ outgoing: { type: 'text', content: text } });
  const sendPhoto = (file: File) => {
    if (!file.type.startsWith('image/')) return;
    queue({ outgoing: null, file, preview: URL.createObjectURL(file) });
  };
  const discard = (item: Pending) => {
    setPending((have) => have.filter((p) => p.localId !== item.localId));
    if (item.preview) URL.revokeObjectURL(item.preview);
  };

  // ---- what to draw
  const pendingMessages = pending.map((p) => pendingAsMessage(p, conversationId, myId));
  const shown = [...messages, ...pendingMessages];
  const pendingById = new Map(pending.map((p) => [p.localId, p]));
  const entryOf = (m: Message): Entry => ({ id: idOf(m), senderId: m.senderId, date: dateOf(m.createdAt), isMine: m.senderId === myId, readByOther: readByOther(m) });
  const rows = timelineRows(shown.map(entryOf), { grouped: true });
  const byId = new Map(shown.map((m) => [idOf(m), m]));
  const lastShown = shown[shown.length - 1];
  const status = !group && lastShown && !pendingById.has(idOf(lastShown)) ? receipt(messages.map(entryOf)) : null;

  const failedLoad = latest.isError && !latest.data;
  const notFound = failedLoad && latest.error instanceof ApiError && (latest.error.status === 404 || latest.error.status === 403);

  return (
    <>
      <Head title={title} back="/messages">
        {!group && other && idOf(other) ? (
          <Link to={`/user/${encodeURIComponent(idOf(other))}`} className="chat-head-person" aria-label={`${title}'s profile`}>
            <Avatar name={title} src={other.profilePicture} seed={idOf(other)} size={34} />
          </Link>
        ) : group ? <Avatar name={title} src={conversation?.avatar} seed={conversationId} size={34} /> : null}
      </Head>
      <main className="chat-screen" ref={screen}>
        <div className="chat-scroll" ref={scroller} onScroll={onScroll}>
          <div className="chat-content" ref={content}>
            {latest.isPending ? <Spinner /> : null}
            {failedLoad ? (
              <LoadError
                message={notFound ? "This chat isn't here. It may have been deleted, or you're not in it." : messageOf(latest.error)}
                retry={notFound ? undefined : () => latest.refetch()}
              />
            ) : null}
            {latest.data && messages.length > 0 ? (
              <div className="chat-top small">
                {older === 'loading' ? 'Loading earlier messages…' : null}
                {older === 'error' ? <>Earlier messages didn't load. <button type="button" className="linkish" onClick={loadOlder}>Try again</button></> : null}
                {older === 'idle' && hasMore ? <button type="button" className="linkish" onClick={loadOlder}>Show earlier messages</button> : null}
                {older === 'idle' && !hasMore ? (group ? 'The start of this group chat' : `The start of your chat with ${otherFirst || title}`) : null}
              </div>
            ) : null}
            {latest.data && shown.length === 0 ? (
              <div className="chat-hello card">
                <Avatar name={title} src={group ? conversation?.avatar : other?.profilePicture} seed={group ? conversationId : idOf(other)} size={72} />
                <h2>{title}</h2>
                <p className="muted">{group ? 'Nobody has said anything yet.' : `This is the start of your chat with ${otherFirst || title}.`}</p>
                <p className="chat-hello-wave">Say hi 👋</p>
              </div>
            ) : null}
            {rows.map((row, index) => {
              if (row.kind === 'day') return <p key={`day-${index}`} className="chat-day small">{row.title}</p>;
              const message = byId.get(row.id);
              if (!message) return null;
              const mine = message.senderId === myId;
              const local = pendingById.get(row.id);
              const sender = people.get(message.senderId) || message.senderDetails || null;
              const senderLabel = sender?.displayName || 'FavCircles member';
              let footer: ReactNode = null;
              if (local) {
                footer = local.status === 'sending'
                  ? <span className="muted">Sending…</span>
                  : (
                    <span className="chat-failed">
                      {local.error}{' '}
                      {!blocked ? <button type="button" className="linkish" onClick={() => deliver(local)}>Try again</button> : null}
                      {' '}<button type="button" className="linkish muted" onClick={() => discard(local)}>Remove</button>
                    </span>
                  );
              } else if (row.endsRun || status?.id === row.id) {
                const time = timeLabel(dateOf(message.createdAt));
                footer = <span className="muted">{time}{status?.id === row.id ? ` · ${status.text}` : ''}</span>;
              }
              return (
                <MessageBubble
                  key={row.id}
                  message={message}
                  mine={mine}
                  startsRun={row.startsRun}
                  endsRun={row.endsRun}
                  senderName={group && !mine && row.startsRun ? senderLabel : undefined}
                  avatar={!mine ? <Avatar name={senderLabel} src={sender?.profilePicture} seed={message.senderId} size={28} /> : undefined}
                  localImage={local?.preview}
                  onMenu={local ? undefined : () => setMenuFor(message)}
                  footer={footer}
                />
              );
            })}
          </div>
        </div>
        {blocked ? (
          <p className="chat-blocked small">You can't send messages in this chat. One of you has blocked the other.</p>
        ) : (
          <Composer
            placeholder={otherFirst ? `Message ${otherFirst}` : 'Message'}
            onSend={sendText}
            onPhoto={sendPhoto}
            disabled={failedLoad}
          />
        )}
      </main>
      {menuFor ? (
        <MessageActionsSheet
          message={menuFor}
          myId={myId}
          onClose={() => setMenuFor(null)}
          onEdited={(saved) => patch(idOf(saved), (m) => ({ ...m, content: saved.content, editedAt: saved.editedAt || new Date().toISOString() }))}
          onDeleted={(messageId) => {
            patch(messageId, (m) => ({ ...m, content: '[Message deleted]', deletedAt: new Date().toISOString() }));
            queryClient.invalidateQueries({ queryKey: [...MESSAGE_KEYS.conversations] });
          }}
        />
      ) : null}
    </>
  );
}
