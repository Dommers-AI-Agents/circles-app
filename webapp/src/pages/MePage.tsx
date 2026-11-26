// "Me": who I am, and my circles in the order I arranged them.
import { useState } from 'react';
import { Link } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import { myCircles } from '../api/circles';
import { me } from '../api/users';
import { messageOf } from '../api/client';
import { useAuth } from '../auth/AuthContext';
import { plural } from '../logic/labels';
import { Avatar, ConfirmSheet, Empty, Head, LoadError, Spinner } from '../ui/kit';
import { CircleCard } from '../ui/CircleCard';
import { CircleEditSheet } from '../ui/CircleEditSheet';
import { PushSwitch } from '../ui/PushSwitch';
import { useUnreadNotifications } from '../realtime/badges';

const LINKS = [
  { to: '/people', mark: '👥', title: 'People', detail: 'Find friends, requests, who you follow' },
  { to: '/rewards', mark: '🎁', title: 'My rewards', detail: 'Points, coupons and tickets at stores' },
  { to: '/notifications', mark: '🔔', title: 'Notifications', detail: 'What happened while you were away' },
  { to: '/trash', mark: '🗑️', title: 'Trash', detail: 'Put back a circle or a place' }
];

export function MePage() {
  const { session, signOut } = useAuth();
  const unread = useUnreadNotifications();
  const [creating, setCreating] = useState(false);
  const [leaving, setLeaving] = useState(false);
  const profile = useQuery({ queryKey: ['me'], queryFn: me });
  const circles = useQuery({ queryKey: ['circles', 'mine'], queryFn: myCircles });
  const user = profile.data;
  const name = user?.displayName || session?.name || 'You';

  return (
    <>
      <Head title="Me" lead>
        <Link className="icon-btn" to="/me/edit">Edit</Link>
        <Link className="icon-btn" to="/settings" aria-label="Settings">Settings</Link>
      </Head>
      <main className="page">
        <div className="profile-top">
          <Avatar name={name} src={user?.profilePicture} size={72} seed={user?._id} />
          <div className="grow">
            <h2 className="clip">{name}</h2>
            {user?.location ? <p className="muted small">{user.location}</p> : null}
            {user?.bio ? <p className="small" style={{ marginTop: 4 }}>{user.bio}</p> : null}
          </div>
        </div>
        {user ? (
          <div className="counts">
            <span><b>{user.followersCount ?? 0}</b> followers</span>
            <span><b>{user.followingCount ?? 0}</b> following</span>
          </div>
        ) : null}

        <ul className="list card" style={{ marginTop: 18, overflow: 'hidden' }}>
          {LINKS.map((link) => (
            <li key={link.to}>
              <Link className="item" to={link.to}>
                <span className="thumb" style={{ width: 40, height: 40, fontSize: 20 }} aria-hidden="true">{link.mark}</span>
                <span className="grow">
                  <span style={{ display: 'block', fontWeight: 600 }}>{link.title}</span>
                  <span className="small muted">{link.detail}</span>
                </span>
                {link.to === '/notifications' && unread > 0 ? <span className="chip">{unread} new</span> : null}
                <span className="muted" aria-hidden="true">›</span>
              </Link>
            </li>
          ))}
        </ul>
        <PushSwitch />

        <div className="row" style={{ margin: '22px 4px 10px' }}>
          <p className="section-title grow" style={{ margin: 0 }}>
            My circles{circles.data ? ` · ${plural(circles.data.length, 'circle')}` : ''}
          </p>
          <button className="btn small soft" onClick={() => setCreating(true)}>New circle</button>
        </div>
        {circles.isPending ? <Spinner /> : null}
        {circles.isError ? <LoadError message={messageOf(circles.error)} retry={() => circles.refetch()} /> : null}
        {circles.data && circles.data.length === 0 ? (
          <Empty mark="⭕" title="No circles yet" action={<button className="btn" onClick={() => setCreating(true)}>Make your first circle</button>}>
            A circle is a list of places you love: date night, coffee, a city you know well.
          </Empty>
        ) : null}
        {circles.data && circles.data.length > 0 ? (
          <div className="circle-grid">
            {circles.data.map((circle) => <CircleCard key={circle._id} circle={circle} />)}
          </div>
        ) : null}
        <button className="btn block plain" style={{ marginTop: 26 }} onClick={() => setLeaving(true)}>Sign out</button>
      </main>
      {creating ? <CircleEditSheet onClose={() => setCreating(false)} /> : null}
      {leaving ? (
        <ConfirmSheet title="Sign out?" body="You can sign back in with your email any time." action="Sign out"
          onConfirm={signOut} onClose={() => setLeaving(false)} />
      ) : null}
    </>
  );
}
