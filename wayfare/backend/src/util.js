/**
 * Small shared helpers: JSON responses, the error type, base64url, hashing.
 * Nothing in here touches Cloudflare-specific APIs, so it is unit-testable.
 */

export const API_VERSION = '1';

/** Error codes allowed by the API contract. */
export const ERROR_STATUS = {
  bad_request: 400,
  unauthorized: 401,
  forbidden: 403,
  not_found: 404,
  conflict: 409,
  rate_limited: 429,
  internal: 500,
};

/** Throw one of these anywhere in a handler; the router turns it into the contract error shape. */
export class HttpError extends Error {
  constructor(code, message, status) {
    super(message);
    this.code = code in ERROR_STATUS ? code : 'internal';
    this.status = status || ERROR_STATUS[this.code];
  }
}

export const badRequest = (msg) => new HttpError('bad_request', msg);
export const forbidden = (msg = 'You do not have permission to do that.') => new HttpError('forbidden', msg);
export const notFound = (msg = 'Not found.') => new HttpError('not_found', msg);
export const conflict = (msg) => new HttpError('conflict', msg);

export function json(body, status = 200, extraHeaders = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store', ...extraHeaders },
  });
}

export function noContent() {
  return new Response(null, { status: 204, headers: { 'Cache-Control': 'no-store' } });
}

export function errorResponse(err) {
  if (err instanceof HttpError) {
    return json({ error: { code: err.code, message: err.message } }, err.status);
  }
  // Never leak internals (stack traces, SQL) to the client.
  return json({ error: { code: 'internal', message: 'Something went wrong on our side. Please try again.' } }, 500);
}

const MAX_BODY_BYTES = 256 * 1024;

/** Reads and parses a JSON object body, with a size cap and a clean 400 on bad input. */
export async function readJson(request) {
  const declared = Number(request.headers.get('Content-Length') || 0);
  if (declared > MAX_BODY_BYTES) throw badRequest('Request body is too large.');
  const text = await request.text();
  if (text.length > MAX_BODY_BYTES) throw badRequest('Request body is too large.');
  if (!text.trim()) throw badRequest('Request body must be a JSON object.');
  let parsed;
  try {
    parsed = JSON.parse(text);
  } catch {
    throw badRequest('Request body is not valid JSON.');
  }
  if (parsed === null || typeof parsed !== 'object' || Array.isArray(parsed)) {
    throw badRequest('Request body must be a JSON object.');
  }
  return parsed;
}

// ---------- base64url ----------

export function bytesToBase64Url(bytes) {
  const u8 = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  let bin = '';
  for (let i = 0; i < u8.length; i++) bin += String.fromCharCode(u8[i]);
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

export function base64UrlToBytes(str) {
  if (typeof str !== 'string' || !/^[A-Za-z0-9_-]*$/.test(str)) throw new Error('invalid base64url');
  const b64 = str.replace(/-/g, '+').replace(/_/g, '/') + '==='.slice((str.length + 3) % 4);
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

export function stringToBase64Url(s) {
  return bytesToBase64Url(new TextEncoder().encode(s));
}

export function base64UrlToString(s) {
  return new TextDecoder().decode(base64UrlToBytes(s));
}

// ---------- crypto helpers ----------

export async function sha256Hex(input) {
  const data = typeof input === 'string' ? new TextEncoder().encode(input) : input;
  const digest = await crypto.subtle.digest('SHA-256', data);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

/** 32 random bytes, base64url: the opaque session token handed to the app. */
export function newSessionToken() {
  return bytesToBase64Url(crypto.getRandomValues(new Uint8Array(32)));
}

/** Parses a PEM (e.g. the contents of an Apple .p8 file) into DER bytes. */
export function pemToDer(pem) {
  if (typeof pem !== 'string') throw new Error('PEM must be a string');
  // Tolerate keys pasted with literal "\n" sequences or stray whitespace.
  const body = pem
    .replace(/\\n/g, '\n')
    .replace(/-----BEGIN [^-]+-----/g, '')
    .replace(/-----END [^-]+-----/g, '')
    .replace(/\s+/g, '');
  if (!body) throw new Error('PEM is empty');
  const bin = atob(body);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

/** Epoch ms -> "2026-10-01T14:30:00Z" (no fractional seconds, per the contract). */
export function isoInstant(ms) {
  return new Date(ms).toISOString().replace(/\.\d{3}Z$/, 'Z');
}
