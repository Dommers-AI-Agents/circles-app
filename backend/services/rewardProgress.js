// What a scan is worth at THIS store, in the store's own terms (Wes,
// 2026-10-29): the cheapest reward on the menu, and how far a balance is
// from it. Pure; the app's Logic/RewardsAvailability has the same rule for
// the screens it draws itself, so the two never disagree.

/** Live offers, cheapest first; never the ones switched off or free. */
const rewardLadder = (offers) => (offers || [])
  .filter((o) => o && o.active !== false && Number.isInteger(o.pointsCost) && o.pointsCost > 0 && o.title)
  .map((o) => ({ offerId: o.offerId, title: String(o.title).trim(), pointsCost: o.pointsCost }))
  .sort((a, b) => a.pointsCost - b.pointsCost);

/** The first thing points buy here, or null when the store has no offers. */
const firstReward = (offers) => rewardLadder(offers)[0] || null;

/**
 * The reward a balance is working toward: the cheapest one still out of
 * reach; or, once something is affordable, the best one they can take now.
 * `visitsLeft` counts register scans at the earn rate (null when unknown).
 */
const nextReward = (offers, venueBalance, earnRate) => {
  const ladder = rewardLadder(offers);
  if (!ladder.length) return null;
  const balance = Math.max(0, Number(venueBalance) || 0);
  const affordable = ladder.filter((o) => o.pointsCost <= balance);
  if (affordable.length) {
    const best = affordable[affordable.length - 1];
    return { ...best, remaining: 0, visitsLeft: 0, canRedeem: true };
  }
  const next = ladder[0];
  const remaining = next.pointsCost - balance;
  const rate = Number(earnRate);
  const visitsLeft = Number.isFinite(rate) && rate > 0 ? Math.ceil(remaining / rate) : null;
  return { ...next, remaining, visitsLeft, canRedeem: false };
};

/** "Free coffee" → "a free coffee"; titles already starting with a/an/the/your keep theirs. */
const article = (title) => {
  const t = String(title || '').trim();
  if (!t) return t;
  const lower = t.toLowerCase();
  if (['a ', 'an ', 'the ', 'your ', 'free!'].some((p) => lower.startsWith(p))) return t;
  const vowel = 'aeiou'.includes(lower[0]);
  return `${vowel ? 'an' : 'a'} ${t[0].toLowerCase()}${t.slice(1)}`;
};

/** "75 more points for a free coffee · about 3 more visits" / "You've got enough for a free coffee". */
const nextRewardLine = (reward) => {
  if (!reward) return null;
  if (reward.canRedeem) return `You've got enough for ${article(reward.title)}. Scan at the register to use it.`;
  let line = `${reward.remaining} more ${reward.remaining === 1 ? 'point' : 'points'} for ${article(reward.title)}`;
  if (reward.visitsLeft > 0) line += ` · about ${reward.visitsLeft} more ${reward.visitsLeft === 1 ? 'visit' : 'visits'}`;
  return line;
};

/** "100 points = Free coffee": the card's one-line promise. */
const firstRewardLine = (reward) => (reward ? `${reward.pointsCost} points = ${reward.title}` : null);

module.exports = { rewardLadder, firstReward, nextReward, nextRewardLine, firstRewardLine, article };
