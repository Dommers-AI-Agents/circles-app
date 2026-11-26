// Settings: who sees my profile, what reaches me, who I blocked, the fine
// print, signing out and deleting my account.
import { useState } from 'react';
import { get, put } from '../api/client';
import { Link, useNavigate } from 'react-router-dom';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { messageOf } from '../api/client';
import {
  blocks as loadBlocks, deleteMyAccount, myNotificationPreferences, personOf, profile as loadProfile, saveNotificationPreferences,
  setProfilePrivacy, unblock, type Block
} from '../api/people';
import { useAuth } from '../auth/AuthContext';
import {
  flipOf, isStoresOnly, SWITCHES, switchIsOn, type NotificationPreferences, type SwitchKey
} from '../logic/notificationSwitches';
import { ConfirmSheet, Head, LoadError, Sheet, Spinner, toast } from '../ui/kit';
import { PushSwitch } from '../ui/PushSwitch';
import { PersonRow } from '../ui/people/PersonRow';
import { Switch } from '../ui/people/Switch';
import { useRelationshipRefresh } from '../ui/people/hooks';
import '../ui/people/people.css';
import './settings.css';

const NOTIFICATIONS_KEY = ['me', 'notificationPreferences'];

export function SettingsPage() {
  const { userId: myId, signOut } = useAuth();
  const [asking, setAsking] = useState<null | 'signOut' | 'delete'>(null);

  return (
    <>
      <Head title="Settings" back="/me" />
      <main className="page settings">
        <p className="section-title">Profile</p>
        <div className="card settings-card">
          <Link className="settings-link" to="/me/edit">
            <span className="grow">Edit profile<span className="small muted">Name, photo, bio and city</span></span>
            <span aria-hidden="true">›</span>
          </Link>
          <PrivateProfile myId={myId} />
        </div>

        <p className="section-title">Notifications</p>
        <Notifications />
        <PushSwitch />

        <p className="section-title">Emails</p>
        <EmailSwitches />

        <p className="section-title">Blocked people</p>
        <Blocked />

        <p className="section-title">About</p>
        <div className="card settings-card">
          <a className="settings-link" href="https://favcircles.com/support.html" target="_blank" rel="noreferrer">
            <span className="grow">Help and support</span><span aria-hidden="true">↗</span>
          </a>
          <a className="settings-link" href="https://favcircles.com/terms.html" target="_blank" rel="noreferrer">
            <span className="grow">Terms of use</span><span aria-hidden="true">↗</span>
          </a>
          <a className="settings-link" href="https://favcircles.com/privacy.html" target="_blank" rel="noreferrer">
            <span className="grow">Privacy policy</span><span aria-hidden="true">↗</span>
          </a>
        </div>

        <div className="settings-end">
          <button className="btn block soft" type="button" onClick={() => setAsking('signOut')}>Sign out</button>
          <button className="btn block plain settings-delete" type="button" onClick={() => setAsking('delete')}>Delete my account</button>
        </div>
      </main>

      {asking === 'signOut' ? (
        <ConfirmSheet title="Sign out?" action="Sign out"
          body="Your circles and places stay in your account. Sign in again any time with your email."
          onConfirm={() => { setAsking(null); signOut(); }} onClose={() => setAsking(null)} />
      ) : null}
      {asking === 'delete' ? <DeleteAccount onClose={() => setAsking(null)} onDeleted={signOut} /> : null}
    </>
  );
}

