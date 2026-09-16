// backend/utils/ratingHistory.js
//
// A saver's rating of a place is "latest wins, history kept": `userRating`
// on the save doc is the current score, `ratingHistory[]` is every score they
// ever gave, oldest first, each stamped with when and (optionally) which
// check-in prompted it. The place page reads it as "7 → 9 over 3 visits".
// Never pruned — it is user data.
const MAX_ENTRY_NOTE = 0; // history entries carry no free text; reviews are comments

const sanitizeRating = (value) => {
  if (value === null || value === undefined || value === '') return null;
  const num = Number(value);
  if (Number.isNaN(num)) return null;
  return Math.min(10, Math.max(0, Math.round(num)));
};

// Returns the new history array, or null when nothing should be appended:
// a null/invalid rating never appends, and re-sending the same score with
// no check-in attached is a no-op (a re-rate after a check-in is a real
// data point even when the score didn't move).
//
// `seedFrom` = { rating, at }: the save's pre-history rating. Saves rated
// before history existed carry only `userRating`; without seeding, the first
// change would forget where they started and never read "9/10 · was 7".
const appendRating = (existing, { rating, at, checkInId = null }, seedFrom = null) => {
  const score = sanitizeRating(rating);
  if (score === null) return null;
  let history = Array.isArray(existing) ? existing.slice() : [];
  const seedScore = seedFrom ? sanitizeRating(seedFrom.rating) : null;
  if (history.length === 0 && seedScore !== null) {
    history = [{ rating: seedScore, at: seedFrom.at || null }];
  }
  const last = history[history.length - 1];
  if (last && last.rating === score && !checkInId) return null;
  const entry = { rating: score, at: at || new Date().toISOString() };
  if (checkInId) entry.checkInId = String(checkInId);
  history.push(entry);
  return history;
};

module.exports = { appendRating, sanitizeRating };
