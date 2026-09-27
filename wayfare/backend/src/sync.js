/**
 * GET /v1/sync?since=<cursor>
 *
 * Visibility rules (U = caller, S = since):
 *  - Trips where U is an active member: returned when the trip changed after S,
 *    OR when U's membership row changed after S (U just joined / re-joined, so
 *    they need the whole trip even if it was last edited long ago).
 *  - Items and member rows of those trips: same rule.
 *  - Trips U was removed from (membership tombstoned after S): returned as a
 *    trip tombstone (deletedAt = removal time), plus U's own member tombstone,
 *    so the client drops the trip.
 *
 * Cursor: the server's clock at the start of the request minus a 5-second
 * safety margin. A write whose timestamp was taken just before our read but
 * committed just after it is therefore still picked up on the next sync. The
 * price is that the last few seconds of rows may be sent twice, which is
 * harmless because clients upsert by id.
 */
import { json } from './util.js';
import { parseSince } from './validate.js';
import { tripJson, itemJson, memberJson } from './model.js';

export const CURSOR_SAFETY_MS = 5000;

export function nextCursor(requestStartMs) {
  return Math.max(0, requestStartMs - CURSOR_SAFETY_MS);
}

export const SYNC_SQL = {
  trips: `
    SELECT t.* FROM trips t
      JOIN trip_members me ON me.trip_id = t.id AND me.user_id = ?1 AND me.deleted_at IS NULL
     WHERE t.updated_at > ?2 OR me.updated_at > ?2`,
  removedTrips: `
    SELECT t.*, me.updated_at AS removed_updated_at, me.deleted_at AS removed_at FROM trip_members me
      JOIN trips t ON t.id = me.trip_id
     WHERE me.user_id = ?1 AND me.deleted_at IS NOT NULL AND me.updated_at > ?2`,
  items: `
    SELECT i.* FROM items i
      JOIN trip_members me ON me.trip_id = i.trip_id AND me.user_id = ?1 AND me.deleted_at IS NULL
     WHERE i.updated_at > ?2 OR me.updated_at > ?2`,
  members: `
    SELECT m.*, u.display_name FROM trip_members me
      JOIN trip_members m ON m.trip_id = me.trip_id
      LEFT JOIN users u ON u.id = m.user_id
     WHERE me.user_id = ?1 AND me.deleted_at IS NULL AND (m.updated_at > ?2 OR me.updated_at > ?2)
    UNION ALL
    SELECT m.*, u.display_name FROM trip_members m
      LEFT JOIN users u ON u.id = m.user_id
     WHERE m.user_id = ?1 AND m.deleted_at IS NOT NULL AND m.updated_at > ?2`,
};

/** A removed member sees the trip only as a tombstone (no notes). */
export function removedTripTombstone(row) {
  const t = tripJson(row);
  const deletedAt = row.deleted_at && row.deleted_at > row.removed_at ? row.deleted_at : row.removed_at;
  return { ...t, notes: '', updatedAt: Math.max(row.removed_updated_at, row.updated_at), deletedAt };
}

export async function getSync({ request, env, user }) {
  const startedAt = Date.now();
  const since = parseSince(new URL(request.url).searchParams.get('since'));
  const db = env.DB;
  const [trips, removed, items, members] = await db.batch([
    db.prepare(SYNC_SQL.trips).bind(user.id, since),
    db.prepare(SYNC_SQL.removedTrips).bind(user.id, since),
    db.prepare(SYNC_SQL.items).bind(user.id, since),
    db.prepare(SYNC_SQL.members).bind(user.id, since),
  ]);
  return json({
    trips: [...trips.results.map(tripJson), ...removed.results.map(removedTripTombstone)],
    items: items.results.map(itemJson),
    members: members.results.map(memberJson),
    cursor: nextCursor(startedAt),
  });
}
