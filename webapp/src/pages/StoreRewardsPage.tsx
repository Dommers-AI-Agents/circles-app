// One store's rewards (iOS Controllers/Rewards/GetRewardsViewController.swift):
// its cover and name, my points there and the bar toward the next reward,
// every reward with Redeem on the ones I can afford (→ the counter ticket),
// what the store has posted, my coupons and my history there, and a switch
// for getting its specials by email. Loaded by the store's place
// (GET /rewards/venues/by-place/:placeId): the route carries the venueId and
// the place rides along as ?p=, or is found in my balances / the offers list.
import { useState, type ReactNode } from 'react';
import { Link, useParams, useSearchParams } from 'react-router-dom';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import {
  balance as loadBalance, followStore, nearbyOffers, redeemOffer, shareWithStore, storeAlertsOff, storeAlertsOn,
  storeFollowState, storeRewards, type Offer, type Voucher
} from '../api/rewards';
import { ApiError, messageOf } from '../api/client';
import { useAuth } from '../auth/AuthContext';
import { DEFAULT_CENTER } from '../logic/geo';
import { endsLine, eventWhen, localDayKey, stampDay } from '../logic/eventTime';
import { isOpenCoupon, placeOfVenue, pointsText, redeemExplainer, rewardLadder, shortByText } from '../logic/rewards';
import { Empty, Head, LoadError, Sheet, Spinner, toast } from '../ui/kit';
import { RewardBar } from '../ui/rewards/RewardBar';
import { CouponCard, HistoryList, ShareWithStoreSheet } from '../ui/rewards/RewardPieces';
import { ScannerSheet } from '../ui/rewards/ScannerSheet';
import { TicketSheet } from '../ui/rewards/TicketSheet';
import { rememberVenuePlace, venuePlaceOf } from '../ui/rewards/venuePlaces';
import '../ui/rewards/rewards.css';
import './store-rewards.css';

class StoreNotFound extends Error {}

/** The store's place, from the link, this phone's memory, my balances or the stores running rewards. */
function useStorePlace(venueId: string, fromLink: string | null) {
  const queryClient = useQueryClient();
  const known = fromLink || venuePlaceOf(venueId) || null;
  const lookup = useQuery({
    queryKey: ['rewards', 'venuePlace', venueId],
    enabled: !known,
    retry: false,
    queryFn: async () => {
      const mine = await queryClient.fetchQuery({ queryKey: ['rewards', 'balance'], queryFn: loadBalance });
      let found = placeOfVenue(venueId, mine.venueBalances);
      if (!found) {
        const browse = await nearbyOffers(DEFAULT_CENTER.lat, DEFAULT_CENTER.lng);
        found = placeOfVenue(venueId, browse.venues, browse.venueBalances);
      }
      if (!found) throw new StoreNotFound("We couldn't find this store's rewards.");
      rememberVenuePlace(venueId, found);
      return found;
    }
  });
  return { placeId: known || lookup.data || null, lookup };
}

function Section({ title, children }: { title: string; children: ReactNode }) {
  return <section className="rw-section"><h2>{title}</h2>{children}</section>;
}

