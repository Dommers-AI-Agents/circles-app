// Messages: conversations, one chat's messages, sending, editing, deleting,
// read receipts, and the people a new chat can be started with. Shapes are
// read from backend/controllers/messagingController.js (routes in
// routes/messagingRoutes.js, mounted at /api/messages).
import { del, get, post, put } from './client';
import type { User } from './types';
import type { ConversationLike, MessageLike, PersonLike } from '../logic/chatThread';
import { idOf, messageablePeople } from '../logic/chatThread';
import { outgoingShare, type ShareInput } from '../logic/messageShare';

const uid = (id: string) => encodeURIComponent(id);

/** A person as the messaging endpoints send them (the public card; some use `id`, some `_id`) */
export type ChatPerson = PersonLike & { _id?: string; id?: string; displayName?: string; profilePicture?: string | null };

export interface Conversation extends ConversationLike {
  _id?: string;
  id?: string;
  type?: 'direct' | 'group' | string;
  participants: string[];
  participantDetails?: ChatPerson[] | null;
  lastMessageType?: string | null;
  updatedAt?: string | null;
}

export type MessageType = 'text' | 'image' | 'location' | 'place_share' | 'circle_share' | 'connection_request' | string;

export interface Message extends MessageLike {
  _id?: string;
  id?: string;
  conversationId: string;
  senderId: string;
  type: MessageType;
  content: string;
  mediaUrl?: string | null;
  metadata?: Record<string, unknown> | null;
  readBy?: string[];
  editedAt?: string | null;
  deletedAt?: string | null;
  createdAt: string;
  senderDetails?: ChatPerson | null;
}

export const conversations = () =>
  get<{ conversations: Conversation[] }>('/messages/conversations').then((r) => r.conversations || []);

/**
 * The one-on-one chat with someone, made the first time. Only connections
 * can message each other: a 403 says so (no `code`).
 */
export const directConversation = (userId: string) =>
  post<{ conversation: Conversation }>(`/messages/conversations/direct/${uid(userId)}`).then((r) => r.conversation);

/** A page of messages, oldest first. `before` is the oldest createdAt already shown. */
export const messagesPage = (conversationId: string, before?: string, limit = 50) =>
  get<{ messages: Message[] }>(`/messages/conversations/${uid(conversationId)}/messages`, { limit, before })
    .then((r) => r.messages || []);

export interface Outgoing {
  type: MessageType;
  content: string;
  mediaUrl?: string;
  metadata?: Record<string, unknown>;
}

/** 403 `code: 'blocked'` when one of you blocked the other */
export const sendMessage = (conversationId: string, message: Outgoing) =>
  post<{ message: Message }>(`/messages/conversations/${uid(conversationId)}/messages`, message).then((r) => r.message);

/** A place or circle card, with the same content and metadata the iOS app sends */
export const sendShare = (conversationId: string, share: ShareInput) => {
  const outgoing = outgoingShare(share);
  return sendMessage(conversationId, { type: outgoing.type, content: outgoing.content, metadata: outgoing.metadata });
};

/** Text messages only, and only your own */
export const editMessage = (messageId: string, content: string) =>
  put<{ message: Message }>(`/messages/${uid(messageId)}`, { content }).then((r) => r.message);

/** Soft delete: the message stays as "[Message deleted]" */
export const deleteMessage = (messageId: string) => del<{ message: string }>(`/messages/${uid(messageId)}`);

export const markRead = (conversationId: string, messageIds: string[]) =>
  post<{ message: string }>(`/messages/conversations/${uid(conversationId)}/read`, { messageIds });

// ---- who a new chat can be with
interface RawConnection {
  userId: string;
  connectedUserId: string;
  status: string;
  connectedUser?: ChatPerson & User;
}

const personOf = (raw: ChatPerson): ChatPerson => ({ ...raw, _id: String(raw._id || raw.id || '') });

/** My accepted connections (they can be messaged), then people I follow (they can't, until we connect) */
export async function messageable(myId: string): Promise<Array<ChatPerson & { connected: boolean }>> {
  const [connectionList, followingList] = await Promise.all([
    get<{ connections: RawConnection[] }>('/connections').then((r) => r.connections || []),
    get<{ following: ChatPerson[] }>(`/users/${uid(myId)}/following`).then((r) => r.following || []).catch(() => [] as ChatPerson[])
  ]);
  const connected = connectionList
    .filter((connection) => connection.status === 'accepted' && connection.connectedUser)
    .map((connection) => personOf(connection.connectedUser as ChatPerson))
    .filter((person) => idOf(person));
  const followed = followingList.map(personOf).filter((person) => idOf(person));
  return messageablePeople(connected, followed, myId);
}
