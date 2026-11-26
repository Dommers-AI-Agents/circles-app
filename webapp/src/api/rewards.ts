// Store rewards and the Locals tab: the same endpoints the iOS app and the
// store's web page (/s/<code>) call. Shapes are read from
// backend/controllers/venues/rewardScanController.js and the services it uses.
import { del, get, post } from './client';
import type { GeoPoint } from './types';

// ---- shapes

export interface Offer {
  offerId?: string;
  title: string;
  pointsCost: number;
  active?: boolean;
}

/** The reward a balance is working toward (backend/services/rewardProgress.js). */
export interface NextReward {
  offerId?: string;
  title: string;
  pointsCost: number;
  remaining: number;
  visitsLeft: number | null;
  canRedeem: boolean;
}

export interface VenueInfo {
  venueId: string;
  venueName: string;
  placeName?: string | null;
  placeAddress?: string | null;
  category?: string;
  globalPlaceId?: string | null;
  location?: { lat: number; lng: number } | null;
  isVirtual?: boolean;
  genericJoin?: boolean;
  coverPhotoUrl?: string | null;
  earnRate?: number | null;
}

/** A store event rides on an announcement. */
export interface AnnouncementEvent {
  startsAt: string;
  endsAt?: string | null;
  localDate: string;
  localTime?: string | null;
  isFree?: boolean | null;
}

export interface Announcement {
  announcementId: string;
  title: string;
  message?: string | null;
  expiresAt?: string | null;
  createdAt?: string;
  event?: AnnouncementEvent | null;
}

/** My points at one store, with what they buy there. */
export interface VenueBalance {
  venueId: string;
  venueName: string;
  points: number;
  globalPlaceId?: string;
  offers?: { title: string; pointsCost: number }[];
  earnRate?: number | null;
}

/** A row of the points ledger (rewardEvents). */
export interface RewardEvent {
  id: string;
  type: string;
  points: number;
  venueId?: string | null;
  venueName?: string | null;
  offerTitle?: string | null;
  status?: string | null;
  via?: string | null;
  createdAt?: string;
}

/** A counter ticket: 15 minutes, staff tap Given. */
export interface Voucher {
  voucherId: string;
  voucherCode: string;
  offerTitle: string;
  expiresAt: string;
  venueId?: string;
  venueName?: string | null;
  /** 0 for a coupon's ticket: nothing was spent, nothing comes back */
  pointsCost?: number;
  status?: 'issued' | 'given' | 'expired';
  createdAt?: string;
  givenAt?: string | null;
  refunded?: boolean;
  couponId?: string;
  onlineCode?: string | null;
}

export interface CouponClaim {
  claimId: string;
  venueId: string;
  venueName?: string | null;
  couponId?: string;
  title: string;
  detail?: string | null;
  onlineCode?: string | null;
  expiresAt?: string | null;
  claimedAt?: string | null;
  status: 'claimed' | 'ticket' | 'used' | 'expired' | string;
  voucherId?: string | null;
  usedAt?: string | null;
}

/** What a scan's coupon link did (services/storeCoupons.claim / issueTicket). */
export interface ScanCoupon {
  status: string;
  coupon?: { title?: string; detail?: string | null; expiresAt?: string | null } | null;
  claim?: CouponClaim | null;
  voucher?: Voucher | null;
}

export interface ScanResult {
  kind: 'window' | 'register' | 'generic';
  generic?: boolean;
  venue?: VenueInfo | null;
  awarded?: { type: string; points: number } | null;
  coupon?: ScanCoupon | null;
  saved?: boolean;
  savePending?: boolean;
  alreadySaved?: boolean;
  alreadyEarnedToday?: boolean;
  notAtStore?: boolean;
  removedFromRewards?: boolean;
  loyaltyPaused?: boolean;
  loyaltyState?: 'not_started' | 'paused';
  loyaltyLive?: boolean;
  balance?: number;
  venueBalance?: number;
  earnRate?: number | null;
  saveBonusPoints?: number;
  nextReward?: NextReward | null;
  nextRewardLine?: string | null;
  offers?: Offer[];
}

/** Where the phone is, for a register scan (same rule as store-page.js). */
export type ScanWhere =
  | { location: { latitude: number; longitude: number; accuracy: number } }
  | { locationOff: true }
  | Record<string, never>;

export interface ScanInput {
  code: string;
  /** an NFC sticker's tag (?t=) */
  t?: string;
  /** a coupon's id (?c=) */
  c?: string;
  /** who invited them (?ref=) */
  ref?: string;
}

export interface HistoryRow {
  at?: string;
  points: number;
  kind: 'earn' | 'redeem' | 'expired' | 'refund' | string;
  title: string;
}

export interface StoreHistory {
  visits: number;
  earned: number;
  redeemed: number;
  firstAt?: string | null;
  lastVisitAt?: string | null;
  recent: HistoryRow[];
}

export interface StoreRewards {
  venue: VenueInfo | null;
  rewardsLive?: boolean;
  offers?: Offer[];
  announcements?: Announcement[];
  balance?: number;
  venueBalance?: number;
  nextReward?: NextReward | null;
  myCoupons?: CouponClaim[];
  myHistory?: StoreHistory;
  isOwner?: boolean;
}

export interface NearbyVenue extends VenueInfo {
  savedByUser?: boolean;
  photoUrl?: string | null;
  distanceMeters?: number | null;
  offers: Offer[];
  announcements: Announcement[];
}

