/**
 * PUT /v1/trips/:tripId (upsert) and DELETE /v1/trips/:tripId, plus the
 * membership / permission helpers the other modules share.
 */
import { json, noContent, readJson, forbidden, notFound, conflict } from './util.js';
import { validateTripInput, requireUuid } from './validate.js';
import { tripJson } from './model.js';

/** The caller's active membership row for a trip, or null. */
export async function getMembership(db, tripId, userId) {
  return db
    .prepare('SELECT role FROM trip_members WHERE trip_id = ? AND user_id = ? AND deleted_at IS NULL')
    .bind(tripId, userId)
    .first();
}

export const canWrite = (membership) => Boolean(membership && (membership.role === 'owner' || membership.role === 'editor'));

/**
 * Loads a trip the caller may write to (owner/editor), for item writes, invites and import.
 * 404 if the trip doesn't exist, 403 if not a member or a viewer, 409 if the trip was deleted.
 */
export async function requireWritableTrip(db, tripId, userId) {
  const trip = await db.prepare('SELECT * FROM trips WHERE id = ?').bind(tripId).first();
  if (!trip) throw notFound('Trip not found.');
  const membership = await getMembership(db, tripId, userId);
  if (!membership) throw forbidden('You are not a member of this trip.');
  if (!canWrite(membership)) throw forbidden('Viewers cannot make changes to this trip.');
  if (trip.deleted_at) throw conflict('This trip has been deleted.');
  return { trip, membership };
}

function isUniqueViolation(err) {
  return /UNIQUE|constraint/i.test(String(err && err.message));
}

/** PUT /v1/trips/:tripId */
export async function putTrip({ request, env, params, user }) {
  const tripId = requireUuid(params.tripId, 'tripId');
  const input = validateTripInput(await readJson(request));
  return upsertTrip(env.DB, tripId, input, user.id);
}

export async function upsertTrip(db, tripId, input, userId, retried = false) {
  const now = Date.now();
  const existing = await db.prepare('SELECT id, deleted_at FROM trips WHERE id = ?').bind(tripId).first();

  if (existing) {
    const membership = await getMembership(db, tripId, userId);
    if (!canWrite(membership)) throw forbidden(membership ? 'Viewers cannot edit this trip.' : 'You are not a member of this trip.');
    if (existing.deleted_at) throw conflict('This trip has been deleted.');
    const row = await db
      .prepare(
        `UPDATE trips SET title = ?, destination = ?, start_date = ?, end_date = ?, time_zone = ?,
                cover_emoji = ?, color_hex = ?, notes = ?, updated_at = ?
          WHERE id = ? RETURNING *`,
      )
      .bind(input.title, input.destination, input.startDate, input.endDate, input.timeZone,
        input.coverEmoji, input.colorHex, input.notes, now, tripId)
      .first();
    return json(tripJson(row));
  }

  // New trip: create it and make the caller its owner, atomically.
  try {
    await db.batch([
      db
        .prepare(
          `INSERT INTO trips (id, owner_id, title, destination, start_date, end_date, time_zone,
                              cover_emoji, color_hex, notes, created_at, updated_at, deleted_at)
           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL)`,
        )
        .bind(tripId, userId, input.title, input.destination, input.startDate, input.endDate, input.timeZone,
          input.coverEmoji, input.colorHex, input.notes, now, now),
      db
        .prepare(
          `INSERT INTO trip_members (trip_id, user_id, role, created_at, updated_at, deleted_at)
           VALUES (?, ?, 'owner', ?, ?, NULL)`,
        )
        .bind(tripId, userId, now, now),
    ]);
  } catch (err) {
    // Two devices created the same trip id at the same moment: treat as an update.
    if (!retried && isUniqueViolation(err)) return upsertTrip(db, tripId, input, userId, true);
    throw err;
  }
  const row = await db.prepare('SELECT * FROM trips WHERE id = ?').bind(tripId).first();
  return json(tripJson(row));
}

/** DELETE /v1/trips/:tripId (owner only; soft-deletes the trip and all its items) */
export async function deleteTrip({ env, params, user }) {
  const tripId = requireUuid(params.tripId, 'tripId');
  const db = env.DB;
  const trip = await db.prepare('SELECT id, deleted_at FROM trips WHERE id = ?').bind(tripId).first();
  if (!trip) throw notFound('Trip not found.');
  const membership = await getMembership(db, tripId, user.id);
  if (!membership) throw forbidden('You are not a member of this trip.');
  if (membership.role !== 'owner') throw forbidden('Only the trip owner can delete it.');
  if (trip.deleted_at) return noContent();
  const now = Date.now();
  await db.batch([
    db.prepare('UPDATE trips SET deleted_at = ?1, updated_at = ?1 WHERE id = ?2').bind(now, tripId),
    db.prepare('UPDATE items SET deleted_at = ?1, updated_at = ?1 WHERE trip_id = ?2 AND deleted_at IS NULL').bind(now, tripId),
    db.prepare('DELETE FROM invites WHERE trip_id = ?').bind(tripId),
  ]);
  return noContent();
}
