/**
 * Input validation for every write. Pure functions, no Cloudflare APIs.
 * Each validator either returns a clean, normalized object or throws a 400.
 */
import { badRequest } from './util.js';

export const ITEM_KINDS = ['flight', 'lodging', 'activity', 'food', 'transport', 'note'];
export const MEMBER_ROLES = ['owner', 'editor', 'viewer'];
export const INVITE_ROLES = ['editor', 'viewer'];
export const DEVICE_ENVIRONMENTS = ['sandbox', 'production'];

export const LIMITS = {
  title: 200,
  destination: 200,
  displayName: 100,
  coverEmoji: 16,
  notes: 10000,
  locationName: 300,
  address: 500,
  confirmationCode: 100,
  detailsKeys: 30,
  detailsKey: 50,
  detailsValue: 1000,
  reminderMinutes: 40320, // 4 weeks
  importText: 20000,
};

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;
const ISO_INSTANT_RE = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})Z$/;
const DATE_RE = /^(\d{4})-(\d{2})-(\d{2})$/;
const COLOR_RE = /^#[0-9A-Fa-f]{6}$/;
const APNS_TOKEN_RE = /^[0-9a-f]{64,200}$/;

/**
 * UUIDs: the contract says lowercase. Swift's UUID().uuidString is uppercase,
 * so we accept either case and normalize to lowercase (see Contract issues).
 * Returns null if the value is not a UUID.
 */
export function normalizeUuid(value) {
  if (typeof value !== 'string') return null;
  const v = value.toLowerCase();
  return UUID_RE.test(v) ? v : null;
}

export function requireUuid(value, name) {
  const v = normalizeUuid(value);
  if (!v) throw badRequest(`${name} must be a UUID.`);
  return v;
}

const tzCache = new Map();
export function isValidTimeZone(tz) {
  if (typeof tz !== 'string' || tz.length === 0 || tz.length > 64) return false;
  if (tzCache.has(tz)) return tzCache.get(tz);
  let ok = false;
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: tz });
    // Only IANA-style names ("Europe/Lisbon", "UTC"), not offsets like "+01:00".
    ok = /^[A-Za-z][A-Za-z0-9_+\-/]*$/.test(tz);
  } catch {
    ok = false;
  }
  if (tzCache.size < 1000) tzCache.set(tz, ok);
  return ok;
}

/** "2026-10-01T14:30:00Z" exactly, and a real calendar instant. */
export function isIsoInstant(value) {
  if (typeof value !== 'string') return false;
  const m = ISO_INSTANT_RE.exec(value);
  if (!m) return false;
  const d = new Date(value);
  if (Number.isNaN(d.getTime())) return false;
  return d.toISOString() === `${m[1]}-${m[2]}-${m[3]}T${m[4]}:${m[5]}:${m[6]}.000Z`;
}

/** "YYYY-MM-DD" and a real date (rejects 2026-02-30). */
export function isCalendarDate(value) {
  if (typeof value !== 'string') return false;
  const m = DATE_RE.exec(value);
  if (!m) return false;
  const d = new Date(`${value}T00:00:00Z`);
  return !Number.isNaN(d.getTime()) && d.toISOString().slice(0, 10) === value;
}

// ---------- field helpers ----------

function has(body, key) {
  return Object.prototype.hasOwnProperty.call(body, key) && body[key] !== undefined;
}

function str(body, key, { max, required = false, def = '', allowEmpty = true } = {}) {
  if (!has(body, key) || body[key] === null) {
    if (required) throw badRequest(`${key} is required.`);
    return def;
  }
  const v = body[key];
  if (typeof v !== 'string') throw badRequest(`${key} must be a string.`);
  const trimmedCheck = v.trim();
  if (!allowEmpty && trimmedCheck.length === 0) throw badRequest(`${key} must not be empty.`);
  if (max && v.length > max) throw badRequest(`${key} must be at most ${max} characters.`);
  if (/[\u0000]/.test(v)) throw badRequest(`${key} contains invalid characters.`);
  return v;
}

function bool(body, key, def) {
  if (!has(body, key) || body[key] === null) return def;
  if (typeof body[key] !== 'boolean') throw badRequest(`${key} must be true or false.`);
  return body[key];
}

function int(body, key, { min, max, def = null, nullable = true } = {}) {
  if (!has(body, key) || body[key] === null) {
    if (!nullable && def === null) throw badRequest(`${key} is required.`);
    return def;
  }
  const v = body[key];
  if (typeof v !== 'number' || !Number.isInteger(v)) throw badRequest(`${key} must be a whole number.`);
  if ((min !== undefined && v < min) || (max !== undefined && v > max)) {
    throw badRequest(`${key} must be between ${min} and ${max}.`);
  }
  return v;
}

function num(body, key, { min, max }) {
  if (!has(body, key) || body[key] === null) return null;
  const v = body[key];
  if (typeof v !== 'number' || !Number.isFinite(v)) throw badRequest(`${key} must be a number.`);
  if (v < min || v > max) throw badRequest(`${key} must be between ${min} and ${max}.`);
  return v;
}

function timeZone(body, key, { required }) {
  if (!has(body, key) || body[key] === null) {
    if (required) throw badRequest(`${key} is required.`);
    return null;
  }
  if (!isValidTimeZone(body[key])) throw badRequest(`${key} must be an IANA time zone like "Europe/Lisbon".`);
  return body[key];
}

function instant(body, key, { required }) {
  if (!has(body, key) || body[key] === null) {
    if (required) throw badRequest(`${key} is required.`);
    return null;
  }
  if (!isIsoInstant(body[key])) {
    throw badRequest(`${key} must be an ISO-8601 UTC instant without fractional seconds, like "2026-10-01T14:30:00Z".`);
  }
  return body[key];
}

