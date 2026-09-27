import { describe, it, expect } from 'vitest';
import {
  sanitizeDraft, sanitizeDrafts, normalizeInstant, extractStructuredOutput, buildRequestBody, DRAFT_SCHEMA, ANTHROPIC_MODEL,
} from '../src/importer.js';
import { validateItemInput } from '../src/validate.js';

const trip = { title: 'Lisbon & Porto', destination: 'Portugal', start_date: '2026-10-01', end_date: '2026-10-09', time_zone: 'Europe/Lisbon' };
const raw = {
  kind: 'flight', title: 'TP 202 JFK → LIS', startAt: '2026-10-01T22:30:00Z', endAt: '2026-10-02T09:45:00Z',
  startTimeZone: 'America/New_York', endTimeZone: 'Europe/Lisbon', allDay: false, locationName: 'JFK Terminal 1',
  address: '', latitude: null, longitude: null, confirmationCode: 'ABC123',
  details: [{ key: 'airline', value: 'TAP' }, { key: 'flightNumber', value: 'TP202' }], notes: '', reminderMinutes: 180,
};

describe('request body', () => {
  it('uses structured output with a strict schema and the trip context', () => {
    const body = buildRequestBody(trip, 'hello');
    expect(body.model).toBe(ANTHROPIC_MODEL);
    expect(body.output_config.format).toEqual({ type: 'json_schema', schema: DRAFT_SCHEMA });
    const msg = body.messages[0].content;
    expect(msg).toContain('2026-10-01 to 2026-10-09');
    expect(msg).toContain('Europe/Lisbon');
    expect(msg).toContain('<pasted_text>\nhello\n</pasted_text>');
  });
  it('sets additionalProperties:false on every object (structured-output requirement)', () => {
    const walk = (s) => {
      if (!s || typeof s !== 'object') return;
      if (s.type === 'object') expect(s.additionalProperties).toBe(false);
      Object.values(s).forEach(walk);
    };
    walk(DRAFT_SCHEMA);
  });
});

describe('sanitizing model output', () => {
  it('turns a good draft into a valid ItemDraft', () => {
    const d = sanitizeDraft(raw, trip);
    expect(d.details).toEqual({ airline: 'TAP', flightNumber: 'TP202' });
    expect(d).not.toHaveProperty('id');
    expect(d).not.toHaveProperty('sortIndex');
    // Every sanitized draft must pass the same validator the PUT endpoint uses.
    expect(() => validateItemInput(d)).not.toThrow();
  });
  it('repairs near-miss values', () => {
    const d = sanitizeDraft({
      ...raw, kind: 'cruise', startAt: '2026-10-01T23:30:00.000+01:00', endAt: '2026-09-01T00:00:00Z',
      startTimeZone: 'Not/AZone', endTimeZone: 'Europe/Lisbon', title: `  ${'x'.repeat(300)} `,
      latitude: 38.7, longitude: null, reminderMinutes: -3, confirmationCode: 'A\u0000B',
    }, trip);
    expect(d.kind).toBe('note');
    expect(d.startAt).toBe('2026-10-01T22:30:00Z');
    expect(d.endAt).toBeNull();
    expect(d.startTimeZone).toBe('Europe/Lisbon');
    expect(d.endTimeZone).toBeNull(); // same as start -> null
    expect(d.title).toHaveLength(200);
    expect(d.latitude).toBeNull();
    expect(d.reminderMinutes).toBeNull();
    expect(d.confirmationCode).toBe('AB');
    expect(() => validateItemInput(d)).not.toThrow();
  });
  it('drops unusable drafts and caps the list', () => {
    expect(sanitizeDraft({ ...raw, startAt: 'next tuesday' }, trip)).toBeNull();
    expect(sanitizeDraft({ ...raw, title: '   ' }, trip)).toBeNull();
    expect(sanitizeDrafts({ items: Array.from({ length: 80 }, () => raw) }, trip)).toHaveLength(50);
    expect(sanitizeDrafts({ nope: 1 }, trip)).toEqual([]);
  });
  it('normalizes instants', () => {
    expect(normalizeInstant('2026-10-01T14:30:00Z')).toBe('2026-10-01T14:30:00Z');
    expect(normalizeInstant('2026-10-01T14:30Z')).toBe('2026-10-01T14:30:00Z');
    expect(normalizeInstant('2026-10-01')).toBeNull();
    expect(normalizeInstant(5)).toBeNull();
  });
});

describe('reading the Messages API response', () => {
  it('finds the JSON text block after thinking blocks', () => {
    const msg = { stop_reason: 'end_turn', content: [{ type: 'thinking', thinking: '' }, { type: 'text', text: '{"items":[]}' }] };
    expect(extractStructuredOutput(msg)).toEqual({ items: [] });
  });
  it('maps refusal and truncation to a friendly 400', () => {
    expect(() => extractStructuredOutput({ stop_reason: 'refusal', content: [] })).toThrow(expect.objectContaining({ status: 400 }));
    expect(() => extractStructuredOutput({ stop_reason: 'max_tokens', content: [] })).toThrow(expect.objectContaining({ status: 400 }));
  });
});