export interface LocalEvent {
  id: string;
  source?: 'store' | 'library' | 'ticketmaster' | string;
  sourceName?: string | null;
  name: string;
  message?: string | null;
  startLocalDate: string;
  startLocalTime?: string | null;
  venueName?: string | null;
  venueAddress?: string | null;
  city?: string | null;
  category?: string | null;
  imageUrl?: string | null;
  url?: string | null;
  priceMin?: number | null;
  priceMax?: number | null;
  currency?: string | null;
  isFree?: boolean | null;
  distanceMeters?: number | null;
  lat?: number | null;
  lng?: number | null;
  /** store events only */
  venueId?: string;
  globalPlaceId?: string | null;
}

export interface Market {
  id: string;
  name: string;
  address?: string | null;
  lat: number;
  lng: number;
  distanceMeters?: number | null;
  acceptsSnap?: boolean;
  organic?: boolean;
  photoUrl?: string | null;
  website?: string | null;
  hoursSummary?: string | null;
}

export interface LocalFeed {
  events: LocalEvent[];
  markets: Market[];
  attribution: string | null;
}

type Data<T> = { data: T };
const id = encodeURIComponent;

// ---- my rewards

export const balance = () =>
  get<Data<{ balance: number; venueBalances: VenueBalance[]; events: RewardEvent[] }>>('/rewards/balance').then((r) => r.data);

/** Open tickets and the last 20. Listing also refunds any of mine that ran out. */
export const vouchers = () =>
  get<Data<{ active: Voucher[]; recent: Voucher[] }>>('/rewards/vouchers').then((r) => r.data);

export const voucherGiven = (voucherId: string) =>
  post<Data<Voucher>>(`/rewards/vouchers/${id(voucherId)}/given`).then((r) => r.data);

export const coupons = () => get<Data<{ coupons: CouponClaim[] }>>('/rewards/coupons').then((r) => r.data.coupons || []);

/** A claimed coupon becomes its 15-minute ticket (or hands back the one already open). */
export const useCoupon = (claimId: string) =>
  post<Data<{ claim: CouponClaim; voucher: Voucher; already?: boolean }>>(`/rewards/coupons/${id(claimId)}/use`).then((r) => r.data);

// ---- scanning a store's code

/** Which store a code is and whether it is the window or the register one. */
export const codeName = (input: ScanInput) =>
  get<Data<{ venueName: string | null; kind: 'window' | 'register' | 'generic' }>>(`/rewards/code-name/${id(input.code)}`, { t: input.t })
    .then((r) => r.data);

/**
 * `save: true` saves the store as the scan signs them up, like the store's
 * web page. Never `counted`: that flag says a served /s/ page already
 * counted this visit, and no page was served here.
 */
export const scan = (input: ScanInput, where: ScanWhere = {}) =>
  post<Data<ScanResult>>('/rewards/scan', { ...input, save: true, ...where }).then((r) => r.data);

// ---- one store

export const storeRewards = (globalPlaceId: string) =>
  get<Data<StoreRewards>>(`/rewards/venues/by-place/${id(globalPlaceId)}`, { history: 1 }).then((r) => r.data);

export const redeemOffer = (venueId: string, offerId: string) =>
  post<Data<{ voucher: Voucher; venueBalance: number }>>('/rewards/redeem-offer', { venueId, offerId, canShare: true }).then((r) => r.data);

/** Asked once per store, before the first reward there. */
export const shareWithStore = (venueId: string) => post<Data<{ shared: boolean }>>(`/rewards/venues/${id(venueId)}/share`);

/** The venue record: who follows it and who has its bell on. */
export const storeFollowState = (globalPlaceId: string, userId: string | undefined) =>
  get<Data<{ globalPlace: { followers?: string[]; alertFollowerIds?: string[]; location?: GeoPoint | null } }>>(`/places/global/${id(globalPlaceId)}`)
    .then((r) => {
      const place = r.data.globalPlace || {};
      const following = !!userId && (place.followers || []).includes(userId);
      return { following, alerts: following && !!userId && (place.alertFollowerIds || []).includes(userId) };
    });

export const followStore = (globalPlaceId: string) => post(`/places/${id(globalPlaceId)}/follow`);
export const storeAlertsOn = (globalPlaceId: string) => post(`/places/${id(globalPlaceId)}/follow/alerts`);
/** The bell off. Never unfollows. */
export const storeAlertsOff = (globalPlaceId: string) => del(`/places/${id(globalPlaceId)}/follow/alerts`);

// ---- Locals

export const nearbyOffers = (lat: number, lng: number) =>
  get<Data<{ venues: NearbyVenue[]; balance: number; venueBalances: VenueBalance[] }>>('/rewards/offers', { events: 1, lat, lng }).then((r) => r.data);

export const nearbyEvents = (lat: number, lng: number) =>
  get<Data<LocalFeed>>('/rewards/nearby-events', { lat, lng }).then((r) => r.data);

export const searchEvents = (q: string, lat: number, lng: number) =>
  get<Data<{ events: LocalEvent[]; nearby: boolean; attribution: string | null }>>('/rewards/nearby-events/search', { q, lat, lng }).then((r) => r.data);

/** Where the account was last seen, when it has said (the iOS app records it). */
export const accountLocation = () =>
  get<{ user: { lastKnownLocation?: { latitude?: number; longitude?: number; lat?: number; lng?: number } | null } }>('/users/me').then((r) => {
    // Written as { latitude, longitude } by the app and { lat, lng } by sign-up
    const spot = (r.user && r.user.lastKnownLocation) || {};
    const lat = spot.latitude ?? spot.lat;
    const lng = spot.longitude ?? spot.lng;
    return typeof lat === 'number' && typeof lng === 'number' && Number.isFinite(lat) && Number.isFinite(lng) && !(lat === 0 && lng === 0)
      ? { lat, lng }
      : null;
  });
