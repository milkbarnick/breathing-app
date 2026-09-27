/**
 * Time-zone helpers built only on Intl.DateTimeFormat (works in Workers and Node).
 */

const fmtCache = new Map();

function formatter(timeZone) {
  let f = fmtCache.get(timeZone);
  if (!f) {
    f = new Intl.DateTimeFormat('en-US', {
      timeZone,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      hourCycle: 'h23',
    });
    if (fmtCache.size < 500) fmtCache.set(timeZone, f);
  }
  return f;
}

/** Wall-clock parts of an instant in a time zone: { date: "YYYY-MM-DD", hour: 0-23, minute: 0-59 }. */
export function localParts(instant, timeZone) {
  const d = instant instanceof Date ? instant : new Date(instant);
  const parts = {};
  for (const p of formatter(timeZone).formatToParts(d)) parts[p.type] = p.value;
  // Some engines print midnight as "24" even with h23; normalize.
  const hour = Number(parts.hour) % 24;
  return {
    date: `${parts.year}-${parts.month}-${parts.day}`,
    hour,
    minute: Number(parts.minute),
  };
}

export function localDate(instant, timeZone) {
  return localParts(instant, timeZone).date;
}

export function localHour(instant, timeZone) {
  return localParts(instant, timeZone).hour;
}

/** "8:30", "20:05" (24-hour clock, no leading zero on the hour). */
export function formatClock(instant, timeZone) {
  const { hour, minute } = localParts(instant, timeZone);
  return `${hour}:${String(minute).padStart(2, '0')}`;
}

/** UTC calendar day "YYYY-MM-DD" (used for the import rate-limit bucket). */
export function utcDay(ms) {
  return new Date(ms).toISOString().slice(0, 10);
}
