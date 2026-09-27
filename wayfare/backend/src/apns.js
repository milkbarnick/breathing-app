/**
 * Apple Push Notification service (token-based auth) + the shared ES256 JWT signer.
 *
 * APNs auth: an ES256 JWT { alg: ES256, kid: APNS_KEY_ID } . { iss: APNS_TEAM_ID, iat }
 * signed with the .p8 key (PKCS#8 PEM). Apple wants it reused for 20-60 minutes,
 * so we cache it for ~50 minutes per Worker isolate.
 *
 * Transport: Workers' fetch() negotiates HTTP/2 with api.push.apple.com, which is
 * what APNs requires. Sandbox devices (Xcode / TestFlight-from-Xcode builds) go to
 * api.sandbox.push.apple.com, App Store / TestFlight builds to api.push.apple.com.
 */
import { pemToDer, stringToBase64Url, bytesToBase64Url } from './util.js';

const APNS_HOSTS = {
  production: 'https://api.push.apple.com',
  sandbox: 'https://api.sandbox.push.apple.com',
};
const APNS_JWT_TTL_MS = 50 * 60 * 1000;

// ---------- ES256 signer (shared with Sign in with Apple client secrets) ----------

const keyCache = new Map(); // pem -> Promise<CryptoKey>

/** Imports an Apple .p8 (PKCS#8, P-256) private key for ECDSA signing. Cached per isolate. */
export function importP8(pem) {
  let p = keyCache.get(pem);
  if (!p) {
    p = crypto.subtle
      .importKey('pkcs8', pemToDer(pem), { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign'])
      .catch((err) => {
        keyCache.delete(pem);
        throw err;
      });
    keyCache.set(pem, p);
  }
  return p;
}

/**
 * Signs a compact JWS with ES256. WebCrypto's ECDSA output is already the raw
 * 64-byte r||s form JOSE expects, so no DER conversion is needed.
 */
export async function signEs256Jwt(header, claims, pem) {
  const key = await importP8(pem);
  const signingInput = `${stringToBase64Url(JSON.stringify({ ...header, alg: 'ES256' }))}.${stringToBase64Url(JSON.stringify(claims))}`;
  const sig = await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key, new TextEncoder().encode(signingInput));
  return `${signingInput}.${bytesToBase64Url(sig)}`;
}

// ---------- APNs provider token ----------

let cachedApnsJwt = null; // { token, createdAt, cacheKey }

export async function getApnsJwt(env, nowMs = Date.now()) {
  const cacheKey = `${env.APNS_KEY_ID}|${env.APNS_TEAM_ID}`;
  if (cachedApnsJwt && cachedApnsJwt.cacheKey === cacheKey && nowMs - cachedApnsJwt.createdAt < APNS_JWT_TTL_MS) {
    return cachedApnsJwt.token;
  }
  const token = await signEs256Jwt(
    { kid: env.APNS_KEY_ID, typ: 'JWT' },
    { iss: env.APNS_TEAM_ID, iat: Math.floor(nowMs / 1000) },
    env.APNS_PRIVATE_KEY,
  );
  cachedApnsJwt = { token, createdAt: nowMs, cacheKey };
  return token;
}

/** For tests. */
export function _resetApnsCache() {
  cachedApnsJwt = null;
  keyCache.clear();
}

export function apnsConfigured(env) {
  return Boolean(env.APNS_PRIVATE_KEY && env.APNS_KEY_ID && env.APNS_TEAM_ID && (env.APNS_TOPIC || env.APPLE_BUNDLE_ID));
}

/** Builds the JSON payload: aps alert + the contract's custom keys. */
export function buildPayload({ title, body, custom = {} }) {
  return { aps: { alert: { title, body }, sound: 'default' }, ...custom };
}

/** Whether an APNs response means the device token is dead and the row should go. */
export function isDeadTokenResponse(status, reason) {
  return status === 410 || reason === 'BadDeviceToken' || reason === 'Unregistered';
}

/**
 * Sends one alert push. Never throws; returns { ok, status, reason }.
 * `device` = { apns_token, environment }.
 */
export async function sendPush(env, device, payload, { collapseId, fetchImpl = fetch } = {}) {
  try {
    const jwt = await getApnsJwt(env);
    const host = APNS_HOSTS[device.environment] || APNS_HOSTS.production;
    const headers = {
      authorization: `bearer ${jwt}`,
      'apns-topic': env.APNS_TOPIC || env.APPLE_BUNDLE_ID,
      'apns-push-type': 'alert',
      'apns-priority': '10',
      'apns-expiration': String(Math.floor(Date.now() / 1000) + 24 * 3600),
      'content-type': 'application/json',
    };
    if (collapseId) headers['apns-collapse-id'] = collapseId.slice(0, 64);
    const resp = await fetchImpl(`${host}/3/device/${device.apns_token}`, {
      method: 'POST',
      headers,
      body: JSON.stringify(payload),
    });
    if (resp.status === 200) return { ok: true, status: 200, reason: null };
    let reason = null;
    try {
      reason = (await resp.json()).reason || null;
    } catch {
      /* body may be empty */
    }
    if (resp.status === 403 && (reason === 'ExpiredProviderToken' || reason === 'InvalidProviderToken')) {
      cachedApnsJwt = null; // force a fresh JWT next time
    }
    return { ok: false, status: resp.status, reason };
  } catch (err) {
    console.error('APNs send failed', err && err.message);
    return { ok: false, status: 0, reason: 'NetworkError' };
  }
}

/**
 * Sends the same payload to many devices and deletes rows for dead tokens
 * (410 / BadDeviceToken), as the contract requires. Returns the number delivered.
 */
export async function sendToDevices(env, devices, payload, opts = {}) {
  if (!apnsConfigured(env) || devices.length === 0) return 0;
  const results = await Promise.all(devices.map((d) => sendPush(env, d, payload, opts)));
  const dead = [];
  let delivered = 0;
  results.forEach((r, i) => {
    if (r.ok) delivered++;
    else if (isDeadTokenResponse(r.status, r.reason)) dead.push(devices[i].apns_token);
    else console.warn('APNs rejected push', r.status, r.reason);
  });
  if (dead.length) {
    await env.DB.batch(dead.map((t) => env.DB.prepare('DELETE FROM devices WHERE apns_token = ?').bind(t)));
  }
  return delivered;
}
