// The counter ticket: a reward (or a coupon) the customer shows to staff.
// It lasts 15 minutes; staff tap "Given" on this phone. A ticket that runs
// out unshown gives the points back (a coupon's ticket gives the coupon back).
import { useCallback, useEffect, useState } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { voucherGiven, type Voucher } from '../../api/rewards';
import { ApiError, messageOf } from '../../api/client';
import { countdownText, isCouponTicket, secondsLeft, ticketRanOutLine } from '../../logic/rewards';
import { Sheet } from '../kit';
import './rewards.css';

/** Seconds left on a ticket, ticking once a second. */
export function useCountdown(expiresAt: string | undefined): number {
  const [left, setLeft] = useState(() => secondsLeft(expiresAt, Date.now()));
  useEffect(() => {
    setLeft(secondsLeft(expiresAt, Date.now()));
    const timer = setInterval(() => setLeft(secondsLeft(expiresAt, Date.now())), 1000);
    return () => clearInterval(timer);
  }, [expiresAt]);
  return left;
}

export function TicketSheet({ voucher, storeName, onClose }: { voucher: Voucher; storeName?: string; onClose: () => void }) {
  const queryClient = useQueryClient();
  const left = useCountdown(voucher.expiresAt);
  const [given, setGiven] = useState(voucher.status === 'given');
  const [ranOut, setRanOut] = useState(voucher.status === 'expired');
  const [asking, setAsking] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const store = storeName || voucher.venueName || '';
  const over = ranOut || (!given && left <= 0);
  const coupon = isCouponTicket(voucher);

  // Listing my tickets is what hands the points back, so ask as soon as it runs out
  const refresh = useCallback(() => queryClient.invalidateQueries({ queryKey: ['rewards'] }), [queryClient]);
  useEffect(() => { if (over) refresh(); }, [over, refresh]);
  const close = useCallback(() => { refresh(); onClose(); }, [refresh, onClose]);

  const markGiven = async () => {
    setBusy(true);
    setError('');
    try {
      await voucherGiven(voucher.voucherId);
      setGiven(true);
      refresh();
    } catch (e) {
      if (e instanceof ApiError && e.status === 409) setRanOut(true);
      else setError(messageOf(e));
    } finally {
      setBusy(false);
      setAsking(false);
    }
  };

  return (
    <Sheet title={coupon ? 'Your coupon' : 'Your reward'} onClose={close}>
      <div className="ticket">
        <div className="what">{voucher.offerTitle || 'Your reward'}</div>
        {store ? <div className="where">at {store}</div> : null}
        <div className="code" aria-label="Ticket code">{voucher.voucherCode}</div>
        {given ? <div className="left done">Given ✓ Enjoy!</div> : null}
        {!given && over ? <div className="left out">Time’s up</div> : null}
        {!given && !over ? <div className="left" role="timer">Good for {countdownText(left)}</div> : null}
        {voucher.onlineCode && !given ? <div className="online">Ordering online? Use code {voucher.onlineCode}.</div> : null}
      </div>

      {given ? null : over ? (
        <p className="ticket-note">{ticketRanOutLine(voucher, store)}</p>
      ) : (
        <p className="ticket-note">
          Show this screen to staff. They tap Given when they hand it over. You can close it and come back: it waits in Rewards.
          {' '}{coupon
            ? 'If it runs out first, the coupon stays yours.'
            : 'If it runs out first, your points come back.'}
        </p>
      )}

      <p className="err" role="alert">{error}</p>
      {!given && !over && !asking ? (
        <button className="btn block" onClick={() => setAsking(true)}>Staff: tap when given</button>
      ) : null}
      {!given && !over && asking ? (
        <div className="card" style={{ padding: 14, marginBottom: 8 }}>
          <strong>Hand over {voucher.offerTitle || 'this reward'}?</strong>
          <p className="small muted" style={{ margin: '4px 0 12px' }}>For staff: this marks it as given. It can’t be used again.</p>
          <div className="rw-actions" style={{ marginTop: 0 }}>
            <button className="btn soft" onClick={() => setAsking(false)} disabled={busy}>Not yet</button>
            <button className="btn" onClick={markGiven} disabled={busy}>{busy ? 'Marking…' : 'Yes, given'}</button>
          </div>
        </div>
      ) : null}
      <button className="btn block plain" onClick={close}>{given || over ? 'Done' : 'Close'}</button>
    </Sheet>
  );
}

/** A live ticket as a row: tap to show it at the counter. */
export function LiveTicketRow({ voucher, onOpen }: { voucher: Voucher; onOpen: (voucher: Voucher) => void }) {
  const left = useCountdown(voucher.expiresAt);
  if (left <= 0) return null;
  return (
    <button className="card ticket-live" onClick={() => onOpen(voucher)}>
      <span className="grow">
        <strong className="clip" style={{ display: 'block' }}>{voucher.offerTitle}</strong>
        <span className="small muted clip" style={{ display: 'block' }}>{voucher.venueName ? `${voucher.venueName} · ` : ''}Show at the counter</span>
      </span>
      <span style={{ textAlign: 'right' }}>
        <span className="code">{voucher.voucherCode}</span><br />
        <span className="left">{countdownText(left)}</span>
      </span>
    </button>
  );
}
