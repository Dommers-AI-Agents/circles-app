// What a live-stream event makes stale. Pure: an event in, query keys out;
// realtime/LiveUpdates.tsx hands them to the query client.
import type { StreamEvent } from './sseParser';

export type Key = ReadonlyArray<string>;

export interface BadgeKeys { messages: Key; notifications: Key }

export const MESSAGE_KEYS = {
  conversations: ['messages', 'conversations'] as Key,
  people: ['messages', 'people'] as Key,
  thread: (conversationId: string): Key => ['messages', 'thread', conversationId]
};

const record = (value: unknown): Record<string, unknown> =>
  (value && typeof value === 'object' && !Array.isArray(value) ? (value as Record<string, unknown>) : {});
const idText = (value: unknown): string | undefined => (typeof value === 'string' && value ? value : undefined);

/** Every person an event about connections or follows names, whatever the field is called at that call site */
function peopleIn(data: Record<string, unknown>): string[] {
  const ids = new Set<string>();
  ['userId', 'connectedUserId', 'targetUserId', 'followerId', 'fromUserId', 'otherUserId', 'acceptedBy'].forEach((field) => {
    const id = idText(data[field]);
    if (id) ids.add(id);
  });
  ['from', 'user', 'connectedUser', 'acceptedByUser'].forEach((field) => {
    const person = record(data[field]);
    const id = idText(person._id) || idText(person.id);
    if (id) ids.add(id);
  });
  return Array.from(ids);
}

export function invalidationsFor(event: StreamEvent, badges: BadgeKeys, myId?: string): Key[] {
  const data = record(event.data);
  const type = event.type;
  if (type === 'new_message') {
    const conversationId = idText(data.conversationId);
    return [MESSAGE_KEYS.conversations, ...(conversationId ? [MESSAGE_KEYS.thread(conversationId)] : []), badges.messages];
  }
  if (type === 'new_notification' || type === 'notification_count') return [badges.notifications, ['notifications']];
  if (type === 'new_activity' || type === 'activity_comment' || type === 'activity_reaction') return [['feed']];
  if (type.startsWith('connection_') || type.startsWith('follower_') || type.startsWith('following_')) {
    const ids = new Set(peopleIn(data));
    if (myId) ids.add(myId);
    // Who I can message changes with my connections and follows
    return [['people'], MESSAGE_KEYS.people, ...Array.from(ids).map((id): Key => ['user', id])];
  }
  if (type === 'specials_updated') return [['rewards'], ['locals']];
  return [];
}
