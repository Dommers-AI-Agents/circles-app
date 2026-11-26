// Someone else's profile: who they are, where I stand with them (follow,
// connect, message, block) and their circles in their own order. Shared
// profile links (/user/<id>) open here; my own id goes to /me.
import { useState } from 'react';
import { Navigate, useNavigate, useParams } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import { messageOf } from '../api/client';
import {
  acceptConnection, block, blockStatus, connections as loadConnections, declineConnection, directConversation,
  invite, profile as loadProfile, removeConnection, unblock
} from '../api/people';
import type { Circle } from '../api/types';
import { useAuth } from '../auth/AuthContext';
import { plural } from '../logic/labels';
import { connectionWith, type ConnectionStanding } from '../logic/relationship';
import { Avatar, ConfirmSheet, Empty, Head, LoadError, Sheet, Spinner, toast } from '../ui/kit';
import { CircleCard } from '../ui/CircleCard';
import { SHARE_BASE, shareLink } from '../ui/share';
import { FollowButton } from '../ui/people/FollowButton';
import { PeopleListSheet } from '../ui/people/PeopleListSheet';
import { useRelationshipRefresh } from '../ui/people/hooks';
import '../ui/people/people.css';
import './user.css';

export function UserPage() {
  const { userId = '' } = useParams();
  const { userId: myId } = useAuth();
  if (userId && userId === myId) return <Navigate to="/me" replace />;
  // A new person is a new screen: no sheet or busy state carries over
  return <UserProfile key={userId} userId={userId} myId={myId} />;
}

type Asking = null | 'more' | 'cancelInvite' | 'disconnect' | 'block' | 'unblock' | 'followers' | 'following';

/** Places in the circles this viewer can see or sees locked (a save lives in one circle). */
const placesIn = (circles: Circle[]) => circles.reduce((sum, c) => sum + (c.placesCount ?? (c.places ? c.places.length : 0)), 0);

