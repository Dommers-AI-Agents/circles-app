// Follow / Following / Requested, for one person. A private profile turns a
// follow into a request (the server answers `requested: true`); tapping
// Requested takes it back, tapping Following unfollows.
import { useEffect, useState } from 'react';
import { ApiError, messageOf } from '../../api/client';
import { follow, unfollow } from '../../api/people';
import { followLabel, followStateOf, type FollowState } from '../../logic/relationship';
import { ConfirmSheet, toast } from '../kit';
import { useRelationshipRefresh } from './hooks';

export function FollowButton({ person, small, confirmUnfollow, onChanged }: {
  person: { _id: string; displayName: string; isFollowing?: boolean; followRequested?: boolean };
  small?: boolean;
  /** Ask before unfollowing (the profile does; list rows don't) */
  confirmUnfollow?: boolean;
  onChanged?: (state: FollowState) => void;
}) {
  const refresh = useRelationshipRefresh();
  const fromServer = followStateOf(person);
  const [state, setState] = useState<FollowState>(fromServer);
  const [busy, setBusy] = useState(false);
  const [asking, setAsking] = useState(false);
  // A fresh load is the truth: adopt it
  useEffect(() => { setState(fromServer); }, [fromServer, person._id]);

  const settle = (next: FollowState, said: string) => {
    setState(next);
    toast(said);
    onChanged?.(next);
    void refresh();
  };

  const startFollowing = async () => {
    setBusy(true);
    try {
      const result = await follow(person._id);
      if (result.requested) settle('requested', `Asked to follow ${person.displayName}`);
      else settle('following', `Following ${person.displayName}`);
    } catch (error) {
      toast(messageOf(error));
    } finally {
      setBusy(false);
    }
  };

  const stopFollowing = async () => {
    setAsking(false);
    setBusy(true);
    try {
      const result = await unfollow(person._id);
      settle('none', result.requestCancelled ? 'Follow request taken back' : `Unfollowed ${person.displayName}`);
    } catch (error) {
      // Connected always means following: the way out is to remove the connection
      if (error instanceof ApiError && error.code === 'connected') setState('following');
      toast(messageOf(error));
    } finally {
      setBusy(false);
    }
  };

  const tap = () => {
    if (state === 'none') void startFollowing();
    else if (confirmUnfollow && state === 'following') setAsking(true);
    else void stopFollowing();
  };

  return (
    <>
      <button
        type="button"
        className={`btn ${small ? 'small' : ''} ${state === 'none' ? '' : 'soft'} follow-btn`}
        disabled={busy}
        aria-pressed={state !== 'none'}
        onClick={tap}
      >
        {followLabel(state)}
      </button>
      {asking ? (
        <ConfirmSheet title={`Unfollow ${person.displayName}?`} action="Unfollow"
          body="Their new places stop showing in your feed. You can follow them again any time."
          onConfirm={stopFollowing} onClose={() => setAsking(false)} />
      ) : null}
    </>
  );
}
