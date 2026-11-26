// The rules of one conversation and of the conversations list that don't
// need a screen: who the chat is with, what the list shows under a name,
// which messages to mark read, how pages of messages join up.
import { dayNumber, type Clock } from './chatTimeline';

export interface PersonLike {
  _id?: string;
  id?: string;
  displayName?: string | null;
  firstName?: string | null;
  profilePicture?: string | null;
}

export interface ConversationLike {
  _id?: string;
  id?: string;
  type?: string;
  participants?: string[];
  name?: string | null;
  avatar?: string | null;
  lastMessage?: string | null;
  lastMessageTime?: string | null;
  lastMessageSenderId?: string | null;
  lastMessageSenderName?: string | null;
  unreadCounts?: Record<string, number> | null;
  participantDetails?: PersonLike[] | null;
  createdAt?: string | null;
}

export interface MessageLike {
  _id?: string;
  id?: string;
  senderId: string;
  type?: string;
  content?: string | null;
  readBy?: string[] | null;
  deletedAt?: string | null;
  createdAt?: string | null;
}

export const idOf = (thing: { _id?: string; id?: string } | null | undefined): string => (thing && (thing._id || thing.id)) || '';

export const isGroup = (conversation: ConversationLike | null | undefined): boolean => !!conversation && conversation.type === 'group';

/** The other person in a one-on-one chat (the server sends only them in participantDetails) */
export function otherPerson(conversation: ConversationLike | null | undefined, myId: string | undefined): PersonLike | null {
  if (!conversation || isGroup(conversation)) return null;
  const details = conversation.participantDetails || [];
  const found = details.find((person) => idOf(person) && idOf(person) !== myId);
  if (found) return found;
  const otherId = (conversation.participants || []).find((id) => id !== myId);
  return otherId ? { _id: otherId } : null;
}

export function conversationTitle(conversation: ConversationLike | null | undefined, myId: string | undefined): string {
  if (!conversation) return 'Chat';
  if (isGroup(conversation)) return (conversation.name || '').trim() || 'Group chat';
  const other = otherPerson(conversation, myId);
  return (other?.displayName || '').trim() || 'FavCircles member';
}

/** "Sam" from "Sam Rivera": what the composer and the empty chat call them */
export function firstName(person: PersonLike | null | undefined): string {
  if (!person) return '';
  const first = (person.firstName || '').trim();
  if (first) return first;
  return (person.displayName || '').trim().split(/\s+/)[0] || '';
}

export function unreadCount(conversation: ConversationLike, myId: string | undefined): number {
  const value = myId && conversation.unreadCounts ? conversation.unreadCounts[myId] : 0;
  return typeof value === 'number' && value > 0 ? Math.floor(value) : 0;
}

/**
 * The words for one message in a list. The server stores the last message
 * as its text, or "[image]" / "[location]" when it had none, and
 * "[Message deleted]" for a deleted one.
 */
export function previewText(content: string | null | undefined, type?: string | null): string {
  const value = (content || '').trim();
  if (value === '[Message deleted]') return 'Message deleted';
  if (value === '[image]' || (!value && type === 'image')) return '📷 Photo';
  if (value === '[location]' || (!value && type === 'location')) return '📌 Location';
  if (value === '[place_share]' || (!value && type === 'place_share')) return '📍 A place';
  if (value === '[circle_share]' || (!value && type === 'circle_share')) return '⭕️ A circle';
  if (/^\[[a-z_]+\]$/.test(value)) return 'Message';
  return value.replace(/\s+/g, ' ');
}

/** The line under the name in the conversations list: "You: See you there", "Sam: 📷 Photo", "No messages yet" */
export function conversationPreview(conversation: ConversationLike, myId: string | undefined): string {
  const words = previewText(conversation.lastMessage);
  if (!words) return 'No messages yet';
  if (conversation.lastMessageSenderId && conversation.lastMessageSenderId === myId) return `You: ${words}`;
  if (isGroup(conversation)) {
    const sender = (conversation.lastMessageSenderName || '').trim().split(/\s+/)[0];
    if (sender) return `${sender}: ${words}`;
  }
  return words;
}

/** When the list says a chat last moved: the time today, "Yesterday", the weekday this week, then the date */
export function listTime(value: string | null | undefined, clock: Clock = {}): string {
  if (!value) return '';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '';
  const { timeZone, locale } = clock;
  const now = clock.now || new Date();
  const days = dayNumber(now, timeZone) - dayNumber(date, timeZone);
  if (days === 0) return new Intl.DateTimeFormat(locale, { timeZone, hour: 'numeric', minute: '2-digit' }).format(date);
  if (days === 1) return 'Yesterday';
  if (days > 0 && days < 7) return new Intl.DateTimeFormat(locale, { timeZone, weekday: 'short' }).format(date);
  const sameYear = new Intl.DateTimeFormat('en-US', { timeZone, year: 'numeric' }).format(date)
    === new Intl.DateTimeFormat('en-US', { timeZone, year: 'numeric' }).format(now);
  return new Intl.DateTimeFormat(locale, sameYear ? { timeZone, month: 'short', day: 'numeric' } : { timeZone, month: 'short', day: 'numeric', year: 'numeric' }).format(date);
}

