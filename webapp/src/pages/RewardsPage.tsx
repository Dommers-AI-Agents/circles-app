// My Rewards (iOS Controllers/Rewards/RewardsViewController.swift): a ticket
// that is open right now first, then the coupons on hand, my points store by
// store (each store keeps its own; there is no account-wide total), the
// rewards I've used and the points ledger. "Scan a store code" opens the
// scanner (camera where the browser can read QR codes, always a typed code).
import { useState } from 'react';
import { Link } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import { balance as loadBalance, coupons as loadCoupons, vouchers as loadVouchers, type Voucher } from '../api/rewards';
import { messageOf } from '../api/client';
import { historyRowOf, isOpenCoupon, nextReward, orderBalances, voucherStatusLine } from '../logic/rewards';
import { stampDay } from '../logic/eventTime';
import { Empty, Head, LoadError, Spinner } from '../ui/kit';
import { RewardBar } from '../ui/rewards/RewardBar';
import { CouponCard, HistoryList } from '../ui/rewards/RewardPieces';
import { ScannerSheet } from '../ui/rewards/ScannerSheet';
import { LiveTicketRow, TicketSheet } from '../ui/rewards/TicketSheet';
import { storeRewardsPath } from '../ui/rewards/venuePlaces';
import '../ui/rewards/rewards.css';
import './rewards-page.css';

const HOW_IT_WORKS: [string, string][] = [
  ['📍', 'Spot the FavCircles QR code in the window of a place you love.'],
  ['📲', 'Scan it, or type the 6 characters under it, to save the store to your map.'],
  ['🧾', 'At stores running FavCircles Rewards, scan the code at the register when you buy something. Each store sets its own points.'],
  ['🏬', 'Points stay with the store: earn them there, spend them on that store’s rewards.'],
  ['🎁', 'Redeem at the counter: you get a 15-minute ticket to show staff.']
];

export function RewardsPage() {
  const [scanning, setScanning] = useState(false);
  const [ticket, setTicket] = useState<{ voucher: Voucher; storeName: string } | null>(null);
  const balance = useQuery({ queryKey: ['rewards', 'balance'], queryFn: loadBalance });
  const vouchers = useQuery({ queryKey: ['rewards', 'vouchers'], queryFn: loadVouchers });
  const coupons = useQuery({ queryKey: ['rewards', 'coupons'], queryFn: loadCoupons });

  const showTicket = (voucher: Voucher, storeName = '') => setTicket({ voucher, storeName });
  const live = (vouchers.data?.active || []).filter((v) => v.status !== 'given' && v.status !== 'expired');
  const liveIds = new Set(live.map((v) => v.voucherId));
  const used = (vouchers.data?.recent || []).filter((v) => !liveIds.has(v.voucherId)).slice(0, 10);
  const openCoupons = (coupons.data || []).filter(isOpenCoupon);
  const stores = orderBalances(balance.data?.venueBalances);
  const ledger = (balance.data?.events || [])
    .map((event) => {
      const row = historyRowOf(event);
      return row ? { ...row, store: event.venueName } : null;
    })
    .filter((row): row is NonNullable<typeof row> => !!row);
  const nothingYet = !!balance.data && stores.length === 0 && ledger.length === 0 && openCoupons.length === 0 && live.length === 0;

  return (
    <>
      <Head title="Rewards" back />
      <main className="page">
        <button className="btn block" onClick={() => setScanning(true)}>📷 Scan a store code</button>

        {live.map((voucher) => <LiveTicketRow key={voucher.voucherId} voucher={voucher} onOpen={(v) => showTicket(v)} />)}

        {openCoupons.length > 0 ? (
          <section className="rw-section">
            <h2>{openCoupons.length === 1 ? 'Your coupon' : 'Your coupons'}</h2>
            {openCoupons.map((coupon) => <CouponCard key={coupon.claimId} coupon={coupon} showStore onTicket={showTicket} />)}
          </section>
        ) : null}

        {balance.isPending ? <Spinner /> : null}
        {balance.isError ? <LoadError message={messageOf(balance.error)} retry={() => balance.refetch()} /> : null}

        {nothingYet ? (
          <Empty mark="🎁" title="No store rewards yet"
            action={<button className="btn" onClick={() => setScanning(true)}>Scan a store code</button>}>
            Scan a store’s FavCircles QR code to save it. Stores that run FavCircles Rewards give their own points when you scan the code at the register.
          </Empty>
        ) : null}

        {stores.length > 0 ? (
          <section className="rw-section">
            <h2>Your rewards by store</h2>
            {stores.map((store) => {
              const next = nextReward(store.offers, store.points, store.earnRate);
              const body = (
                <>
                  <div className="row" style={{ alignItems: 'baseline' }}>
                    <h3 className="grow">{store.venueName || 'A store'}</h3>
                    <span className="rw-pts">{store.points} pts</span>
                  </div>
                  <RewardBar reward={next} points={store.points} />
                  {store.globalPlaceId ? <p className="rw-more">See rewards here ›</p> : null}
                </>
              );
              return store.globalPlaceId ? (
                <Link key={store.venueId} className="card rw-card rw-link" to={storeRewardsPath(store.venueId, store.globalPlaceId)}>{body}</Link>
              ) : (
                <div key={store.venueId} className="card rw-card">{body}</div>
              );
            })}
          </section>
        ) : null}

        {used.length > 0 ? (
          <section className="rw-section">
            <h2>Rewards used</h2>
            <ul className="list card" style={{ marginTop: 12, overflow: 'hidden' }}>
              {used.map((voucher) => (
                <li key={voucher.voucherId} className="rw-row">
                  <span aria-hidden="true">{voucher.status === 'given' ? '✅' : voucher.status === 'expired' ? '⌛' : '🎟️'}</span>
                  <span className="grow">
                    <span className="clip" style={{ display: 'block' }}>{voucher.offerTitle}</span>
                    <span className="small muted clip" style={{ display: 'block' }}>
                      {[voucher.venueName, stampDay(voucher.givenAt || voucher.createdAt), voucherStatusLine(voucher)].filter(Boolean).join(' · ')}
                    </span>
                  </span>
                </li>
              ))}
            </ul>
          </section>
        ) : null}

        {ledger.length > 0 ? (
          <section className="rw-section">
            <h2>Recent activity</h2>
            <HistoryList rows={ledger} />
          </section>
        ) : null}

        <section className="rw-section">
          <h2>How it works</h2>
          <div className="card rw-card">
            <ul className="rw-steps">
              {HOW_IT_WORKS.map(([mark, line]) => <li key={mark}><span aria-hidden="true">{mark}</span><span>{line}</span></li>)}
            </ul>
          </div>
          <p className="small muted" style={{ margin: '12px 2px 0' }}>
            Looking for deals near you? <Link to="/locals" style={{ color: 'var(--brand)', fontWeight: 600 }}>See Locals</Link>
          </p>
        </section>
      </main>
      {scanning ? <ScannerSheet onClose={() => setScanning(false)} onTicket={(v, name) => { setScanning(false); showTicket(v, name); }} /> : null}
      {ticket ? <TicketSheet voucher={ticket.voucher} storeName={ticket.storeName} onClose={() => setTicket(null)} /> : null}
    </>
  );
}
