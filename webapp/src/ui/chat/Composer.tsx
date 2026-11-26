// The box a message is typed in. It grows with the words; Enter sends on a
// computer and makes a new line on a phone (the send button always sends).
import { useEffect, useRef, useState, type ChangeEvent, type FormEvent, type KeyboardEvent } from 'react';
import { enterSends } from '../../logic/chatThread';

/** The longest message the server takes (services/conversationAccess.js) */
export const MAX_MESSAGE_CHARS = 4000;
const MAX_FIELD_PX = 150;

const touchKeyboard = (): boolean =>
  typeof window !== 'undefined' && typeof window.matchMedia === 'function' && window.matchMedia('(pointer: coarse)').matches;

export function Composer({ placeholder, onSend, onPhoto, disabled }: {
  placeholder: string;
  onSend: (text: string) => void;
  onPhoto: (file: File) => void;
  disabled?: boolean;
}) {
  const [text, setText] = useState('');
  const field = useRef<HTMLTextAreaElement>(null);
  const picker = useRef<HTMLInputElement>(null);

  useEffect(() => {
    const el = field.current;
    if (!el) return;
    el.style.height = 'auto';
    el.style.height = `${Math.min(MAX_FIELD_PX, el.scrollHeight)}px`;
    el.style.overflowY = el.scrollHeight > MAX_FIELD_PX ? 'auto' : 'hidden';
  }, [text]);

  const send = (event?: FormEvent) => {
    event?.preventDefault();
    const words = text.trim();
    if (!words || disabled) return;
    onSend(words);
    setText('');
    field.current?.focus();
  };

  const onKeyDown = (event: KeyboardEvent<HTMLTextAreaElement>) => {
    if (enterSends({ key: event.key, shiftKey: event.shiftKey, isComposing: event.nativeEvent.isComposing, keyCode: event.keyCode }, touchKeyboard())) {
      event.preventDefault();
      send();
    }
  };

  const onFile = (event: ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files && event.target.files[0];
    event.target.value = '';
    if (file) onPhoto(file);
  };

  return (
    <form className="composer" onSubmit={send}>
      <button type="button" className="composer-photo" aria-label="Send a photo" disabled={disabled} onClick={() => picker.current?.click()}>
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
          <path d="M4 7h3l2-2.500h6L17 7h3v12H4V7Z" /><circle cx="12" cy="13" r="3.600" />
        </svg>
      </button>
      <input ref={picker} type="file" accept="image/*" hidden onChange={onFile} />
      <textarea
        ref={field}
        rows={1}
        value={text}
        maxLength={MAX_MESSAGE_CHARS}
        placeholder={placeholder}
        aria-label={placeholder}
        disabled={disabled}
        onChange={(event) => setText(event.target.value)}
        onKeyDown={onKeyDown}
      />
      <button type="submit" className="composer-send" aria-label="Send" disabled={disabled || !text.trim()}>
        <svg viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M3.400 20.400 21 12 3.400 3.600 3.400 10.200 15 12 3.400 13.800Z" /></svg>
      </button>
    </form>
  );
}
