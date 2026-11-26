// Where I stand with another person. Two separate things, as in the iOS app:
// following is one-way (a private profile turns it into a request), and a
// connection is the "I know them" step both people agree to.

export type FollowState = 'none' | 'requested' | 'following';

export function followStateOf(person: { isFollowing?: boolean; followRequested?: boolean } | null | undefined): FollowState {
  if (!person) return 'none';
  if (person.isFollowing === true) return 'following';
  if (person.followRequested === true) return 'requested';
  return 'none';
}

export const followLabel = (state: FollowState): string =>
  state === 'following' ? 'Following' : state === 'requested' ? 'Requested' : 'Follow';

export type ConnectionState = 'none' | 'outgoing' | 'incoming' | 'connected';

export interface ConnectionLike {
  _id?: string;
  id?: string;
  userId: string;
  connectedUserId: string;
  status: string;
}

export interface ConnectionStanding {
  state: ConnectionState;
  /** The connection record to accept, decline or remove; absent for 'none' */
  connectionId?: string;
}

/**
 * My standing with `otherId`, from my connections list. `userId` is who
 * asked and `connectedUserId` who was asked, so a pending record I was asked
 * in is "incoming". A blocked record counts as none: there is nothing to accept.
 */
export function connectionWith(connections: ConnectionLike[] | undefined, myId: string | undefined, otherId: string): ConnectionStanding {
  if (!connections || !myId || !otherId || myId === otherId) return { state: 'none' };
  const between = connections.filter((c) =>
    (c.userId === myId && c.connectedUserId === otherId) || (c.userId === otherId && c.connectedUserId === myId));
  // An accepted record wins over a stray pending one for the same pair
  const record = between.find((c) => c.status === 'accepted') || between.find((c) => c.status === 'pending');
  if (!record) return { state: 'none' };
  const connectionId = record._id || record.id;
  if (record.status === 'accepted') return { state: 'connected', connectionId };
  return { state: record.userId === myId ? 'outgoing' : 'incoming', connectionId };
}

export interface PeopleLists<C extends ConnectionLike> {
  /** Invitations waiting for my answer */
  incoming: C[];
  /** Invitations I sent that haven't been answered */
  outgoing: C[];
  connected: C[];
}

/** My connections list split by what each record needs from me. Order is kept. */
export function splitConnections<C extends ConnectionLike>(connections: C[] | undefined, myId: string | undefined): PeopleLists<C> {
  const lists: PeopleLists<C> = { incoming: [], outgoing: [], connected: [] };
  (connections || []).forEach((c) => {
    if (c.status === 'accepted') lists.connected.push(c);
    else if (c.status === 'pending' && c.connectedUserId === myId) lists.incoming.push(c);
    else if (c.status === 'pending' && c.userId === myId) lists.outgoing.push(c);
  });
  return lists;
}

/** The other person's id in a connection record. */
export const otherIdOf = (connection: ConnectionLike, myId: string | undefined): string =>
  connection.userId === myId ? connection.connectedUserId : connection.userId;

export interface ReasonSource {
  suggestionReason?: string | null;
  /** Kilometres, when the server placed them near me */
  distance?: number | null;
  followsYou?: boolean;
  discoveryType?: string;
  location?: string | null;
  placesCount?: number;
  /** Friends of friends: who we both know */
  mutualConnectionNames?: string[] | null;
}

/** The one line under a person in a list (the iOS rule, NetworkDiscoverLayout.reason). */
export function reasonFor(person: ReasonSource): string {
  if (person.suggestionReason) return person.suggestionReason;
  if (typeof person.distance === 'number' && Number.isFinite(person.distance)) {
    const miles = person.distance * 0.621371;
    return miles < 1 ? '📍 Near you' : `📍 ${Math.round(miles)} mi away`;
  }
  if (person.followsYou === true || person.discoveryType === 'followsYou') return '👋 Follows you';
  const mutual = person.mutualConnectionNames && person.mutualConnectionNames[0];
  if (mutual) return `Knows ${mutual}`;
  const parts: string[] = [];
  if (person.location) parts.push(person.location);
  if (typeof person.placesCount === 'number' && person.placesCount > 0) parts.push(`${person.placesCount} ${person.placesCount === 1 ? 'place' : 'places'}`);
  return parts.join(' · ') || 'On FavCircles';
}

/**
 * Suggestions are people I can still follow or connect with: anyone I'm
 * already connected to, or have an invitation open with, is left out (the
 * iOS rule, NetworkDiscoverLayout.mergePeople).
 */
export const stillToMeet = <P extends { connectionStatus?: string | null }>(people: P[]): P[] =>
  people.filter((p) => !['accepted', 'connected', 'pending'].includes(String(p.connectionStatus || '').toLowerCase()));