export function StoreRewardsPage() {
  const { venueId = '' } = useParams();
  const [search] = useSearchParams();
  const { userId } = useAuth();
  const queryClient = useQueryClient();
  const { placeId, lookup } = useStorePlace(venueId, search.get('p'));

  const store = useQuery({ queryKey: ['rewards', 'store', placeId], queryFn: () => storeRewards(placeId!), enabled: !!placeId });
  const follow = useQuery({ queryKey: ['rewards', 'follow', placeId, userId], queryFn: () => storeFollowState(placeId!, userId), enabled: !!placeId });

  const [confirming, setConfirming] = useState<Offer | null>(null);
  const [sharing, setSharing] = useState<Offer | null>(null);
  const [shareError, setShareError] = useState('');
  const [busy, setBusy] = useState(false);
  const [redeemError, setRedeemError] = useState('');
  const [ticket, setTicket] = useState<{ voucher: Voucher; storeName: string } | null>(null);
  const [scanning, setScanning] = useState(false);
  const [switching, setSwitching] = useState(false);

  const data = store.data;
  const venue = data && data.venue && data.venue.venueId === venueId ? data.venue : null;
  const name = venue ? venue.venueName || venue.placeName || 'this store' : 'Store';
  const live = !!data && data.rewardsLive === true;
  const points = (data && data.venueBalance) || 0;
  const ladder = live ? rewardLadder(data && data.offers) : [];
  const todayKey = localDayKey();

  const redeem = async (offer: Offer) => {
    if (!offer.offerId) return;
    setBusy(true);
    setRedeemError('');
    try {
      const result = await redeemOffer(venueId, offer.offerId);
      queryClient.invalidateQueries({ queryKey: ['rewards'] });
      setConfirming(null);
      setSharing(null);
      setTicket({ voucher: result.voucher, storeName: name });
    } catch (e) {
      setConfirming(null);
      if (e instanceof ApiError && e.code === 'share_required') {
        setShareError('');
        setSharing(offer);
      } else {
        setSharing(null);
        setRedeemError(messageOf(e));
        queryClient.invalidateQueries({ queryKey: ['rewards', 'store', placeId] });
      }
    } finally {
      setBusy(false);
    }
  };

  const agreeAndRedeem = async () => {
    if (!sharing) return;
    setBusy(true);
    setShareError('');
    try {
      await shareWithStore(venueId);
    } catch (e) {
      setBusy(false);
      setShareError(messageOf(e));
      return;
    }
    await redeem(sharing);
  };

  // The bell needs following; turning it off never unfollows
  const setEmails = async (on: boolean) => {
    if (!placeId || !follow.data) return;
    setSwitching(true);
    try {
      if (on) {
        if (!follow.data.following) await followStore(placeId);
        await storeAlertsOn(placeId);
        toast(`You'll get ${name}'s specials by email`);
      } else {
        await storeAlertsOff(placeId);
        toast(`No more emails from ${name}`);
      }
      queryClient.setQueryData(['rewards', 'follow', placeId, userId], { following: on || follow.data.following, alerts: on });
      queryClient.invalidateQueries({ queryKey: ['place', placeId] });
    } catch (e) {
      toast(messageOf(e));
    } finally {
      setSwitching(false);
      queryClient.invalidateQueries({ queryKey: ['rewards', 'follow', placeId] });
    }
  };

  const loading = (!placeId && lookup.isPending) || (!!placeId && store.isPending);
  const failed = lookup.isError ? lookup.error : store.isError ? store.error : null;
  const coupons = ((data && data.myCoupons) || []).filter(isOpenCoupon);
  const history = data && data.myHistory;
  const posts = (data && data.announcements) || [];

  return (
    <>
      <Head title={venue ? name : 'Store rewards'} back="/rewards" />
      <main className="page">
        {loading ? <Spinner /> : null}
        {failed ? (
          failed instanceof StoreNotFound ? (
            <Empty mark="🏬" title="We couldn't find this store" action={<Link className="btn" to="/rewards">See my rewards</Link>}>
              Its rewards may have ended, or the link is old. Your points at every store are in Rewards.
            </Empty>
          ) : <LoadError message={messageOf(failed)} retry={() => (lookup.isError ? lookup.refetch() : store.refetch())} />
        ) : null}
        {data && !venue ? (
          <Empty mark="🏬" title="This place isn't running FavCircles Rewards"
            action={placeId ? <Link className="btn" to={`/place/${encodeURIComponent(placeId)}`}>Open its page</Link> : undefined}>
            You can still save it to your map and follow its news from its page.
          </Empty>
        ) : null}

        {venue ? (
          <>
            <div className="sr-hero" style={venue.coverPhotoUrl ? { backgroundImage: `url("${venue.coverPhotoUrl.replace(/"/g, '%22')}")` } : undefined}>
              <div>
                <h2>{name}</h2>
                {venue.placeAddress ? <p>{venue.placeAddress}</p> : venue.isVirtual ? <p>Online store</p> : null}
              </div>
            </div>
            {placeId ? <Link className="sr-place-link" to={`/place/${encodeURIComponent(placeId)}`}>Open {name}’s page ›</Link> : null}

            {live ? (
              <div className="card rw-card sr-balance">
                <div className="row" style={{ alignItems: 'flex-start' }}>
                  <div className="grow">
                    <p className="small muted sr-label">{data!.nextReward && data!.nextReward.canRedeem ? 'Ready to redeem' : 'Your points here'}</p>
                    <p className="sr-points">{points}</p>
                  </div>
                  <span className="sr-star" aria-hidden="true">⭐</span>
                </div>
                <RewardBar reward={data!.nextReward} points={points} />
                {venue.earnRate ? (
                  <p className="small muted" style={{ marginTop: 10 }}>
                    Earn {pointsText(venue.earnRate)} each visit: after you buy something, scan the FavCircles QR code by the register. Once a day.
                  </p>
                ) : null}
                <button className="btn block soft" style={{ marginTop: 12 }} onClick={() => setScanning(true)}>📷 Scan the register code</button>
              </div>
            ) : (
              <div className="card rw-card">
                <h3>Rewards aren’t running here right now</h3>
                <p className="small muted" style={{ marginTop: 4 }}>
                  {name} isn’t giving points at the moment. You can still follow it for its specials and events.
                </p>
              </div>
            )}

            {live ? (
              <Section title="What your points get you">
                {ladder.length === 0 ? (
                  <p className="card rw-card small muted">{name} hasn’t posted rewards yet. Points you earn here stay here for when it does.</p>
                ) : (
                  <ul className="list card" style={{ marginTop: 12, overflow: 'hidden' }}>
                    {ladder.map((offer) => {
                      const affordable = points >= offer.pointsCost;
                      return (
                        <li key={offer.offerId || offer.title} className="rw-row">
                          <span aria-hidden="true">🎁</span>
                          <span className="grow">
                            <span style={{ display: 'block', fontWeight: 600 }}>{offer.title}</span>
                            <span className="small muted">{pointsText(offer.pointsCost)}</span>
                          </span>
                          {affordable ? (
                            <button className="btn small" disabled={busy} onClick={() => { setRedeemError(''); setConfirming(offer); }}>Redeem</button>
                          ) : (
                            <span className="small muted" style={{ whiteSpace: 'nowrap' }}>{shortByText(offer.pointsCost, points)}</span>
                          )}
                        </li>
                      );
                    })}
                  </ul>
                )}
                <p className="err" role="alert" style={{ marginTop: 8 }}>{redeemError}</p>
              </Section>
            ) : null}

            {coupons.length > 0 ? (
              <Section title={coupons.length === 1 ? 'Your coupon' : 'Your coupons'}>
                {coupons.map((coupon) => (
                  <CouponCard key={coupon.claimId} coupon={coupon}
                    onTicket={(voucher) => setTicket({ voucher, storeName: name })} />
                ))}
              </Section>
            ) : null}

            <Section title={`What’s on at ${name}`}>
              {posts.length === 0 ? (
                <p className="card rw-card small muted">Nothing posted right now. Turn on emails below to hear about specials and events.</p>
              ) : posts.map((post) => {
                const when = post.event ? eventWhen(post.event.localDate, post.event.localTime, todayKey) : '';
                const ends = !post.event ? endsLine(post.expiresAt) : '';
                return (
                  <div key={post.announcementId} className="card rw-card">
                    <p className="small sr-kind">{post.event ? `📅 ${[when, post.event.isFree ? 'Free' : ''].filter(Boolean).join(' · ')}` : '📣 Special'}</p>
                    <h3>{post.title}</h3>
                    {post.message ? <p className="sr-message">{post.message}</p> : null}
                    {ends ? <p className="small muted" style={{ marginTop: 6 }}>{ends}</p> : null}
                  </div>
                );
              })}
            </Section>

            <label className="card rw-switch" style={{ marginTop: 16 }}>
              <span className="grow">
                <strong style={{ display: 'block' }}>Get its specials by email</strong>
                <span className="small muted">
                  {follow.isError ? 'This switch didn’t load. Pull down or come back to try again.'
                    : `When ${name} posts a special or an event, we email you.`}
                </span>
              </span>
              <input type="checkbox" checked={!!follow.data && follow.data.alerts} disabled={!follow.data || switching}
                onChange={(e) => setEmails(e.target.checked)} />
              <span className="track" aria-hidden="true" />
            </label>

            {history && (history.visits > 0 || history.earned > 0 || history.redeemed > 0 || history.recent.length > 0) ? (
              <Section title={`You at ${name}`}>
                <div className="sr-tiles">
                  <div className="card"><b>{history.visits}</b><span>{history.visits === 1 ? 'Visit' : 'Visits'}</span></div>
                  <div className="card"><b>{history.earned}</b><span>Points earned</span></div>
                  <div className="card"><b>{history.redeemed}</b><span>{history.redeemed === 1 ? 'Reward used' : 'Rewards used'}</span></div>
                </div>
                {history.firstAt ? <p className="small muted" style={{ margin: '10px 2px 0' }}>Since {stampDay(history.firstAt)}</p> : null}
                {history.recent.length > 0 ? <HistoryList rows={history.recent} /> : null}
              </Section>
            ) : null}

            <Link className="btn block plain" style={{ marginTop: 18 }} to="/rewards">All my rewards</Link>
          </>
        ) : null}
      </main>

      {confirming ? (
        <Sheet title={`Redeem ${confirming.title}?`} onClose={() => setConfirming(null)}>
          <p className="muted" style={{ marginBottom: 16 }}>{redeemExplainer(confirming.pointsCost, name)}</p>
          <button className="btn block" disabled={busy} onClick={() => redeem(confirming)}>{busy ? 'Redeeming…' : 'Redeem'}</button>
          <button className="btn block plain" onClick={() => setConfirming(null)}>Cancel</button>
        </Sheet>
      ) : null}
      {sharing ? (
        <ShareWithStoreSheet storeName={name} busy={busy} error={shareError} onAgree={agreeAndRedeem} onClose={() => setSharing(null)} />
      ) : null}
      {ticket ? <TicketSheet voucher={ticket.voucher} storeName={ticket.storeName} onClose={() => setTicket(null)} /> : null}
      {scanning ? (
        <ScannerSheet onClose={() => setScanning(false)} onTicket={(voucher, storeName) => { setScanning(false); setTicket({ voucher, storeName }); }} />
      ) : null}
    </>
  );
}
