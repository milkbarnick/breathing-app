/**
 * Sharing: create invite codes, accept them, remove members / leave a trip.
 */
import { json, noContent, readJson, badRequest, forbidden, notFound, conflict, isoInstant } from './util.js';
import { INVITE_ROLES, requireUuid, normalizeUuid } from './validate.js';
import { tripJson } from './model.js';
import { requireWritableTrip, getMembership } from './trips.js';

export const INVITE_TTL_MS = 7 * 24 * 60 * 60 * 1000;
// No 0/O, 1/I/L: easy to read aloud and type.
export const INVITE_ALPHABET = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
const CODE_RE = new RegExp(`^[${INVITE_ALPHABET}]{8}$`);

/** 8 characters, uniformly random (rejection sampling avoids modulo bias). */
export function generateInviteCode() {
  const n = INVITE_ALPHABET.length;
  const limit = 256 - (256 % n);
  let out = '';
  while (out.length < 8) {
    for (const b of crypto.getRandomValues(new Uint8Array(16))) {
      if (b < limit && out.length < 8) out += INVITE_ALPHABET[b % n];
    }
  }
  return out;
}

/** Normalizes user-typed codes: case-insensitive, ignores spaces/dashes. Returns null if impossible. */
export function normalizeInviteCode(raw) {
  if (typeof raw !== 'string') return null;
  const c = raw.replace(/[\s-]/g, '').toUpperCase();
  return CODE_RE.test(c) ? c : null;
}

/** POST /v1/trips/:tripId/invites */
export async function createInvite({ request, env, params, user }) {
  const tripId = requireUuid(params.tripId, 'tripId');
  const body = await readJson(request);
  if (!INVITE_ROLES.includes(body.role)) throw badRequest('role must be "editor" or "viewer".');
  const db = env.DB;
  await requireWritableTrip(db, tripId, user.id);
  const now = Date.now();
  const expiresAt = now + INVITE_TTL_MS;
  for (let attempt = 0; attempt < 5; attempt++) {
    const code = generateInviteCode();
    const res = await db
      .prepare(
        `INSERT INTO invites (code, trip_id, role, created_by, created_at, expires_at)
         VALUES (?, ?, ?, ?, ?, ?) ON CONFLICT (code) DO NOTHING`,
      )
      .bind(code, tripId, body.role, user.id, now, expiresAt)
      .run();
    if (res.meta && res.meta.changes === 1) {
      return json({ code, url: `wayfare://invite/${code}`, expiresAt: isoInstant(expiresAt) });
    }
  }
  throw new Error('Could not allocate a unique invite code');
}

/** POST /v1/invites/:code/accept */
export async function acceptInvite({ env, params, user }) {
  const code = normalizeInviteCode(params.code);
  if (!code) throw notFound('This invite code is not valid or has expired.');
  const db = env.DB;
  const now = Date.now();
  const invite = await db
    .prepare(
      `SELECT i.trip_id, i.role FROM invites i JOIN trips t ON t.id = i.trip_id
        WHERE i.code = ? AND i.expires_at > ? AND t.deleted_at IS NULL`,
    )
    .bind(code, now)
    .first();
  if (!invite) throw notFound('This invite code is not valid or has expired.');

  // Idempotent: an existing active member keeps their current role.
  // A previously removed member is re-activated with the invite's role.
  await db
    .prepare(
      `INSERT INTO trip_members (trip_id, user_id, role, created_at, updated_at, deleted_at)
       VALUES (?1, ?2, ?3, ?4, ?4, NULL)
       ON CONFLICT (trip_id, user_id) DO UPDATE SET role = excluded.role, updated_at = excluded.updated_at, deleted_at = NULL
       WHERE trip_members.deleted_at IS NOT NULL`,
    )
    .bind(invite.trip_id, user.id, invite.role, now)
    .run();
  const trip = await db.prepare('SELECT * FROM trips WHERE id = ?').bind(invite.trip_id).first();
  return json(tripJson(trip));
}

/** DELETE /v1/trips/:tripId/members/:userId */
export async function removeMember({ env, params, user }) {
  const tripId = requireUuid(params.tripId, 'tripId');
  const targetId = normalizeUuid(params.userId);
  if (!targetId) throw badRequest('userId must be a UUID.');
  const db = env.DB;
  const trip = await db.prepare('SELECT id FROM trips WHERE id = ?').bind(tripId).first();
  if (!trip) throw notFound('Trip not found.');
  const mine = await getMembership(db, tripId, user.id);
  if (!mine) throw forbidden('You are not a member of this trip.');

  const isSelf = targetId === user.id;
  if (isSelf && mine.role === 'owner') {
    throw forbidden('The owner cannot leave their own trip. Delete the trip instead.');
  }
  if (!isSelf && mine.role !== 'owner') throw forbidden('Only the trip owner can remove other members.');

  const target = isSelf ? mine : await getMembership(db, tripId, targetId);
  if (!target) throw notFound('That person is not a member of this trip.');
  if (target.role === 'owner') throw conflict('The owner cannot be removed.');

  const now = Date.now();
  await db.batch([
    db
      .prepare('UPDATE trip_members SET deleted_at = ?1, updated_at = ?1 WHERE trip_id = ?2 AND user_id = ?3')
      .bind(now, tripId, targetId),
    db.prepare('DELETE FROM push_log WHERE trip_id = ? AND user_id = ?').bind(tripId, targetId),
  ]);
  return noContent();
}