function UserProfile({ userId, myId }: { userId: string; myId: string | undefined }) {
  const navigate = useNavigate();
  const refresh = useRelationshipRefresh();
  const [asking, setAsking] = useState<Asking>(null);
  const [busy, setBusy] = useState(false);

  const profile = useQuery({ queryKey: ['user', userId], queryFn: () => loadProfile(userId) });
  const connections = useQuery({ queryKey: ['people', 'connections'], queryFn: loadConnections });
  const blocked = useQuery({ queryKey: ['user', userId, 'block'], queryFn: () => blockStatus(userId) });

  const user = profile.data?.user;
  const circles = profile.data?.circles || [];
  const name = user?.displayName || 'This person';
  const standing: ConnectionStanding = connectionWith(connections.data, myId, userId);
  const blockedByMe = blocked.data?.isBlockedByMe === true;
  const following = user?.isFollowing === true;
  const connected = standing.state === 'connected';
  // A private profile shows its circles only to followers and connections
  const closedToMe = !!user && user.profilePrivate === true && !following && !connected;

  /** One write, then reload what it changed and say what happened. */
  const act = async (work: () => Promise<unknown>, said: string | ((result: unknown) => string)) => {
    setAsking(null);
    setBusy(true);
    try {
      const result = await work();
      await refresh();
      toast(typeof said === 'function' ? said(result) : said);
    } catch (error) {
      toast(messageOf(error));
    } finally {
      setBusy(false);
    }
  };

  const connect = () => act(() => invite(userId), (result) => {
    const reply = result as { data?: { status?: string } };
    return reply.data?.status === 'accepted' ? `You're connected with ${name}` : `Invitation sent to ${name}`;
  });
  const accept = () => standing.connectionId && act(() => acceptConnection(standing.connectionId as string), `You're connected with ${name}`);
  const decline = () => standing.connectionId && act(() => declineConnection(standing.connectionId as string), 'Invitation declined');
  const cancelInvite = () => standing.connectionId && act(() => declineConnection(standing.connectionId as string), 'Invitation taken back');
  const disconnect = () => standing.connectionId && act(() => removeConnection(standing.connectionId as string), `You're no longer connected with ${name}`);
  const doBlock = () => act(() => block(userId), `You blocked ${name}`);
  const doUnblock = () => act(() => unblock(userId), `You unblocked ${name}`);

  const message = async () => {
    setBusy(true);
    try {
      const conversationId = await directConversation(userId);
      if (!conversationId) throw new Error("That conversation couldn't be opened. Try again.");
      navigate(`/messages/${encodeURIComponent(conversationId)}`);
    } catch (error) {
      toast(messageOf(error));
      setBusy(false);
    }
  };

  const share = () => {
    setAsking(null);
    void shareLink(`${name} on FavCircles`, `${SHARE_BASE}/user/${encodeURIComponent(userId)}`);
  };

  return (
    <>
      <Head title={user ? user.displayName : 'Profile'} back>
        {user ? <button className="icon-btn" onClick={() => setAsking('more')} aria-label="More">•••</button> : null}
      </Head>
      <main className="page">
        {profile.isPending ? <Spinner /> : null}
        {profile.isError ? <LoadError message={messageOf(profile.error)} retry={() => profile.refetch()} /> : null}
        {user ? (
          <>
            <div className="profile-top">
              <Avatar name={user.displayName} src={user.profilePicture} size={76} seed={user._id} />
              <div className="grow">
                <h2 className="user-name">{user.displayName}</h2>
                {user.location ? <p className="muted small">{user.location}</p> : null}
                <p className="user-chips">
                  {user.followsYou ? <span className="chip">Follows you</span> : null}
                  {user.profilePrivate ? <span className="chip gray">🔒 Private profile</span> : null}
                  {connected ? <span className="chip">Connected</span> : null}
                </p>
              </div>
            </div>
            {user.bio ? <p className="user-bio">{user.bio}</p> : null}

            <div className="user-counts">
              <button type="button" onClick={() => setAsking('followers')}><b>{user.followersCount ?? 0}</b> {user.followersCount === 1 ? 'follower' : 'followers'}</button>
              <button type="button" onClick={() => setAsking('following')}><b>{user.followingCount ?? 0}</b> following</button>
              <span><b>{user.placesCount ?? placesIn(circles)}</b> {(user.placesCount ?? placesIn(circles)) === 1 ? 'place' : 'places'}</span>
            </div>

            {blockedByMe ? (
              <div className="card user-note">
                <strong>You blocked {name}</strong>
                <p className="small muted">Neither of you sees the other's places, circles or messages.</p>
                <button className="btn soft block" disabled={busy} onClick={() => setAsking('unblock')}>Unblock</button>
              </div>
            ) : (
              <>
                {standing.state === 'incoming' ? (
                  <div className="card user-note">
                    <strong>{name} wants to connect</strong>
                    <p className="small muted">Connections see each other's My Network circles and follow each other.</p>
                    <div className="row">
                      <button className="btn grow" disabled={busy} onClick={accept}>Accept</button>
                      <button className="btn soft grow" disabled={busy} onClick={decline}>Decline</button>
                    </div>
                  </div>
                ) : null}
                <div className="user-actions">
                  <FollowButton person={user} confirmUnfollow />
                  {standing.state === 'none' ? (
                    <button className="btn soft" disabled={busy || connections.isPending} onClick={connect}>Connect</button>
                  ) : null}
                  {standing.state === 'outgoing' ? (
                    <button className="btn soft" disabled={busy} onClick={() => setAsking('cancelInvite')}>Invitation sent</button>
                  ) : null}
                  {connected ? (
                    <button className="btn soft" disabled={busy} onClick={() => setAsking('disconnect')}>Connected</button>
                  ) : null}
                  {/* The server lets only connections message each other */}
                  {connected ? <button className="btn soft" disabled={busy} onClick={message}>Message</button> : null}
                </div>
                {connections.isError ? <p className="small muted user-hint">Couldn't check whether you're connected. Try again in a moment.</p> : null}
              </>
            )}

            {closedToMe && !blockedByMe ? (
              <div className="card user-note">
                <strong>🔒 This profile is private</strong>
                <p className="small muted">
                  {user.followRequested
                    ? `You asked to follow ${name}. Their circles and places open when they say yes.`
                    : `Only people ${name} lets follow them see their circles and places. Tap Follow to ask.`}
                </p>
              </div>
            ) : null}

            {!blockedByMe ? (
              <>
                <p className="section-title">
                  Circles{circles.length ? ` · ${plural(circles.length, 'circle')}` : ''}
                </p>
                {circles.length === 0 ? (
                  <Empty mark="⭕" title={closedToMe ? 'Circles are hidden' : 'No circles to show'}>
                    {closedToMe
                      ? `${name}'s circles show once you follow them.`
                      : `${name} hasn't shared any circles you can see yet.`}
                  </Empty>
                ) : (
                  <div className="circle-grid">
                    {circles.map((circle) => <CircleCard key={circle._id} circle={circle} />)}
                  </div>
                )}
              </>
            ) : null}
          </>
        ) : null}
      </main>

      {asking === 'more' && user ? (
        <Sheet title={name} onClose={() => setAsking(null)}>
          <button className="btn block soft sheet-choice" onClick={share}>Share profile</button>
          {connected ? <button className="btn block soft sheet-choice" onClick={() => setAsking('disconnect')}>Remove connection</button> : null}
          {blockedByMe
            ? <button className="btn block soft sheet-choice" onClick={() => setAsking('unblock')}>Unblock</button>
            : <button className="btn block danger" onClick={() => setAsking('block')}>Block</button>}
          <button className="btn block plain" onClick={() => setAsking(null)}>Cancel</button>
        </Sheet>
      ) : null}
      {asking === 'cancelInvite' ? (
        <ConfirmSheet title="Take back your invitation?" action="Take it back"
          body={`${name} hasn't answered yet. You can invite them again later.`}
          onConfirm={cancelInvite} onClose={() => setAsking(null)} />
      ) : null}
      {asking === 'disconnect' ? (
        <ConfirmSheet title={`Remove ${name} as a connection?`} danger action="Remove connection"
          body="You stop following them and no longer see each other's My Network circles. They aren't told."
          onConfirm={disconnect} onClose={() => setAsking(null)} />
      ) : null}
      {asking === 'block' ? (
        <ConfirmSheet title={`Block ${name}?`} danger action="Block"
          body="You stop following each other, any connection ends, and neither of you sees the other's places, circles or messages. They aren't told. You can unblock them in Settings."
          onConfirm={doBlock} onClose={() => setAsking(null)} />
      ) : null}
      {asking === 'unblock' ? (
        <ConfirmSheet title={`Unblock ${name}?`} action="Unblock"
          body="You can find and follow each other again. You won't be following or connected until one of you asks."
          onConfirm={doUnblock} onClose={() => setAsking(null)} />
      ) : null}
      {(asking === 'followers' || asking === 'following') && user ? (
        <PeopleListSheet userId={userId} name={name} kind={asking} myId={myId} onClose={() => setAsking(null)} />
      ) : null}
    </>
  );
}
