/**
 * Sign in with Apple + session tokens.
 *
 *  - verifyAppleIdentityToken: RS256 JWT check against Apple's JWKS
 *    (https://appleid.apple.com/auth/keys, cached per isolate), iss/aud/exp.
 *  - Session tokens: 32 random bytes, base64url. Only SHA-256(token) is stored.
 *  - Token exchange / revocation with Apple (client secret = ES256 JWT signed
 *    with the Sign in with Apple .p8, reusing the APNs signer).
 */
import { HttpError, base64UrlToBytes, base64UrlToString, sha256Hex, newSessionToken } from './util.js';
import { signEs256Jwt } from './apns.js';

const APPLE_ISSUER = 'https://appleid.apple.com';
const APPLE_JWKS_URL = 'https://appleid.apple.com/auth/keys';
const APPLE_TOKEN_URL = 'https://appleid.apple.com/auth/token';
const APPLE_REVOKE_URL = 'https://appleid.apple.com/auth/revoke';
const JWKS_TTL_MS = 6 * 60 * 60 * 1000;
const JWKS_MIN_REFRESH_MS = 5 * 60 * 1000;
const CLOCK_SKEW_S = 60;

const unauthorized = (msg = 'Please sign in again.') => new HttpError('unauthorized', msg);

// ---------- Apple JWKS ----------

let jwksCache = null; // { keys: Map(kid -> CryptoKey), fetchedAt }

async function fetchJwks(fetchImpl) {
  const resp = await fetchImpl(APPLE_JWKS_URL, { signal: AbortSignal.timeout(10000) });
  if (!resp.ok) throw new Error(`Apple JWKS fetch failed: ${resp.status}`);
  const { keys } = await resp.json();
  const map = new Map();
  for (const jwk of keys || []) {
    if (jwk.kty !== 'RSA' || !jwk.kid) continue;
    const key = await crypto.subtle.importKey(
      'jwk',
      { kty: 'RSA', n: jwk.n, e: jwk.e, alg: 'RS256', ext: true },
      { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
      false,
      ['verify'],
    );
    map.set(jwk.kid, key);
  }
  return map;
}

async function appleKey(kid, fetchImpl, nowMs) {
  const fresh = jwksCache && nowMs - jwksCache.fetchedAt < JWKS_TTL_MS;
  if (fresh && jwksCache.keys.has(kid)) return jwksCache.keys.get(kid);
  // Unknown kid (Apple rotated keys) or stale cache: refetch, but not more than every 5 minutes.
  if (!jwksCache || !fresh || nowMs - jwksCache.fetchedAt > JWKS_MIN_REFRESH_MS) {
    jwksCache = { keys: await fetchJwks(fetchImpl), fetchedAt: nowMs };
  }
  return jwksCache.keys.get(kid) || null;
}

export function _resetJwksCache() {
  jwksCache = null;
}

/**
 * Verifies a Sign in with Apple identity token. Returns its claims
 * ({ sub, email?, ... }) or throws a 401 HttpError.
 */
export async function verifyAppleIdentityToken(token, { bundleId, nowMs = Date.now(), fetchImpl = fetch } = {}) {
  if (typeof token !== 'string' || token.length > 8192) throw unauthorized('identityToken is missing or malformed.');
  const parts = token.split('.');
  if (parts.length !== 3) throw unauthorized('identityToken is malformed.');
  let header;
  let claims;
  try {
    header = JSON.parse(base64UrlToString(parts[0]));
    claims = JSON.parse(base64UrlToString(parts[1]));
  } catch {
    throw unauthorized('identityToken is malformed.');
  }
  if (header.alg !== 'RS256' || typeof header.kid !== 'string') throw unauthorized('identityToken uses an unexpected algorithm.');

  const key = await appleKey(header.kid, fetchImpl, nowMs);
  if (!key) throw unauthorized('identityToken was not signed by Apple.');
  let valid = false;
  try {
    valid = await crypto.subtle.verify(
      'RSASSA-PKCS1-v1_5',
      key,
      base64UrlToBytes(parts[2]),
      new TextEncoder().encode(`${parts[0]}.${parts[1]}`),
    );
  } catch {
    valid = false;
  }
  if (!valid) throw unauthorized('identityToken signature is invalid.');

  const nowS = Math.floor(nowMs / 1000);
  if (claims.iss !== APPLE_ISSUER) throw unauthorized('identityToken has the wrong issuer.');
  const aud = Array.isArray(claims.aud) ? claims.aud : [claims.aud];
  if (!bundleId || !aud.includes(bundleId)) throw unauthorized('identityToken is for a different app.');
  if (typeof claims.exp !== 'number' || claims.exp + CLOCK_SKEW_S < nowS) throw unauthorized('identityToken has expired.');
  if (typeof claims.iat === 'number' && claims.iat - CLOCK_SKEW_S > nowS) throw unauthorized('identityToken is not valid yet.');
  if (typeof claims.sub !== 'string' || !claims.sub || claims.sub.length > 255) throw unauthorized('identityToken has no subject.');
  return claims;
}

// ---------- Apple client secret, code exchange, revocation ----------

let cachedClientSecret = null; // { token, expS, cacheKey }

export function siwaConfigured(env) {
  return Boolean(env.APPLE_SIWA_PRIVATE_KEY && env.APPLE_SIWA_KEY_ID && env.APPLE_TEAM_ID && env.APPLE_BUNDLE_ID);
}

/** The client_secret Apple wants: ES256 JWT, iss=team, sub=bundle id, aud=appleid.apple.com, exp <= 6 months. */
export async function appleClientSecret(env, nowMs = Date.now()) {
  const nowS = Math.floor(nowMs / 1000);
  const cacheKey = `${env.APPLE_TEAM_ID}|${env.APPLE_SIWA_KEY_ID}|${env.APPLE_BUNDLE_ID}`;
  if (cachedClientSecret && cachedClientSecret.cacheKey === cacheKey && cachedClientSecret.expS - nowS > 300) {
    return cachedClientSecret.token;
  }
  const expS = nowS + 3600; // short-lived on purpose; well under Apple's 6-month maximum
  const token = await signEs256Jwt(
    { kid: env.APPLE_SIWA_KEY_ID },
    { iss: env.APPLE_TEAM_ID, iat: nowS, exp: expS, aud: APPLE_ISSUER, sub: env.APPLE_BUNDLE_ID },
    env.APPLE_SIWA_PRIVATE_KEY,
  );
  cachedClientSecret = { token, expS, cacheKey };
  return token;
}

/**
 * Exchanges the one-time authorizationCode for a refresh token.
 * Best effort: returns the refresh_token or null, never throws.
 */
export async function exchangeAuthorizationCode(env, code, { fetchImpl = fetch } = {}) {
  if (!siwaConfigured(env)) {
    console.warn('Sign in with Apple key not configured; skipping authorization code exchange');
    return null;
  }
  try {
    const body = new URLSearchParams({
      client_id: env.APPLE_BUNDLE_ID,
      client_secret: await appleClientSecret(env),
      code,
      grant_type: 'authorization_code',
    });
    const resp = await fetchImpl(APPLE_TOKEN_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: body.toString(),
      signal: AbortSignal.timeout(10000),
    });
    if (!resp.ok) {
      let detail = '';
      try {
        detail = (await resp.json()).error || '';
      } catch {
        /* ignore */
      }
      console.warn('Apple code exchange failed', resp.status, detail);
      return null;
    }
    const data = await resp.json();
    return typeof data.refresh_token === 'string' ? data.refresh_token : null;
  } catch (err) {
    console.warn('Apple code exchange error', err && err.message);
    return null;
  }
}