// ---- Private profile: PUT /users/me/profile-privacy. The flag is read from
// my own profile (GET /users/me doesn't carry it).
function PrivateProfile({ myId }: { myId: string | undefined }) {
  const queryClient = useQueryClient();
  const mine = useQuery({ queryKey: ['user', myId], queryFn: () => loadProfile(myId || ''), enabled: !!myId });
  const [saving, setSaving] = useState<boolean | null>(null);
  const on = saving ?? mine.data?.user.profilePrivate === true;

  const flip = async (next: boolean) => {
    setSaving(next);
    try {
      const result = await setProfilePrivacy(next);
      await Promise.all([
        queryClient.invalidateQueries({ queryKey: ['user', myId] }),
        queryClient.invalidateQueries({ queryKey: ['me'] }),
        queryClient.invalidateQueries({ queryKey: ['people', 'requests'] })
      ]);
      if (result.profilePrivate) toast('Your profile is private');
      else if (result.acceptedRequests > 0) toast(`Your profile is public. ${result.acceptedRequests} waiting ${result.acceptedRequests === 1 ? 'person follows' : 'people follow'} you now.`);
      else toast('Your profile is public');
    } catch (error) {
      toast(messageOf(error));
    } finally {
      setSaving(null);
    }
  };

  if (mine.isError) {
    return <p className="small muted settings-inline">Couldn't load your profile privacy. <button className="link-btn" onClick={() => mine.refetch()}>Try again</button></p>;
  }
  return (
    <Switch label="Private profile" checked={on} disabled={mine.isPending || saving !== null} onChange={flip}
      detail={on
        ? 'Only your followers and connections see your circles, places and Moments. Anyone else sees your name, photo and counts, and asks before following you.'
        : "Anyone can see your public circles and places, and follow you without asking. Updates only ever reach your followers and connections."} />
  );
}

// ---- Notification switches (they also cover the emails sent in their place)
function Notifications() {
  const queryClient = useQueryClient();
  const saved = useQuery({ queryKey: NOTIFICATIONS_KEY, queryFn: myNotificationPreferences, staleTime: 60_000 });
  const [busy, setBusy] = useState(false);

  const save = async (changes: NotificationPreferences, said: string) => {
    const before = saved.data;
    queryClient.setQueryData<NotificationPreferences>(NOTIFICATIONS_KEY, { ...(before || {}), ...changes });
    setBusy(true);
    try {
      const next = await saveNotificationPreferences(changes);
      queryClient.setQueryData(NOTIFICATIONS_KEY, next);
      toast(said);
    } catch (error) {
      queryClient.setQueryData(NOTIFICATIONS_KEY, before);
      toast(messageOf(error));
    } finally {
      setBusy(false);
    }
  };

  if (saved.isPending) return <div className="card settings-card"><Spinner /></div>;
  if (saved.isError) return <LoadError message={messageOf(saved.error)} retry={() => saved.refetch()} />;
  const prefs = saved.data;
  const storesOnly = isStoresOnly(prefs);

  return (
    <div className="card settings-card">
      {storesOnly ? (
        <div className="settings-mode">
          <strong>You hear only from stores you follow</strong>
          <p className="small muted">
            Stores whose bell you turned on can reach you, plus news about your orders and lines. Everything else is held back.
          </p>
          <button className="btn small soft" type="button" disabled={busy}
            onClick={() => save({ mode: 'all' }, 'You hear about everything again')}>Hear about everything</button>
        </div>
      ) : null}
      {SWITCHES.map((item) => {
        const heldBack = storesOnly && item.key !== 'storeAlerts';
        return (
          <Switch key={item.key} label={item.label}
            detail={heldBack ? 'Held back while you hear only from stores.' : `${item.detail}${item.email ? ' Also by email when a notification can’t reach you.' : ''}`}
            checked={switchIsOn(prefs, item.key as SwitchKey)} disabled={busy || heldBack}
            onChange={(on) => save(flipOf(item.key, on), on ? `${item.label}: on` : `${item.label}: off`)} />
        );
      })}
      {!storesOnly ? (
        <button className="settings-link settings-stores-only" type="button" disabled={busy}
          onClick={() => save({ mode: 'storesOnly' }, 'You hear only from stores you follow')}>
          <span className="grow">Only hear from stores I follow<span className="small muted">Pauses everything above except stores</span></span>
        </button>
      ) : null}
    </div>
  );
}

