// Pieces both rewards screens draw: a coupon on hand, the points ledger,
// and the once-per-store "share your name and email" step before a reward.
import { useState } from 'react';
import { Link } from 'react-router-dom';
import { useQueryClient } from '@tanstack/react-query';
import { useCoupon as openCouponTicket, type CouponClaim, type HistoryRow, type Voucher } from '../../api/rewards';
import { messageOf } from '../../api/client';
import { COUPON_USE_EXPLAINER, couponAction, couponDetail, signedPoints } from '../../logic/rewards';
import { stampDay } from '../../logic/eventTime';
import { Sheet, toast } from '../kit';
import { storeRewardsPath } from './venuePlaces';
import './rewards.css';

/** One coupon: the store, what it gives, when it ends, and the button that opens its ticket. */
export function CouponCard({ coupon, showStore, onTicket }: {
  coupon: CouponClaim; showStore?: boolean; onTicket: (voucher: Voucher, storeName: string) => void;
}) {
  const queryClient = useQueryClient();
  const [asking, setAsking] = useState(false);
  const [busy, setBusy] = useState(false);
  const action = couponAction(coupon);
  const store = coupon.venueName || '';

  const open = async () => {
    setBusy(true);
    try {
      const data = await openCouponTicket(coupon.claimId);
      queryClient.invalidateQueries({ queryKey: ['rewards'] });
      setAsking(false);
      onTicket(data.voucher, store);
    } catch (e) {
      toast(messageOf(e));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="card rw-card">
      <div className="row" style={{ alignItems: 'flex-start' }}>
        <span aria-hidden="true" style={{ fontSize: 22 }}>🎟️</span>
        <div className="grow">
          {showStore && store ? (
            <Link className="small muted rw-store-link" to={storeRewardsPath(coupon.venueId)}>{store} ›</Link>
          ) : null}
          <h3>{coupon.title}</h3>
          <p className="small muted">{couponDetail(coupon)}</p>
        </div>
      </div>
      {action ? (
        <button className="btn block" style={{ marginTop: 12 }} disabled={busy}
          onClick={() => (coupon.status === 'ticket' ? open() : setAsking(true))}>
          {busy && coupon.status === 'ticket' ? 'Opening…' : action}
        </button>
      ) : null}
      {asking ? (
        <Sheet title={`Use ${coupon.title}?`} onClose={() => setAsking(false)}>
          <p className="muted" style={{ marginBottom: 16 }}>{COUPON_USE_EXPLAINER}</p>
          <button className="btn block" onClick={open} disabled={busy}>{busy ? 'Opening…' : 'Use now'}</button>
          <button className="btn block plain" onClick={() => setAsking(false)}>Not yet</button>
        </Sheet>
      ) : null}
    </div>
  );
}

/** Rows of the points ledger: what, when, and the points it moved. */
export function HistoryList({ rows }: { rows: (HistoryRow & { store?: string | null })[] }) {
  return (
    <ul className="list card" style={{ marginTop: 12, overflow: 'hidden' }}>
      {rows.map((row, i) => {
        const points = signedPoints(row.points);
        return (
          <li key={`${row.at || ''}:${i}`} className="rw-row">
            <span aria-hidden="true">{row.kind === 'earn' ? '⭐' : row.kind === 'refund' ? '↩️' : row.kind === 'expired' ? '⌛' : '🎁'}</span>
            <span className="grow">
              <span className="clip" style={{ display: 'block' }}>{row.title}</span>
              <span className="small muted clip" style={{ display: 'block' }}>
                {[row.store, stampDay(row.at), row.kind === 'expired' ? 'Ran out · points back' : ''].filter(Boolean).join(' · ')}
              </span>
            </span>
            {points ? <span className={`amount${row.points > 0 ? ' plus' : ''}`}>{points}</span> : null}
          </li>
        );
      })}
    </ul>
  );
}

/**
 * Rewards are claimed by name: the first one at a store asks to share the
 * FavCircles name, photo and email with it (iOS ShareWithStoreViewController).
 */
export function ShareWithStoreSheet({ storeName, busy, error, onAgree, onClose }: {
  storeName: string; busy: boolean; error?: string; onAgree: () => void; onClose: () => void;
}) {
  const [agreed, setAgreed] = useState(false);
  return (
    <Sheet title={`Share your name and email with ${storeName}`} onClose={onClose}>
      <p className="muted" style={{ marginBottom: 14 }}>
        Rewards at {storeName} are claimed by name, so the counter knows whose reward it is. You only do this once here.
      </p>
      <label className="card rw-check">
        <input type="checkbox" checked={agreed} onChange={(e) => setAgreed(e.target.checked)} />
        <span>I agree to share my FavCircles name, photo and email with {storeName}.</span>
      </label>
      <p className="err" role="alert">{error}</p>
      <button className="btn block" disabled={!agreed || busy} onClick={onAgree}>{busy ? 'Claiming…' : 'Claim reward'}</button>
      <button className="btn block plain" onClick={onClose}>Not now</button>
    </Sheet>
  );
}
