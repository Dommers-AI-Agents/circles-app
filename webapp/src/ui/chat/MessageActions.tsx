// What a long-press on a message offers: copy its words, and for your own,
// edit (words only) or delete.
import { useState, type FormEvent } from 'react';
import { deleteMessage, editMessage, type Message } from '../../api/messages';
import { messageOf } from '../../api/client';
import { idOf, messageActions } from '../../logic/chatThread';
import { ConfirmSheet, Sheet, toast } from '../kit';
import { MAX_MESSAGE_CHARS } from './Composer';

export function MessageActionsSheet({ message, myId, onClose, onEdited, onDeleted }: {
  message: Message;
  myId: string | undefined;
  onClose: () => void;
  onEdited: (message: Message) => void;
  onDeleted: (messageId: string) => void;
}) {
  const can = messageActions(message, myId);
  const [step, setStep] = useState<'menu' | 'edit' | 'delete'>('menu');
  const [text, setText] = useState(message.content || '');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(message.content || '');
      toast('Copied');
    } catch {
      toast("This browser didn't let us copy. Select the words and copy them instead.");
    }
    onClose();
  };

  const save = async (event: FormEvent) => {
    event.preventDefault();
    const words = text.trim();
    if (!words) { setError('A message needs some words. To take it back, delete it.'); return; }
    if (words === (message.content || '').trim()) { onClose(); return; }
    setBusy(true);
    setError('');
    try {
      const saved = await editMessage(idOf(message), words);
      // The server sends the whole sender record back here; keep the card we had
      onEdited({ ...message, ...saved, senderDetails: message.senderDetails });
      toast('Message edited');
      onClose();
    } catch (e) {
      setError(messageOf(e));
      setBusy(false);
    }
  };

  const remove = async () => {
    setBusy(true);
    try {
      await deleteMessage(idOf(message));
      onDeleted(idOf(message));
      toast('Message deleted');
      onClose();
    } catch (e) {
      toast(messageOf(e));
      onClose();
    }
  };

  if (step === 'delete') {
    return (
      <ConfirmSheet
        title="Delete this message?"
        body="It will say “Message deleted” for everyone in the chat."
        action={busy ? 'Deleting…' : 'Delete'}
        danger
        onConfirm={remove}
        onClose={onClose}
      />
    );
  }

  if (step === 'edit') {
    return (
      <Sheet title="Edit message" onClose={onClose}>
        <form onSubmit={save} noValidate>
          <label className="field"><span>Message</span>
            <textarea value={text} maxLength={MAX_MESSAGE_CHARS} onChange={(e) => setText(e.target.value)} autoFocus />
          </label>
          <p className="err" role="alert">{error}</p>
          <button className="btn block" type="submit" disabled={busy} style={{ marginTop: 8 }}>{busy ? 'Saving…' : 'Save'}</button>
          <button className="btn block plain" type="button" onClick={onClose}>Cancel</button>
        </form>
      </Sheet>
    );
  }

  return (
    <Sheet title="Message" onClose={onClose}>
      <div className="card chat-actions">
        {can.copy ? <button type="button" className="item" onClick={copy}>Copy</button> : null}
        {can.edit ? <button type="button" className="item" onClick={() => setStep('edit')}>Edit</button> : null}
        {can.remove ? <button type="button" className="item danger-text" onClick={() => setStep('delete')}>Delete</button> : null}
        {!can.copy && !can.edit && !can.remove ? <p className="item muted">Nothing to do with this message.</p> : null}
      </div>
      <button className="btn block plain" type="button" onClick={onClose} style={{ marginTop: 8 }}>Cancel</button>
    </Sheet>
  );
}
