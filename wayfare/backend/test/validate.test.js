import { describe, it, expect } from 'vitest';
import {
  normalizeUuid, isIsoInstant, isCalendarDate, isValidTimeZone, validateTripInput, validateItemInput,
  validateDeviceInput, parseSince, validateDisplayName,
} from '../src/validate.js';

const TRIP = { title: 'Lisbon & Porto', destination: 'Portugal', startDate: '2026-10-01', endDate: '2026-10-09', timeZone: 'Europe/Lisbon', coverEmoji: '🇵🇹', colorHex: '#2F6FEB', notes: '' };
const ITEM = {
  kind: 'flight', title: 'TP 202 JFK → LIS', startAt: '2026-10-01T22:30:00Z', endAt: '2026-10-02T09:45:00Z',
  startTimeZone: 'America/New_York', endTimeZone: 'Europe/Lisbon', allDay: false, locationName: 'JFK T1', address: '',
  latitude: 40.6413, longitude: -73.7781, confirmationCode: 'ABC123', details: { airline: 'TAP', seat: '14A' },
  notes: '', reminderMinutes: 180, sortIndex: 0,
};

describe('primitives', () => {
  it('normalizes UUIDs to lowercase and rejects junk', () => {
    expect(normalizeUuid('3F2504E0-4F89-11D3-9A0C-0305E82C3301')).toBe('3f2504e0-4f89-11d3-9a0c-0305e82c3301');
    expect(normalizeUuid('not-a-uuid')).toBeNull();
    expect(normalizeUuid(42)).toBeNull();
  });
  it('accepts only canonical UTC instants without fractional seconds', () => {
    expect(isIsoInstant('2026-10-01T14:30:00Z')).toBe(true);
    expect(isIsoInstant('2026-10-01T14:30:00.000Z')).toBe(false);
    expect(isIsoInstant('2026-10-01T14:30:00+01:00')).toBe(false);
    expect(isIsoInstant('2026-02-30T14:30:00Z')).toBe(false);
    expect(isIsoInstant('2026-10-01T24:00:00Z')).toBe(false);
  });
  it('validates calendar dates', () => {
    expect(isCalendarDate('2028-02-29')).toBe(true);
    expect(isCalendarDate('2026-02-29')).toBe(false);
    expect(isCalendarDate('2026-1-01')).toBe(false);
  });
  it('validates IANA time zones', () => {
    expect(isValidTimeZone('Europe/Lisbon')).toBe(true);
    expect(isValidTimeZone('America/Argentina/Buenos_Aires')).toBe(true);
    expect(isValidTimeZone('UTC')).toBe(true);
    expect(isValidTimeZone('Mars/Olympus')).toBe(false);
    expect(isValidTimeZone('+01:00')).toBe(false);
    expect(isValidTimeZone('')).toBe(false);
  });
  it('parses since', () => {
    expect(parseSince(null)).toBe(0);
    expect(parseSince('1727000000000')).toBe(1727000000000);
    expect(() => parseSince('-1')).toThrow();
    expect(() => parseSince('abc')).toThrow();
  });
  it('display names are trimmed and bounded', () => {
    expect(validateDisplayName('  Nick ', { required: true })).toBe('Nick');
    expect(validateDisplayName(null, { required: false })).toBeNull();
    expect(() => validateDisplayName('', { required: true })).toThrow();
    expect(() => validateDisplayName('x'.repeat(101), { required: true })).toThrow();
  });
});

describe('trip input', () => {
  it('accepts the contract example and ignores server-owned keys', () => {
    const t = validateTripInput({ ...TRIP, id: 'x', ownerId: 'y', updatedAt: 1 });
    expect(t).toEqual(TRIP);
  });
  it('applies defaults for optional fields', () => {
    const t = validateTripInput({ title: 'T', startDate: '2026-10-01', endDate: '2026-10-01', timeZone: 'UTC' });
    expect(t).toMatchObject({ destination: '', coverEmoji: '', colorHex: '#2F6FEB', notes: '' });
  });
  it.each([
    [{ title: '' }, 'title'],
    [{ title: 'x'.repeat(201) }, 'title'],
    [{ startDate: '2026-10-10' }, 'endDate'],
    [{ timeZone: 'Nowhere/City' }, 'timeZone'],
    [{ colorHex: 'blue' }, 'colorHex'],
    [{ notes: 5 }, 'notes'],
  ])('rejects %j', (patch, field) => {
    expect(() => validateTripInput({ ...TRIP, ...patch })).toThrow(new RegExp(field));
  });
});

describe('item input', () => {
  it('accepts the contract example', () => {
    expect(validateItemInput(ITEM)).toEqual(ITEM);
  });
  it('defaults nullable / optional fields', () => {
    const i = validateItemInput({ kind: 'note', title: 'Hi', startAt: '2026-10-01T10:00:00Z', startTimeZone: 'UTC' });
    expect(i).toMatchObject({ endAt: null, endTimeZone: null, allDay: false, latitude: null, details: {}, reminderMinutes: null, sortIndex: 0 });
  });
  it('checks body id against the URL (case-insensitively)', () => {
    const id = '3f2504e0-4f89-11d3-9a0c-0305e82c3301';
    expect(() => validateItemInput({ ...ITEM, id: id.toUpperCase() }, { itemId: id })).not.toThrow();
    expect(() => validateItemInput({ ...ITEM, id: '00000000-0000-0000-0000-000000000000' }, { itemId: id })).toThrow(/id/);
  });
  it.each([
    [{ kind: 'cruise' }, 'kind'],
    [{ startAt: '2026-10-01 22:30' }, 'startAt'],
    [{ startAt: null }, 'startAt'],
    [{ endAt: '2026-10-01T20:00:00Z' }, 'endAt'],
    [{ startTimeZone: 'EST5' }, 'startTimeZone'],
    [{ latitude: 91 }, 'latitude'],
    [{ longitude: 'x' }, 'longitude'],
    [{ details: { seat: 14 } }, 'details'],
    [{ details: [] }, 'details'],
    [{ reminderMinutes: 1.5 }, 'reminderMinutes'],
    [{ reminderMinutes: -5 }, 'reminderMinutes'],
    [{ allDay: 'yes' }, 'allDay'],
  ])('rejects %j', (patch, field) => {
    expect(() => validateItemInput({ ...ITEM, ...patch })).toThrow(new RegExp(field));
  });
});

describe('device input', () => {
  const D = { apnsToken: 'AB'.repeat(32), environment: 'sandbox', timeZone: 'America/New_York', briefingEnabled: true, briefingHour: 7, collabAlertsEnabled: true };
  it('normalizes the token to lowercase hex', () => {
    expect(validateDeviceInput(D).apnsToken).toBe('ab'.repeat(32));
  });
  it.each([
    [{ apnsToken: 'zz' }],
    [{ environment: 'dev' }],
    [{ briefingHour: 24 }],
    [{ timeZone: 'nope' }],
  ])('rejects %j', (patch) => {
    expect(() => validateDeviceInput({ ...D, ...patch })).toThrow();
  });
});
