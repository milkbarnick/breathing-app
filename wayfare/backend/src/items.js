/**
 * PUT / DELETE /v1/trips/:tripId/items/:itemId, and the collaborator push.
 */
import { json, noContent, readJson, notFound, conflict, forbidden } from './util.js';
import { validateItemInput, requireUuid } from './validate.js';
import { itemJson } from './model.js';
import { requireWritableTrip, getMembership, canWrite } from './trips.js';
import { apnsConfigured, buildPayload, sendToDevices } from './apns.js';

export const PUSH_COALESCE_MS = 2 * 60 * 1000;

/** PUT /v1/trips/:tripId/items/:itemId */
export async function putItem({ request, env, ctx, params, user }) {
  const tripId = requireUuid(params.tripId, 'tripId');
  const itemId = requireUuid(params.itemId, 'itemId');
  const input = validateItemInput(await readJson(request), { itemId, tripId });
  const db = env.DB;
  const { trip } = await requireWritableTrip(db, tripId, user.id);

  const before = await db.prepare('SELECT trip_id, deleted_at FROM items WHERE id = ?').bind(itemId).first();
  if (before && before.trip_id !== tripId) throw conflict('An item with this id already belongs to another trip.');
  const isNew = !before || before.deleted_at !== null;
  const now = Date.now();

  // Last write wins: a PUT always overwrites (and revives a tombstoned item).
  const row = await db
    .prepare(
      `INSERT INTO items (id, trip_id, kind, title, start_at, end_at, start_time_zone, end_time_zone, all_day,
                          location_name, address, latitude, longitude, confirmation_code, details, notes,
                          reminder_minutes, sort_index, created_at, updated_at, updated_by, deleted_at)
       VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19, ?19, ?20, NULL)
       ON CONFLICT (id) DO UPDATE SET
         kind = excluded.kind, title = excluded.title, start_at = excluded.start_at, end_at = excluded.end_at,
         start_time_zone = excluded.start_time_zone, end_time_zone = excluded.end_time_zone,
         all_day = excluded.all_day, location_name = excluded.location_name, address = excluded.address,
         latitude = excluded.latitude, longitude = excluded.longitude,
         confirmation_code = excluded.confirmation_code, details = excluded.details, notes = excluded.notes,
         reminder_minutes = excluded.reminder_minutes, sort_index = excluded.sort_index,
         updated_at = excluded.updated_at, updated_by = excluded.updated_by, deleted_at = NULL
       WHERE items.trip_id = excluded.trip_id
       RETURNING *`,
    )
    .bind(
      itemId, tripId, input.kind, input.title, input.startAt, input.endAt, input.startTimeZone, input.endTimeZone,
      input.allDay ? 1 : 0, input.locationName, input.address, input.latitude, input.longitude,
      input.confirmationCode, JSON.stringify(input.details), input.notes, input.reminderMinutes, input.sortIndex,
      now, user.id,
    )
    .first();
  if (!row) throw conflict('An item with this id already belongs to another trip.');

  // Push to collaborators without delaying the response.
  if (ctx && ctx.waitUntil && apnsConfigured(env)) {
    ctx.waitUntil(
      notifyCollaborators(env, { trip, item: row, actor: user, isNew, now }).catch((err) =>
        console.error('Collaborator push failed', err && err.message),
      ),
    );
  }
  return json(itemJson(row));
}

/** DELETE /v1/trips/:tripId/items/:itemId */
export async function deleteItem({ env, params, user }) {
  const tripId = requireUuid(params.tripId, 'tripId');
  const itemId = requireUuid(params.itemId, 'itemId');
  const db = env.DB;
  const trip = await db.prepare('SELECT id FROM trips WHERE id = ?').bind(tripId).first();
  if (!trip) throw notFound('Trip not found.');
  const membership = await getMembership(db, tripId, user.id);
  if (!membership) throw forbidden('You are not a member of this trip.');
  if (!canWrite(membership)) throw forbidden('Viewers cannot make changes to this trip.');
  const item = await db.prepare('SELECT deleted_at FROM items WHERE id = ? AND trip_id = ?').bind(itemId, tripId).first();
  if (!item) throw notFound('Item not found.');
  if (item.deleted_at) return noContent();
  const now = Date.now();
  await db
    .prepare('UPDATE items SET deleted_at = ?1, updated_at = ?1, updated_by = ?2 WHERE id = ?3')
    .bind(now, user.id, itemId)
    .run();
  return noContent();
}

/** "Sam added “Dinner at Taberna” to Lisbon & Porto" */
export function collaboratorMessage({ actorName, itemTitle, tripTitle, isNew }) {
  const who = (actorName || '').trim() || 'Someone';
  const what = truncate(itemTitle, 80);
  return isNew ? `${who} added “${what}” to ${tripTitle}` : `${who} updated “${what}” in ${tripTitle}`;
}

function truncate(s, n) {
  s = String(s || '');
  return s.length > n ? `${s.slice(0, n - 1)}…` : s;
}

/**
 * Sends the "itemChanged" push to every other active member who has a device with
 * collab alerts on. Coalesced: at most one push per trip per recipient per 2 minutes.
 * The coalescing slot is claimed atomically in push_log (an upsert that only
 * succeeds when the previous push is older than the window).
 */
export async function notifyCollaborators(env, { trip, item, actor, isNew, now = Date.now() }) {
  const db = env.DB;
  const { results: recipients } = await db
    .prepare(
      `SELECT DISTINCT m.user_id FROM trip_members m
         JOIN devices d ON d.user_id = m.user_id AND d.collab_alerts_enabled = 1
        WHERE m.trip_id = ? AND m.deleted_at IS NULL AND m.user_id <> ?`,
    )
    .bind(trip.id, actor.id)
    .all();
  if (!recipients.length) return 0;

  const claims = await db.batch(
    recipients.map((r) =>
      db
        .prepare(
          `INSERT INTO push_log (trip_id, user_id, last_sent_at) VALUES (?1, ?2, ?3)
           ON CONFLICT (trip_id, user_id) DO UPDATE SET last_sent_at = excluded.last_sent_at
           WHERE push_log.last_sent_at <= ?4
           RETURNING user_id`,
        )
        .bind(trip.id, r.user_id, now, now - PUSH_COALESCE_MS),
    ),
  );
  const claimed = claims.filter((res) => res.results && res.results.length).map((res) => res.results[0].user_id);
  if (!claimed.length) return 0;

  const devices = [];
  for (const userId of claimed) {
    const { results } = await db
      .prepare('SELECT apns_token, environment FROM devices WHERE user_id = ? AND collab_alerts_enabled = 1')
      .bind(userId)
      .all();
    devices.push(...results);
  }
  const payload = buildPayload({
    title: trip.title,
    body: collaboratorMessage({ actorName: actor.display_name, itemTitle: item.title, tripTitle: trip.title, isNew }),
    custom: { type: 'itemChanged', tripId: trip.id, itemId: item.id },
  });
  return sendToDevices(env, devices, payload, { collapseId: `trip-${trip.id}` });
}