export function validateDetails(value) {
  if (value === undefined || value === null) return {};
  if (typeof value !== 'object' || Array.isArray(value)) throw badRequest('details must be an object of text values.');
  const keys = Object.keys(value);
  if (keys.length > LIMITS.detailsKeys) throw badRequest(`details can have at most ${LIMITS.detailsKeys} entries.`);
  const out = {};
  for (const k of keys) {
    const v = value[k];
    if (k.length === 0 || k.length > LIMITS.detailsKey) throw badRequest(`details keys must be 1-${LIMITS.detailsKey} characters.`);
    if (typeof v !== 'string') throw badRequest(`details.${k} must be a string.`);
    if (v.length > LIMITS.detailsValue) throw badRequest(`details.${k} must be at most ${LIMITS.detailsValue} characters.`);
    out[k] = v;
  }
  return out;
}

// ---------- object validators ----------

/** Writable Trip fields (PUT is a full replace; unknown / server-owned keys are ignored). */
export function validateTripInput(body) {
  const trip = {
    title: str(body, 'title', { max: LIMITS.title, required: true, allowEmpty: false }),
    destination: str(body, 'destination', { max: LIMITS.destination }),
    startDate: null,
    endDate: null,
    timeZone: timeZone(body, 'timeZone', { required: true }),
    coverEmoji: str(body, 'coverEmoji', { max: LIMITS.coverEmoji }),
    colorHex: str(body, 'colorHex', { max: 7, def: '#0A6B7C' }),
    notes: str(body, 'notes', { max: LIMITS.notes }),
  };
  for (const key of ['startDate', 'endDate']) {
    if (!isCalendarDate(body[key])) throw badRequest(`${key} must be a date like "2026-10-01".`);
    trip[key] = body[key];
  }
  if (trip.endDate < trip.startDate) throw badRequest('endDate must be on or after startDate.');
  if (!COLOR_RE.test(trip.colorHex)) throw badRequest('colorHex must look like "#0A6B7C".');
  return trip;
}

/**
 * Writable Item fields minus id/tripId (those come from the URL).
 * If the body does carry id/tripId they must match the URL.
 */
export function validateItemInput(body, { itemId, tripId } = {}) {
  if (has(body, 'id') && body.id !== null && itemId && normalizeUuid(body.id) !== itemId) {
    throw badRequest('id in the body does not match the URL.');
  }
  if (has(body, 'tripId') && body.tripId !== null && tripId && normalizeUuid(body.tripId) !== tripId) {
    throw badRequest('tripId in the body does not match the URL.');
  }
  if (!ITEM_KINDS.includes(body.kind)) throw badRequest(`kind must be one of: ${ITEM_KINDS.join(', ')}.`);
  const item = {
    kind: body.kind,
    title: str(body, 'title', { max: LIMITS.title, required: true, allowEmpty: false }),
    startAt: instant(body, 'startAt', { required: true }),
    endAt: instant(body, 'endAt', { required: false }),
    startTimeZone: timeZone(body, 'startTimeZone', { required: true }),
    endTimeZone: timeZone(body, 'endTimeZone', { required: false }),
    allDay: bool(body, 'allDay', false),
    locationName: str(body, 'locationName', { max: LIMITS.locationName }),
    address: str(body, 'address', { max: LIMITS.address }),
    latitude: num(body, 'latitude', { min: -90, max: 90 }),
    longitude: num(body, 'longitude', { min: -180, max: 180 }),
    confirmationCode: str(body, 'confirmationCode', { max: LIMITS.confirmationCode }),
    details: validateDetails(body.details),
    notes: str(body, 'notes', { max: LIMITS.notes }),
    reminderMinutes: int(body, 'reminderMinutes', { min: 0, max: LIMITS.reminderMinutes }),
    sortIndex: int(body, 'sortIndex', { min: -1e9, max: 1e9, def: 0 }),
  };
  if (item.endAt && item.endAt < item.startAt) throw badRequest('endAt must not be before startAt.');
  return item;
}

export function validateDeviceInput(body) {
  const rawToken = str(body, 'apnsToken', { required: true, max: 200 }).toLowerCase();
  if (!APNS_TOKEN_RE.test(rawToken)) throw badRequest('apnsToken must be the hex device token from APNs.');
  if (!DEVICE_ENVIRONMENTS.includes(body.environment)) throw badRequest('environment must be "sandbox" or "production".');
  return {
    apnsToken: rawToken,
    environment: body.environment,
    timeZone: timeZone(body, 'timeZone', { required: true }),
    briefingEnabled: bool(body, 'briefingEnabled', true),
    briefingHour: int(body, 'briefingHour', { min: 0, max: 23, def: 7 }),
    collabAlertsEnabled: bool(body, 'collabAlertsEnabled', true),
  };
}

export function validateDisplayName(value, { required }) {
  if (value === undefined || value === null) {
    if (required) throw badRequest('displayName is required.');
    return null;
  }
  if (typeof value !== 'string') throw badRequest('displayName must be a string.');
  const v = value.trim();
  if (required && !v) throw badRequest('displayName must not be empty.');
  if (v.length > LIMITS.displayName) throw badRequest(`displayName must be at most ${LIMITS.displayName} characters.`);
  return v || null;
}

/** ?since= cursor: optional non-negative integer ms. */
export function parseSince(raw) {
  if (raw === null || raw === undefined || raw === '') return 0;
  if (!/^\d{1,16}$/.test(raw)) throw badRequest('since must be a whole number of milliseconds.');
  const n = Number(raw);
  if (!Number.isSafeInteger(n)) throw badRequest('since is out of range.');
  return n;
}
