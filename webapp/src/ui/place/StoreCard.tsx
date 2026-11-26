// The place as a store: follow it, turn on its alerts (the bell needs a
// follow), and, when it's a FavCircles rewards store, my points there.
import { useState } from 'react';
import { Link } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import { messageOf } from '../../api/client';
import { followPlace, setPlaceAlerts, storeRewards, unfollowPlace } from '../../api/places';
import { plural } from '../../logic/labels';
import { pointsText } from '../../logic/rewards';
import type { PlaceView } from '../../logic/placeView';
import { toast } from '../kit';
import { RewardBar } from '../rewards/RewardBar';
import '../rewards/rewards.css';
import { usePatchView, usePlaceRefresh } from './hooks';

export function FollowCard({ view }: { view: PlaceView }) {
  const patch = usePatchView(view.routeId);
  const refresh = usePlaceRefresh();
  const [busy, setBusy] = useState(false);

  const follow = async () => {
    setBusy(true);
    try {
      const result = view.isFollowing ? await unfollowPlace(view.storeId) : await followPlace(view.storeId);
      const following = result.following === true;
      patch((v) => ({
        ...v,
        isFollowing: following,
        followAlerts: following ? v.followAlerts : false,
        followersCount: typeof result.followersCount === 'number' ? result.followersCount : v.followersCount
      }));
      toast(following ? `Following ${view.venue.name}` : `Stopped following ${view.venue.name}`);
      // Following files it in Places I follow (a save of mine); unfollowing takes that out
      refresh();
    } catch (e) {
      toast(messageOf(e));
    } finally {
      setBusy(false);
    }
  };

  const bell = async () => {
    if (!view.isFollowing) return;
    setBusy(true);
    try {
      const result = await setPlaceAlerts(view.storeId, !view.followAlerts);
      const on = result.alertsOn === true;
      patch((v) => ({ ...v, followAlerts: on }));
      toast(on ? "Alerts on: you'll hear about its specials and events" : 'Alerts off');
    } catch (e) {
      toast(messageOf(e));
    } finally {
      setBusy(false);
    }
  };

  return (
    <section className="card pl-card" aria-label="Follow">
      <div className="row">
        <div className="grow">
          <h3>{view.isFollowing ? 'You follow this place' : 'Follow this place'}</h3>
          <p className="small muted">
            {view.isFollowing
              ? view.followAlerts ? 'Alerts are on for its specials and events.' : 'Turn on the bell to hear about its specials and events.'
              : 'Keep it in Places I follow and see what it posts.'}
            {view.followersCount > 0 ? ` ${plural(view.followersCount, 'follower')}.` : ''}
          </p>
        </div>
        {view.isFollowing ? (
          <button className={`icon-btn pl-bell${view.followAlerts ? ' on' : ''}`} onClick={bell} disabled={busy}
            aria-pressed={view.followAlerts} aria-label={view.followAlerts ? 'Turn alerts off' : 'Turn alerts on'}>
            {view.followAlerts ? '🔔' : '🔕'}
          </button>
        ) : null}
        <button className={`btn small ${view.isFollowing ? 'soft' : ''}`} onClick={follow} disabled={busy}>
          {view.isFollowing ? 'Following' : 'Follow'}
        </button>
      </div>
    </section>
  );
}

/** Only for a FavCircles rewards store; nothing at all for an ordinary place. */
export function RewardsCard({ view }: { view: PlaceView }) {
  const rewards = useQuery({ queryKey: ['rewards', 'by-place', view.storeId], queryFn: () => storeRewards(view.storeId) });
  const data = rewards.data;
  if (!data || !data.venue) return null;
  const points = data.venueBalance || 0;
  return (
    <Link className="card pl-card rw-link pl-rewards" to={`/rewards/${encodeURIComponent(data.venue.venueId)}`}>
      <div className="row">
        <div className="grow">
          <h3>Rewards at this store</h3>
          <p className="small muted">
            {data.rewardsLive === false ? 'This store has paused its rewards for now.' : 'Scan its code at the counter to earn points.'}
          </p>
        </div>
        <div className="rw-points">{points}<small>{pointsText(points).replace(/^\d+ /, '')}</small></div>
      </div>
      <RewardBar reward={data.nextReward} points={points} />
      <p className="small pl-link-line">See its rewards ›</p>
    </Link>
  );
}
