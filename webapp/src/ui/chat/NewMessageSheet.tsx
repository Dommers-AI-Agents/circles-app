// "New message": pick someone to write to. Connections can be messaged
// straight away; people I only follow are listed too, with the step that
// opens messaging (connecting), since the server refuses a chat otherwise.
import { useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { directConversation, messageable } from '../../api/messages';
import { messageOf } from '../../api/client';
import { useAuth } from '../../auth/AuthContext';
import { filterPeople, idOf } from '../../logic/chatThread';
import { MESSAGE_KEYS } from '../../logic/liveInvalidations';
import { Avatar, LoadError, Sheet, Spinner } from '../kit';
import './chat.css';

export function useMessageablePeople() {
  const { userId } = useAuth();
  return useQuery({
    queryKey: [...MESSAGE_KEYS.people, userId || ''],
    queryFn: () => messageable(userId || ''),
    enabled: !!userId
  });
}

export function NewMessageSheet({ onClose }: { onClose: () => void }) {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const people = useMessageablePeople();
  const [typed, setTyped] = useState('');
  const [opening, setOpening] = useState('');
  const [error, setError] = useState('');

  const list = filterPeople(people.data || [], typed);
  const connected = list.filter((person) => person.connected);
  const followed = list.filter((person) => !person.connected);

  const open = async (personId: string) => {
    setOpening(personId);
    setError('');
    try {
      const conversation = await directConversation(personId);
      await queryClient.invalidateQueries({ queryKey: [...MESSAGE_KEYS.conversations] });
      onClose();
      navigate(`/messages/${encodeURIComponent(idOf(conversation))}`);
    } catch (e) {
      setError(messageOf(e));
      setOpening('');
    }
  };

  return (
    <Sheet title="New message" onClose={onClose}>
      <label className="field">
        <span>To</span>
        <input type="search" value={typed} onChange={(e) => setTyped(e.target.value)} placeholder="Search your connections" autoFocus />
      </label>
      <p className="err" role="alert">{error}</p>
      {people.isPending ? <Spinner /> : null}
      {people.isError ? <LoadError message={messageOf(people.error)} retry={() => people.refetch()} /> : null}
      {people.data && people.data.length === 0 ? (
        <div className="chat-note card">
          <p><strong>No one to message yet</strong></p>
          <p className="muted small">You can message your connections. Find people you know, connect, and you can write to each other here.</p>
          <button type="button" className="btn soft small" onClick={() => { onClose(); navigate('/people'); }}>Find people</button>
        </div>
      ) : null}
      {people.data && people.data.length > 0 && list.length === 0
        ? <p className="muted chat-pad">No one by that name among your connections.</p>
        : null}
      {connected.length > 0 ? (
        <ul className="list card chat-people">
          {connected.map((person) => (
            <li key={idOf(person)}>
              <button type="button" className="item" disabled={!!opening} onClick={() => open(idOf(person))}>
                <Avatar name={person.displayName || '?'} src={person.profilePicture} seed={idOf(person)} size={40} />
                <span className="grow clip"><strong>{person.displayName || 'FavCircles member'}</strong></span>
                <span className="small muted">{opening === idOf(person) ? 'Opening…' : 'Message'}</span>
              </button>
            </li>
          ))}
        </ul>
      ) : null}
      {followed.length > 0 ? (
        <>
          <p className="section-title">People you follow</p>
          <p className="muted small chat-pad">Connect with them first, then you can message each other.</p>
          <ul className="list card chat-people">
            {followed.map((person) => (
              <li key={idOf(person)}>
                <button type="button" className="item" onClick={() => { onClose(); navigate(`/user/${encodeURIComponent(idOf(person))}`); }}>
                  <Avatar name={person.displayName || '?'} src={person.profilePicture} seed={idOf(person)} size={40} />
                  <span className="grow clip"><strong>{person.displayName || 'FavCircles member'}</strong></span>
                  <span className="small muted">Connect</span>
                </button>
              </li>
            ))}
          </ul>
        </>
      ) : null}
    </Sheet>
  );
}
