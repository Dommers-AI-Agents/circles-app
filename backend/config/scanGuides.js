// backend/config/scanGuides.js
//
// "Show me how" QR codes (Scan Actions, Wes 2026-11-11): each guide is a fixed,
// printable link, https://api.favcircles.com/q/<id>, that opens the app and
// walks the person through one thing, step by step, over the real screens.
// They never expire and need no create call; the app's ScreenGuide runs the
// steps (ScreenGuideKind raw value = `appGuide`).
//
// An id is lowercase letters and hyphens only, and never 8 bare letters
// (that reads as a made code, services/scanActionService normalizeCode).
//
// Adding a guide: a row here + its ScreenGuideKind stops in the app
// (Logic/ScreenGuideCopy.swift) + a ScanActionPlan test.

const SCAN_GUIDES = [
  {
    id: 'share-a-place',
    appGuide: 'sharePlace',
    title: 'Share a place',
    blurb: 'Send a place to a friend, or show a QR they scan to save it.'
  },
  {
    id: 'make-a-circle',
    appGuide: 'makeCircle',
    title: 'Make a circle',
    blurb: 'Group your favorite places: brunch spots, date nights, coffee.'
  },
  {
    id: 'add-a-place',
    appGuide: 'addPlace',
    title: 'Add a place',
    blurb: 'Save a place you love to your map.'
  },
  {
    id: 'check-in',
    appGuide: 'checkIn',
    title: 'Check in',
    blurb: 'Mark where you are and keep a history of your visits.'
  },
  {
    id: 'see-widgets',
    appGuide: 'widgets',
    title: 'Try the widgets',
    blurb: 'Little apps inside FavCircles: water, habits, runs, postcards and more.'
  },
  {
    id: 'rewards',
    appGuide: 'rewards',
    title: 'Earn rewards',
    blurb: 'Collect points at local stores and see what they give back.'
  },
  {
    id: 'store-setup',
    appGuide: 'storeSetup',
    title: 'Set up your store',
    blurb: 'Claim your business, set your points and post your first reward.',
    // A store owner's walkthrough: finds their business, files the claim,
    // then the rewards setup once it's approved
    storeOwner: true
  }
];

const byId = new Map(SCAN_GUIDES.map((guide) => [guide.id, guide]));

/** The guide for a code, or null. */
const scanGuide = (id) => byId.get(String(id || '').toLowerCase()) || null;

module.exports = { SCAN_GUIDES, scanGuide };
