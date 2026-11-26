// "Notifications in this browser": one switch. Hidden where the browser
// can't do it; when the person blocked it, says how to allow it again.
import { useEffect, useState } from 'react';
import { messageOf } from '../api/client';
import { pushState, turnPushOff, turnPushOn, type PushState } from '../realtime/push';
import { toast } from './kit';

export function PushSwitch() {
  const [state, setState] = useState<PushState | null>(null);
  const [busy, setBusy] = useState(false);
  useEffect(() => { pushState().then(setState).catch(() => setState('unsupported')); }, []);
  if (!state || state === 'unsupported') return null;

  const flip = async () => {
    setBusy(true);
    try {
      const next = state === 'on' ? await turnPushOff() : await turnPushOn();
      setState(next);
      if (next === 'on') toast('Notifications are on in this browser');
      if (next === 'blocked') toast('Notifications are blocked for this site');
    } catch (e) {
      toast(messageOf(e));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="card" style={{ padding: '14px 16px', marginTop: 16 }}>
      <label className="row" style={{ cursor: state === 'blocked' ? 'default' : 'pointer' }}>
        <span className="grow">
          <strong>Notifications in this browser</strong><br />
          <span className="small muted">
            {state === 'blocked'
              ? "They're blocked for this site. Allow notifications for app.favcircles.com in your browser's site settings, then come back."
              : 'New messages, followers, comments and news from stores you follow.'}
          </span>
        </span>
        {state !== 'blocked' ? (
          <input type="checkbox" role="switch" checked={state === 'on'} disabled={busy} onChange={flip}
            style={{ width: 22, height: 22 }} aria-label="Notifications in this browser" />
        ) : null}
      </label>
    </div>
  );
}