/** Revokes a refresh token with Apple. Best effort: returns true/false, never throws. */
export async function revokeAppleToken(env, refreshToken, { fetchImpl = fetch } = {}) {
  if (!refreshToken) return false;
  if (!siwaConfigured(env)) {
    console.warn('Sign in with Apple key not configured; cannot revoke Apple token');
    return false;
  }
  try {
    const body = new URLSearchParams({
      client_id: env.APPLE_BUNDLE_ID,
      client_secret: await appleClientSecret(env),
      token: refreshToken,
      token_type_hint: 'refresh_token',
    });
    const resp = await fetchImpl(APPLE_REVOKE_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: body.toString(),
      signal: AbortSignal.timeout(10000),
    });
    if (!resp.ok) console.warn('Apple token revocation failed', resp.status);
    return resp.ok;
  } catch (err) {
    console.warn('Apple token revocation error', err && err.message);
    return false;
  }
}

export function _resetClientSecretCache() {
  cachedClientSecret = null;
}

// ---------- sessions ----------

export async function createSession(db, userId, nowMs = Date.now()) {
  const token = newSessionToken();
  await db
    .prepare('INSERT INTO sessions (token_hash, user_id, created_at, last_used_at) VALUES (?, ?, ?, ?)')
    .bind(await sha256Hex(token), userId, nowMs, nowMs)
    .run();
  return token;
}

/** Extracts the bearer token from the Authorization header, or null. */
export function bearerToken(request) {
  const h = request.headers.get('Authorization') || '';
  const m = /^Bearer\s+([A-Za-z0-9_-]{20,200})\s*$/.exec(h);
  return m ? m[1] : null;
}

/**
 * Resolves the session for a request. Returns { user, tokenHash } or throws 401.
 * Refreshes last_used_at at most once a day, in the background.
 */
export async function authenticate(request, env, ctx) {
  const token = bearerToken(request);
  if (!token) throw unauthorized('Missing or malformed Authorization header.');
  const tokenHash = await sha256Hex(token);
  const row = await env.DB.prepare(
    `SELECT s.last_used_at, u.id, u.display_name, u.email, u.created_at
       FROM sessions s JOIN users u ON u.id = s.user_id
      WHERE s.token_hash = ?`,
  )
    .bind(tokenHash)
    .first();
  if (!row) throw unauthorized();
  const now = Date.now();
  if (now - row.last_used_at > 24 * 3600 * 1000 && ctx && ctx.waitUntil) {
    ctx.waitUntil(
      env.DB.prepare('UPDATE sessions SET last_used_at = ? WHERE token_hash = ?').bind(now, tokenHash).run().catch(() => {}),
    );
  }
  return { user: row, tokenHash };
}
