/**
 * Hourly cron: the daily "Today in Lisbon" briefing, plus light housekeeping.
 *
 * For each device with briefingEnabled whose local hour (device time zone) equals
 * briefingHour, and for each trip of that user where today (in the TRIP's time
 * zone) is between startDate and endDate, send:
 *   title "Today in <destination or title>"
 *   body  "3 plans · first: Breakfast at 8:30"
 *   custom { type: "briefing", tripId, date }
 *
 * The selection / wording logic is pure (exported for tests); runBriefings does the I/O.
 */
import { localParts, localDate, formatClock } from './time.js';
import { apnsConfigured, buildPayload, sendToDevices } from './apns.js';

const D1_MAX_PARAMS = 90; // D1 allows 100 bound parameters per statement

export function chunk(arr, size) {
  const out = [];
  for (let i = 0; i < arr.length; i += size) out.push(arr.slice(i, i + size));
  return out;
}

/** Devices whose local hour is their briefing hour and that haven't had today's briefing yet. */
export function dueDevices(devices, now) {
  const due = [];
  for (const d of devices) {
    let parts;
    try {
      parts = localParts(now, d.time_zone);
    } catch {
      continue; // bad time zone stored somehow; skip rather than break the whole run
    }
    if (parts.hour === d.briefing_hour && d.last_briefing_date !== parts.date) {
      due.push({ ...d, localDate: parts.date });
    }
  }
  return due;
}

/** "Today" in the trip's own time zone if the trip is in progress, else null. */
export function tripToday(trip, now) {
  let today;
  try {
    today = localDate(now, trip.time_zone);
  } catch {
    return null;
  }
  return today >= trip.start_date && today <= trip.end_date ? today : null;
}

/** Items whose start falls on `date` in the item's own start time zone, in time order. */
export function itemsOnDate(items, date) {
  return items
    .filter((i) => {
      try {
        return localDate(i.start_at, i.start_time_zone) === date;
      } catch {
        return false;
      }
    })
    .sort((a, b) => (a.start_at < b.start_at ? -1 : a.start_at > b.start_at ? 1 : a.sort_index - b.sort_index));
}

function clip(s, n) {
  s = String(s || '').trim();
  return s.length > n ? `${s.slice(0, n - 1)}…` : s;
}

/** Title and body for one trip's briefing. */
export function composeBriefing(trip, todaysItems) {
  const place = clip(trip.destination || trip.title, 60);
  const title = `Today in ${place}`;
  const n = todaysItems.length;
  if (n === 0) return { title, body: 'No plans yet today. Tap to add some.' };
  // "first" = the first plan with a time; all-day entries only if nothing is timed.
  const first = todaysItems.find((i) => !i.all_day) || todaysItems[0];
  const when = first.all_day ? '' : ` at ${formatClock(first.start_at, first.start_time_zone)}`;
  return { title, body: `${n} ${n === 1 ? 'plan' : 'plans'} · first: ${clip(first.title, 80)}${when}` };
}

/**
 * Pure planner: given due devices, the users' trips (with a user_id column), and
 * the candidate items, returns [{ device, trip, date, title, body }].
 */
export function planBriefings({ devices, trips, items, now }) {
  const tripsByUser = new Map();
  for (const t of trips) {
    const today = tripToday(t, now);
    if (!today) continue;
    if (!tripsByUser.has(t.user_id)) tripsByUser.set(t.user_id, []);
    tripsByUser.get(t.user_id).push({ trip: t, today });
  }
  const itemsByTrip = new Map();
  for (const i of items) {
    if (!itemsByTrip.has(i.trip_id)) itemsByTrip.set(i.trip_id, []);
    itemsByTrip.get(i.trip_id).push(i);
  }
  const out = [];
  for (const device of devices) {
    for (const { trip, today } of tripsByUser.get(device.user_id) || []) {
      const { title, body } = composeBriefing(trip, itemsOnDate(itemsByTrip.get(trip.id) || [], today));
      out.push({ device, trip, date: today, title, body });
    }
  }
  return out;
}

async function allChunked(db, sqlForPlaceholders, ids, extraBinds = []) {
  const rows = [];
  for (const part of chunk(ids, D1_MAX_PARAMS - extraBinds.length)) {
    const placeholders = part.map(() => '?').join(', ');
    const { results } = await db.prepare(sqlForPlaceholders(placeholders)).bind(...part, ...extraBinds).all();
    rows.push(...results);
  }
  return rows;
}

export async function runBriefings(env, nowMs = Date.now()) {
  const db = env.DB;
  const now = new Date(nowMs);
  const { results: all } = await db
    .prepare(
      `SELECT apns_token, environment, user_id, time_zone, briefing_hour, last_briefing_date
         FROM devices WHERE briefing_enabled = 1`,
    )
    .all();
  const due = dueDevices(all, now);
  if (!due.length) return 0;

  const userIds = [...new Set(due.map((d) => d.user_id))];
  // Pre-filter on dates with a +/-1 day margin; the exact check happens in tripToday().
  const lo = new Date(nowMs - 86400000).toISOString().slice(0, 10);
  const hi = new Date(nowMs + 86400000).toISOString().slice(0, 10);
  const trips = await allChunked(
    db,
    (ph) => `SELECT t.*, m.user_id FROM trips t
               JOIN trip_members m ON m.trip_id = t.id AND m.deleted_at IS NULL
              WHERE m.user_id IN (${ph}) AND t.deleted_at IS NULL AND t.start_date <= ? AND t.end_date >= ?`,
    userIds,
    [hi, lo],
  );
  const tripIds = [...new Set(trips.map((t) => t.id))];
  // Items starting within +/-36h of now can be "today" in any time zone.
  const from = new Date(nowMs - 36 * 3600000).toISOString().replace(/\.\d{3}Z$/, 'Z');
  const to = new Date(nowMs + 36 * 3600000).toISOString().replace(/\.\d{3}Z$/, 'Z');
  const items = tripIds.length
    ? await allChunked(
        db,
        (ph) => `SELECT id, trip_id, title, start_at, start_time_zone, all_day, sort_index FROM items
                  WHERE trip_id IN (${ph}) AND deleted_at IS NULL AND start_at >= ? AND start_at <= ?`,
        tripIds,
        [from, to],
      )
    : [];

  const plan = planBriefings({ devices: due, trips, items, now });

  // Mark every due device first so an overlapping/retried cron run can't double-send.
  await db.batch(
    due.map((d) => db.prepare('UPDATE devices SET last_briefing_date = ? WHERE apns_token = ?').bind(d.localDate, d.apns_token)),
  );
  if (!apnsConfigured(env)) return 0;

  let sent = 0;
  for (const p of plan) {
    sent += await sendToDevices(
      env,
      [p.device],
      buildPayload({ title: p.title, body: p.body, custom: { type: 'briefing', tripId: p.trip.id, date: p.date } }),
      { collapseId: `briefing-${p.trip.id}` },
    );
  }
  return sent;
}

/** Housekeeping run alongside the briefing: expired invites and stale bookkeeping rows. */
export async function housekeeping(env, nowMs = Date.now()) {
  const db = env.DB;
  const twoDaysAgo = new Date(nowMs - 2 * 86400000).toISOString().slice(0, 10);
  await db.batch([
    db.prepare('DELETE FROM invites WHERE expires_at < ?').bind(nowMs),
    db.prepare('DELETE FROM push_log WHERE last_sent_at < ?').bind(nowMs - 86400000),
    db.prepare('DELETE FROM import_usage WHERE day < ?').bind(twoDaysAgo),
  ]);
}
