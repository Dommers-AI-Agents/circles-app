import type { NextReward } from '../../api/rewards';
import { nextRewardLine, rewardFraction } from '../../logic/rewards';

/** Progress toward the next reward at one store, with the line under it. */
export function RewardBar({ reward, points }: { reward: NextReward | null | undefined; points: number }) {
  if (!reward) return null;
  const percent = Math.round(rewardFraction(reward, points) * 100);
  return (
    <>
      <div className={`rw-bar${reward.canRedeem ? ' ready' : ''}`} role="progressbar" aria-valuemin={0} aria-valuemax={100} aria-valuenow={percent}
        aria-label={`Toward ${reward.title}`}>
        <i style={{ width: `${percent}%` }} />
      </div>
      <p className={`small ${reward.canRedeem ? 'rw-ready' : 'muted'}`}>{nextRewardLine(reward)}</p>
    </>
  );
}