/** Newest first, by the last message (a chat with none sorts by when it was made). The server sorts too; this holds after a local change. */
export function newestFirst<T extends ConversationLike>(conversations: T[]): T[] {
  const stamp = (c: ConversationLike) => c.lastMessageTime || c.createdAt || '';
  return conversations.map((c, index) => ({ c, index }))
    .sort((a, b) => (stamp(b.c) < stamp(a.c) ? -1 : stamp(b.c) > stamp(a.c) ? 1 : a.index - b.index))
    .map((entry) => entry.c);
}

/** Pages of messages joined into one list, oldest first, each message once; a later copy of a message replaces the earlier one. */
export function mergeMessages<T extends MessageLike>(have: T[], incoming: T[]): T[] {
  if (incoming.length === 0) return have;
  const byId = new Map<string, T>();
  have.forEach((message) => byId.set(idOf(message), message));
  incoming.forEach((message) => { if (idOf(message)) byId.set(idOf(message), message); });
  return Array.from(byId.values()).map((message, index) => ({ message, index })).sort((a, b) => {
    const x = a.message.createdAt || '';
    const y = b.message.createdAt || '';
    return x < y ? -1 : x > y ? 1 : a.index - b.index;
  }).map((entry) => entry.message);
}

/** Messages from someone else that I haven't read yet (what POST …/read is sent) */
export function unreadIds(messages: MessageLike[], myId: string | undefined, alreadySent: ReadonlySet<string> = new Set()): string[] {
  if (!myId) return [];
  return messages
    .filter((message) => message.senderId !== myId && !(message.readBy || []).includes(myId))
    .map(idOf)
    .filter((id) => id && !alreadySent.has(id));
}

export function chunk<T>(items: T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < items.length; i += Math.max(1, size)) out.push(items.slice(i, i + Math.max(1, size)));
  return out;
}

/** Someone other than the sender has read it */
export const readByOther = (message: MessageLike): boolean => (message.readBy || []).some((id) => id !== message.senderId);

/** The `before` cursor for the next older page */
export const oldestStamp = (messages: MessageLike[]): string | undefined => messages.find((message) => message.createdAt)?.createdAt || undefined;

/** Enter sends on a computer; on a phone it makes a new line (the send button sends). Shift+Enter is always a new line. */
export function enterSends(key: { key: string; shiftKey?: boolean; isComposing?: boolean; keyCode?: number }, touchKeyboard: boolean): boolean {
  if (key.key !== 'Enter' || key.shiftKey || key.isComposing || key.keyCode === 229) return false;
  return !touchKeyboard;
}

/** People whose name matches what was typed; everyone when nothing was */
export function filterPeople<T extends { displayName?: string | null }>(people: T[], typed: string): T[] {
  const words = typed.trim().toLowerCase().split(/\s+/).filter(Boolean);
  if (words.length === 0) return people;
  return people.filter((person) => {
    const name = (person.displayName || '').toLowerCase();
    return words.every((word) => name.split(/\s+/).some((part) => part.startsWith(word)) || name.includes(word));
  });
}

/** Connections first (they can be messaged), then the people I follow who aren't connections; nobody twice, never me. */
export function messageablePeople<T extends PersonLike>(connections: T[], following: T[], myId: string | undefined): Array<T & { connected: boolean }> {
  const seen = new Set<string>(myId ? [myId] : []);
  const out: Array<T & { connected: boolean }> = [];
  const add = (person: T, connected: boolean) => {
    const id = idOf(person);
    if (!id || seen.has(id)) return;
    seen.add(id);
    out.push({ ...person, connected });
  };
  connections.forEach((person) => add(person, true));
  following.forEach((person) => add(person, false));
  return out;
}

/** Deleted messages stay as "[Message deleted]" with deletedAt set (an image keeps its mediaUrl) */
export const isDeleted = (message: MessageLike): boolean => !!message.deletedAt || (message.content || '').trim() === '[Message deleted]';

/** What a long-press can do to a message: copy words it has; edit (text only) and delete your own */
export function messageActions(message: MessageLike, myId: string | undefined): { copy: boolean; edit: boolean; remove: boolean } {
  const mine = !!myId && message.senderId === myId;
  const deleted = isDeleted(message);
  const words = (message.content || '').trim();
  const placeholder = /^\[[a-z_]+\]$/i.test(words);
  return {
    copy: !deleted && !!words && !placeholder,
    edit: mine && !deleted && (message.type || 'text') === 'text',
    remove: mine && !deleted
  };
}