// ---- People I blocked
function Blocked() {
  const refresh = useRelationshipRefresh();
  const list = useQuery({ queryKey: ['people', 'blocks'], queryFn: loadBlocks });
  const [asking, setAsking] = useState<Block | null>(null);
  const [busy, setBusy] = useState('');

  const doUnblock = async (entry: Block) => {
    setAsking(null);
    setBusy(entry.blockedUserId);
    try {
      await unblock(entry.blockedUserId);
      await refresh();
      toast(`You unblocked ${nameOf(entry)}`);
    } catch (error) {
      toast(messageOf(error));
    } finally {
      setBusy('');
    }
  };

  if (list.isPending) return <div className="card settings-card"><Spinner /></div>;
  if (list.isError) return <LoadError message={messageOf(list.error)} retry={() => list.refetch()} />;
  return (
    <>
      {list.data.length === 0 ? (
        <div className="card settings-note"><p className="small muted">You haven't blocked anyone. Block someone from the ••• on their profile.</p></div>
      ) : (
        <ul className="list card people-list">
          {list.data.map((entry) => {
            const person = personOf({ displayName: nameOf(entry), ...(entry.blockedUser || {}), _id: entry.blockedUserId });
            return (
              <li key={entry.id || entry.blockedUserId}>
                <PersonRow person={person} detail="Blocked">
                  <button className="btn small soft" type="button" disabled={busy === entry.blockedUserId}
                    onClick={() => setAsking(entry)}>Unblock</button>
                </PersonRow>
              </li>
            );
          })}
        </ul>
      )}
      {asking ? (
        <ConfirmSheet title={`Unblock ${nameOf(asking)}?`} action="Unblock"
          body="You can find and follow each other again. You won't be following or connected until one of you asks."
          onConfirm={() => doUnblock(asking)} onClose={() => setAsking(null)} />
      ) : null}
    </>
  );
}

const nameOf = (entry: Block) => (entry.blockedUser && entry.blockedUser.displayName) || 'This person';

// ---- Delete my account: DELETE /users/me, after typing DELETE
function DeleteAccount({ onClose, onDeleted }: { onClose: () => void; onDeleted: () => void }) {
  const navigate = useNavigate();
  const [typed, setTyped] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const ready = typed.trim() === 'DELETE';

  const confirm = async () => {
    if (!ready) return;
    setBusy(true);
    setError('');
    try {
      await deleteMyAccount();
      toast('Your account was deleted');
      onDeleted();
      navigate('/', { replace: true });
    } catch (e) {
      setError(messageOf(e));
      setBusy(false);
    }
  };

  return (
    <Sheet title="Delete your account?" onClose={busy ? () => undefined : onClose}>
      <p className="muted settings-delete-body">
        This deletes your account and everything you made: your circles, saved places, comments, check-ins, Moments,
        messages, connections and reward points. People you messaged keep their side of the conversation. There is no undo.
      </p>
      <label className="field"><span>Type DELETE to confirm</span>
        <input type="text" value={typed} autoComplete="off" autoCapitalize="characters" spellCheck={false}
          onChange={(e) => setTyped(e.target.value)} aria-label="Type DELETE to confirm" />
      </label>
      <p className="err" role="alert">{error}</p>
      <button className="btn block danger" type="button" disabled={!ready || busy} onClick={confirm}>
        {busy ? 'Deleting…' : 'Delete my account'}
      </button>
      <button className="btn block plain" type="button" disabled={busy} onClick={onClose}>Cancel</button>
    </Sheet>
  );
}

// ---- Email switches: the same opt-outs as the unsubscribe link in each email
interface EmailSwitch { kind: string; title: string; detail: string; on: boolean }

function EmailSwitches() {
  const queryClient = useQueryClient();
  const [busy, setBusy] = useState<string | null>(null);
  const query = useQuery({
    queryKey: ['me', 'email-preferences'],
    queryFn: () => get<{ data: { switches: EmailSwitch[] } }>('/users/me/email-preferences').then((r) => r.data.switches)
  });
  if (query.isPending) return <Spinner />;
  if (query.isError) return <LoadError message={messageOf(query.error)} retry={() => query.refetch()} />;
  const flip = async (row: EmailSwitch, on: boolean) => {
    setBusy(row.kind);
    try {
      const { data } = await put<{ data: { switches: EmailSwitch[] } }>('/users/me/email-preferences', { [row.kind]: on });
      queryClient.setQueryData(['me', 'email-preferences'], data.switches);
      toast(on ? `${row.title}: on` : `${row.title}: off`);
    } catch (e) {
      toast(messageOf(e));
    } finally {
      setBusy(null);
    }
  };
  return (
    <div className="card settings-card">
      {query.data.map((row) => (
        <Switch key={row.kind} label={row.title} detail={row.detail} checked={row.on}
          disabled={busy !== null} onChange={(next) => flip(row, next)} />
      ))}
    </div>
  );
}
