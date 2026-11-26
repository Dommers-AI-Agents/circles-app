// Which map pins get a full category pin and which shrink to a small dot.
// Wes's rule: "map pin tiering, not clustering" — a place is never folded
// into a numbered blob. Only pins in view are drawn; where full pins would
// pile on top of each other (zoomed out), the lower-priority ones become
// dots, and zooming in frees room so they grow back.
//
// Screen-space only (the map projects each place to a point first), so it is
// testable without a map. The same greedy pass as the iOS PinTierPlanner.

export interface PinCandidate {
  id: string;
  /** Where the place is on screen, in px from the map's top-left corner */
  x: number;
  y: number;
  /** Smaller wins a full pin first (e.g. distance from the middle of the map) */
  priority: number;
}

export interface PinTierOptions {
  /** Beyond this many full pins, everything else in view is a dot */
  maxFullPins?: number;
  /** Beyond this many dots, the lowest-priority places in view are left out */
  maxDots?: number;
  /** A full pin's footprint, centred on its point */
  pinSize?: number;
  /** Pins just outside the edge still take part, so panning doesn't make them pop */
  overscan?: number;
  /** Ids that keep a full pin no matter what (the selected place) */
  pinned?: string[];
}

export interface PinPlan {
  full: string[];
  dots: string[];
}

export function planPins(candidates: PinCandidate[], view: { width: number; height: number }, options: PinTierOptions = {}): PinPlan {
  const { maxFullPins = 45, maxDots = 400, pinSize = 36, overscan = 48, pinned = [] } = options;
  const keep = new Set(pinned);
  const full: string[] = [];
  const dots: string[] = [];
  const accepted: PinCandidate[] = [];
  const inView = (c: PinCandidate) =>
    c.x >= -overscan && c.x <= view.width + overscan && c.y >= -overscan && c.y <= view.height + overscan;
  const collides = (c: PinCandidate) => accepted.some((a) => Math.abs(a.x - c.x) < pinSize && Math.abs(a.y - c.y) < pinSize);

  // The selected place first, so nothing can take its spot; then by priority.
  // The sort is stable: equal priorities keep the order they came in.
  const ordered = candidates
    .filter((c) => Number.isFinite(c.x) && Number.isFinite(c.y) && (keep.has(c.id) || inView(c)))
    .map((c, index) => ({ c, index }))
    .sort((a, b) => Number(keep.has(b.c.id)) - Number(keep.has(a.c.id)) || a.c.priority - b.c.priority || a.index - b.index)
    .map(({ c }) => c);

  for (const candidate of ordered) {
    if (keep.has(candidate.id)) {
      full.push(candidate.id);
      accepted.push(candidate);
    } else if (full.length < maxFullPins && !collides(candidate)) {
      full.push(candidate.id);
      accepted.push(candidate);
    } else if (dots.length < maxDots) {
      dots.push(candidate.id);
    }
  }
  return { full, dots };
}

const MIN_RADIUS_M = 100;
const MAX_RADIUS_M = 100000;

/** The radius the friends' pins are asked for: the server takes 100 m – 100 km. */
export const clampRadius = (meters: number): number =>
  Math.round(Math.min(MAX_RADIUS_M, Math.max(MIN_RADIUS_M, Number.isFinite(meters) ? meters : MAX_RADIUS_M)));
