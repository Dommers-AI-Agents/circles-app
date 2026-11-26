// Send a place or a circle to people in Messages, as the same card the iOS
// app sends (content "📍 Name" / "⭕️ Name", metadata from
// logic/messageShare.ts). Recent chats first, then connections with no chat
// yet. Several people can be picked one after another.
//
//   <SharePickerSheet share={{ kind: 'place', placeId, placeName, address, photoUrl, lat, lng }} onClose={…} />
//   <SharePickerSheet share={{ kind: 'circle', circleId, circleName, placeCount, coverUrl }} onClose={…} />
import { useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { conversations as loadConversations, directConversation, sendShare, type Conversation } from '../../api/messages';
import { ApiError, messageOf } from '../../api/client';
import { useAuth } from '../../auth/AuthContext';
import { conversationTitle, filterPeople, idOf, isGroup, newestFirst, otherPerson } from '../../logic/chatThread';
import { MESSAGE_KEYS } from '../../logic/liveInvalidations';
import type { ShareInput } from '../../logic/messageShare';
import { Avatar, LoadError, Sheet, Spinner, toast } from '../kit';
import { useMessageablePeople } from './NewMessageSheet';
import './chat.css';

type Target = { key: string; name: string; photo?: string | null; seed: string; conversationId?: string; personId?: string };
type SendState = 'sending' | 'sent' | 'failed';

export function SharePickerSheet({ share, onClose }: { share: ShareInput; onClose: () => void }) {
  const { userId } = useAuth();
  const queryClient = useQueryClient();
  const chats = useQuery({ queryKey: [...MESSAGE_KEYS.conversations], queryFn: loadConversations });
  const people = useMessageablePeople();
  const [typed, setTyped] = useState('');
  const [state, setState] = useState<Record<string, SendState>>({});
  const [error, setError] = useState('');

  // Recent chats, then connections I haven't written to yet
  const withChat = new Set<string>();
  const fromChats: Target[] = newestFirst(chats.data || []).map((conversation: Conversation) => {
    const other = otherPerson(conversation, userId);
    if (other && idOf(other)) withChat.add(idOf(other));
    const group = isGroup(conversation);
    return {
      key: `c:${idOf(conversation)}`,
      name: conversationTitle(conversation, userId),
      photo: group ? conversation.avatar : other?.profilePicture,
      seed: group ? idOf(conversation) : idOf(other),
      conversationId: idOf(conversation)
    };
  });
  const fromPeople: Target[] = (people.data || [])
    .filter((person) => person.connected && !withChat.has(idOf(person)))
    .map((person) => ({ key: `p:${idOf(person)}`, name: person.displayName || 'FavCircles member', photo: person.profilePicture, seed: idOf(person), personId: idOf(person) }));
  const targets = filterPeople([...fromChats, ...fromPeople].map((target) => ({ ...target, displayName: target.name })), typed);

  const send = async (target: Target) => {
    if (state[target.key] === 'sending' || state[target.key] === 'sent') return;
    setState((s) => ({ ...s, [target.key]: 'sending' }));
    setError('');
    try {
      const conversationId = target.conversationId || idOf(await directConversation(target.personId || ''));
      await sendShare(conversationId, share);
      setState((s) => ({ ...s, [target.key]: 'sent' }));
      toast(`Sent to ${target.name}`);
      queryClient.invalidateQueries({ queryKey: [...MESSAGE_KEYS.conversations] });
      queryClient.invalidateQueries({ queryKey: [...MESSAGE_KEYS.thread(conversationId)] });
    } catch (e) {
      setState((s) => ({ ...s, [target.key]: 'failed' }));
      setError(e instanceof ApiError && e.code === 'blocked' ? `You can't message ${target.name}.` : messageOf(e));
    }
  };

  const title = share.kind === 'place' ? share.placeName : share.circleName;
  const loading = chats.isPending || people.isPending;
  const failed = chats.isError && people.isError;

  return (
    <Sheet title={`Send ${share.kind === 'place' ? 'this place' : 'this circle'}`} onClose={onClose}>
      <div className="share-preview card">
        <span className="share-preview-mark" aria-hidden="true">{share.kind === 'place' ? '📍' : '⭕️'}</span>
        <span className="grow clip"><strong>{title}</strong></span>
      </div>
      <label className="field">
        <span>To</span>
        <input type="search" value={typed} onChange={(e) => setTyped(e.target.value)} placeholder="Search chats and connections" />
      </label>
      <p className="err" role="alert">{error}</p>
      {loading ? <Spinner /> : null}
      {failed ? <LoadError message={messageOf(chats.error)} retry={() => { chats.refetch(); people.refetch(); }} /> : null}
      {!loading && !failed && fromChats.length + fromPeople.length === 0 ? (
        <div className="chat-note card">
          <p><strong>No one to send it to yet</strong></p>
          <p className="muted small">You can send places and circles to your connections. Connect with people you know first.</p>
        </div>
      ) : null}
      {!loading && fromChats.length + fromPeople.length > 0 && targets.length === 0
        ? <p className="muted chat-pad">No chat or connection by that name.</p>
        : null}
      {targets.length > 0 ? (
        <ul className="list card chat-people">
          {targets.map((target) => {
            const status = state[target.key];
            return (
              <li key={target.key}>
                <div className="item">
                  <Avatar name={target.name} src={target.photo} seed={target.seed} size={40} />
                  <span className="grow clip"><strong>{target.name}</strong></span>
                  <button
                    type="button"
                    className={`btn small ${status === 'sent' ? 'soft' : ''}`}
                    disabled={status === 'sending' || status === 'sent'}
                    onClick={() => send(target)}
                  >
                    {status === 'sending' ? 'Sending…' : status === 'sent' ? 'Sent ✓' : status === 'failed' ? 'Try again' : 'Send'}
                  </button>
                </div>
              </li>
            );
          })}
        </ul>
      ) : null}
      <button type="button" className="btn block plain" onClick={onClose} style={{ marginTop: 8 }}>Done</button>
    </Sheet>
  );
}
