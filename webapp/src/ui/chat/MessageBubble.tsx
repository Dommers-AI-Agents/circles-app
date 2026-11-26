// One message as a bubble: words (links tappable), a photo, a place or
// circle card, a location, or "Message deleted". Long-press, right-click or
// the "⋯" that shows on hover opens the message's actions.
import { useRef, type MouseEvent, type ReactNode } from 'react';
import { Link } from 'react-router-dom';
import type { Message } from '../../api/messages';
import { linkParts, safeHttpUrl } from '../../logic/chatLinks';
import { isDeleted, previewText } from '../../logic/chatThread';
import { shareCard } from '../../logic/messageShare';
import { Thumb } from '../kit';

const LONG_PRESS_MS = 480;

function Words({ text }: { text: string }) {
  return (
    <>
      {linkParts(text).map((part, index) => (part.kind === 'link'
        ? <a key={index} href={part.href} target="_blank" rel="noopener noreferrer nofollow">{part.text}</a>
        : <span key={index}>{part.text}</span>))}
    </>
  );
}

/** The words a message carries besides its photo or card ("[image]" is the server's stand-in for none) */
const caption = (message: Message): string => {
  const words = (message.content || '').trim();
  return /^\[[a-z_]+\]$/i.test(words) ? '' : words;
};

function Body({ message, localImage }: { message: Message; localImage?: string }) {
  if (isDeleted(message)) return <p className="bubble-text deleted">Message deleted</p>;
  const card = shareCard(message.type, message.metadata);
  if (card) {
    const inner = (
      <>
        <Thumb src={card.imageUrl} mark={card.symbol} className="share-thumb" />
        <span className="share-words">
          <strong className="clip">{card.title}</strong>
          {card.subtitle ? <span className="small clip">{card.subtitle}</span> : null}
          <span className="share-kind small">{card.kind === 'place' ? 'Place' : card.kind === 'circle' ? 'Circle' : 'Open in Maps'}</span>
        </span>
      </>
    );
    return card.path
      ? <Link className="share-card" to={card.path}>{inner}</Link>
      : <a className="share-card" href={card.mapUrl} target="_blank" rel="noopener noreferrer">{inner}</a>;
  }
  if (message.type === 'image') {
    const src = localImage || safeHttpUrl(message.mediaUrl);
    const words = caption(message);
    return (
      <>
        {src ? (
          <a className="bubble-photo" href={localImage ? undefined : src} target="_blank" rel="noopener noreferrer">
            <img src={src} alt="Photo" loading="lazy" />
          </a>
        ) : <p className="bubble-text">📷 Photo</p>}
        {words ? <p className="bubble-text"><Words text={words} /></p> : null}
      </>
    );
  }
  if (message.type === 'location') {
    const href = safeHttpUrl(message.mediaUrl);
    return href
      ? <a className="share-card" href={href} target="_blank" rel="noopener noreferrer"><Thumb mark="📌" className="share-thumb" /><span className="share-words"><strong>Location</strong><span className="share-kind small">Open in Maps</span></span></a>
      : <p className="bubble-text">📌 Location</p>;
  }
  const words = caption(message) || previewText(message.content, message.type) || 'Message';
  return <p className="bubble-text"><Words text={words} /></p>;
}

export function MessageBubble({ message, mine, startsRun, endsRun, senderName, avatar, localImage, onMenu, footer }: {
  message: Message;
  mine: boolean;
  startsRun: boolean;
  endsRun: boolean;
  /** Group chats: the sender's name over the first bubble of their run */
  senderName?: string;
  /** Their avatar beside the last bubble of a run (empty space keeps the column otherwise) */
  avatar?: ReactNode;
  localImage?: string;
  onMenu?: () => void;
  /** Under the bubble: the time, "Read", "Couldn't send" */
  footer?: ReactNode;
}) {
  const timer = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const deleted = isDeleted(message);
  const edited = !!message.editedAt && !deleted;
  const card = !deleted && (message.type === 'image' || !!shareCard(message.type, message.metadata));
  const cancel = () => { clearTimeout(timer.current); timer.current = undefined; };
  const touchHandlers = onMenu ? {
    onTouchStart: () => { cancel(); timer.current = setTimeout(() => { timer.current = undefined; onMenu(); }, LONG_PRESS_MS); },
    onTouchMove: cancel,
    onTouchEnd: cancel,
    onTouchCancel: cancel,
    onContextMenu: (event: MouseEvent) => { event.preventDefault(); cancel(); onMenu(); }
  } : {};

  return (
    <div className={`msg ${mine ? 'mine' : 'theirs'} ${startsRun ? 'run-start' : ''} ${endsRun ? 'run-end' : ''}`}>
      {!mine ? <div className="msg-avatar">{endsRun ? avatar : null}</div> : null}
      <div className="msg-col">
        {senderName ? <p className="msg-name small">{senderName}</p> : null}
        <div className="msg-line">
          <div className={`bubble ${card ? 'has-card' : ''} ${deleted ? 'is-deleted' : ''}`} {...touchHandlers}>
            <Body message={message} localImage={localImage} />
            {edited ? <span className="bubble-edited">Edited</span> : null}
          </div>
          {onMenu ? <button type="button" className="msg-more" aria-label="Message actions" onClick={onMenu}>⋯</button> : null}
        </div>
        {footer ? <div className="msg-foot small">{footer}</div> : null}
      </div>
    </div>
  );
}
