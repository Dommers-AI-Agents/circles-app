// Small shared pieces every screen uses.
import { useEffect, useState, type ReactNode } from 'react';
import { createPortal } from 'react-dom';
import { useNavigate } from 'react-router-dom';

const COLORS = ['#3478F6', '#1B9AAA', '#E0723C', '#8E5BD6', '#2E9E6B', '#D6457B', '#C79A14'];
const colorFor = (seed: string) => {
  let sum = 0;
  for (let i = 0; i < seed.length; i++) sum = (sum * 31 + seed.charCodeAt(i)) >>> 0;
  return COLORS[sum % COLORS.length];
};
const initials = (name: string) => name.trim().split(/\s+/).slice(0, 2).map((part) => part.charAt(0).toUpperCase()).join('') || '?';

/** A person's photo, or their initials on a colour that is always theirs. */
export function Avatar({ name, src, size = 44, seed }: { name: string; src?: string | null; size?: number; seed?: string }) {
  const [broken, setBroken] = useState(false);
  const style = { width: size, height: size, fontSize: Math.round(size * 0.38) };
  if (src && !broken) return <img className="avatar" style={style} src={src} alt="" loading="lazy" onError={() => setBroken(true)} />;
  return <span className="avatar" style={{ ...style, background: colorFor(seed || name) }} aria-hidden="true">{initials(name)}</span>;
}

/** A photo that falls back to a mark (an emoji) on the brand tint. */
export function Thumb({ src, mark = '📍', className = 'thumb' }: { src?: string | null; mark?: string; className?: string }) {
  const [broken, setBroken] = useState(false);
  if (src && !broken) return <img className={className} src={src} alt="" loading="lazy" onError={() => setBroken(true)} />;
  return <span className={className} aria-hidden="true">{mark}</span>;
}

export const Spinner = () => <div className="spinner" role="status" aria-label="Loading" />;

export function Empty({ mark, title, children, action }: { mark: string; title: string; children?: ReactNode; action?: ReactNode }) {
  return (
    <div className="empty card">
      <div className="mark" aria-hidden="true">{mark}</div>
      <h2>{title}</h2>
      {children ? <p>{children}</p> : null}
      {action}
    </div>
  );
}

/** A failed load: what went wrong and a way to try again. Never a blank page. */
export function LoadError({ message, retry }: { message: string; retry?: () => void }) {
  return (
    <Empty mark="⚠️" title="That didn't load" action={retry ? <button className="btn soft" onClick={retry}>Try again</button> : undefined}>
      {message}
    </Empty>
  );
}

export function Head({ title, back, lead, children }: { title: string; back?: boolean | string; lead?: boolean; children?: ReactNode }) {
  const navigate = useNavigate();
  const goBack = () => {
    if (typeof back === 'string') navigate(back);
    else if (window.history.length > 1) navigate(-1);
    else navigate('/');
  };
  return (
    <header className="head">
      {back ? <button className="icon-btn" onClick={goBack} aria-label="Back">‹ Back</button> : null}
      <h1 className={lead ? 'lead' : undefined}>{title}</h1>
      {children}
    </header>
  );
}

export function Sheet({ title, onClose, children }: { title?: string; onClose: () => void; children: ReactNode }) {
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => { if (event.key === 'Escape') onClose(); };
    document.addEventListener('keydown', onKey);
    const overflow = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    return () => { document.removeEventListener('keydown', onKey); document.body.style.overflow = overflow; };
  }, [onClose]);
  return createPortal(
    <div className="scrim" onClick={(event) => { if (event.target === event.currentTarget) onClose(); }}>
      <div className="sheet" role="dialog" aria-modal="true" aria-label={title}>
        <div className="grab" />
        {title ? <h2>{title}</h2> : null}
        {children}
      </div>
    </div>,
    document.body
  );
}

// ---- toast: one short line that says what just happened
type ToastListener = (text: string | null) => void;
let toastListener: ToastListener | null = null;
let toastTimer: ReturnType<typeof setTimeout> | undefined;
export function toast(text: string) {
  if (!toastListener) return;
  toastListener(text);
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => toastListener && toastListener(null), 2600);
}
export function ToastHost() {
  const [text, setText] = useState<string | null>(null);
  useEffect(() => { toastListener = setText; return () => { toastListener = null; }; }, []);
  return text ? <div className="toast" role="status">{text}</div> : null;
}

/** Confirm before something that can't be taken back with one tap. */
export function ConfirmSheet({ title, body, action, danger, onConfirm, onClose }: {
  title: string; body?: string; action: string; danger?: boolean; onConfirm: () => void; onClose: () => void;
}) {
  return (
    <Sheet title={title} onClose={onClose}>
      {body ? <p className="muted" style={{ marginBottom: 16 }}>{body}</p> : null}
      <button className={`btn block ${danger ? 'danger' : ''}`} onClick={onConfirm}>{action}</button>
      <button className="btn block plain" onClick={onClose}>Cancel</button>
    </Sheet>
  );
}
