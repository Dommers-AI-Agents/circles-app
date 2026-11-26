// Messages: every chat, the one that moved last on top, with what was said
// last and how many I haven't read.
import { useState } from 'react';
import { Link } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import { conversations as loadConversations, type Conversation } from '../api/messages';
import { messageOf } from '../api/client';
import { useAuth } from '../auth/AuthContext';
import {
  conversationPreview, conversationTitle, idOf, isGroup, listTime, newestFirst, otherPerson, unreadCount
} from '../logic/chatThread';
import { MESSAGE_KEYS } from '../logic/liveInvalidations';
import { useStreamStatus } from '../realtime/sse';
import { Avatar, Empty, Head, LoadError, Spinner } from '../ui/kit';
import { NewMessageSheet } from '../ui/chat/NewMessageSheet';
import './MessagesPage.css';

function ConversationRow({ conversation, myId }: { conversation: Conversation; myId: string | undefined }) {
  const group = isGroup(conversation);
  const other = otherPerson(conversation, myId);
  const name = conversationTitle(conversation, myId);
  const unread = unreadCount(conversation, myId);
  return (
    <li>
      <Link className={`item convo ${unread > 0 ? 'unread' : ''}`} to={`/messages/${encodeURIComponent(idOf(conversation))}`}>
        <Avatar name={name} src={group ? conversation.avatar : other?.profilePicture} seed={group ? idOf(conversation) : idOf(other)} size={48} />
        <span className="grow">
          <span className="convo-top">
            <strong className="grow clip">{name}</strong>
            <span className="convo-time small">{listTime(conversation.lastMessageTime || conversation.createdAt)}</span>
          </span>
          <span className="convo-bottom">
            <span className="grow clip convo-preview">{conversationPreview(conversation, myId)}</span>
            {unread > 0 ? <span className="convo-unread" aria-label={`${unread} unread`}>{unread > 99 ? '99+' : unread}</span> : null}
          </span>
        </span>
      </Link>
    </li>
  );
}

export function MessagesPage() {
  const { userId } = useAuth();
  const live = useStreamStatus() === 'live';
  const [composing, setComposing] = useState(false);
  const list = useQuery({
    queryKey: [...MESSAGE_KEYS.conversations],
    queryFn: loadConversations,
    // The live stream refreshes this on a new message; without it, look every 30 s
    refetchInterval: live ? false : 30_000
  });
  const chats = newestFirst(list.data || []);

  return (
    <>
      <Head title="Messages" lead>
        <button className="icon-btn" onClick={() => setComposing(true)} aria-label="New message">
          <svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
            <path d="M4 20h4L19 9l-4-4L4 16v4Zm9-13 4 4" />
          </svg>
        </button>
      </Head>
      <main className="page">
        {list.isPending ? <Spinner /> : null}
        {list.isError && !list.data ? <LoadError message={messageOf(list.error)} retry={() => list.refetch()} /> : null}
        {list.data && chats.length === 0 ? (
          <Empty
            mark="💬"
            title="No messages yet"
            action={<button className="btn" onClick={() => setComposing(true)}>Write your first message</button>}
          >
            Send a connection a note, a place you love, or a circle to try.
          </Empty>
        ) : null}
        {chats.length > 0 ? (
          <>
            <button className="btn soft block convo-new" onClick={() => setComposing(true)}>New message</button>
            <ul className="list card convo-list">
              {chats.map((conversation) => <ConversationRow key={idOf(conversation)} conversation={conversation} myId={userId} />)}
            </ul>
          </>
        ) : null}
      </main>
      {composing ? <NewMessageSheet onClose={() => setComposing(false)} /> : null}
    </>
  );
}
