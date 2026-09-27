/**
 * /v1/auth/apple, /v1/auth/logout, /v1/me (GET, PATCH, DELETE).
 */
import { json, noContent, readJson, badRequest } from './util.js';
import { validateDisplayName } from './validate.js';
import { userJson } from './model.js';
import { verifyAppleIdentityToken, createSession, exchangeAuthorizationCode, revokeAppleToken } from './auth.js';

const USER_COLS = 'id, display_name, email, created_at';

/** POST /v1/auth/apple */
export async function signInWithApple({ request, env, ctx }) {
  const body = await readJson(request);
  if (typeof body.identityToken !== 'string' || !body.identityToken) throw badRequest('identityToken is required.');
  const displayName = validateDisplayName(body.displayName, { required: false });
  let authorizationCode = null;
  if (body.authorizationCode !== undefined && body.authorizationCode !== null) {
    if (typeof body.authorizationCode !== 'string' || body.authorizationCode.length > 2048) {
      throw badRequest('authorizationCode must be a string.');
    }
    authorizationCode = body.authorizationCode || null;
  }

  const claims = await verifyAppleIdentityToken(body.identityToken, { bundleId: env.APPLE_BUNDLE_ID });
  const email = typeof claims.email === 'string' && claims.email.length <= 320 ? claims.email : null;
  const now = Date.now();

  // Upsert by Apple `sub`. displayName / email only overwrite when provided.
  const user = await env.DB.prepare(
    `INSERT INTO users (id, apple_sub, display_name, email, created_at, updated_at)
     VALUES (?1, ?2, COALESCE(?3, ''), ?4, ?5, ?5)
     ON CONFLICT (apple_sub) DO UPDATE SET
       display_name = COALESCE(?3, users.display_name),
       email        = COALESCE(?4, users.email),
       updated_at   = ?5
     RETURNING ${USER_COLS}`,
  )
    .bind(crypto.randomUUID(), claims.sub, displayName, email, now)
    .first();

  const token = await createSession(env.DB, user.id, now);

  // Exchange the one-time code for a refresh token (needed to revoke on account
  // deletion). Done after responding so sign-in stays fast; failures are only logged.
  if (authorizationCode) {
    ctx.waitUntil(
      (async () => {
        const refreshToken = await exchangeAuthorizationCode(env, authorizationCode);
        if (refreshToken) {
          await env.DB.prepare('UPDATE users SET apple_refresh_token = ? WHERE id = ?').bind(refreshToken, user.id).run();
        }
      })().catch((err) => console.warn('Storing Apple refresh token failed', err && err.message)),
    );
  }

  return json({ token, user: userJson(user) });
}

/**
 * POST /v1/auth/logout. Optional body { apnsToken } also unregisters this
 * phone, so a signed-out device stops receiving the user's pushes.
 */
export async function logout({ request, env, user, tokenHash }) {
  let apnsToken = null;
  try {
    const body = JSON.parse((await request.text()) || '{}');
    if (body && typeof body.apnsToken === 'string' && body.apnsToken.length <= 200) apnsToken = body.apnsToken;
  } catch {
    // An empty or malformed body still logs out.
  }
  const stmts = [env.DB.prepare('DELETE FROM sessions WHERE token_hash = ?').bind(tokenHash)];
  if (apnsToken) {
    stmts.push(env.DB.prepare('DELETE FROM devices WHERE apns_token = ?1 AND user_id = ?2').bind(apnsToken, user.id));
  }
  await env.DB.batch(stmts);
  return noContent();
}

/** GET /v1/me */
export async function getMe({ user }) {
  return json(userJson(user));
}

/** PATCH /v1/me */
export async function patchMe({ request, env, user }) {
  const body = await readJson(request);
  const displayName = validateDisplayName(body.displayName, { required: true });
  const row = await env.DB.prepare(`UPDATE users SET display_name = ?, updated_at = ? WHERE id = ? RETURNING ${USER_COLS}`)
    .bind(displayName, Date.now(), user.id)
    .first();
  // Members' displayName comes from the users table, so bump this user's
  // membership rows so other devices pick up the new name on their next sync.
  await env.DB.prepare('UPDATE trip_members SET updated_at = ? WHERE user_id = ? AND deleted_at IS NULL')
    .bind(Date.now(), user.id)
    .run();
  return json(userJson(row));
}

/**
 * Statements that erase an account. Run as one D1 batch (a single transaction).
 *
 *  - Owned trips nobody else is on: hard-deleted (items, members, invites cascade).
 *  - Owned trips shared with others: items and invites hard-deleted, the trip row
 *    scrubbed to a content-free tombstone (deletedAt set) so collaborators'
 *    devices drop it on their next sync.
 *  - Other people's trips: this user's membership becomes a tombstone (no PII,
 *    just ids) so the member list updates on everyone else's devices.
 *  - Sessions, devices, rate-limit and push bookkeeping, and the user row: deleted.
 */
export function accountDeletionStatements(db, userId, now) {
  const owned = 'SELECT id FROM trips WHERE owner_id = ?1';
  const sql = [
    `DELETE FROM trips WHERE owner_id = ?1 AND NOT EXISTS (
         SELECT 1 FROM trip_members m WHERE m.trip_id = trips.id AND m.user_id <> ?1 AND m.deleted_at IS NULL)`,
    `DELETE FROM items WHERE trip_id IN (${owned})`,
    `DELETE FROM invites WHERE trip_id IN (${owned}) OR created_by = ?1`,
    `DELETE FROM push_log WHERE user_id = ?1 OR trip_id IN (${owned})`,
    `DELETE FROM trip_members WHERE user_id = ?1 AND trip_id IN (${owned})`,
    `UPDATE trips SET title = '', destination = '', start_date = '1970-01-01', end_date = '1970-01-01',
              time_zone = 'UTC', cover_emoji = '', color_hex = '#2F6FEB', notes = '',
              updated_at = ?2, deleted_at = COALESCE(deleted_at, ?2)
        WHERE owner_id = ?1`,
    'UPDATE trip_members SET deleted_at = ?2, updated_at = ?2 WHERE user_id = ?1 AND deleted_at IS NULL',
    'DELETE FROM import_usage WHERE user_id = ?1',
    'DELETE FROM devices WHERE user_id = ?1',
    'DELETE FROM sessions WHERE user_id = ?1',
    'DELETE FROM users WHERE id = ?1',
  ];
  return sql.map((q) => (q.includes('?2') ? db.prepare(q).bind(userId, now) : db.prepare(q).bind(userId)));
}

/** DELETE /v1/me */
export async function deleteMe({ env, user }) {
  // Revoke with Apple first (best effort), while we still have the token.
  const row = await env.DB.prepare('SELECT apple_refresh_token FROM users WHERE id = ?').bind(user.id).first();
  if (row && row.apple_refresh_token) {
    await revokeAppleToken(env, row.apple_refresh_token);
  }
  await env.DB.batch(accountDeletionStatements(env.DB, user.id, Date.now()));
  return noContent();
}
