// backend/utils/hoursText.js — a store's opening hours as the words a page
// prints. Rows come from globalPlaces.googleData.openingHours in either
// shape the app writes: { day, open:'HH:MM', close:'HH:MM', isClosed } for
// one stretch, or { day, hours:'11 AM–2 PM, 5–9 PM' } for a split day.
const DAY_LABELS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

/** '09:30' or '0930' → '9:30 AM'; on the hour drops the minutes. */
function clock12(hhmm) {
  const digits = String(hhmm || '').replace(/\D/g, '').padStart(4, '0').slice(0, 4);
  const h = parseInt(digits.slice(0, 2), 10);
  const m = digits.slice(2, 4);
  if (!Number.isFinite(h)) return '';
  return `${h % 12 === 0 ? 12 : h % 12}${m !== '00' ? `:${m}` : ''} ${h < 12 ? 'AM' : 'PM'}`;
}

/** [{ day, label, text }] for all seven days, Sunday first; null when there are no hours. */
function formatHours(openingHours) {
  if (!Array.isArray(openingHours) || !openingHours.length) return null;
  const byDay = new Map();
  openingHours.forEach((row) => {
    if (!row || typeof row.day !== 'number' || row.day < 0 || row.day > 6) return;
    let text;
    if (row.isClosed) text = 'Closed';
    else if (row.hours) text = String(row.hours);
    else if (row.open && row.close) text = `${clock12(row.open)}–${clock12(row.close)}`;
    else if (row.open) text = `${clock12(row.open)}–late`;
    else return;
    byDay.set(row.day, text);
  });
  if (!byDay.size) return null;
  return DAY_LABELS.map((label, day) => ({ day, label, text: byDay.get(day) || 'Closed' }));
}

module.exports = { formatHours, clock12, DAY_LABELS };
